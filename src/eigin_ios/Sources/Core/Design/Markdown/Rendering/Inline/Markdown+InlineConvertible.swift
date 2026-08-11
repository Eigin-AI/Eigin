import Foundation
import Markdown
import SwiftUI
import UniformTypeIdentifiers

extension Markdown.Text: InlineConvertible {
    func convert(
        attributeContainer: NSAttributeContainer,
        config: MarkdownRenderConfig
    ) -> NSMutableAttributedString {
        let result = NSMutableAttributedString(string: string).mergingAttributes(attributeContainer)
        // Don't autolink inside an existing link (e.g. the text of `[text](url)`).
        if attributeContainer[.link] == nil {
            result.applyAutolinks(config: config)
        }
        return result
    }
}

/// Detects bare URLs and email addresses so they render as tappable links.
/// swift-markdown does not enable cmark's autolink extension, so plain URLs /
/// emails arrive as text; we link them ourselves.
private let autolinkDetector = try? NSDataDetector(
    types: NSTextCheckingResult.CheckingType.link.rawValue
)

private extension NSMutableAttributedString {
    /// Styles any detected URLs / emails in the receiver as links, using the
    /// same inline link styling as explicit markdown links.
    func applyAutolinks(config: MarkdownRenderConfig) {
        guard let detector = autolinkDetector, length > 0 else { return }
        let range = NSRange(location: 0, length: length)
        for match in detector.matches(in: string, options: [], range: range) {
            guard let url = match.url else { continue }
            addAttribute(.link, value: url, range: match.range)
            addAttribute(.font, value: config.inlineStyle.linkTextFont, range: match.range)
            addAttribute(
                .foregroundColor,
                value: MDColor(config.inlineStyle.linkTextColor),
                range: match.range
            )
            addAttribute(
                .underlineStyle,
                value: config.inlineStyle.linkUnderlineStyle.rawValue,
                range: match.range
            )
        }
    }
}

extension Markdown.Emphasis: InlineConvertible {
    func convert(
        attributeContainer: NSAttributeContainer,
        config: MarkdownRenderConfig
    ) -> NSMutableAttributedString {
        let str = NSMutableAttributedString()
        var newContainer = attributeContainer

        if let currentTextFonts = attributeContainer[.typography] as? TextFonts {
            let currentFont = attributeContainer[.font] as? MDFont
            newContainer[.font] = currentFont
                .map { currentTextFonts.italicize(font: $0) } ?? currentTextFonts.italic
        } else {
            newContainer[.font] = config.paragraphStyle.textFonts.italic ?? config.paragraphStyle
                .textFonts.normal
        }
        for convertible in inlineConvertibleChildren {
            str.append(convertible.convert(attributeContainer: newContainer, config: config))
        }
        return str
    }
}

extension Markdown.Strong: InlineConvertible {
    func convert(
        attributeContainer: NSAttributeContainer,
        config: MarkdownRenderConfig
    ) -> NSMutableAttributedString {
        let str = NSMutableAttributedString()
        var newContainer = attributeContainer
        if let currentTextFonts = attributeContainer[.typography] as? TextFonts {
            let currentFont = attributeContainer[.font] as? MDFont
            newContainer[.font] = currentFont
                .map { currentTextFonts.bold(font: $0) } ?? currentTextFonts.bold
        } else {
            newContainer[.font] = config.paragraphStyle.textFonts.bold ?? config.paragraphStyle
                .textFonts.normal
        }
        if parent is Paragraph, indexInParent == 0, parent?.parent is ListItem,
           parent?.indexInParent == 0
        {
            newContainer[.foregroundColor] = MDColor(config.inlineStyle.boldTextColor)
        }
        for convertible in inlineConvertibleChildren {
            str.append(convertible.convert(attributeContainer: newContainer, config: config))
        }
        return str
    }
}

extension Markdown.Strikethrough: InlineConvertible {
    func convert(
        attributeContainer: NSAttributeContainer,
        config: MarkdownRenderConfig
    ) -> NSMutableAttributedString {
        let str = NSMutableAttributedString()
        var container = attributeContainer
        container[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
        container[.strikethroughColor] = container[.foregroundColor]
        for convertible in inlineConvertibleChildren {
            str.append(convertible.convert(attributeContainer: container, config: config))
        }
        return str
    }
}

extension Markdown.Link: InlineConvertible {
    func convert(
        attributeContainer: NSAttributeContainer,
        config: MarkdownRenderConfig
    ) -> NSMutableAttributedString {
        var container = attributeContainer

        func buildAttributedString() -> NSMutableAttributedString {
            let str = NSMutableAttributedString()
            for convertible in inlineConvertibleChildren {
                str.append(convertible.convert(attributeContainer: container, config: config))
            }
            return str
        }

        guard let destination,
              let url = URL.fromMixedEncodingString(destination)
        else {
            // Not a valid URL, return plain text
            return buildAttributedString()
        }

        container[.link] = url
        container[.font] = config.inlineStyle.linkTextFont
        container[.foregroundColor] = MDColor(config.inlineStyle.linkTextColor)
        container[.underlineStyle] = config.inlineStyle.linkUnderlineStyle.rawValue
        return buildAttributedString()
    }
}

extension Markdown.SoftBreak: InlineConvertible {
    func convert(
        attributeContainer: NSAttributeContainer,
        config: MarkdownRenderConfig
    ) -> NSMutableAttributedString {
        NSMutableAttributedString(string: "\n").mergingAttributes(attributeContainer)
    }
}

extension Markdown.LineBreak: InlineConvertible {
    func convert(
        attributeContainer: NSAttributeContainer,
        config: MarkdownRenderConfig
    ) -> NSMutableAttributedString {
        NSMutableAttributedString(string: "\n").mergingAttributes(attributeContainer)
    }
}

extension Markdown.InlineCode: InlineConvertible {
    var isInlineLatex: Bool {
        code.hasPrefix(LaTexPreProcessorImpl.inlineCodePrefix) && code
            .hasSuffix(LaTexPreProcessorImpl.inlineCodeSuffix)
    }

    func convert(
        attributeContainer: NSAttributeContainer,
        config: MarkdownRenderConfig
    ) -> NSMutableAttributedString {
        var codeContent = code
        if isInlineLatex {
            codeContent = String(code
                .dropFirst(LaTexPreProcessorImpl.inlineCodePrefix.count)
                .dropLast(LaTexPreProcessorImpl.inlineCodeSuffix.count))
            let font = attributeContainer[NSAttributedString.Key.font] as? MDFont ?? config
                .paragraphStyle.textFonts.normal
            let textColor = MDColor(config.paragraphStyle.textColor)
#if canImport(UIKit)
            let lightHex = textColor
                .resolvedColor(with: UITraitCollection(userInterfaceStyle: .light)).toHexString()
            let darkHex = textColor
                .resolvedColor(with: UITraitCollection(userInterfaceStyle: .dark)).toHexString()
#elseif canImport(AppKit)
            let lightHex = textColor.resolvedForAppearance(.aqua).toHexString()
            let darkHex = textColor.resolvedForAppearance(.darkAqua).toHexString()
#endif
            let attachmentData = LatexAttachmentData(
                latex: codeContent,
                fontSize: font.pointSize,
                lightTextColor: lightHex,
                darkTextColor: darkHex
            )
            let encoder = JSONEncoder()
            if let payload = try? encoder.encode(attachmentData) {
                let attachment = NSTextAttachment(data: payload, ofType: UTType.data.identifier)
                return NSMutableAttributedString(attachment: attachment)
            }
        }
        var container = attributeContainer
        container[.font] = config.inlineStyle.codeTextFont
        container[.foregroundColor] = MDColor(config.inlineStyle.codeTextColor)
        container[.backgroundColor] = MDColor(config.inlineStyle.codeBackgroundColor)
        container[.underlineStyle] = NSUnderlineStyle.patternDot.rawValue
        container[.underlineColor] = MDColor(config.inlineStyle.codeUnderlineColor)
        return NSMutableAttributedString(string: codeContent).mergingAttributes(container)
    }
}

extension Markdown.Table.Cell: InlineConvertible {
    func convert(
        attributeContainer: NSAttributeContainer,
        config: MarkdownRenderConfig
    ) -> NSMutableAttributedString {
        let str = NSMutableAttributedString()
        for convertible in inlineConvertibleChildren {
            str.append(convertible.convert(attributeContainer: attributeContainer, config: config))
        }
        return str
    }
}
