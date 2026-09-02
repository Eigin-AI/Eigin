# Model mirror

Put a downloadable model asset on the bucket and make it live. The app fetches
these from the relay's `/v1/assets` mirror instead of HuggingFace. The id is a
label you choose; encode the runtime so different builds of a model don't collide
(`plapre-pico-coreml`, `gemma4-e2b-litertlm`).

Always land a version on **staging**, test the app against it, then promote the
*same* version to **production**.

## Current assets

The uploader mirrors a local directory 1:1, so you download **only the files the
app needs** — these repos hold many unrelated variants. The include patterns come
from what the app checks for on disk (`GemmaModelDownloader`, `PlaprePicoAssets`,
`PocketTTSModelDownloader`).

| id | HuggingFace repo | files to include |
|---|---|---|
| `gemma4-e2b-litertlm` | `litert-community/gemma-4-E2B-it-litert-lm` | `gemma-4-E2B-it.litertlm` |
| `plapre-pico-coreml` | `42futures/plapre-pico-coreml` | `PlaprePico.mlpackage/*` `KanadeDecoder.mlpackage/*` `Vocoder.mlpackage/*` `tokenizer.json` `tokenizer_config.json` `speakers.json` `rope_cos.npy` `rope_sin.npy` |
| `pocket-tts-coreml` | `FluidInference/pocket-tts-coreml` | `cond_step.mlmodelc/*` `flowlm_step.mlmodelc/*` `flow_decoder.mlmodelc/*` `mimi_decoder_v2.mlmodelc/*` `constants_bin/*` |

## Prerequisites

The HF CLI (`hf`). On macOS, Homebrew's Python is externally managed, so use a
venv or pipx:

```sh
python3 -m venv /tmp/hf-venv && /tmp/hf-venv/bin/pip install -U "huggingface_hub[cli]"
export PATH="/tmp/hf-venv/bin:$PATH"    # or: pipx install "huggingface_hub[cli]"
```

Prepare your shell for the target environment:

```sh
export ENV=staging
eval "$(cargo run -q --manifest-path tools/Cargo.toml -- infra tf-vars $ENV)"
cd infra/scaleway && terraform workspace select $ENV
BUCKET=$(terraform output -raw assets_bucket)
AK=$(terraform output -raw assets_write_access_key)
SK=$(terraform output -raw assets_write_secret_key)
```

The write identity is Terraform-owned and never deployed.

## 1. Download only the files the app needs

Pin the repo to a commit and pull just the included files.

> **Gotcha:** `hf --include` takes **one pattern per flag**. Passing several
> patterns after a single `--include` silently drops all but the first (the
> extras leak into positional filenames and disable `--include`). Repeat the flag.

```sh
REPO=42futures/plapre-pico-coreml
COMMIT=$(git ls-remote "https://huggingface.co/$REPO" HEAD | cut -f1)
hf download "$REPO" --revision "$COMMIT" --local-dir /tmp/plapre-pico-coreml \
  --include "PlaprePico.mlpackage/*" --include "KanadeDecoder.mlpackage/*" \
  --include "Vocoder.mlpackage/*" --include tokenizer.json \
  --include tokenizer_config.json --include speakers.json \
  --include rope_cos.npy --include rope_sin.npy
```

Sanity-check the file set before uploading (the `.cache/` metadata `hf` leaves
behind is skipped by the uploader):

```sh
find /tmp/plapre-pico-coreml -type f -not -path '*/.*' | sed 's#.*/plapre-pico-coreml/##' | sort
```

## 2. Upload

```sh
just assets upload \
  --id plapre-pico-coreml \
  --source-dir /tmp/plapre-pico-coreml \
  --origin-repo "$REPO" --origin-rev "$COMMIT" \
  --endpoint https://s3.fr-par.scw.cloud --region fr-par \
  --bucket "$BUCKET" --access-key "$AK" --secret-key "$SK"
```

It hashes every file, streams large files as multipart uploads, writes +
uploads `manifest.json`, and prints the `[[assets]]` block. Re-runs skip
already-present objects. **Note the version id** — you reuse it for production.

## 3. Point the relay at it

Paste the printed block into `src/eigin_relay/config/assets.toml` (replacing the
old entry for that id) and deploy — the image hash covers `config/**`:

```sh
just infra deploy $ENV
```

## 4. Verify

```sh
KEY=$(terraform output -raw eigin_relay_primary_key)
URL=$(terraform output -raw service_url)

# version + file count
curl -s -H "x-eigin-key: $KEY" "$URL/v1/assets/plapre-pico-coreml" \
  | jq '{version, files: (.files|length)}'

# a presigned URL actually serves bytes (range GET — the URL is signed for GET,
# so a HEAD would 403). Expect 200/206:
u=$(curl -s -H "x-eigin-key: $KEY" "$URL/v1/assets/plapre-pico-coreml" | jq -r '.files[0].url')
curl -s -o /dev/null -w '%{http_code}\n' -r 0-0 "$u"
```

Confirm the file count matches what you uploaded, then test the app: run the
`EiginDev` scheme (staging) on a device and download the model.

## 5. Promote to production

One `assets.toml` is baked into both images, so production needs the **same id +
version + bytes**. Re-upload from the same source dir with the staging version
and origin — every manifest input is identical, so the `manifest_sha256` pin
stays valid:

```sh
export ENV=production
eval "$(cargo run -q --manifest-path tools/Cargo.toml -- infra tf-vars $ENV)"
cd infra/scaleway && terraform workspace select $ENV
# first `just infra deploy production` once, to create the bucket

just assets upload \
  --id plapre-pico-coreml --source-dir /tmp/plapre-pico-coreml \
  --version <staging version id> \
  --origin-repo "$REPO" --origin-rev "$COMMIT" \
  --endpoint https://s3.fr-par.scw.cloud --region fr-par \
  --bucket "$(terraform output -raw assets_bucket)" \
  --access-key "$(terraform output -raw assets_write_access_key)" \
  --secret-key "$(terraform output -raw assets_write_secret_key)"
```

The relay reads the bucket per request, so once the objects exist it serves them
with no redeploy. Verify as in step 4 with `ENV=production`.

> Pin `--version` **and** `--origin-rev` to staging's. If you let the version
> default (new timestamp) or re-resolve the repo HEAD, the manifest bytes differ,
> its sha won't match the committed `assets.toml`, and the relay 503s.

## Recovering a bad upload

Version prefixes are immutable in practice: create-only puts refuse to
overwrite, and versioning means a rewrite makes a new version rather than
mutating one. To replace a bad version, delete its prefix with the write
identity (the only principal that can delete — the relay is read-only), then
re-run with a fresh timestamp. Never reuse a deleted id. Old versions persist
until deleted, so rollback is just re-pointing `assets.toml` at an older id.
