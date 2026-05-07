# Eigin

**A personal AI agent that's uniquely yours.**

Eigin is free, open-source, and local-first. Your chats, knowledge, and agent configuration live on your device. There is no Eigin account and no Eigin-hosted data. The only outgoing requests are the ones you allow.

### Your agent, your data
The agent persists across conversations. It has its own identity, knowledge, intents, and goals. Everything lives on-device. Uninstall and it's gone.

### Your choice of provider
Cloud or on-device. Connect to OpenAI, Anthropic, Google, Mistral, or any OpenAI-compatible API with your own key - or run fully on-device with local models. No subscriptions, no lock-in.

### Voice as a first-class input
Dictate anything. Or use live call mode for a hands-free, half-duplex conversation. Speech recognition runs on-device.

### Deeply integrated
Calendar, reminders, location, email, and more built in. Add any MCP server to connect external services. Web search runs through Eigin Relay: a free, anonymous bridge that never sees your chat content.

### Open and extensible
No premium tier, no tracking, no hidden incentives.

## Build

**iOS:** Xcode (`xcode-select -s /Applications/Xcode.app/Contents/Developer`), [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`), [SwiftFormat](https://github.com/nicklockwood/SwiftFormat) (`brew install swiftformat`)

**Relay:** Rust and Cargo via [rustup](https://rustup.rs)

**Relay deployment:** [Terraform](https://developer.hashicorp.com/terraform/install) (`brew install terraform`), [Scaleway CLI](https://github.com/scaleway/scaleway-cli) (`brew install scw`). Run `scw init` to authenticate — the Terraform provider reads your credentials from the scw config automatically.

```
make generate     # Regenerate .xcodeproj from project.yml

make ios-build    # Generate + build iOS
make ios-test     # Generate + run iOS unit tests
make ios-open     # Generate + open in Xcode
make ios-clean    # Clean iOS build artifacts

make relay-build  # Build relay (cargo build --release)
make relay-test   # Run relay tests
make relay-run    # Run relay locally

make infra-init   # First-time Terraform setup (downloads providers)
make infra-plan   # Preview infrastructure changes
make infra-deploy # Apply infrastructure changes (builds + pushes image)

make format       # Format all code (Swift + Rust)
make lint         # Lint without modifying
make hooks        # Install git hooks
make test         # Run all tests
```

## License

Open source. See [LICENSE](LICENSE) for details.
