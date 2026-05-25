# Eigin

**Your personal AI - running on your own hardware, under your control.**

To get real value from AI, you have to let it know you. The more it knows, the more useful it becomes - and the more personal it gets. Eigin is built so you can actually share: no questions about who owns your words, no concern that your thoughts are training someone else's model.

You bring the model. Eigin holds everything it learns about you, on your device.

## How it works

**You bring the AI, Eigin holds the context.**
Connect any model you trust - OpenAI, Anthropic, Google, Mistral, any OpenAI-compatible API, or a local model on your own silicon. Chats, knowledge, and agent configuration are stored locally. Uninstall and it's gone.

**It starts blank.**
No assumptions, no agenda. The agent persists across conversations and learns from you - knowledge, intents, and goals shaped by use.

**Deeply integrated.**
Calendar, reminders, location, email, and more built in. Add any MCP server to extend it. Web search runs through Eigin Relay - a narrow, anonymous bridge that never sees your chat content.

**Built for people, not platforms.**
Open source with European roots. We fund the mission by offering sovereign AI to institutions that need the same guarantees you do.

## Build

**iOS:**

- Xcode — `xcode-select -s /Applications/Xcode.app/Contents/Developer`
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) — `brew install xcodegen`
- [SwiftFormat](https://github.com/nicklockwood/SwiftFormat) — `brew install swiftformat`

**Relay:**

- [Rust and Cargo](https://rustup.rs) — via rustup

**Relay deployment:**

- [Terraform](https://developer.hashicorp.com/terraform/install) — `brew install terraform`
- [Scaleway CLI](https://github.com/scaleway/scaleway-cli) — `brew install scw`, then `scw init` to authenticate (the Terraform provider reads credentials from the scw config automatically)

**Command runner:**

- [just](https://just.systems) — `brew install just`

After cloning, run:

```
just hooks      # Install git hooks (one-time)
just generate   # Regenerate the project
```

and then:

```
just build      # Build all targets
just test       # Run all tests
just format     # Auto-format all code
```

Run `just --list` to see all available commands.

## License

Open source. See [LICENSE](LICENSE) for details.
