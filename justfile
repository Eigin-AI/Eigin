# `tools config` reads .env and renders it per consumer. Recipes capture an
# export block before eval, so a tool failure fails the recipe.

ios_dir   := "src/eigin_ios"

simulator := "iPhone 17 Pro"
dest      := "platform=iOS Simulator,name=" + simulator
relay_dir := "src/eigin_relay"
infra_dir := "infra/scaleway"
log_dir   := "logs"
tools     := "cargo run --quiet --manifest-path tools/Cargo.toml --"

# --- Cross-cutting ---

[doc('Regenerate the Xcode project and other generated files')]
generate:
    #!/usr/bin/env bash
    set -euo pipefail
    vars="$({{ tools }} config export ios)"
    eval "$vars"
    {{ tools }} generate

[doc('Config (init | check | secret <NAME> <env> | export ios|relay|tf-vars [env])')]
config *args="check":
    {{ tools }} config {{ args }}

[doc('Auto-format all code')]
format:
    {{ tools }} format

[doc('Lint all code')]
lint:
    {{ tools }} lint

[doc('Scan dependencies and the Relay image for vulnerabilities (all | deps | image)')]
security scope="all":
    {{ tools }} security {{ scope }}

[doc('Install git hooks (one-time setup)')]
hooks:
    {{ tools }} hooks install

[doc('Build or serve the docs (build | serve)')]
docs command="build":
    #!/usr/bin/env bash
    case "{{ command }}" in
        build) cd docs && mdbook build ;;
        serve) cd docs && mdbook serve ;;
        *) echo "Unknown docs command: {{ command }}"; exit 1 ;;
    esac

# --- Test ---

[private]
_test-ios env="staging" verbose="false": generate
    #!/usr/bin/env bash
    scheme=$([ "{{ env }}" = "staging" ] && echo "EiginDev" || echo "Eigin")
    if [ "{{ verbose }}" = "true" ]; then
        xcodebuild -project "{{ ios_dir }}/Eigin-iOS.xcodeproj" \
            -scheme "$scheme" -destination '{{ dest }}' -derivedDataPath "{{ ios_dir }}/DerivedData" -skipMacroValidation \
            -skip-testing:EiginTests/ProviderIntegrationTests test
    else
        {{ tools }} run --log "{{ log_dir }}/ios-test.log" --label "Running iOS tests" -- \
            xcodebuild -project "{{ ios_dir }}/Eigin-iOS.xcodeproj" \
                -scheme "$scheme" -destination '{{ dest }}' -derivedDataPath "{{ ios_dir }}/DerivedData" -skipMacroValidation \
                -skip-testing:EiginTests/ProviderIntegrationTests test
    fi

[private]
_test-relay verbose="false":
    if [ "{{ verbose }}" = "true" ]; then \
        cd {{ relay_dir }} && cargo test; \
    else \
        {{ tools }} run --log "{{ log_dir }}/relay-test.log" --label "Running relay tests" -- \
            sh -c 'cd {{ relay_dir }} && cargo test'; \
    fi

[arg("verbose", short="v", long="verbose", value="true")]
[doc('Run tests (target: all | ios | relay, variant: unit | postgres)')]
test target="all" variant="unit" env="staging" verbose="false":
    #!/usr/bin/env bash
    if [ "{{ target }}" = "ios" ] || [ "{{ target }}" = "all" ]; then just _test-ios {{ env }} {{ verbose }}; fi
    if [ "{{ target }}" = "relay" ] || [ "{{ target }}" = "all" ]; then
        if [ "{{ variant }}" = "postgres" ]; then
            just _test-relay-postgres
        else
            just _test-relay {{ verbose }}
        fi
    fi

[private]
_test-relay-postgres:
    #!/usr/bin/env bash
    set -e
    container=$(docker run --rm -d -p 5432:5432 -e POSTGRES_PASSWORD=postgres postgres:16)
    trap "docker stop $container" EXIT
    echo "Waiting for Postgres to be ready..."
    until docker exec "$container" pg_isready -U postgres -q; do sleep 0.5; done
    DATABASE_URL=postgres://postgres:postgres@localhost/postgres \
        cargo test --manifest-path {{ relay_dir }}/Cargo.toml -- --ignored --nocapture

# --- Build ---

[private]
_build-ios env="staging" verbose="false": generate
    #!/usr/bin/env bash
    scheme=$([ "{{ env }}" = "staging" ] && echo "EiginDev" || echo "Eigin")
    if [ "{{ verbose }}" = "true" ]; then
        xcodebuild -project "{{ ios_dir }}/Eigin-iOS.xcodeproj" \
            -scheme "$scheme" -destination '{{ dest }}' -derivedDataPath "{{ ios_dir }}/DerivedData" -skipMacroValidation build
    else
        {{ tools }} run --log "{{ log_dir }}/ios-build.log" --label "Building Eigin for iOS" -- \
            xcodebuild -project "{{ ios_dir }}/Eigin-iOS.xcodeproj" \
                -scheme "$scheme" -destination '{{ dest }}' -derivedDataPath "{{ ios_dir }}/DerivedData" -skipMacroValidation build
    fi

[private]
_build-relay verbose="false":
    if [ "{{ verbose }}" = "true" ]; then \
        cd {{ relay_dir }} && cargo build --release; \
    else \
        {{ tools }} run --log "{{ log_dir }}/relay-build.log" --label "Building Eigin relay" -- \
            sh -c 'cd {{ relay_dir }} && cargo build --release'; \
    fi

[arg("verbose", short="v", long="verbose", value="true")]
[doc('Build all targets (target: all | ios | relay)')]
build target="all" env="staging" verbose="false":
    @if [ "{{ target }}" = "ios"   ] || [ "{{ target }}" = "all" ]; then just _build-ios {{ env }} {{ verbose }}; fi
    @if [ "{{ target }}" = "relay" ] || [ "{{ target }}" = "all" ]; then just _build-relay {{ verbose }}; fi

# --- Release ---

# `env`/`track` default to the least public target: no args means staging beta.
[doc('Build, sign and upload a release (target: ios, env: staging | production, track: beta | metadata | iap)')]
release target="ios" env="staging" track="beta": generate
    #!/usr/bin/env bash
    set -euo pipefail
    if [ "{{ target }}" != "ios" ]; then echo "Unknown release target: {{ target }}"; exit 1; fi
    case "{{ track }}" in
        beta)     lane=beta ;;
        metadata) lane=sync_metadata ;;
        iap)      lane=sync_iap ;;
        *) echo "Unknown release track: {{ track }}"; exit 1 ;;
    esac
    # fastlane reads BUNDLE_ID / DEVELOPMENT_TEAM / ASC_* from the environment.
    vars="$({{ tools }} config export ios)"
    eval "$vars"
    # Exported empty for simulator builds, so a release must assert a real one.
    if [ -z "${DEVELOPMENT_TEAM:-}" ]; then
        echo "DEVELOPMENT_TEAM is not set in .env — required to sign a release."; exit 1
    fi
    {{ tools }} run --log "{{ log_dir }}/ios-release.log" --label "Releasing Eigin for iOS ({{ env }}/{{ track }})" -- \
        sh -c 'cd {{ ios_dir }} && bundle exec fastlane ios '"$lane"' env:{{ env }}'

# --- Grants ---

# Generate or sign credit grant tokens.
#
# Local dev key in {{ relay_dir }}/config/grant (gitignored, local testing only):
#   just grant keygen
#   just grant sign
#   just grant sign eigin.credits.v1.grant.500
#
# Remote: sign with a deployed environment's Terraform-generated key
# (pulled from state into the environment, never written to disk):
#   just grant sign-remote staging
#   just grant sign-remote staging eigin.credits.v1.grant.500
[doc('Generate or sign credit grant tokens (keygen | sign | sign-remote)')]
grant command="keygen" *args:
    #!/usr/bin/env bash
    set -euo pipefail
    grant_dir="{{ relay_dir }}/config/grant"
    default_product="eigin.credits.v1.grant.500"
    args=({{ args }})
    case "{{ command }}" in
        keygen) {{ tools }} grant keygen --out-dir "$grant_dir" ;;
        sign)
            product="${args[0]:-$default_product}"
            if [ ! -f "$grant_dir/grant_private.pem" ]; then
                echo "No local signing key. Run 'just grant keygen' first."; exit 1
            fi
            {{ tools }} grant sign --private-key "$grant_dir/grant_private.pem" --product "$product"
            ;;
        sign-remote)
            env="${args[0]:-staging}"
            product="${args[1]:-$default_product}"
            vars="$({{ tools }} config export tf-vars "$env")"
            eval "$vars"
            terraform -chdir={{ infra_dir }} workspace select -or-create "$env" >/dev/null
            GRANT_PRIVATE_KEY="$(terraform -chdir={{ infra_dir }} output -raw grant_private_key_pem)" \
                {{ tools }} grant sign --product "$product"
            ;;
        *) echo "Unknown grant command: {{ command }}"; exit 1 ;;
    esac

# Manage self-hosted model assets. Thin pass-through to `eigin-tools assets`.
# See the model-mirror runbook for the upload/promote procedure.
#   just assets upload --id <id> --source-dir <dir> --version <v> \
#     --origin-repo <repo> --origin-rev <sha> --endpoint <url> --region <r> \
#     --bucket <b> --access-key <k> --secret-key <s>
[doc('Manage self-hosted model assets (upload)')]
assets *args:
    {{ tools }} assets {{ args }}

# --- Run / Clean / Open ---

[doc('Run a target locally (target: relay)')]
run target env="staging":
    #!/usr/bin/env bash
    set -euo pipefail
    case "{{ target }}" in
        relay)
            # Suffixed secrets and the environment's non-secret tfvars values,
            # resolved and stripped to the names the relay reads.
            vars="$({{ tools }} config export relay {{ env }})"
            eval "$vars"

            grant_key_file="{{ relay_dir }}/config/grant/grant_public.pem"
            if [ -f "$grant_key_file" ]; then
                export GRANT_PUBLIC_KEY="$(cat "$grant_key_file")"
            fi
            cd {{ relay_dir }} && cargo run
            ;;
        *) echo "Unknown run target: {{ target }}"; exit 1 ;;
    esac

[doc('Clean the iOS build and derived data')]
clean env="staging":
    #!/usr/bin/env bash
    scheme=$([ "{{ env }}" = "staging" ] && echo "EiginDev" || echo "Eigin")
    xcodebuild -project {{ ios_dir }}/Eigin-iOS.xcodeproj \
        -scheme "$scheme" -destination '{{ dest }}' -derivedDataPath "{{ ios_dir }}/DerivedData" clean
    rm -rf {{ ios_dir }}/DerivedData {{ ios_dir }}/Build

# --- Infra ---

[doc('Manage infra (bootstrap | init | plan | deploy | migrate | token-key-status | token-key-replace | token-key-sweep | token-key-retire)')]
infra command env="staging":
    #!/usr/bin/env bash
    set -euo pipefail
    case "{{ command }}" in
        bootstrap)
            # One-time: create the dedicated project + private, versioned state
            # bucket + scoped key. Uses local state. See the remote-state runbook.
            cd {{ infra_dir }}/bootstrap
            terraform init
            read -p "Create the remote Terraform state bucket? [y/N] " confirm && [ "$confirm" = "y" ] || exit 1
            terraform apply
            echo
            echo "Add these to your repo-root .env, then follow the runbook:"
            echo "  TFSTATE_ACCESS_KEY=$(terraform output -raw tfstate_access_key)"
            echo "  TFSTATE_SECRET_KEY=$(terraform output -raw tfstate_secret_key)"
            echo "  TFSTATE_REGION=$(terraform output -raw tfstate_region)"
            echo "Backend bucket: $(terraform output -raw tfstate_bucket_name)"
            ;;
        init)
            vars="$({{ tools }} config export tf-vars {{ env }})"
            eval "$vars"
            cd {{ infra_dir }}
            # Init the backend first: a fresh worktree has no .terraform/, and
            # `workspace select` needs an initialized backend to run.
            terraform init && terraform workspace select -or-create {{ env }}
            ;;
        migrate)
            # One-time: copy local state to the remote backend. Migrates all
            # workspaces at once. Requires backend.tf. See the remote-state runbook.
            vars="$({{ tools }} config export tf-vars {{ env }})"
            eval "$vars"
            cd {{ infra_dir }}
            terraform init -migrate-state
            ;;
        plan)
            vars="$({{ tools }} config export tf-vars {{ env }})"
            eval "$vars"
            cd {{ infra_dir }}
            terraform workspace select -or-create {{ env }}
            terraform plan -var-file=environments/{{ env }}.tfvars
            ;;
        deploy)
            docker info > /dev/null 2>&1 || (echo "Docker daemon is not running. Start Docker Desktop and try again."; exit 1)
            if [ "{{ env }}" = "production" ]; then
                read -p "Deploy to production? [y/N] " confirm && [ "$confirm" = "y" ] || exit 1
            fi
            vars="$({{ tools }} config export tf-vars {{ env }})"
            eval "$vars"
            cd {{ infra_dir }}
            terraform workspace select -or-create {{ env }}
            terraform apply -var-file=environments/{{ env }}.tfvars
            ;;
        token-key-status)
            # Read-only: how many wallets are still on which token encryption key.
            vars="$({{ tools }} config export tf-vars {{ env }})"
            eval "$vars"
            terraform -chdir={{ infra_dir }} workspace select {{ env }} >/dev/null
            export DATABASE_URL="$(terraform -chdir={{ infra_dir }} output -raw database_url)"
            key="$(terraform -chdir={{ infra_dir }} output -raw token_encryption_key)"
            cargo run --quiet --release --manifest-path {{ relay_dir }}/Cargo.toml --bin rotate-key -- check --key "$key"
            ;;
        token-key-replace)
            # Deploy a new primary token key, keeping the current one as the decrypt
            # fallback. Refuses until the current key is saved as the secondary in .env.
            suffix=$(echo "{{ env }}" | tr '[:lower:]' '[:upper:]')
            vars="$({{ tools }} config export tf-vars {{ env }})"
            eval "$vars"
            terraform -chdir={{ infra_dir }} workspace select {{ env }} >/dev/null
            old="$(terraform -chdir={{ infra_dir }} output -raw token_encryption_key)"
            var="TOKEN_ENCRYPTION_SECONDARY_KEY_${suffix}"
            secondary="$({{ tools }} config secret TOKEN_ENCRYPTION_SECONDARY_KEY {{ env }})"
            if [ "$secondary" != "$old" ]; then
                echo "Add the current key to your repo-root .env as the secondary, then re-run:"
                echo "  ${var}=${old}"
                exit 1
            fi
            terraform -chdir={{ infra_dir }} apply -replace=module.relay.random_bytes.token_encryption_key -var-file=environments/{{ env }}.tfvars
            ;;
        token-key-sweep)
            # Re-encrypt every wallet onto the new key (dry-run, confirm, then verify).
            suffix=$(echo "{{ env }}" | tr '[:lower:]' '[:upper:]')
            vars="$({{ tools }} config export tf-vars {{ env }})"
            eval "$vars"
            terraform -chdir={{ infra_dir }} workspace select {{ env }} >/dev/null
            export DATABASE_URL="$(terraform -chdir={{ infra_dir }} output -raw database_url)"
            new="$(terraform -chdir={{ infra_dir }} output -raw token_encryption_key)"
            var="TOKEN_ENCRYPTION_SECONDARY_KEY_${suffix}"
            old="$({{ tools }} config secret TOKEN_ENCRYPTION_SECONDARY_KEY {{ env }})"
            if [ -z "$old" ]; then
                echo "No ${var} in .env — run 'just infra token-key-replace {{ env }}' first."
                exit 1
            fi
            bin="cargo run --quiet --release --manifest-path {{ relay_dir }}/Cargo.toml --bin rotate-key --"
            $bin sweep --new-key "$new" --old-key "$old" --dry-run
            read -p "Proceed with re-encryption? [y/N] " confirm && [ "$confirm" = "y" ] || exit 1
            $bin sweep --new-key "$new" --old-key "$old"
            $bin check --key "$new"
            ;;
        token-key-retire)
            # Drop the old key once the sweep has drained. Refuses until the secondary
            # is removed from .env, then redeploys.
            suffix=$(echo "{{ env }}" | tr '[:lower:]' '[:upper:]')
            var="TOKEN_ENCRYPTION_SECONDARY_KEY_${suffix}"
            # Capture separately: inside [ -n "$(…)" ] a tool failure is invisible to
            # set -e, and an empty result would wave this retire through.
            secondary="$({{ tools }} config secret TOKEN_ENCRYPTION_SECONDARY_KEY {{ env }})"
            if [ -n "$secondary" ]; then
                echo "Remove ${var} from your repo-root .env first, then re-run."
                exit 1
            fi
            docker info > /dev/null 2>&1 || (echo "Docker daemon is not running. Start Docker Desktop and try again."; exit 1)
            vars="$({{ tools }} config export tf-vars {{ env }})"
            eval "$vars"
            terraform -chdir={{ infra_dir }} workspace select {{ env }} >/dev/null
            terraform -chdir={{ infra_dir }} apply -var-file=environments/{{ env }}.tfvars
            ;;
        *)
            echo "Unknown infra command: {{ command }}"
            exit 1
            ;;
    esac
