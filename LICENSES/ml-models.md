# ML Model Licenses

Model weights are not bundled in the app. They are mirrored at build/runbook time
from their original sources (HuggingFace) into Eigin's private asset mirror
(Scaleway Object Storage) and downloaded by the app from there. Mirroring and
redistribution happen under each model's license: record any new model's
license here before mirroring it, and keep the mirror's version provenance
(`--origin-repo` / `--origin-rev` in the manifest) pointing at the exact
upstream revision mirrored.

Distribution of the mirror is access-controlled: presigned URLs are only issued
to clients that hold the relay key.

---

## PocketTTS (Kyutai, CoreML adaptation by FluidInference)

| | |
|---|---|
| **Model** | PocketTTS |
| **Original provider** | Kyutai |
| **Original HuggingFace** | https://huggingface.co/kyutai/pocket-tts |
| **CoreML adaptation** | FluidInference |
| **CoreML HuggingFace** | https://huggingface.co/FluidInference/pocket-tts-coreml |
| **Library** | FluidAudio (Apache 2.0) — see swift-packages.md |
| **Model license** | CC BY 4.0 |

---

## Plapre Pico (syv.ai, CoreML adaptation by 42futures)

| | |
|---|---|
| **Model** | Plapre Pico |
| **Original provider** | syv.ai |
| **Original HuggingFace** | https://huggingface.co/syvai/plapre-pico |
| **CoreML adaptation** | 42futures |
| **CoreML HuggingFace** | https://huggingface.co/42futures/plapre-pico-coreml |
| **Tokenizer** | swift-transformers (Apache 2.0) — see swift-packages.md |
| **Model license** | CC BY 4.0 |

---

## Gemma 4 E2B (Google, LiteRT-LM QAT build by litert-community)

| | |
|---|---|
| **Model** | Gemma 4 E2B (instruction-tuned, QAT 2/4/8-bit mobile) |
| **Original provider** | Google |
| **Original HuggingFace** | https://huggingface.co/google/gemma-4-E2B-it-qat-mobile-transformers |
| **LiteRT-LM build** | litert-community |
| **LiteRT-LM HuggingFace** | https://huggingface.co/litert-community/gemma-4-E2B-it-litert-lm |
| **Runtime** | LiteRT-LM (Apache 2.0) — see swift-packages.md |
| **Model license** | Gemma Terms of Use |
