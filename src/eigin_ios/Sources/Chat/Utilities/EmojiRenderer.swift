import UIKit

enum EmojiRenderer {
    /// Renders an emoji string into a square `UIImage` of the given point size.
    static func image(for emoji: String, size: CGFloat = 100) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: size, height: size))
        return renderer.image { _ in
            let attributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: size * 0.8),
            ]
            let string = emoji as NSString
            let textSize = string.size(withAttributes: attributes)
            let origin = CGPoint(
                x: (size - textSize.width) / 2,
                y: (size - textSize.height) / 2
            )
            string.draw(at: origin, withAttributes: attributes)
        }
    }
}
