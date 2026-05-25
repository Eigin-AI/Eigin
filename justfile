set dotenv-load := true

ios_dir   := "src/eigin_ios"
simulator := "iPhone 17 Pro"
dest      := "platform=iOS Simulator,name=" + simulator
relay_dir := "src/eigin_relay"
infra_dir := "infra/scaleway"
log_dir   := "logs"
tools     := "cargo run --quiet --manifest-path tools/Cargo.toml --"

# --- Cross-cutting ---

generate:
    {{ tools }} generate

format:
    {{ tools }} format

lint:
    {{ tools }} lint

hooks:
    {{ tools }} hooks install

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
test target="all" env="staging" verbose="false":
    @if [ "{{ target }}" = "ios"   ] || [ "{{ target }}" = "all" ]; then just _test-ios {{ env }} {{ verbose }}; fi
    @if [ "{{ target }}" = "relay" ] || [ "{{ target }}" = "all" ]; then just _test-relay {{ verbose }}; fi

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
build target="all" env="staging" verbose="false":
    @if [ "{{ target }}" = "ios"   ] || [ "{{ target }}" = "all" ]; then just _build-ios {{ env }} {{ verbose }}; fi
    @if [ "{{ target }}" = "relay" ] || [ "{{ target }}" = "all" ]; then just _build-relay {{ verbose }}; fi

# --- Run / Clean / Open ---

run target env="staging":
    #!/usr/bin/env bash
    case "{{ target }}" in
        relay)
            [ -f .env ] && source .env
            suffix=$(echo "{{ env }}" | tr '[:lower:]' '[:upper:]')
            mojeek_key="MOJEEK_API_KEY_${suffix}"
            relay_key="EIGIN_RELAY_KEY_${suffix}"
            export MOJEEK_API_KEY="${!mojeek_key}"
            export EIGIN_RELAY_KEY="${!relay_key}"
            cd {{ relay_dir }} && cargo run
            ;;
        *) echo "Unknown run target: {{ target }}"; exit 1 ;;
    esac

clean env="staging":
    #!/usr/bin/env bash
    scheme=$([ "{{ env }}" = "staging" ] && echo "EiginDev" || echo "Eigin")
    xcodebuild -project {{ ios_dir }}/Eigin-iOS.xcodeproj \
        -scheme "$scheme" -destination '{{ dest }}' clean
    rm -rf ~/Library/Developer/Xcode/DerivedData/Eigin-iOS-*

# --- Infra ---

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
