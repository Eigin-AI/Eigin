import Foundation

/// Response shape for `profiles.getProfilesByLogin`.
struct AulaProfilesResponse: Decodable {
    struct Payload: Decodable { let profiles: [Profile] }
    struct Profile: Decodable {
        let children: [Child]?
        /// The guardian's own institution-profile memberships — separate
        /// from each child's, but combined with them to scope
        /// `posts.getAllPosts` (see `DefaultAulaProvider.fetchPosts`).
        let institutionProfiles: [InstitutionProfile]?
    }

    struct Child: Decodable {
        let id: Int
        let name: String?
        let institutionProfile: InstitutionProfile?
    }

    struct InstitutionProfile: Decodable {
        let id: Int
        let institutionName: String?
    }

    let data: Payload
}
