import Foundation

/// Response shape for `messaging.getThreads`.
struct AulaThreadsResponse: Decodable {
    struct Payload: Decodable { let threads: [Thread] }
    struct Thread: Decodable {
        let id: Int
        let subject: String?
        let read: Bool?
        let latestMessage: AulaMessageFragment?
    }

    let data: Payload
}

/// Response shape for `messaging.getMessagesForThread`.
struct AulaThreadMessagesResponse: Decodable {
    struct Payload: Decodable {
        let subject: String?
        let messages: [AulaMessageFragment]
    }

    let data: Payload
}

/// A single message within a thread, as Aula's API returns it.
struct AulaMessageFragment: Decodable {
    let text: AulaRichTextFragment?
    let sender: AulaProfileFragment?
    let sendDateTime: String?
}
