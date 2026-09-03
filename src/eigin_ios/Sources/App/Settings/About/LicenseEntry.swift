import Foundation

/// A third-party package shipped in the app. Mirrors `LICENSES/swift-packages.md`
/// at the repo root: add a row there and here together.
struct LicenseEntry: Identifiable {
    /// The license family the package ships under. Determines the license text
    /// shown in the app.
    enum Kind: String {
        case mit = "MIT"
        case apache2 = "Apache 2.0"
        case bsd2 = "BSD 2-Clause"
        case ccBy4 = "CC BY 4.0"
        case gemma = "Gemma Terms of Use"

        func licenseText() -> String {
            switch self {
            case .mit: LicenseTexts.mit
            case .apache2: LicenseTexts.apache2
            case .bsd2: LicenseTexts.bsd2
            case .ccBy4: LicenseTexts.ccBy4
            case .gemma: LicenseTexts.gemma
            }
        }
    }

    let name: String
    /// Upstream repository, opened from the app when present.
    let repository: URL?
    /// Pinned version, when the package has one, e.g. "2.4.0".
    let version: String?
    /// How the package is included when there's no plain version, e.g.
    /// "Vendored & modified" or "Pinned by commit".
    let distribution: String?
    let kind: Kind
    /// The copyright line from the package's own LICENSE file.
    let copyright: String
    var id: String {
        name
    }

    /// Short provenance for the list row: a version, or how it's included.
    var provenance: String {
        version ?? distribution ?? ""
    }

    /// Subtitle under the package name in the list, e.g. "Vendored & modified · MIT".
    var rowSubtitle: String {
        let provenance = provenance
        return provenance.isEmpty ? kind.rawValue : "\(provenance) · \(kind.rawValue)"
    }

    /// Full provenance for the detail page, e.g. "Version 0.7.3 · Apache 2.0"
    /// or "Pinned by commit · MIT".
    var detailProvenance: String {
        var parts: [String] = []
        if let version { parts.append("\(Localized.Settings.About.licenseVersion) \(version)") }
        if let distribution { parts.append(distribution) }
        parts.append(kind.rawValue)
        return parts.joined(separator: " · ")
    }

    /// Every package distributed inside the app binary, in display order.
    static let all: [LicenseEntry] = [
        LicenseEntry(
            name: "SwiftStreamingMarkdown",
            repository: URL(string: "https://github.com/microsoft/SwiftStreamingMarkdown"),
            version: nil,
            distribution: "Vendored & modified",
            kind: .mit,
            copyright: "Copyright (c) Microsoft Corporation."
        ),
        LicenseEntry(
            name: "swift-markdown",
            repository: URL(string: "https://github.com/swiftlang/swift-markdown"),
            version: "0.7.3",
            distribution: nil,
            kind: .apache2,
            copyright: "Copyright (c) 2021-2023 Apple Inc. and the Swift Project authors."
        ),
        LicenseEntry(
            name: "iosMath",
            repository: URL(string: "https://github.com/junyan72/iosMath"),
            version: nil,
            distribution: "Pinned by commit",
            kind: .mit,
            copyright: "Copyright (c) 2013 MathChat"
        ),
        LicenseEntry(
            name: "HighlightSwift",
            repository: URL(string: "https://github.com/appstefan/HighlightSwift"),
            version: nil,
            distribution: "Pinned by commit",
            kind: .mit,
            copyright: "Copyright (c) 2023 Stefan Britton"
        ),
        LicenseEntry(
            name: "MCP Swift SDK",
            repository: URL(string: "https://github.com/modelcontextprotocol/swift-sdk"),
            version: "0.11.0",
            distribution: nil,
            kind: .apache2,
            copyright: "Copyright The MCP Swift SDK Authors"
        ),
        LicenseEntry(
            name: "Factory",
            repository: URL(string: "https://github.com/hmlongco/Factory"),
            version: "2.4.0",
            distribution: nil,
            kind: .mit,
            copyright: "Copyright (c) 2022 Michael Long"
        ),
        LicenseEntry(
            name: "FluidAudio",
            repository: URL(string: "https://github.com/42futures/FluidAudio"),
            version: nil,
            distribution: "Pinned to a branch",
            kind: .apache2,
            copyright: "Copyright FluidInference"
        ),
        LicenseEntry(
            name: "swift-transformers",
            repository: URL(string: "https://github.com/huggingface/swift-transformers"),
            version: "1.3.0",
            distribution: nil,
            kind: .apache2,
            copyright: "Copyright Hugging Face, Inc."
        ),
        LicenseEntry(
            name: "SwiftMail",
            repository: URL(string: "https://github.com/Cocoanetics/SwiftMail"),
            version: "1.8.0",
            distribution: nil,
            kind: .bsd2,
            copyright: "Copyright (c) 2025, Oliver Drobnik"
        ),
        LicenseEntry(
            name: "swift-nio-imap",
            repository: URL(string: "https://github.com/apple/swift-nio-imap"),
            version: nil,
            distribution: "Resolved transitively",
            kind: .apache2,
            copyright: "Copyright 2020 The SwiftNIO Project"
        ),
        LicenseEntry(
            name: "swift-nio-ssl",
            repository: URL(string: "https://github.com/apple/swift-nio-ssl"),
            version: nil,
            distribution: "Resolved transitively",
            kind: .apache2,
            copyright: "Copyright 2017, 2018 The SwiftNIO Project"
        ),
        LicenseEntry(
            name: "LiteRT-LM",
            repository: URL(string: "https://github.com/google-ai-edge/LiteRT-LM"),
            version: "0.16.0",
            distribution: "Vendored",
            kind: .apache2,
            copyright: "Copyright Google LLC"
        ),
    ]

    /// Every model whose weights the app downloads, in display order.
    /// Mirrors `LICENSES/ml-models.md`.
    static let models: [LicenseEntry] = [
        LicenseEntry(
            name: "PocketTTS",
            repository: URL(string: "https://huggingface.co/kyutai/pocket-tts"),
            version: nil,
            distribution: "Downloaded on demand",
            kind: .ccBy4,
            copyright: "Copyright Kyutai"
        ),
        LicenseEntry(
            name: "Plapre Pico",
            repository: URL(string: "https://huggingface.co/syvai/plapre-pico"),
            version: nil,
            distribution: "Downloaded on demand",
            kind: .ccBy4,
            copyright: "Copyright syv.ai"
        ),
        LicenseEntry(
            name: "Gemma 4 E2B",
            repository: URL(
                string: "https://huggingface.co/litert-community/gemma-4-E2B-it-litert-lm"
            ),
            version: nil,
            distribution: "Downloaded on demand",
            kind: .gemma,
            copyright: "Copyright Google LLC"
        ),
    ]
}
