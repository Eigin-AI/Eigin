# Swift Package Licenses

| Package | Repository | Version | License |
|---------|-----------|---------|---------|
| Textual | https://github.com/42futures/textual | main | MIT |
| MCP Swift SDK | https://github.com/modelcontextprotocol/swift-sdk | 0.11.0 | MIT |
| Factory | https://github.com/hmlongco/Factory | 2.4.0 | MIT |
| FluidAudio | https://github.com/42futures/FluidAudio | feature/pocket-tts-sessions | Apache 2.0 |
| swift-transformers | https://github.com/huggingface/swift-transformers | 1.3.0 | Apache 2.0 |
| SwiftMail | https://github.com/Cocoanetics/SwiftMail | 1.8.0 (pinned by commit, see project.yml) | BSD 2-Clause |
| swift-nio-imap (SwiftMail dependency) | https://github.com/apple/swift-nio-imap | resolved transitively | Apache 2.0 |
| swift-nio-ssl (SwiftMail dependency) | https://github.com/apple/swift-nio-ssl | resolved transitively | Apache 2.0 |
| LiteRT-LM (vendored, `src/eigin_ios/Packages/LiteRTLM`) | https://github.com/google-ai-edge/LiteRT-LM | 0.12.0 | Apache 2.0 |

## Notes

- License types listed are as of the date this file was last updated (2026-07-04).
- Verify against each repository when upgrading to a new version.
- LiteRT-LM is vendored as a local package rather than a remote SPM dependency (see `src/eigin_ios/Packages/LiteRTLM/README.md`)
