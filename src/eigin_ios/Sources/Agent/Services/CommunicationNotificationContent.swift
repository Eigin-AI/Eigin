import Intents
import UserNotifications

/// Builds Communication Notifications with the agent's emoji as a circular avatar.
enum CommunicationNotificationContent {
    /// Category identifier registered in EiginApp.init().
    static let categoryIdentifier = "AGENT_MESSAGE"

    /// Upgrades a notification to a Communication Notification with the agent's
    /// emoji as a circular avatar. Returns the original content on failure.
    static func upgrade(
        _ content: UNMutableNotificationContent,
        agentName: String,
        agentEmoji: String?,
        agentID: UUID
    ) async -> UNNotificationContent {
        content.categoryIdentifier = categoryIdentifier

        let handle = INPersonHandle(value: agentID.uuidString, type: .unknown)

        var personImage: INImage?
        var tempAvatarURL: URL?
        if let emoji = agentEmoji {
            let rendered = EmojiRenderer.image(for: emoji)
            if let pngData = rendered.pngData() {
                // Write to temp file — INImage(imageData:) is unreliable
                // for Communication Notification avatars on some iOS versions.
                let url = FileManager.default.temporaryDirectory
                    .appendingPathComponent("agent-avatar-\(agentID.uuidString).png")
                try? pngData.write(to: url)
                personImage = INImage(url: url)
                tempAvatarURL = url
            }
        }

        var nameComponents = PersonNameComponents()
        nameComponents.nickname = agentName
        let sender = INPerson(
            personHandle: handle,
            nameComponents: nameComponents,
            displayName: agentName,
            image: personImage,
            contactIdentifier: nil,
            customIdentifier: agentID.uuidString,
            isMe: false,
            suggestionType: .none
        )

        let intent = INSendMessageIntent(
            recipients: nil,
            outgoingMessageType: .outgoingMessageText,
            content: content.body,
            speakableGroupName: INSpeakableString(spokenPhrase: agentName),
            conversationIdentifier: agentID.uuidString,
            serviceName: nil,
            sender: sender,
            attachments: nil
        )
        if let personImage {
            intent.setImage(personImage, forParameterNamed: \.sender)
        }

        let interaction = INInteraction(intent: intent, response: nil)
        interaction.direction = .incoming

        do {
            try await interaction.donate()
            let updated = try content.updating(from: intent)

            if let tempAvatarURL {
                try? FileManager.default.removeItem(at: tempAvatarURL)
            }

            return updated
        } catch {
            AppLogger.error(
                "Failed to build communication notification: \(private: error.localizedDescription)",
                category: .backgroundPrompt
            )

            if let tempAvatarURL {
                try? FileManager.default.removeItem(at: tempAvatarURL)
            }

            return content
        }
    }
}
