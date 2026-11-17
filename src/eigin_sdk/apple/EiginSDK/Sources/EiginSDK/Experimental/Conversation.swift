import EiginSDKBindings

public extension EiginSDK.Experimental {
    /// Request-local conversation preparation before attachment resolution and inference.
    enum Conversation {
        public typealias PreparationError = ConversationPreparationError
        public typealias Message = ConversationMessage
        public typealias AttachmentReference = ConversationAttachmentReference
        public typealias Selection = SelectedConversation
        public typealias Options = ConversationPreparationOptions
        public typealias PreparedMessage = PreparedConversationMessage
        public typealias Origin = PreparedConversationOrigin

        /// Selects active history and assigns original snapshot indices.
        public static func select(_ history: [Message]) throws -> Selection {
            try conversationSelect(history: history)
        }

        /// Prepares messages using externally gathered prompt content and capabilities.
        public static func prepare(_ selected: Selection, options: Options) -> [PreparedMessage] {
            conversationPrepare(selected: selected, options: options)
        }

        /// Places a hint in an already assembled request without repeating preparation.
        public static func appendHint(_ hint: String, to messages: [PreparedMessage]) -> [PreparedMessage] {
            conversationAppendHint(messages: messages, hint: hint)
        }
    }
}
