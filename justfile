set dotenv-load := true

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
    {{ tools }} generate

[doc('Auto-format all code')]
format:
    {{ tools }} format

[doc('Lint all code')]
lint:
    {{ tools }} lint

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
            -scheme "$scheme" -destination '{{ dest }}' \
            -skip-testing:EiginTests/ProviderIntegrationTests test
    else
        {{ tools }} run --log "{{ log_dir }}/ios-test.log" --label "Running iOS tests" -- \
            xcodebuild -project "{{ ios_dir }}/Eigin-iOS.xcodeproj" \
                -scheme "$scheme" -destination '{{ dest }}' \
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
            -scheme "$scheme" -destination '{{ dest }}' build
    else
        {{ tools }} run --log "{{ log_dir }}/ios-build.log" --label "Building Eigin for iOS" -- \
            xcodebuild -project "{{ ios_dir }}/Eigin-iOS.xcodeproj" \
                -scheme "$scheme" -destination '{{ dest }}' build
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
            eval "$({{ tools }} infra tf-vars "$env")"
            terraform -chdir={{ infra_dir }} workspace select -or-create "$env" >/dev/null
            GRANT_PRIVATE_KEY="$(terraform -chdir={{ infra_dir }} output -raw grant_private_key_pem)" \
                {{ tools }} grant sign --product "$product"
            ;;
        *) echo "Unknown grant command: {{ command }}"; exit 1 ;;
    esac

# --- Run / Clean / Open ---

[doc('Run a target locally (target: relay)')]
run target env="staging":
    #!/usr/bin/env bash
    case "{{ target }}" in
        relay)
            [ -f .env ] && source .env
            suffix=$(echo "{{ env }}" | tr '[:lower:]' '[:upper:]')

            # Secrets come from .env, per environment (suffixed).
            mojeek_key="MOJEEK_API_KEY_${suffix}"
            relay_primary_key="EIGIN_RELAY_PRIMARY_KEY_${suffix}"
            relay_secondary_key="EIGIN_RELAY_SECONDARY_KEY_${suffix}"
            upstream_api_key="UPSTREAM_API_KEY_${suffix}"
            export MOJEEK_API_KEY="${!mojeek_key}"
            export EIGIN_RELAY_PRIMARY_KEY="${!relay_primary_key}"
            export EIGIN_RELAY_SECONDARY_KEY="${!relay_secondary_key:-}"
            export UPSTREAM_API_KEY="${!upstream_api_key}"

            # Non-secret config comes from the environment's tfvars (single source of truth).
            tfvars="{{ infra_dir }}/environments/{{ env }}.tfvars"
            get_tfvar() { grep -E "^[[:space:]]*$1[[:space:]]*=" "$tfvars" | sed -E 's/^[^=]*=[[:space:]]*"?([^"]*)"?.*/\1/'; }
            # List-valued tfvars (e.g. ["Production", "Sandbox"]) flatten to the
            # comma-separated string the relay parses: strip brackets/quotes/spaces.
            get_tfvar_csv() { grep -E "^[[:space:]]*$1[[:space:]]*=" "$tfvars" | sed -E 's/^[^=]*=//' | tr -d '[]" '; }
            export UPSTREAM_API_URL="$(get_tfvar upstream_api_url)"
            export APPLE_BUNDLE_ID="$(get_tfvar apple_bundle_id)"
            export APPLE_APP_APPLE_ID="$(get_tfvar apple_app_apple_id)"
            apple_envs="$(get_tfvar_csv apple_environments)"
            export APPLE_ENVIRONMENTS="${apple_envs:-Sandbox}"
            sandbox_budget="$(get_tfvar sandbox_monthly_credit_budget)"
            export SANDBOX_MONTHLY_CREDIT_BUDGET="${sandbox_budget:-25000}"

            grant_key_file="{{ relay_dir }}/config/grant/grant_public.pem"
            [ -f "$grant_key_file" ] && export GRANT_PUBLIC_KEY="$(cat "$grant_key_file")"
            cd {{ relay_dir }} && cargo run
            ;;
        *) echo "Unknown run target: {{ target }}"; exit 1 ;;
    esac

[doc('Clean the iOS build and derived data')]
clean env="staging":
    #!/usr/bin/env bash
    scheme=$([ "{{ env }}" = "staging" ] && echo "EiginDev" || echo "Eigin")
    xcodebuild -project {{ ios_dir }}/Eigin-iOS.xcodeproj \
        -scheme "$scheme" -destination '{{ dest }}' clean
    rm -rf ~/Library/Developer/Xcode/DerivedData/Eigin-iOS-*

# --- Infra ---

[doc('Manage infra (command: init | plan | deploy)')]
infra command env="staging":
    #!/usr/bin/env bash
    case "{{ command }}" in
        init)
            eval "$({{ tools }} infra tf-vars {{ env }})"
            cd {{ infra_dir }}
            terraform workspace select -or-create {{ env }} && terraform init
            ;;
        plan)
            eval "$({{ tools }} infra tf-vars {{ env }})"
            cd {{ infra_dir }}
            terraform workspace select -or-create {{ env }}
            terraform plan -var-file=environments/{{ env }}.tfvars
            ;;
        deploy)
            docker info > /dev/null 2>&1 || (echo "Docker daemon is not running. Start Docker Desktop and try again."; exit 1)
            if [ "{{ env }}" = "production" ]; then
                read -p "Deploy to production? [y/N] " confirm && [ "$confirm" = "y" ] || exit 1
            fi
            eval "$({{ tools }} infra tf-vars {{ env }})"
            cd {{ infra_dir }}
            terraform workspace select -or-create {{ env }}
            terraform apply -var-file=environments/{{ env }}.tfvars
            ;;
        *)
            echo "Unknown infra command: {{ command }}"
            exit 1
            ;;
    esac
