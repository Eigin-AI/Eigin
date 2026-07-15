import Foundation

/// Response shape for `posts.getAllPosts`.
struct AulaPostsResponse: Decodable {
    struct Payload: Decodable { let posts: [Post] }
    struct Post: Decodable {
        let id: Int
        let title: String?
        let content: AulaRichTextFragment?
        let ownerProfile: AulaProfileFragment?
        let timestamp: String?
    }

    let data: Payload
}
