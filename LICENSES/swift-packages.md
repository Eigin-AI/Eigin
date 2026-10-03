# Swift Package Licenses

| Package | Repository | Version | License |
|---------|-----------|---------|---------|
| SwiftStreamingMarkdown (vendored & modified) | https://github.com/microsoft/SwiftStreamingMarkdown | see [swift-streaming-markdown.md](swift-streaming-markdown.md) | MIT |
| swift-markdown | https://github.com/swiftlang/swift-markdown | 0.7.3 | Apache 2.0 |
| SwiftSoup | https://github.com/scinfu/SwiftSoup | from 2.13.0, see project.yml | MIT |
| iosMath | https://github.com/junyan72/iosMath | pinned by commit, see project.yml | MIT |
| HighlightSwift | https://github.com/appstefan/highlightswift | pinned by commit, see project.yml | MIT |
| MCP Swift SDK | https://github.com/modelcontextprotocol/swift-sdk | 0.11.0 | Apache 2.0 (relicensing from MIT in progress upstream) |
| Factory | https://github.com/hmlongco/Factory | 2.4.0 | MIT |
| FluidAudio | https://github.com/42futures/FluidAudio | feature/pocket-tts-sessions | Apache 2.0 |
| swift-transformers | https://github.com/huggingface/swift-transformers | 1.3.0 | Apache 2.0 |
| SwiftMail | https://github.com/Cocoanetics/SwiftMail | 1.8.0 (pinned by commit, see project.yml) | BSD 2-Clause |
| swift-nio-imap (SwiftMail dependency) | https://github.com/apple/swift-nio-imap | resolved transitively | Apache 2.0 |
| swift-nio-ssl (SwiftMail dependency) | https://github.com/apple/swift-nio-ssl | resolved transitively | Apache 2.0 |
| LiteRT-LM (vendored, `src/eigin_ios/Packages/LiteRTLM`) | https://github.com/google-ai-edge/LiteRT-LM | 0.16.0 | Apache 2.0 |

## Notes

- License types listed are as of the date this file was last updated (2026-07-04).
- Verify against each repository when upgrading to a new version.
- LiteRT-LM is vendored as a local package rather than a remote SPM dependency (see `src/eigin_ios/Packages/LiteRTLM/README.md`)
- SwiftStreamingMarkdown's streaming-critical rendering core is vendored (and heavily modified) in-source under `src/eigin_ios/Sources/Core/Design/Markdown/Rendering` rather than consumed as an SPM dependency. Full attribution and the MIT license text are in [swift-streaming-markdown.md](swift-streaming-markdown.md). It depends only on Apple's swift-markdown and iosMath.
