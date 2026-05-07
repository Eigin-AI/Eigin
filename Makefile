-include .env
# .env uses `export VAR=value` syntax so all variables propagate to child
# processes (including xcodegen). For direct terraform use, see scripts/tf-env.sh.

VERBOSE ?= 0

# --- iOS ---
IOS_DIR = src/eigin_ios
SIMULATOR = iPhone 17 Pro
SCHEME ?= Eigin
DESTINATION = platform=iOS Simulator,name=$(SIMULATOR)

# --- Relay ---
RELAY_DIR = src/eigin_relay

# --- Infra ---
INFRA_DIR = infra/scaleway
ENV ?= staging
# scripts/tf-env.sh resolves per-env TF_VAR_* exports from .env.
# Run `eval "$(scripts/tf-env.sh staging)"` to load them for direct terraform use.
TF_ENV = eval "$$(scripts/tf-env.sh $(ENV))"

# --- Logging ---
LOG_DIR = logs
LOG_WRAPPER = scripts/log-wrapper.sh

.PHONY: generate ios-build ios-test ios-clean ios-open \
	relay-build relay-test relay-run \
	infra-init infra-plan infra-deploy \
	format lint test docs docs-serve hooks

# --- Cross-cutting ---
generate:
	cd $(IOS_DIR) && xcodegen generate
	xcode-build-server config -project $(IOS_DIR)/Eigin-iOS.xcodeproj -scheme $(SCHEME)
	cd $(IOS_DIR) && swift Scripts/GenerateLocalized.swift Sources/Localizable.xcstrings Sources/Core/Localized.swift
	swiftformat $(IOS_DIR)/Sources/Core/Localized.swift

format:
	swiftformat $(IOS_DIR)/Sources $(IOS_DIR)/Tests $(IOS_DIR)/Scripts
	cargo fmt --manifest-path $(RELAY_DIR)/Cargo.toml

lint:
	swiftformat --lint $(IOS_DIR)/Sources $(IOS_DIR)/Tests $(IOS_DIR)/Scripts
	cargo fmt --manifest-path $(RELAY_DIR)/Cargo.toml --check
	cd $(IOS_DIR) && swift Scripts/ValidateLocalized.swift Sources Sources/Core/Localized.swift

hooks:
	@ln -sf ../../scripts/hooks/pre-commit-swiftformat.sh .git/hooks/pre-commit
	@ln -sf ../../scripts/hooks/commit-msg-conventional.sh .git/hooks/commit-msg
	@echo "Hooks installed."

test: ios-test relay-test

docs:
	cd docs && mdbook build

docs-serve:
	cd docs && mdbook serve

# --- iOS ---
ios-build: generate
	@if [ "$(VERBOSE)" = "1" ]; then \
		xcodebuild -project "$(IOS_DIR)/Eigin-iOS.xcodeproj" \
			-scheme "$(SCHEME)" \
			-destination '$(DESTINATION)' \
			build; \
	else \
		"$(LOG_WRAPPER)" "$(LOG_DIR)/ios-build.log" "Building Eigin for iOS" \
			xcodebuild -project "$(IOS_DIR)/Eigin-iOS.xcodeproj" \
				-scheme "$(SCHEME)" \
				-destination '$(DESTINATION)' \
				build; \
	fi

ios-test: generate
	@if [ "$(VERBOSE)" = "1" ]; then \
		xcodebuild -project "$(IOS_DIR)/Eigin-iOS.xcodeproj" \
			-scheme "$(SCHEME)" \
			-destination '$(DESTINATION)' \
			-skip-testing:EiginTests/ProviderIntegrationTests \
			test; \
	else \
		"$(LOG_WRAPPER)" "$(LOG_DIR)/ios-test.log" "Running iOS tests" \
			xcodebuild -project "$(IOS_DIR)/Eigin-iOS.xcodeproj" \
				-scheme "$(SCHEME)" \
				-destination '$(DESTINATION)' \
				-skip-testing:EiginTests/ProviderIntegrationTests \
				test; \
	fi

ios-clean:
	xcodebuild -project $(IOS_DIR)/Eigin-iOS.xcodeproj \
		-scheme $(SCHEME) \
		-destination '$(DESTINATION)' \
		clean
	rm -rf ~/Library/Developer/Xcode/DerivedData/Eigin-iOS-*

ios-open: generate
	open $(IOS_DIR)/Eigin-iOS.xcodeproj

# --- Relay ---
relay-build:
	@if [ "$(VERBOSE)" = "1" ]; then \
		cd $(RELAY_DIR) && cargo build --release; \
	else \
		"$(LOG_WRAPPER)" "$(LOG_DIR)/relay-build.log" "Building Eigin relay" \
			sh -c 'cd $(RELAY_DIR) && cargo build --release'; \
	fi

relay-test:
	@if [ "$(VERBOSE)" = "1" ]; then \
		cd $(RELAY_DIR) && cargo test; \
	else \
		"$(LOG_WRAPPER)" "$(LOG_DIR)/relay-test.log" "Running relay tests" \
			sh -c 'cd $(RELAY_DIR) && cargo test'; \
	fi

relay-run:
	cd $(RELAY_DIR) && cargo run

infra-init:
	$(TF_ENV) && cd $(INFRA_DIR) && \
		terraform workspace select -or-create $(ENV) && terraform init

infra-plan:
	$(TF_ENV) && cd $(INFRA_DIR) && \
		terraform workspace select -or-create $(ENV) && \
		terraform plan -var-file=environments/$(ENV).tfvars

infra-deploy:
	@docker info > /dev/null 2>&1 || (echo "Docker daemon is not running. Start Docker Desktop and try again."; exit 1)
	@if [ "$(ENV)" = "production" ]; then \
		read -p "Deploy to production? [y/N] " confirm && [ "$$confirm" = "y" ] || exit 1; \
	fi
	$(TF_ENV) && cd $(INFRA_DIR) && \
		terraform workspace select -or-create $(ENV) && \
		terraform apply -var-file=environments/$(ENV).tfvars
