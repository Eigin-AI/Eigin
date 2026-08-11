import Foundation

struct LatexAttachmentData: Codable {
    let latex: String
    let fontSize: CGFloat
    let lightTextColor: String
    let darkTextColor: String
}
