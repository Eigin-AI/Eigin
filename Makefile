-include .env

VERBOSE ?= 0

# --- iOS ---
IOS_DIR = src/eigin_ios
SIMULATOR = iPhone 17 Pro
SCHEME = Eigin
DESTINATION = platform=iOS Simulator,name=$(SIMULATOR)

# --- Relay ---
RELAY_DIR = src/eigin_relay
RELAY_REGION = $(or $(GCP_REGION),europe-west1)
RELAY_IMAGE = $(RELAY_REGION)-docker.pkg.dev/$(GCP_PROJECT_ID)/eigin/relay

# --- Logging ---
LOG_DIR = logs
LOG_WRAPPER = scripts/log-wrapper.sh

.PHONY: generate ios-build ios-test ios-clean ios-open \
	relay-build relay-test relay-run relay-deploy relay-docker \
	format lint test docs docs-serve

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

relay-docker:
	docker build -t eigin-relay $(RELAY_DIR)

relay-deploy:
ifndef GCP_PROJECT_ID
	$(error GCP_PROJECT_ID is not set)
endif
	docker build --platform linux/amd64 -t $(RELAY_IMAGE):latest $(RELAY_DIR)
	docker push $(RELAY_IMAGE):latest
	gcloud run deploy eigin-relay \
		--project $(GCP_PROJECT_ID) \
		--image $(RELAY_IMAGE):latest \
		--region $(RELAY_REGION) \
		--set-env-vars MOJEEK_API_KEY=$${MOJEEK_API_KEY},EIGIN_RELAY_KEY=$${EIGIN_RELAY_KEY},POOL_FILE_PATH=/tmp/pool.json \
		--allow-unauthenticated \
		--port 8080 \
		--memory 128Mi \
		--min-instances 0 \
		--max-instances 1
