import Foundation

/// Auto-generated from Localizable.xcstrings. Do not edit manually.
enum Localized {
    /// Always returns the bundle for the currently selected language.
    /// Computed each time so language changes are reflected immediately.
    static var bundle: Bundle {
        .appLanguage
    }

    private static func get(_ key: String) -> String {
        bundle.localizedString(forKey: key, value: nil, table: nil)
    }

    enum Agent {
        enum EmptyState {
            /// A description text displayed when there is no agent set up in the Agent tab.
            static var setupHint: String {
                Localized.get("agent.emptyState.setupHint")
            }
        }

        /// A heading for the identity section of the agent's core.
        static var identityLabel: String {
            Localized.get("agent.identityLabel")
        }

        /// Hero reveal screen heading. The argument is the agent name and emoji, e.g. 'Nova 🦉'.
        static func identityStatement(_ p1: String) -> String {
            String(format: Localized.get("agent.identityStatement"), p1)
        }

        /// Message confirming the agent is ready, shown on the upgrade screen.
        static func initializedMessage(_ p1: String) -> String {
            String(format: Localized.get("agent.initializedMessage"), p1)
        }

        /// A section header that describes the user's initiative settings.
        static var initiative: String {
            Localized.get("agent.initiative")
        }

        /// A label describing the instructions for a space.
        static var instructions: String {
            Localized.get("agent.instructions")
        }

        /// A label displayed above the list of intents for an agent.
        static var intents: String {
            Localized.get("agent.intents")
        }

        /// A section header in the agent profile view.
        static var presentation: String {
            Localized.get("agent.presentation")
        }

        /// Headline for users who chose privacy priority on the upgrade screen.
        static func privateByDesign(_ p1: String) -> String {
            String(format: Localized.get("agent.privateByDesign"), p1)
        }

        enum Proactivity {
            /// A label displayed below a notification preview, indicating that the agent chose to
            /// notify the user.
            static var choseToNotify: String {
                Localized.get("agent.proactivity.choseToNotify")
            }

            /// A description of the notification that the agent chose not to send.
            static var choseToStaySilent: String {
                Localized.get("agent.proactivity.choseToStaySilent")
            }
        }

        enum Profile {
            enum Section {
                /// Section header for agent identity/user/soul documents
                static var core: String {
                    Localized.get("agent.profile.section.core")
                }

                /// Section header for proactivity settings
                static var initiative: String {
                    Localized.get("agent.profile.section.initiative")
                }

                /// Section header in agent profile
                static var presentation: String {
                    Localized.get("agent.profile.section.presentation")
                }
            }

            /// Section header for voice selection
            static var voice: String {
                Localized.get("agent.profile.voice")
            }

            enum Voice {
                /// Footer hint for installing more voices
                static var installHint: String {
                    Localized.get("agent.profile.voice.installHint")
                }
            }
        }

        /// A text label indicating how many times a particular intent has been reinforced.
        static func reinforcedCount(_ p1: String) -> String {
            String(format: Localized.get("agent.reinforcedCount"), p1)
        }

        /// A label displaying the number of rounds in the current notification session.
        static func roundsCount(_ p1: String) -> String {
            String(format: Localized.get("agent.roundsCount"), p1)
        }

        /// A label displayed above the list of skills for an agent.
        static var skills: String {
            Localized.get("agent.skills")
        }

        /// A heading for the "Soul" section of the agent profile.
        static var soul: String {
            Localized.get("agent.soul")
        }

        enum Status {
            /// A status text indicating that the agent is loading a page. The argument is the
            /// string “Agent”.
            static func loadingPage(_ p1: String) -> String {
                String(format: Localized.get("agent.status.loadingPage"), p1)
            }

            /// A status line that updates as the web view is loading and as it reads. The argument
            /// is the string “Agent”.
            static func readingPage(_ p1: String) -> String {
                String(format: Localized.get("agent.status.readingPage"), p1)
            }
        }

        /// Status label shown while the agent is processing a response
        static var thinking: String {
            Localized.get("agent.thinking")
        }

        /// A heading for the user section of the agent's core.
        static var userLabel: String {
            Localized.get("agent.userLabel")
        }
    }

    enum Auth {
        /// A loading indicator while waiting for the user to sign in to their provider.
        static func signingIn(_ p1: String) -> String {
            String(format: Localized.get("auth.signingIn"), p1)
        }

        /// A description of the process of signing in to OpenRouter.
        static var signingInToOpenRouter: String {
            Localized.get("auth.signingInToOpenRouter")
        }

        /// Status label shown while waiting for the user to complete authorization in the browser
        static var waiting: String {
            Localized.get("auth.waiting")
        }
    }

    enum Chat {
        enum Alert {
            /// Alert title for chat deletion confirmation
            static var deleteTitle: String {
                Localized.get("chat.alert.deleteTitle")
            }

            /// Alert title for chat rename dialog
            static var renameTitle: String {
                Localized.get("chat.alert.renameTitle")
            }
        }

        /// A label for a chat list item that is currently selected.
        static var allChats: String {
            Localized.get("chat.allChats")
        }

        /// Banner shown after the conversation history has been compacted
        static var conversationSummarized: String {
            Localized.get("chat.conversationSummarized")
        }

        /// The message displayed in an alert when confirming the deletion of a chat.
        static var deleteWarning: String {
            Localized.get("chat.deleteWarning")
        }

        enum EmptyState {
            /// A description text displayed below the "+" button in the toolbar of the chat list
            /// view, encouraging users to start a new chat.
            static var hint: String {
                Localized.get("chat.emptyState.hint")
            }

            /// Empty state title when there are no chats
            static var title: String {
                Localized.get("chat.emptyState.title")
            }
        }

        enum Filter {
            /// Filter option for all chats
            static var allChats: String {
                Localized.get("chat.filter.allChats")
            }
        }

        enum Input {
            /// TextField placeholder for chat input
            static var messagePlaceholder: String {
                Localized.get("chat.input.messagePlaceholder")
            }
        }

        /// A button label that lets the user interrupt a live call.
        static var myTurn: String {
            Localized.get("chat.myTurn")
        }

        /// Empty state label shown when no live call transcripts have been recorded
        static var noTranscripts: String {
            Localized.get("chat.noTranscripts")
        }

        /// Placeholder text for the knowledge search field
        static var searchKnowledgePlaceholder: String {
            Localized.get("chat.searchKnowledgePlaceholder")
        }

        /// Label for the system default option in model/provider selection
        static var systemDefault: String {
            Localized.get("chat.systemDefault")
        }

        /// Navigation title for the chat list
        static var title: String {
            Localized.get("chat.title")
        }

        /// A text label displaying the number of chats in a space. The argument is the count of
        /// chats.
        static func titleFormat(_ p1: String, _ p2: String) -> String {
            String(format: Localized.get("chat.titleFormat"), p1, p2)
        }
    }

    enum Common {
        enum Actions {
            /// Generic add button label
            static var add: String {
                Localized.get("common.actions.add")
            }

            /// Generic cancel button label
            static var cancel: String {
                Localized.get("common.actions.cancel")
            }

            /// A button label that allows the user to continue to the next screen.
            static var `continue`: String {
                Localized.get("common.actions.continue")
            }

            /// Generic delete button label
            static var delete: String {
                Localized.get("common.actions.delete")
            }

            /// Button label to initiate a download
            static var download: String {
                Localized.get("common.actions.download")
            }

            /// Generic next/advance button label
            static var next: String {
                Localized.get("common.actions.next")
            }

            /// Button label to dismiss a prompt without acting
            static var notNow: String {
                Localized.get("common.actions.notNow")
            }

            /// Button label to open a named item; %@ is substituted with the item name
            static func openItem(_ p1: String) -> String {
                String(format: Localized.get("common.actions.openItem"), p1)
            }

            /// Generic rename action label
            static var rename: String {
                Localized.get("common.actions.rename")
            }

            /// Generic retry button label
            static var retry: String {
                Localized.get("common.actions.retry")
            }

            /// Generic save button label
            static var save: String {
                Localized.get("common.actions.save")
            }
        }

        enum Alert {
            /// Alert title for chat deletion confirmation
            static var deleteChatTitle: String {
                Localized.get("common.alert.deleteChatTitle")
            }

            /// Alert title for fact deletion confirmation
            static var deleteFactTitle: String {
                Localized.get("common.alert.deleteFactTitle")
            }

            /// Alert title for space deletion confirmation
            static var deleteSpaceTitle: String {
                Localized.get("common.alert.deleteSpaceTitle")
            }

            /// Alert title for chat rename dialog
            static var renameChatTitle: String {
                Localized.get("common.alert.renameChatTitle")
            }

            /// Alert title for space rename dialog
            static var renameSpaceTitle: String {
                Localized.get("common.alert.renameSpaceTitle")
            }
        }

        enum Fields {
            /// TextField placeholder for agent name
            static var agentName: String {
                Localized.get("common.fields.agentName")
            }

            /// TextField placeholder for API key
            static var apiKey: String {
                Localized.get("common.fields.apiKey")
            }

            /// TextField placeholder for renaming a chat
            static var chatName: String {
                Localized.get("common.fields.chatName")
            }

            /// TextField placeholder for OAuth client ID
            static var clientId: String {
                Localized.get("common.fields.clientId")
            }

            /// SecureField placeholder for client secret
            static var clientSecret: String {
                Localized.get("common.fields.clientSecret")
            }

            /// Generic name field placeholder
            static var name: String {
                Localized.get("common.fields.name")
            }

            /// TextField placeholder for server URL
            static var serverUrl: String {
                Localized.get("common.fields.serverUrl")
            }

            /// TextField placeholder for editing a space name
            static var spaceName: String {
                Localized.get("common.fields.spaceName")
            }
        }

        enum Placeholder {
            /// Generic placeholder for unset values
            static var notSet: String {
                Localized.get("common.placeholder.notSet")
            }
        }
    }

    enum Debug {
        /// Button to delete all listed items
        static var deleteAllListed: String {
            Localized.get("debug.deleteAllListed")
        }

        /// Navigation title for development menu
        static var developmentTitle: String {
            Localized.get("debug.developmentTitle")
        }

        /// Generic done button label
        static var done: String {
            Localized.get("debug.done")
        }

        /// Navigation title for error details
        static var errorDetailsTitle: String {
            Localized.get("debug.errorDetailsTitle")
        }

        /// Navigation title for local model test view
        static var localModelTestTitle: String {
            Localized.get("debug.localModelTestTitle")
        }

        /// Navigation title for model storage debug view
        static var modelStorageTitle: String {
            Localized.get("debug.modelStorageTitle")
        }

        /// Navigation title for move to space sheet
        static var moveToSpaceTitle: String {
            Localized.get("debug.moveToSpaceTitle")
        }

        /// Empty state for chat with no messages
        static var noMessagesYet: String {
            Localized.get("debug.noMessagesYet")
        }

        /// Status label while scanning
        static var scanning: String {
            Localized.get("debug.scanning")
        }

        enum Section {
            /// Section header for model storage
            static var onDeviceModelStorage: String {
                Localized.get("debug.section.onDeviceModelStorage")
            }
        }

        /// Navigation title for tool detail sheet
        static var toolDetailTitle: String {
            Localized.get("debug.toolDetailTitle")
        }

        /// Label for total storage
        static var total: String {
            Localized.get("debug.total")
        }

        /// Navigation title for transcript detail
        static var transcriptTitle: String {
            Localized.get("debug.transcriptTitle")
        }
    }

    enum Development {
        /// Label when agent chose to send notification
        static var agentChoseToNotify: String {
            Localized.get("development.agentChoseToNotify")
        }

        /// Label when agent chose not to notify
        static var agentChoseToStaySilent: String {
            Localized.get("development.agentChoseToStaySilent")
        }

        /// Button to cancel scheduled background task
        static var cancelScheduledTask: String {
            Localized.get("development.cancelScheduledTask")
        }

        /// Hint about chat creation from notification
        static var chatWillBeCreated: String {
            Localized.get("development.chatWillBeCreated")
        }

        /// Button to clear background prompt transcripts
        static var clearTranscripts: String {
            Localized.get("development.clearTranscripts")
        }

        /// Toggle label for debug mode
        static var debugMode: String {
            Localized.get("development.debugMode")
        }

        /// Button to export all app data
        static var exportAllData: String {
            Localized.get("development.exportAllData")
        }

        /// Button to run Firm FFI sanity check
        static var firmSanityCheck: String {
            Localized.get("development.firmSanityCheck")
        }

        /// Button to import data
        static var importData: String {
            Localized.get("development.importData")
        }

        /// Success message after data import
        static var importSuccessful: String {
            Localized.get("development.importSuccessful")
        }

        /// Navigation link to model storage view
        static var modelStorage: String {
            Localized.get("development.modelStorage")
        }

        /// Empty state message when no transcripts exist
        static var noTranscripts: String {
            Localized.get("development.noTranscripts")
        }

        /// Confirmation dialog title for data replacement
        static var replaceAllDataConfirm: String {
            Localized.get("development.replaceAllDataConfirm")
        }

        /// Destructive action confirmation message for data import
        static var replaceAllDataMessage: String {
            Localized.get("development.replaceAllDataMessage")
        }

        /// Button to request notification permission
        static var requestNotificationPermission: String {
            Localized.get("development.requestNotificationPermission")
        }

        /// Button to schedule balanced background review
        static var scheduleBalanced: String {
            Localized.get("development.scheduleBalanced")
        }

        /// Button to schedule proactive background review
        static var scheduleProactive: String {
            Localized.get("development.scheduleProactive")
        }

        enum Section {
            /// Section header for background scheduler options
            static var backgroundScheduler: String {
                Localized.get("development.section.backgroundScheduler")
            }

            /// Section header for data backup actions
            static var dataBackup: String {
                Localized.get("development.section.dataBackup")
            }

            /// Section header for local model options
            static var localModel: String {
                Localized.get("development.section.localModel")
            }
        }

        /// Share link label for exported data
        static var shareExportFile: String {
            Localized.get("development.shareExportFile")
        }

        /// Button to send a test notification
        static var testNotification: String {
            Localized.get("development.testNotification")
        }

        /// Button to trigger initiative background run
        static var triggerInitiativeRun: String {
            Localized.get("development.triggerInitiativeRun")
        }

        /// Button to trigger maintenance background run
        static var triggerMaintenanceRun: String {
            Localized.get("development.triggerMaintenanceRun")
        }

        /// Navigation link to app log viewer
        static var viewAppLog: String {
            Localized.get("development.viewAppLog")
        }
    }

    enum Emoji {
        /// TextField placeholder for custom emoji input
        static var custom: String {
            Localized.get("emoji.custom")
        }
    }

    enum Errors {
        enum Access {
            /// Short error title when the server returns HTTP 403
            static var denied: String {
                Localized.get("errors.access.denied")
            }
        }

        enum AppleIntelligence {
            /// Recovery suggestion when Apple Intelligence is disabled in system settings
            static var enableHint: String {
                Localized.get("errors.appleIntelligence.enableHint")
            }

            /// Error message when Apple Intelligence is not available on this device
            static var notAvailable: String {
                Localized.get("errors.appleIntelligence.notAvailable")
            }

            /// Error message when the device hardware does not support Apple Intelligence
            static var notSupported: String {
                Localized.get("errors.appleIntelligence.notSupported")
            }

            /// Error message when the Apple Intelligence model has not finished downloading
            static var stillDownloading: String {
                Localized.get("errors.appleIntelligence.stillDownloading")
            }
        }

        enum Authentication {
            /// Error message when the user cancels the authentication flow
            static var cancelled: String {
                Localized.get("errors.authentication.cancelled")
            }

            /// Short error title when authentication fails (e.g. HTTP 401)
            static var failed: String {
                Localized.get("errors.authentication.failed")
            }
        }

        enum Authorization {
            /// Error message when OAuth authorization fails; %@ is substituted with the underlying
            /// reason
            static func failedWithReason(_ p1: String) -> String {
                String(format: Localized.get("errors.authorization.failedWithReason"), p1)
            }
        }

        enum Connection {
            /// Short error title for a generic connection failure
            static var failed: String {
                Localized.get("errors.connection.failed")
            }

            /// Short error title when the server actively refuses the connection
            static var refused: String {
                Localized.get("errors.connection.refused")
            }

            /// Title for the connection-failed error card shown during provider setup
            static var title: String {
                Localized.get("errors.connection.title")
            }
        }

        enum Network {
            /// Short error title when the device has no internet connection
            static var noConnection: String {
                Localized.get("errors.network.noConnection")
            }

            /// Recovery suggestion telling the user to check their network and try again
            static var retryHint: String {
                Localized.get("errors.network.retryHint")
            }
        }

        /// Short error title when a feature or resource is not available
        static var notAvailable: String {
            Localized.get("errors.notAvailable")
        }

        enum Oauth {
            /// A message indicating that the sign-in process was cancelled by the user.
            static var dismissed: String {
                Localized.get("errors.oauth.dismissed")
            }

            /// An error title shown when the user dismisses the OAuth sign-in sheet.
            static var dismissedTitle: String {
                Localized.get("errors.oauth.dismissedTitle")
            }
        }

        enum Provider {
            /// Error message when the token exchange step of OAuth fails; %@ is substituted with
            /// the underlying reason
            static func apiKeyRetrievalFailed(_ p1: String) -> String {
                String(format: Localized.get("errors.provider.apiKeyRetrievalFailed"), p1)
            }

            /// Recovery suggestion when the provider base URL is rejected as invalid
            static var baseUrlHint: String {
                Localized.get("errors.provider.baseUrlHint")
            }

            /// Recovery suggestion when the server refuses the connection
            static var connectionRefused: String {
                Localized.get("errors.provider.connectionRefused")
            }

            /// Generic recovery suggestion for unexpected provider errors
            static var genericHint: String {
                Localized.get("errors.provider.genericHint")
            }

            /// Recovery suggestion when DNS resolution fails for the provider hostname
            static var hostNotFound: String {
                Localized.get("errors.provider.hostNotFound")
            }

            /// Recovery suggestion when the server rejects the API key (HTTP 401)
            static var invalidApiKey: String {
                Localized.get("errors.provider.invalidApiKey")
            }

            /// Recovery suggestion when the URL cannot be parsed
            static var malformedUrl: String {
                Localized.get("errors.provider.malformedUrl")
            }

            /// Recovery suggestion when the /models endpoint returns HTTP 404
            static var modelsEndpointNotFound: String {
                Localized.get("errors.provider.modelsEndpointNotFound")
            }

            /// Recovery suggestion when the API key lacks permission (HTTP 403)
            static var permissionDenied: String {
                Localized.get("errors.provider.permissionDenied")
            }

            /// Recovery suggestion when the provider returns HTTP 429
            static var rateLimited: String {
                Localized.get("errors.provider.rateLimited")
            }

            /// Recovery suggestion for non-standard HTTP error codes from the provider
            static var returnedError: String {
                Localized.get("errors.provider.returnedError")
            }

            /// Recovery suggestion when the provider returns an HTTP 5xx error
            static var serverError: String {
                Localized.get("errors.provider.serverError")
            }

            /// Recovery suggestion when TLS/SSL negotiation fails
            static var sslFailed: String {
                Localized.get("errors.provider.sslFailed")
            }

            /// Recovery suggestion when the request times out
            static var timeout: String {
                Localized.get("errors.provider.timeout")
            }

            /// Recovery suggestion when the response cannot be decoded as an OpenAI-compatible
            /// payload
            static var unexpectedResponse: String {
                Localized.get("errors.provider.unexpectedResponse")
            }
        }

        enum Request {
            /// Short error title for a failed HTTP request
            static var failed: String {
                Localized.get("errors.request.failed")
            }
        }

        enum Secure {
            enum Connection {
                /// Short error title when TLS/SSL connection fails
                static var failed: String {
                    Localized.get("errors.secure.connection.failed")
                }
            }
        }

        enum Server {
            /// Short error title for a server-side error (HTTP 5xx)
            static var error: String {
                Localized.get("errors.server.error")
            }
        }

        enum Speech {
            /// Error message when the user has not granted speech recognition permission
            static var permissionDenied: String {
                Localized.get("errors.speech.permissionDenied")
            }

            /// Error message when speech recognition is not available on the device
            static var unavailable: String {
                Localized.get("errors.speech.unavailable")
            }
        }
    }

    enum Fact {
        enum Detail {
            enum Label {
                /// Badge text for bundled facts
                static var bundled: String {
                    Localized.get("fact.detail.label.bundled")
                }

                /// Label for entity ID field
                static var id: String {
                    Localized.get("fact.detail.label.id")
                }

                /// Label for entity source field
                static var source: String {
                    Localized.get("fact.detail.label.source")
                }

                /// Label for entity type field
                static var type: String {
                    Localized.get("fact.detail.label.type")
                }
            }

            /// Placeholder text for unset values
            static var notSet: String {
                Localized.get("fact.detail.notSet")
            }

            enum Section {
                /// Section header for fact fields
                static var fields: String {
                    Localized.get("fact.detail.section.fields")
                }

                /// Section header for entity ID
                static var id: String {
                    Localized.get("fact.detail.section.id")
                }

                /// Section header for fact relationships
                static var relationships: String {
                    Localized.get("fact.detail.section.relationships")
                }

                /// Section header for entity source
                static var source: String {
                    Localized.get("fact.detail.section.source")
                }

                /// Section header for fact tags
                static var tags: String {
                    Localized.get("fact.detail.section.tags")
                }

                /// Section header for entity type
                static var type: String {
                    Localized.get("fact.detail.section.type")
                }
            }
        }

        enum List {
            /// Link to show all facts in a type section
            static func showAll(_ p1: String) -> String {
                String(format: Localized.get("fact.list.showAll"), p1)
            }
        }
    }

    enum Facts {
        /// An alert message that appears when the user confirms deleting a fact.
        static var deleteWarning: String {
            Localized.get("facts.deleteWarning")
        }

        enum EmptyState {
            /// A description text that appears when there are no facts to display.
            static var hint: String {
                Localized.get("facts.emptyState.hint")
            }
        }

        enum Kind {
            /// Singular label for the 'actor' fact type
            static var actor: String {
                Localized.get("facts.type.actor")
            }

            /// Plural label for the 'actor' fact type
            static var actors: String {
                Localized.get("facts.type.actors")
            }

            /// Singular label for the generic 'fact' type
            static var fact: String {
                Localized.get("facts.type.fact")
            }

            /// Plural label for the generic 'fact' type
            static var facts: String {
                Localized.get("facts.type.facts")
            }

            /// Label for the 'notes' fact type
            static var notes: String {
                Localized.get("facts.type.notes")
            }

            /// Singular label for the 'output' fact type
            static var output: String {
                Localized.get("facts.type.output")
            }

            /// Plural label for the 'output' fact type
            static var outputs: String {
                Localized.get("facts.type.outputs")
            }

            /// Singular label for the 'thing' fact type
            static var thing: String {
                Localized.get("facts.type.thing")
            }

            /// Plural label for the 'thing' fact type
            static var things: String {
                Localized.get("facts.type.things")
            }
        }
    }

    enum Intent {
        /// A message displayed when dismissing an intent.
        static var dismissWarning: String {
            Localized.get("intent.dismissWarning")
        }

        enum EmptyState {
            /// A description text that appears when there are no active intents.
            static var hint: String {
                Localized.get("intent.emptyState.hint")
            }
        }
    }

    enum Intents {
        /// Confirmation message when dismissing an intent
        static var dismissWarning: String {
            Localized.get("intents.dismissWarning")
        }

        /// Navigation title for intents list
        static var title: String {
            Localized.get("intents.title")
        }
    }

    enum Knowledge {
        enum EmptyState {
            /// A description text that appears when a user's knowledge list is empty.
            static var hint: String {
                Localized.get("knowledge.emptyState.hint")
            }

            /// Empty state title when there are no knowledge items
            static var title: String {
                Localized.get("knowledge.emptyState.title")
            }
        }

        /// A label displayed above the user's knowledge.
        static var sectionTitle: String {
            Localized.get("knowledge.sectionTitle")
        }

        /// Navigation title for knowledge container
        static var title: String {
            Localized.get("knowledge.title")
        }
    }

    enum LocalModel {
        /// Button to cancel download
        static var cancel: String {
            Localized.get("localModel.cancel")
        }

        /// Label showing context length
        static func contextLength(_ p1: String) -> String {
            String(format: Localized.get("localModel.contextLength"), p1)
        }

        /// Button to delete downloaded model
        static var delete: String {
            Localized.get("localModel.delete")
        }

        /// Status when download fails
        static var downloadFailed: String {
            Localized.get("localModel.downloadFailed")
        }

        /// Button to download model from HuggingFace
        static var downloadFromHuggingFace: String {
            Localized.get("localModel.downloadFromHuggingFace")
        }

        /// Status when model is downloaded
        static var prepared: String {
            Localized.get("localModel.prepared")
        }

        /// Status while preparing model
        static var preparing: String {
            Localized.get("localModel.preparing")
        }

        /// Button to retry download
        static var retry: String {
            Localized.get("localModel.retry")
        }
    }

    enum Mcp {
        /// Section or label for MCP server authentication settings
        static var authentication: String {
            Localized.get("mcp.authentication")
        }

        enum Authentication {
            /// A heading for the user section of the agent's core.
            static var user: String {
                Localized.get("mcp.authentication.user")
            }
        }

        /// A description of how a server connects automatically when used in a chat.
        static var autoConnectHint: String {
            Localized.get("mcp.autoConnectHint")
        }

        enum Hint {
            /// Hint about MCP auto-connect behavior
            static var autoConnect: String {
                Localized.get("mcp.hint.autoConnect")
            }

            /// Hint about disabled MCP server
            static var disabled: String {
                Localized.get("mcp.hint.disabled")
            }
        }

        enum Label {
            /// Label for server URL in MCP detail
            static var url: String {
                Localized.get("mcp.label.url")
            }
        }

        /// Empty state when MCP server has no tools
        static var noToolsDiscovered: String {
            Localized.get("mcp.noToolsDiscovered")
        }

        /// Button to re-authorize MCP server
        static var reAuthorize: String {
            Localized.get("mcp.reAuthorize")
        }

        enum Section {
            /// Section header for MCP server status
            static var status: String {
                Localized.get("mcp.section.status")
            }
        }

        enum Setup {
            /// A section header for the client credentials required to access a server that doesn't
            /// use dynamic registration.
            static var clientCredentials: String {
                Localized.get("mcp.setup.clientCredentials")
            }

            /// A footer text in the "Client Credentials" section of the "Add MCP Server" form,
            /// explaining that the server doesn't support automatic registration and that the user
            /// needs to enter client credentials manually.
            static var manualCredentialsHint: String {
                Localized.get("mcp.setup.manualCredentialsHint")
            }

            /// A footer text explaining that the server must support the MCP protocol.
            static var requirement: String {
                Localized.get("mcp.setup.requirement")
            }
        }

        enum Status {
            /// A description of the ongoing process of checking if a server is open or requires
            /// OAuth 2.1 authentication.
            static var checking: String {
                Localized.get("mcp.status.checking")
            }

            /// Status label shown when the MCP server is connected
            static var connected: String {
                Localized.get("mcp.status.connected")
            }

            /// Status label when MCP server is connected
            static var connectionActive: String {
                Localized.get("mcp.status.connectionActive")
            }

            /// Status label shown when the MCP server is disabled
            static var disabled: String {
                Localized.get("mcp.status.disabled")
            }

            /// A description of a disabled MCP server.
            static var disabledHint: String {
                Localized.get("mcp.status.disabledHint")
            }

            /// Status label shown when the MCP server is not connected
            static var notConnected: String {
                Localized.get("mcp.status.notConnected")
            }
        }

        /// Section header for MCP server tools
        static var tools: String {
            Localized.get("mcp.tools")
        }
    }

    enum Memory {
        /// A message displayed in an alert when deleting a memory.
        static var deleteWarning: String {
            Localized.get("memory.deleteWarning")
        }

        enum EmptyState {
            /// A description text displayed when there are no memories.
            static var hint: String {
                Localized.get("memory.emptyState.hint")
            }
        }

        /// A label displayed above the user's memories.
        static var sectionTitle: String {
            Localized.get("memory.sectionTitle")
        }
    }

    enum Model {
        /// Label for Apple Foundation Model option
        static var appleFoundationModel: String {
            Localized.get("model.appleFoundationModel")
        }

        /// Status text when Apple Foundation Model is ready
        static var appleReadyToUse: String {
            Localized.get("model.appleReadyToUse")
        }

        /// Indicates that a fact is part of a larger set of related facts.
        static var bundled: String {
            Localized.get("model.bundled")
        }

        /// Button to download a model
        static var download: String {
            Localized.get("model.download")
        }

        /// Label for Gemma 4 E2B model
        static var gemma4e2b: String {
            Localized.get("model.gemma4e2b")
        }

        enum Gemma4e2b {
            /// The name of the machine learning model used in the app.
            static var name: String {
                Localized.get("model.gemma4e2b.name")
            }
        }

        /// Status text when Gemma model is downloaded
        static var gemmaDownloadedReady: String {
            Localized.get("model.gemmaDownloadedReady")
        }

        enum Picker {
            /// Section header for all models
            static var allModels: String {
                Localized.get("model.picker.allModels")
            }

            /// Separator between recommended models
            static var dotSeparator: String {
                Localized.get("model.picker.dotSeparator")
            }

            /// Empty state when search has no results
            static var noSearchResults: String {
                Localized.get("model.picker.noSearchResults")
            }

            /// Section header for other recommended models
            static var otherRecommended: String {
                Localized.get("model.picker.otherRecommended")
            }

            /// Section header for recommended models
            static var recommendedForYou: String {
                Localized.get("model.picker.recommendedForYou")
            }

            /// Searchable prompt for model picker
            static var searchPrompt: String {
                Localized.get("model.picker.searchPrompt")
            }

            /// Navigation title for model picker
            static var title: String {
                Localized.get("model.picker.title")
            }
        }

        /// Warning message when removing a model
        static var removeStorageWarning: String {
            Localized.get("model.removeStorageWarning")
        }

        /// An alert message that appears when a user deletes a voice engine.
        static var removeWarning: String {
            Localized.get("model.removeWarning")
        }

        enum Status {
            /// A label indicating that a voice engine is installed on the device.
            static var installed: String {
                Localized.get("model.status.installed")
            }
        }

        /// Storage error message with size argument
        static func storageNotEnough(_ p1: String) -> String {
            String(format: Localized.get("model.storageNotEnough"), p1)
        }

        /// A message in an alert that informs the user that they need at least a certain amount of
        /// free storage to download a model. The placeholder value is replaced with the actual
        /// required storage size. The argument is the string “%.1f”.
        static func storageRequirement(_ p1: String) -> String {
            String(format: Localized.get("model.storageRequirement"), p1)
        }
    }

    enum Network {
        /// A label indicating that the app is attempting to connect to a server.
        static var connecting: String {
            Localized.get("network.connecting")
        }
    }

    enum Notification {
        /// A footnote explaining that a chat will be created when a notification is tapped.
        static var chatCreationHint: String {
            Localized.get("notification.chatCreationHint")
        }

        /// Push notification title sent when the on-device model finishes downloading
        static var modelReady: String {
            Localized.get("notification.modelReady")
        }
    }

    enum Onboarding {
        enum Chat {
            /// Recovery opener for the about stage, used when the previous stage failed to extract
            /// a name.
            static var aboutYouPrompt: String {
                Localized.get("onboarding.chat.aboutYouPrompt")
            }

            /// Upgrade pitch for users who chose freedom priority.
            static var choiceExplanation: String {
                Localized.get("onboarding.chat.choiceExplanation")
            }

            /// The onboarding greeting shown as the first message in the guided conversation.
            static var initialGreeting: String {
                Localized.get("onboarding.chat.initialGreeting")
            }

            /// Upgrade pitch for users who chose privacy priority.
            static func localExplanation(_ p1: String) -> String {
                String(format: Localized.get("onboarding.chat.localExplanation"), p1)
            }

            /// Recovery opener for the agent name stage, used when the previous stage failed to
            /// extract priority. The argument is a comma-separated list of suggested names.
            static func namePrompt(_ p1: String) -> String {
                String(format: Localized.get("onboarding.chat.namePrompt"), p1)
            }

            /// Upgrade pitch for users who chose power priority.
            static func powerExplanation(_ p1: String) -> String {
                String(format: Localized.get("onboarding.chat.powerExplanation"), p1)
            }

            /// Recovery opener for the priority stage, used when the previous stage failed to
            /// extract style preference.
            static var priorityPrompt: String {
                Localized.get("onboarding.chat.priorityPrompt")
            }

            /// Subtitle on the final onboarding screen.
            static var readyMessage: String {
                Localized.get("onboarding.chat.readyMessage")
            }

            /// Agent message shown in the onboarding chat while the app configures itself
            static var settingUpMessage: String {
                Localized.get("onboarding.chat.settingUpMessage")
            }

            /// Recovery opener for the style stage, used when the previous stage failed to extract
            /// context.
            static var stylePrompt: String {
                Localized.get("onboarding.chat.stylePrompt")
            }

            /// Generic upgrade pitch when no priority was chosen.
            static func upgradePrompt(_ p1: String) -> String {
                String(format: Localized.get("onboarding.chat.upgradePrompt"), p1)
            }

            /// Recovery opener for the context stage, used when the previous stage failed to
            /// extract background info.
            static var useCasePrompt: String {
                Localized.get("onboarding.chat.useCasePrompt")
            }
        }

        enum Complete {
            /// Heading on the final onboarding screen.
            static var title: String {
                Localized.get("onboarding.complete.title")
            }
        }

        /// A description text displayed below the unavailable view title.
        static var completionHint: String {
            Localized.get("onboarding.completionHint")
        }

        enum Features {
            enum Choice {
                /// Sub-header for users who chose freedom priority on the upgrade screen.
                static var description: String {
                    Localized.get("onboarding.features.choice.description")
                }

                /// Short tagline describing the freedom to switch AI providers
                static var tagline: String {
                    Localized.get("onboarding.features.choice.tagline")
                }

                /// A caption displayed below a value row in the "OnboardingWelcome" view.
                static var title: String {
                    Localized.get("onboarding.features.choice.title")
                }
            }

            enum Power {
                /// Short tagline describing AI-augmented capability
                static var tagline: String {
                    Localized.get("onboarding.features.power.tagline")
                }
            }

            enum Privacy {
                /// Bullet describing the agent's personalization capability on the privacy features
                /// screen
                static var description: String {
                    Localized.get("onboarding.features.privacy.description")
                }

                /// Bullet describing local-only conversation storage on the privacy features screen
                static var storage: String {
                    Localized.get("onboarding.features.privacy.storage")
                }

                /// Main tagline for the privacy features screen
                static var tagline: String {
                    Localized.get("onboarding.features.privacy.tagline")
                }

                /// A description of how Eigin "knows" its users.
                static var title: String {
                    Localized.get("onboarding.features.privacy.title")
                }
            }

            enum Safety {
                /// Short tagline describing the permission-gated safety model
                static var tagline: String {
                    Localized.get("onboarding.features.safety.tagline")
                }
            }

            enum Security {
                /// Sub-header for users who chose privacy priority on the upgrade screen.
                static var description: String {
                    Localized.get("onboarding.features.security.description")
                }

                /// A subtitle for a feature that keeps user data secure.
                static var title: String {
                    Localized.get("onboarding.features.security.title")
                }
            }
        }

        enum LocalModel {
            /// Explanation of the local model option shown on the provider choice screen
            static var description: String {
                Localized.get("onboarding.localModel.description")
            }
        }

        enum ModelSetup {
            /// Button label to start downloading the on-device model
            static var downloadAction: String {
                Localized.get("onboarding.modelSetup.downloadAction")
            }

            /// Subtitle explaining that the model download continues in the background
            static var downloadStatus: String {
                Localized.get("onboarding.modelSetup.downloadStatus")
            }

            /// Status text during model download
            static func downloadingProgress(_ p1: String) -> String {
                String(format: Localized.get("onboarding.modelSetup.downloadingProgress"), p1)
            }

            /// An error title shown when the local model download fails.
            static var errorTitle: String {
                Localized.get("onboarding.modelSetup.errorTitle")
            }

            /// Link/button to skip local model download and use a cloud provider instead
            static var fallbackAction: String {
                Localized.get("onboarding.modelSetup.fallbackAction")
            }

            /// Intro prefix before the cycling words on the model setup screen; e.g. 'Eigin is
            /// built for independence'
            static var intro: String {
                Localized.get("onboarding.modelSetup.intro")
            }

            /// Button label to request a notification when the model finishes downloading
            static var notifyAction: String {
                Localized.get("onboarding.modelSetup.notifyAction")
            }

            /// Confirmation message shown after the user enables download notifications
            static var notifyConfirmation: String {
                Localized.get("onboarding.modelSetup.notifyConfirmation")
            }

            /// Prompt offering to notify the user when the download completes
            static var notifyOffer: String {
                Localized.get("onboarding.modelSetup.notifyOffer")
            }

            /// Progress percentage label
            static func progressPercent(_ p1: String) -> String {
                String(format: Localized.get("onboarding.modelSetup.progressPercent"), p1)
            }

            /// A status label shown when the local model has finished downloading and is ready.
            static var readyStatus: String {
                Localized.get("onboarding.modelSetup.readyStatus")
            }

            /// Success message shown after the on-device model is ready to use
            static var successMessage: String {
                Localized.get("onboarding.modelSetup.successMessage")
            }

            enum Words {
                /// Cycling word on the model setup screen — one of several values the app animates
                /// through
                static var freedom: String {
                    Localized.get("onboarding.modelSetup.words.freedom")
                }

                /// Cycling word on the model setup screen — one of several values the app animates
                /// through
                static var independence: String {
                    Localized.get("onboarding.modelSetup.words.independence")
                }

                /// Cycling word on the model setup screen — one of several values the app animates
                /// through
                static var ownership: String {
                    Localized.get("onboarding.modelSetup.words.ownership")
                }

                /// Cycling word on the model setup screen — one of several values the app animates
                /// through
                static var privacy: String {
                    Localized.get("onboarding.modelSetup.words.privacy")
                }

                /// Cycling word on the model setup screen — one of several values the app animates
                /// through
                static var sovereignty: String {
                    Localized.get("onboarding.modelSetup.words.sovereignty")
                }
            }
        }

        enum Provider {
            /// Button label to add credits on provider website
            static func addCreditsLabel(_ p1: String) -> String {
                String(format: Localized.get("onboarding.provider.addCreditsLabel"), p1)
            }

            /// Explanation shown when the user chooses to use a cloud AI provider during onboarding
            static var cloudExplanation: String {
                Localized.get("onboarding.provider.cloudExplanation")
            }

            /// Button to connect a cloud AI provider on the upgrade screen.
            static var connectAction: String {
                Localized.get("onboarding.provider.connectAction")
            }

            /// Success message after OAuth completes
            static func connectedTo(_ p1: String) -> String {
                String(format: Localized.get("onboarding.provider.connectedTo"), p1)
            }

            /// Warning about provider credits after OAuth
            static var creditsWarning: String {
                Localized.get("onboarding.provider.creditsWarning")
            }

            /// Headline for users who chose power priority on the upgrade screen.
            static func giveBrainPower(_ p1: String) -> String {
                String(format: Localized.get("onboarding.provider.giveBrainPower"), p1)
            }

            /// Headline for users who chose speed priority on the upgrade screen.
            static func keepMovingFast(_ p1: String) -> String {
                String(format: Localized.get("onboarding.provider.keepMovingFast"), p1)
            }

            /// Button to skip connecting a cloud provider and finish onboarding.
            static var localAction: String {
                Localized.get("onboarding.provider.localAction")
            }

            /// Error message when user dismisses OAuth sheet
            static var signInDismissed: String {
                Localized.get("onboarding.provider.signInDismissed")
            }

            /// Recovery hint after OAuth dismissal
            static var signInDismissedHint: String {
                Localized.get("onboarding.provider.signInDismissedHint")
            }

            /// Status message during OAuth sign-in
            static func signingIn(_ p1: String) -> String {
                String(format: Localized.get("onboarding.provider.signingIn"), p1)
            }

            /// Upgrade pitch for users who chose speed priority.
            static func speedExplanation(_ p1: String) -> String {
                String(format: Localized.get("onboarding.provider.speedExplanation"), p1)
            }
        }

        enum Welcome {
            /// Fallback hero text shown when model generation fails.
            static var description: String {
                Localized.get("onboarding.welcome.description")
            }

            /// Wave emoji on welcome screen
            static var emoji: String {
                Localized.get("onboarding.welcome.emoji")
            }

            /// A greeting displayed in the onboarding flow.
            static var greeting: String {
                Localized.get("onboarding.welcome.greeting")
            }

            /// Welcome screen hero text that types in after Hello.
            static var hero: String {
                Localized.get("onboarding.welcome.hero")
            }

            /// A button label that says "Get Started".
            static var primaryAction: String {
                Localized.get("onboarding.welcome.primaryAction")
            }

            /// Subtitle on the welcome screen, introducing the feature list that follows
            static var subtitle: String {
                Localized.get("onboarding.welcome.subtitle")
            }

            /// Main tagline on the welcome screen
            static var tagline: String {
                Localized.get("onboarding.welcome.tagline")
            }

            /// A prefix for a verb describing a benefit of the app.
            static var verbPrefix: String {
                Localized.get("onboarding.welcome.verbPrefix")
            }

            enum Words {
                /// Cycling action word on the welcome screen — one of several the app animates
                /// through
                static var create: String {
                    Localized.get("onboarding.welcome.words.create")
                }

                /// Cycling action word on the welcome screen — one of several the app animates
                /// through
                static var organise: String {
                    Localized.get("onboarding.welcome.words.organise")
                }

                /// Cycling action word on the welcome screen — one of several the app animates
                /// through
                static var plan: String {
                    Localized.get("onboarding.welcome.words.plan")
                }

                /// Cycling action word on the welcome screen — one of several the app animates
                /// through
                static var remember: String {
                    Localized.get("onboarding.welcome.words.remember")
                }

                /// Cycling action word on the welcome screen — one of several the app animates
                /// through
                static var think: String {
                    Localized.get("onboarding.welcome.words.think")
                }

                /// Cycling action word on the welcome screen — one of several the app animates
                /// through
                static var write: String {
                    Localized.get("onboarding.welcome.words.write")
                }
            }
        }
    }

    enum Permission {
        /// A button label that allows a tool to run even when the user is in a chat.
        static var allowForChat: String {
            Localized.get("permission.allowForChat")
        }

        /// A button label that allows a user to grant a tool permission to run once.
        static var allowOnce: String {
            Localized.get("permission.allowOnce")
        }

        /// Permission level label — action is always allowed without asking
        static var always: String {
            Localized.get("permission.always")
        }

        /// Permission level label — user is asked before each action
        static var ask: String {
            Localized.get("permission.ask")
        }

        /// A status indicating that a tool call is waiting for user permission.
        static var awaiting: String {
            Localized.get("permission.awaiting")
        }

        /// A tool call indicator showing that a tool is awaiting user permission. The argument is
        /// the name of the tool.
        static func awaitingFormat(_ p1: String) -> String {
            String(format: Localized.get("permission.awaitingFormat"), p1)
        }

        /// A status indicating that a tool call was denied by the user.
        static var denied: String {
            Localized.get("permission.denied")
        }

        /// A tool call that was denied, displayed in red text.
        static func deniedFormat(_ p1: String) -> String {
            String(format: Localized.get("permission.deniedFormat"), p1)
        }

        /// A button label that denies a request.
        static var deny: String {
            Localized.get("permission.deny")
        }

        /// Permission level label — action is never allowed
        static var never: String {
            Localized.get("permission.never")
        }

        /// A button label that requests notification permissions.
        static var requestNotification: String {
            Localized.get("permission.requestNotification")
        }

        /// A section header that links to a view displaying the user's tool permissions.
        static var sectionTitle: String {
            Localized.get("permission.sectionTitle")
        }

        /// A message displayed when a tool's execution is denied by the user's access policy.
        static var toolDeniedByPolicy: String {
            Localized.get("permission.toolDeniedByPolicy")
        }

        /// A message displayed when a tool's execution is awaiting user permission.
        static var waitingForUser: String {
            Localized.get("permission.waitingForUser")
        }

        /// A message explaining that a user has granted or denied permission to use a tool. The
        /// argument is a user-visible name for the tool.
        static func wantsToUseFormat(_ p1: String, _ p2: String) -> String {
            String(format: Localized.get("permission.wantsToUseFormat"), p1, p2)
        }
    }

    enum Provider {
        enum Add {
            /// Button to add a new provider
            static var addButton: String {
                Localized.get("provider.add.addButton")
            }

            /// TextField placeholder for provider base URL
            static var baseUrlField: String {
                Localized.get("provider.add.baseUrlField")
            }

            /// TextField placeholder for provider name
            static var nameField: String {
                Localized.get("provider.add.nameField")
            }
        }

        /// Button to switch to manual API key entry
        static var addApiKeyManually: String {
            Localized.get("provider.addApiKeyManually")
        }

        /// Button label linking to the provider's credits page; %@ is substituted with the provider
        /// name
        static func addCreditsLabel(_ p1: String) -> String {
            String(format: Localized.get("provider.addCreditsLabel"), p1)
        }

        /// Button label linking to the OpenRouter credits page
        static var addCreditsOpenRouter: String {
            Localized.get("provider.addCreditsOpenRouter")
        }

        /// Label for the 'all models' filter option in the model list
        static var allModels: String {
            Localized.get("provider.allModels")
        }

        /// Field label for the API key input
        static var apiKey: String {
            Localized.get("provider.apiKey")
        }

        enum AppleIntelligence {
            /// Description shown for the Apple Intelligence provider option
            static var description: String {
                Localized.get("provider.appleIntelligence.description")
            }
        }

        /// Field label for the provider base URL input
        static var baseURL: String {
            Localized.get("provider.baseURL")
        }

        /// OAuth connected success message
        static func connectedTo(_ p1: String) -> String {
            String(format: Localized.get("provider.connectedTo"), p1)
        }

        enum Credits {
            /// A description under the "Connected to" message in the OAuth flow, reminding the user
            /// to top up their credits before proceeding.
            static var warning: String {
                Localized.get("provider.credits.warning")
            }

            /// A paragraph below the success message in the checkout view, explaining that users
            /// need to have credits on their API key provider account to continue.
            static func warningFormat(_ p1: String) -> String {
                String(format: Localized.get("provider.credits.warningFormat"), p1)
            }
        }

        /// Credits warning with provider name
        static func creditsWarning(_ p1: String) -> String {
            String(format: Localized.get("provider.creditsWarning"), p1)
        }

        enum Edit {
            /// Button to save provider changes
            static var saveButton: String {
                Localized.get("provider.edit.saveButton")
            }

            /// Navigation title for editing a provider
            static func title(_ p1: String) -> String {
                String(format: Localized.get("provider.edit.title"), p1)
            }

            /// Hint text in edit provider view
            static var updateHintSave: String {
                Localized.get("provider.edit.updateHintSave")
            }
        }

        enum EmptyState {
            /// A description text displayed below the title of a view that instructs the user to
            /// add a provider in the settings to get started.
            static var addProviderHint: String {
                Localized.get("provider.emptyState.addProviderHint")
            }
        }

        /// A label describing the model of an agent.
        static var modelLabel: String {
            Localized.get("provider.modelLabel")
        }

        enum Models {
            /// A message displayed when a provider has no supported models.
            static var empty: String {
                Localized.get("provider.models.empty")
            }

            /// A message displayed when no models match a search query.
            static var noSearchResults: String {
                Localized.get("provider.models.noSearchResults")
            }
        }

        /// Summary label showing how many models are enabled out of total; first %lld is enabled
        /// count, second is total
        static func modelsEnabledCount(_ p1: String, _ p2: String) -> String {
            String(format: Localized.get("provider.modelsEnabledCount"), p1, p2)
        }

        /// A text label showing the number of models enabled for a provider, followed by the total
        /// number of models available. Both numbers are displayed in parentheses.
        static func modelsEnabledCountStr(_ p1: String, _ p2: String) -> String {
            String(format: Localized.get("provider.modelsEnabledCountStr"), p1, p2)
        }

        /// Generic name for locally run models
        static var onDevice: String {
            Localized.get("provider.onDevice")
        }

        enum Picker {
            /// Label for custom provider option
            static var customProvider: String {
                Localized.get("provider.picker.customProvider")
            }

            /// Badge label for experimental providers
            static var experimental: String {
                Localized.get("provider.picker.experimental")
            }

            /// Searchable prompt for provider picker
            static var searchPrompt: String {
                Localized.get("provider.picker.searchPrompt")
            }
        }

        /// A label describing a recommended model for the user.
        static var recommendedForYou: String {
            Localized.get("provider.recommendedForYou")
        }

        /// A label displayed in the picker for selecting a model.
        static var selectModel: String {
            Localized.get("provider.selectModel")
        }

        /// A prompt in the setup form asking the user to select a provider.
        static var selectProvider: String {
            Localized.get("provider.selectProvider")
        }

        enum Setup {
            enum Anthropic {
                /// Step-by-step instruction for obtaining an Anthropic API key
                static var instruction: String {
                    Localized.get("provider.setup.anthropic.instruction")
                }
            }

            /// Alternative link shown below OAuth sign-in to switch to manual API key entry
            static var apiKeyAlternative: String {
                Localized.get("provider.setup.apiKeyAlternative")
            }

            enum Custom {
                /// A description of the API key field, indicating that it is required for using an
                /// OpenAI-compatible API. It also includes a suggestion for how to obtain it from
                /// the provider.
                static var apiRequirement: String {
                    Localized.get("provider.setup.custom.apiRequirement")
                }
            }

            enum Eurouter {
                /// Step-by-step instruction for obtaining a EUrouter API key
                static var instruction: String {
                    Localized.get("provider.setup.eurouter.instruction")
                }

                /// Instruction for connecting via OAuth to EUrouter
                static var oauthInstruction: String {
                    Localized.get("provider.setup.eurouter.oauthInstruction")
                }
            }

            enum Google {
                /// Step-by-step instruction for obtaining a Google AI Studio API key
                static var instruction: String {
                    Localized.get("provider.setup.google.instruction")
                }
            }

            enum Mistral {
                /// Step-by-step instruction for obtaining a Mistral API key
                static var instruction: String {
                    Localized.get("provider.setup.mistral.instruction")
                }
            }

            /// A button label that invites the user to connect with a specific OAuth provider. The
            /// argument is the name of the provider.
            static func oauthConnect(_ p1: String) -> String {
                String(format: Localized.get("provider.setup.oauthConnect"), p1)
            }

            /// A message displayed when the user dismisses the sign-in process and is presented
            /// with options to try again or manually add an API key.
            static var oauthFailureHint: String {
                Localized.get("provider.setup.oauthFailureHint")
            }

            /// Subtitle on the OAuth sign-in button explaining the benefit
            static var oauthSignIn: String {
                Localized.get("provider.setup.oauthSignIn")
            }

            enum Openai {
                /// Step-by-step instruction for obtaining an OpenAI API key
                static var instruction: String {
                    Localized.get("provider.setup.openai.instruction")
                }
            }

            enum Openrouter {
                /// A message encouraging a user to ensure they have credits on their OpenRouter
                /// account before proceeding.
                static var creditsWarning: String {
                    Localized.get("provider.setup.openrouter.creditsWarning")
                }

                /// Step-by-step instruction for obtaining an OpenRouter API key
                static var instruction: String {
                    Localized.get("provider.setup.openrouter.instruction")
                }

                /// A link text that directs users to connect with OpenRouter.
                static var oauthConnect: String {
                    Localized.get("provider.setup.openrouter.oauthConnect")
                }

                /// Instruction for connecting via OAuth to OpenRouter
                static var oauthInstruction: String {
                    Localized.get("provider.setup.openrouter.oauthInstruction")
                }
            }

            enum Ovh {
                /// Step-by-step instruction for obtaining an OVH AI Endpoints token
                static var instruction: String {
                    Localized.get("provider.setup.ovh.instruction")
                }
            }

            enum Scaleway {
                /// Step-by-step instruction for obtaining a Scaleway API key
                static var instruction: String {
                    Localized.get("provider.setup.scaleway.instruction")
                }
            }

            /// A footer label explaining the purpose of the "Next" button in the edit provider
            /// view.
            static var updateApiKeyHintNext: String {
                Localized.get("provider.setup.updateApiKeyHintNext")
            }

            /// A description of the action to update a provider's API key and refresh its models.
            static var updateApiKeyHintSave: String {
                Localized.get("provider.setup.updateApiKeyHintSave")
            }
        }

        /// Error when OAuth sheet is dismissed
        static var signInDismissed: String {
            Localized.get("provider.signInDismissed")
        }

        /// Recovery hint after OAuth dismissal
        static var signInDismissedHint: String {
            Localized.get("provider.signInDismissedHint")
        }

        /// OAuth signing in status
        static func signingIn(_ p1: String) -> String {
            String(format: Localized.get("provider.signingIn"), p1)
        }

        enum Status {
            /// A success message displayed after successfully connecting to a medication provider.
            static func connectedTo(_ p1: String) -> String {
                String(format: Localized.get("provider.status.connectedTo"), p1)
            }

            /// A message displayed when a user successfully connects their account to OpenRouter.
            static var connectedToOpenRouter: String {
                Localized.get("provider.status.connectedToOpenRouter")
            }

            /// A description of a connection that is currently active.
            static var connectionActive: String {
                Localized.get("provider.status.connectionActive")
            }
        }

        /// Generic retry button label
        static var tryAgain: String {
            Localized.get("provider.tryAgain")
        }

        /// The title of the view that explains the use of cloud AI by Eigin.
        static var typeLabel: String {
            Localized.get("provider.typeLabel")
        }
    }

    enum Schedule {
        enum EmptyState {
            /// A message displayed when there are no events logged in the background prompt log.
            static var noEvents: String {
                Localized.get("schedule.emptyState.noEvents")
            }
        }
    }

    enum Settings {
        enum Action {
            /// Button label to add a new MCP server
            static var addMcpServer: String {
                Localized.get("settings.action.addMcpServer")
            }

            /// Button label to add a new provider
            static var addProvider: String {
                Localized.get("settings.action.addProvider")
            }
        }

        /// Settings section header for administrative/debug actions
        static var administration: String {
            Localized.get("settings.administration")
        }

        /// The header text for the "Advanced" section in the settings menu.
        static var advanced: String {
            Localized.get("settings.advanced")
        }

        /// Settings section header for appearance options (theme, etc.)
        static var appearance: String {
            Localized.get("settings.appearance")
        }

        /// Settings section header for agent awareness and context options
        static var awareness: String {
            Localized.get("settings.awareness")
        }

        /// Settings item label for the background prompt configuration
        static var backgroundPrompt: String {
            Localized.get("settings.backgroundPrompt")
        }

        /// Settings item label to view the background prompt log
        static var backgroundPromptLog: String {
            Localized.get("settings.backgroundPromptLog")
        }

        /// Settings item label for the background scheduler configuration
        static var backgroundScheduler: String {
            Localized.get("settings.backgroundScheduler")
        }

        /// Label for the balanced proactivity level option
        static var balanced: String {
            Localized.get("settings.balanced")
        }

        /// A button label that clears the background prompt log.
        static var clearLog: String {
            Localized.get("settings.clearLog")
        }

        enum ClearModelStorage {
            /// A footer text in the Model Storage view that explains the purpose of the "Delete all
            /// listed" button.
            static var description: String {
                Localized.get("settings.clearModelStorage.description")
            }
        }

        enum DebugMode {
            /// Settings toggle label for debug mode, which reveals private data in logs
            static var label: String {
                Localized.get("settings.debugMode.label")
            }
        }

        /// The text that appears next to the icon in the "Development" section of the settings
        /// menu.
        static var development: String {
            Localized.get("settings.development")
        }

        /// A button label that triggers the export of the app's log file.
        static var exportLog: String {
            Localized.get("settings.exportLog")
        }

        enum ImportData {
            /// Destructive action confirmation message shown before replacing all app data with an
            /// import
            static var confirmation: String {
                Localized.get("settings.importData.confirmation")
            }

            /// Settings item label for the import data action
            static var label: String {
                Localized.get("settings.importData.label")
            }
        }

        enum Info {
            /// Describes how many models are available for a provider
            static func modelsAvailable(_ p1: String) -> String {
                String(format: Localized.get("settings.info.modelsAvailable"), p1)
            }
        }

        enum Label {
            /// Navigation link label for tool permissions
            static var permissions: String {
                Localized.get("settings.label.permissions")
            }
        }

        enum Log {
            /// A message displayed when there are no log entries to display.
            static var empty: String {
                Localized.get("settings.log.empty")
            }
        }

        /// A section header in the advanced settings view, describing logging options.
        static var logging: String {
            Localized.get("settings.logging")
        }

        enum Logging {
            /// Button to clear the log file
            static var clearLog: String {
                Localized.get("settings.logging.clearLog")
            }

            /// A description of the "Log to File" toggle in the advanced settings view.
            static var description: String {
                Localized.get("settings.logging.description")
            }

            /// Button to export the log file
            static var exportLog: String {
                Localized.get("settings.logging.exportLog")
            }

            /// Toggle label for file logging
            static var logToFile: String {
                Localized.get("settings.logging.logToFile")
            }

            /// Section header for logging settings
            static var sectionTitle: String {
                Localized.get("settings.logging.sectionTitle")
            }
        }

        enum Permissions {
            /// Default permission level option
            static var defaultLabel: String {
                Localized.get("settings.permissions.defaultLabel")
            }

            /// Label for MCP servers section
            static var mcpServers: String {
                Localized.get("settings.permissions.mcpServers")
            }

            /// Navigation title for tool permissions
            static var title: String {
                Localized.get("settings.permissions.title")
            }
        }

        /// A label displayed above the section for managing an agent's proactivity settings.
        static var proactivity: String {
            Localized.get("settings.proactivity")
        }

        enum Proactivity {
            enum Balanced {
                /// Full description of the balanced proactivity mode
                static var description: String {
                    Localized.get("settings.proactivity.balanced.description")
                }

                /// Short one-line summary of the balanced proactivity mode
                static var short: String {
                    Localized.get("settings.proactivity.balanced.short")
                }
            }

            enum Proactive {
                /// Full description of the high proactivity mode
                static var description: String {
                    Localized.get("settings.proactivity.proactive.description")
                }

                /// Short one-line summary of the high proactivity mode
                static var short: String {
                    Localized.get("settings.proactivity.proactive.short")
                }
            }

            enum Reactive {
                /// Full description of the reactive (off) proactivity mode
                static var description: String {
                    Localized.get("settings.proactivity.reactive.description")
                }

                /// Short one-line summary of the reactive proactivity mode
                static var short: String {
                    Localized.get("settings.proactivity.reactive.short")
                }
            }
        }

        /// Settings item label to restart the onboarding flow (debug/admin)
        static var reTriggerOnboarding: String {
            Localized.get("settings.reTriggerOnboarding")
        }

        enum Schedule {
            /// A button label for scheduling a background review with a balanced interval.
            static var balanced: String {
                Localized.get("settings.schedule.balanced")
            }

            /// A button that reschedules the background prompt for a proactive interval.
            static var proactive: String {
                Localized.get("settings.schedule.proactive")
            }
        }

        enum Section {
            /// Section header for advanced settings
            static var advanced: String {
                Localized.get("settings.section.advanced")
            }

            /// Section header for development tools
            static var development: String {
                Localized.get("settings.section.development")
            }
        }

        /// A button that sends a test notification to the user.
        static var sendTestNotification: String {
            Localized.get("settings.sendTestNotification")
        }

        /// Section header for speech engine assets
        static var speechEngine: String {
            Localized.get("settings.speechEngine")
        }

        /// A label displayed under the button that allows the user to change the response speed of
        /// a live call.
        static var turnDelay: String {
            Localized.get("settings.turnDelay")
        }

        /// Settings item label to open the app log viewer
        static var viewLog: String {
            Localized.get("settings.viewLog")
        }

        /// A label displayed in the settings section of the agent profile view, related to voice
        /// selection.
        static var voice: String {
            Localized.get("settings.voice")
        }
    }

    enum Skills {
        /// Navigation title for skills list
        static var title: String {
            Localized.get("skills.title")
        }
    }

    enum Space {
        enum Alert {
            /// Alert title for space deletion confirmation
            static var deleteTitle: String {
                Localized.get("space.alert.deleteTitle")
            }
        }

        enum Bootstrap {
            /// Button to finish space setup
            static var finishSetup: String {
                Localized.get("space.bootstrap.finishSetup")
            }

            /// Navigation title for space bootstrap
            static var title: String {
                Localized.get("space.bootstrap.title")
            }
        }

        /// An alert message that appears when the user confirms deleting a space. It explains that
        /// the chats and memories in the deleted space will be moved to the "All Chats" space.
        static var deleteWarning: String {
            Localized.get("space.deleteWarning")
        }

        enum Detail {
            enum Action {
                /// Destructive action button to delete a space
                static var deleteSpace: String {
                    Localized.get("space.detail.action.deleteSpace")
                }
            }

            enum Hint {
                /// Hint text for private space toggle
                static var `private`: String {
                    Localized.get("space.detail.hint.private")
                }
            }

            enum Label {
                /// Toggle label for private space
                static var `private`: String {
                    Localized.get("space.detail.label.private")
                }
            }

            enum Section {
                /// Section header for space presentation
                static var presentation: String {
                    Localized.get("space.detail.section.presentation")
                }

                /// Section header for space privacy
                static var privacy: String {
                    Localized.get("space.detail.section.privacy")
                }
            }
        }

        enum EmptyState {
            /// A description text displayed when there are no spaces to show. It encourages the
            /// user to add a new space.
            static var hint: String {
                Localized.get("space.emptyState.hint")
            }
        }

        enum Filter {
            /// Label for all chats filter option
            static var allChats: String {
                Localized.get("space.filter.allChats")
            }

            /// Button to manage spaces
            static var manageSpaces: String {
                Localized.get("space.filter.manageSpaces")
            }
        }

        enum Label {
            /// Toggle label for space privacy
            static var `private`: String {
                Localized.get("space.label.private")
            }
        }

        enum List {
            /// Chat count with plural suffix
            static func chatsCount(_ p1: String) -> String {
                String(format: Localized.get("space.list.chatsCount"), p1)
            }

            /// Navigation title for space list
            static var title: String {
                Localized.get("space.list.title")
            }

            /// Placeholder for unnamed space
            static var untitledSpace: String {
                Localized.get("space.list.untitledSpace")
            }
        }

        enum Privacy {
            /// A description of what happens when a space is marked as private.
            static var hint: String {
                Localized.get("space.privacy.hint")
            }

            /// Placeholder text for unnamed space
            static var untitled: String {
                Localized.get("space.privacy.untitled")
            }
        }

        /// A button label that allows a user to remove their active chat from a space.
        static var removeFromSpace: String {
            Localized.get("space.removeFromSpace")
        }

        enum Section {
            /// Section header for space instructions
            static var instructions: String {
                Localized.get("space.section.instructions")
            }
        }

        /// Navigation title for space list
        static var title: String {
            Localized.get("space.title")
        }
    }

    enum Status {
        /// A status indicating that a tool call has completed successfully.
        static var completed: String {
            Localized.get("status.completed")
        }

        /// Short status label shown while an asset is downloading
        static var downloading: String {
            Localized.get("status.downloading")
        }

        /// A text label below the progress bar indicating the percentage of the download that has
        /// occurred.
        static func downloadingProgress(_ p1: String) -> String {
            String(format: Localized.get("status.downloadingProgress"), p1)
        }

        /// A label indicating that an action failed.
        static var error: String {
            Localized.get("status.error")
        }

        /// A status indicating that a tool call is currently executing.
        static var executing: String {
            Localized.get("status.executing")
        }

        /// A placeholder text indicating that a task is currently in progress.
        static var executingProgress: String {
            Localized.get("status.executingProgress")
        }

        /// A tool call that failed, displayed in red text.
        static func failedFormat(_ p1: String) -> String {
            String(format: Localized.get("status.failedFormat"), p1)
        }

        /// Short status label shown while an asset or model is being prepared/compiled
        static var preparing: String {
            Localized.get("status.preparing")
        }

        /// Longer status label shown while the device is being prepared for the model
        static var preparingDevice: String {
            Localized.get("status.preparingDevice")
        }

        /// Short status label shown when an asset is ready to use
        static var ready: String {
            Localized.get("status.ready")
        }
    }

    enum Timestamp {
        /// Relative timestamp group label for messages sent moments ago
        static var justNow: String {
            Localized.get("timestamp.justNow")
        }

        /// Relative timestamp group label for messages from last week
        static var lastWeek: String {
            Localized.get("timestamp.lastWeek")
        }

        /// Relative timestamp group label for messages older than this month
        static var older: String {
            Localized.get("timestamp.older")
        }

        /// Relative timestamp group label for messages from this month
        static var thisMonth: String {
            Localized.get("timestamp.thisMonth")
        }

        /// Relative timestamp group label for messages from this week
        static var thisWeek: String {
            Localized.get("timestamp.thisWeek")
        }

        /// Relative timestamp group label for messages from today
        static var today: String {
            Localized.get("timestamp.today")
        }

        /// Relative timestamp group label for messages from yesterday
        static var yesterday: String {
            Localized.get("timestamp.yesterday")
        }
    }

    enum Tool {
        enum Group {
            /// Label showing number of tools used
            static func toolsUsed(_ p1: String) -> String {
                String(format: Localized.get("tool.group.toolsUsed"), p1)
            }
        }
    }

    enum ToolCategory {
        /// Tool category label for agent-related tools
        static var agent: String {
            Localized.get("toolCategory.agent")
        }

        /// Tool category label for chat-related tools
        static var chats: String {
            Localized.get("toolCategory.chats")
        }

        /// Tool category label for external/MCP tools
        static var external: String {
            Localized.get("toolCategory.external")
        }

        /// Tool category label for system-level tools
        static var system: String {
            Localized.get("toolCategory.system")
        }
    }

    enum Tools {
        enum Add {
            /// Display name for the add-fact tool
            static var fact: String {
                Localized.get("tools.add.fact")
            }

            /// Display name for the add-knowledge tool
            static var knowledge: String {
                Localized.get("tools.add.knowledge")
            }

            /// Display name for the add-provider tool
            static var provider: String {
                Localized.get("tools.add.provider")
            }
        }

        enum Agent {
            /// Display name for the activate-skill tool
            static var activateSkill: String {
                Localized.get("tools.agent.activateSkill")
            }

            /// Display name for the list-intents tool
            static var listIntents: String {
                Localized.get("tools.agent.listIntents")
            }

            /// Display name for the resolve-intent tool
            static var resolveIntent: String {
                Localized.get("tools.agent.resolveIntent")
            }

            /// Display name for the set-intent tool
            static var setIntent: String {
                Localized.get("tools.agent.setIntent")
            }
        }

        enum Clear {
            /// Display name for the clear-transcripts tool
            static var transcripts: String {
                Localized.get("tools.clear.transcripts")
            }
        }

        enum Compose {
            /// Display name for the compose-email tool
            static var email: String {
                Localized.get("tools.compose.email")
            }
        }

        enum Custom {
            /// Display name for the custom-provider tool
            static var provider: String {
                Localized.get("tools.custom.provider")
            }
        }

        enum Delete {
            /// Display name for the delete-knowledge tool
            static var knowledge: String {
                Localized.get("tools.delete.knowledge")
            }

            /// Display name for the delete-space tool
            static var space: String {
                Localized.get("tools.delete.space")
            }
        }

        enum Deselect {
            /// Button/tool label to deselect all items in a list
            static var all: String {
                Localized.get("tools.deselect.all")
            }
        }

        enum Discovered {
            /// Section header for MCP tools discovered at runtime
            static var tools: String {
                Localized.get("tools.discovered.tools")
            }
        }

        enum Edit {
            /// Display name for the edit-core (agent identity) tool
            static var core: String {
                Localized.get("tools.edit.core")
            }
        }

        enum EmptyState {
            /// A message displayed when there are no tools available to discover.
            static var notAvailable: String {
                Localized.get("tools.emptyState.notAvailable")
            }

            /// A message displayed when a server has not yet discovered any tools.
            static var notDiscovered: String {
                Localized.get("tools.emptyState.notDiscovered")
            }
        }

        enum Error {
            /// Label for the error details section in a tool result
            static var details: String {
                Localized.get("tools.error.details")
            }
        }

        enum Export {
            enum All {
                /// Display name for the export-all-data tool
                static var data: String {
                    Localized.get("tools.export.all.data")
                }
            }
        }

        enum Finish {
            /// Display name for the finish-setup tool used during onboarding chat
            static var setup: String {
                Localized.get("tools.finish.setup")
            }
        }

        enum Forget {
            /// Display name for the forget-memory tool
            static var memory: String {
                Localized.get("tools.forget.memory")
            }
        }

        enum Get {
            enum Chat {
                /// Display name for the get-chat-transcript tool
                static var transcript: String {
                    Localized.get("tools.get.chat.transcript")
                }
            }

            enum Food {
                /// Display name for the get-food-details tool
                static var details: String {
                    Localized.get("tools.get.food.details")
                }

                /// Display name for the get-food-log tool
                static var log: String {
                    Localized.get("tools.get.food.log")
                }
            }

            /// Display name for the get-presentation tool
            static var presentation: String {
                Localized.get("tools.get.presentation")
            }
        }

        enum Knowledge {
            /// Display name for the get-knowledge tool
            static var get: String {
                Localized.get("tools.knowledge.get")
            }

            /// Display name for the search-knowledge tool
            static var search: String {
                Localized.get("tools.knowledge.search")
            }
        }

        enum Last {
            /// Label showing when a piece of data was last updated
            static var updated: String {
                Localized.get("tools.last.updated")
            }
        }

        enum List {
            /// Display name for the list-chats tool
            static var chats: String {
                Localized.get("tools.list.chats")
            }
        }

        enum Log {
            /// Display name for the log-food tool
            static var food: String {
                Localized.get("tools.log.food")
            }
        }

        enum Manage {
            /// Display name for the manage-spaces tool
            static var spaces: String {
                Localized.get("tools.manage.spaces")
            }

            /// Display name for the manage-vocabulary tool
            static var vocabulary: String {
                Localized.get("tools.manage.vocabulary")
            }
        }

        enum Minimum {
            /// Label for the minimum permission level selector
            static var level: String {
                Localized.get("tools.minimum.level")
            }
        }

        enum Model {
            /// Display name for the model-storage tool
            static var storage: String {
                Localized.get("tools.model.storage")
            }
        }

        enum New {
            /// Display name for the new-chat tool
            static var chat: String {
                Localized.get("tools.new.chat")
            }

            /// Display name for the new-space tool
            static var space: String {
                Localized.get("tools.new.space")
            }
        }

        enum No {
            enum Active {
                /// Empty state label shown when no intents are currently active
                static var intents: String {
                    Localized.get("tools.no.active.intents")
                }
            }

            /// Empty state label shown when no chats exist
            static var chats: String {
                Localized.get("tools.no.chats")
            }

            /// Empty state label shown when no knowledge entries exist
            static var knowledge: String {
                Localized.get("tools.no.knowledge")
            }

            /// Empty state label shown when no memories exist
            static var memories: String {
                Localized.get("tools.no.memories")
            }
        }

        enum Other {
            /// Section header for non-primary voice engine options
            static var voices: String {
                Localized.get("tools.other.voices")
            }
        }

        enum Read {
            /// Display name for the read-core (agent identity) tool
            static var core: String {
                Localized.get("tools.read.core")
            }
        }

        enum Recall {
            /// Display name for the recall-memory tool
            static var memory: String {
                Localized.get("tools.recall.memory")
            }
        }

        enum Rename {
            /// Display name for the rename-chat tool
            static var chat: String {
                Localized.get("tools.rename.chat")
            }
        }

        enum Run {
            enum Sanity {
                /// Display name for the sanity-check debug tool
                static var check: String {
                    Localized.get("tools.run.sanity.check")
                }
            }
        }

        enum Save {
            /// Display name for the save-memory tool
            static var memory: String {
                Localized.get("tools.save.memory")
            }
        }

        enum Schedule {
            /// A label for a button that cancels a previously scheduled background task.
            static var cancelTask: String {
                Localized.get("tools.schedule.cancelTask")
            }

            /// Display name for the create-calendar-event tool
            static var createEvent: String {
                Localized.get("tools.schedule.createEvent")
            }

            /// Display name for the get-calendar-events tool
            static var getEvents: String {
                Localized.get("tools.schedule.getEvents")
            }

            /// Display name for the get-reminders tool
            static var getReminders: String {
                Localized.get("tools.schedule.getReminders")
            }

            /// Display name for the manage-calendar-event tool
            static var manageEvent: String {
                Localized.get("tools.schedule.manageEvent")
            }

            /// Display name for the manage-reminder tool
            static var manageReminder: String {
                Localized.get("tools.schedule.manageReminder")
            }
        }

        enum Search {
            /// Display name for the search-food tool
            static var food: String {
                Localized.get("tools.search.food")
            }

            /// Display name for the search-memories tool
            static var memories: String {
                Localized.get("tools.search.memories")
            }
        }

        /// A label displayed above a list of tools discovered on a server.
        static var sectionTitle: String {
            Localized.get("tools.sectionTitle")
        }

        enum Select {
            /// Button/tool label to select all items in a list
            static var all: String {
                Localized.get("tools.select.all")
            }

            /// Display name for the select-models tool
            static var models: String {
                Localized.get("tools.select.models")
            }
        }

        enum Set {
            /// Display name for the set-language tool
            static var language: String {
                Localized.get("tools.set.language")
            }

            /// Display name for the set-presentation tool
            static var presentation: String {
                Localized.get("tools.set.presentation")
            }

            /// Display name for the set-proactivity tool
            static var proactivity: String {
                Localized.get("tools.set.proactivity")
            }
        }

        enum Share {
            enum Export {
                /// Display name for the share-export-file tool
                static var file: String {
                    Localized.get("tools.share.export.file")
                }
            }
        }

        enum Space {
            /// Display name for the create-space tool
            static var create: String {
                Localized.get("tools.space.create")
            }

            /// Display name for the edit-space tool
            static var edit: String {
                Localized.get("tools.space.edit")
            }

            /// Display name for the list-spaces tool
            static var list: String {
                Localized.get("tools.space.list")
            }

            /// Display name for the move-chat-to-space tool
            static var moveChat: String {
                Localized.get("tools.space.moveChat")
            }
        }

        enum System {
            /// Display name for the background-notify system tool
            static var backgroundNotify: String {
                Localized.get("tools.system.backgroundNotify")
            }

            /// Display name for the done/finish system tool
            static var done: String {
                Localized.get("tools.system.done")
            }

            /// Display name for the get-time-and-place system tool
            static var timeAndPlace: String {
                Localized.get("tools.system.timeAndPlace")
            }
        }

        enum Trigger {
            /// A button label that triggers a background review.
            static var backgroundReview: String {
                Localized.get("tools.trigger.backgroundReview")
            }

            enum Initiative {
                /// Display name for the debug tool that manually triggers an initiative run
                static var run: String {
                    Localized.get("tools.trigger.initiative.run")
                }
            }

            enum Maintenance {
                /// Display name for the debug tool that manually triggers a maintenance run
                static var run: String {
                    Localized.get("tools.trigger.maintenance.run")
                }
            }
        }

        enum Update {
            /// Display name for the update-fact tool
            static var fact: String {
                Localized.get("tools.update.fact")
            }

            /// Display name for the update-knowledge tool
            static var knowledge: String {
                Localized.get("tools.update.knowledge")
            }

            /// Display name for the update-memory tool
            static var memory: String {
                Localized.get("tools.update.memory")
            }
        }

        enum Web {
            /// Display name for the web-fetch tool
            static var fetch: String {
                Localized.get("tools.web.fetch")
            }

            /// Display name for the web-search tool
            static var search: String {
                Localized.get("tools.web.search")
            }
        }
    }

    enum Ui {
        /// Button label to switch from OAuth to manual API key entry
        static var addApiKeyManually: String {
            Localized.get("ui.add-api-key-manually")
        }

        /// Button label to add a new MCP server
        static var addMcpServer: String {
            Localized.get("ui.add-mcp-server")
        }

        /// Tab or navigation label for the agent screen
        static var agent: String {
            Localized.get("ui.agent")
        }

        /// Field placeholder or label for the agent name input
        static var agentName: String {
            Localized.get("ui.agent-name")
        }

        /// Generic 'All' filter or tab label
        static var all: String {
            Localized.get("ui.all")
        }

        /// Button label to start an authorization flow
        static var authorize: String {
            Localized.get("ui.authorize")
        }

        /// Field placeholder or label for the chat name input
        static var chatName: String {
            Localized.get("ui.chat-name")
        }

        /// Tab or navigation label for the chats screen
        static var chats: String {
            Localized.get("ui.chats")
        }

        /// Field label for the OAuth client ID input
        static var clientId: String {
            Localized.get("ui.client-id")
        }

        /// Inline status label shown while the conversation is being compacted
        static var compacting: String {
            Localized.get("ui.compacting")
        }

        /// Button label to initiate a provider connection
        static var connect: String {
            Localized.get("ui.connect")
        }

        /// Short error title when a network request times out
        static var connectionTimedOut: String {
            Localized.get("ui.connection-timed-out")
        }

        /// Label for the agent's core identity section
        static var core: String {
            Localized.get("ui.core")
        }

        /// Label showing when an item was created
        static var created: String {
            Localized.get("ui.created")
        }

        /// Label for a custom/user-defined option
        static var custom: String {
            Localized.get("ui.custom")
        }

        /// A text option in a picker, representing the default permission level for a tool.
        static var defaultLabel: String {
            Localized.get("ui.defaultLabel")
        }

        /// Destructive action confirmation title for deleting a chat
        static var deleteChat: String {
            Localized.get("ui.delete-chat")
        }

        /// Destructive action confirmation title for deleting a memory
        static var deleteMemory: String {
            Localized.get("ui.delete-memory")
        }

        /// Destructive action confirmation title for deleting a space
        static var deleteSpace: String {
            Localized.get("ui.delete-space")
        }

        /// Generic 'Details' section label
        static var details: String {
            Localized.get("ui.details")
        }

        /// Generic dismiss button label
        static var dismiss: String {
            Localized.get("ui.dismiss")
        }

        /// Destructive action confirmation title for dismissing an intent
        static var dismissIntent: String {
            Localized.get("ui.dismiss-intent")
        }

        /// Field label or tab label for email
        static var email: String {
            Localized.get("ui.email")
        }

        /// Button label to end a live call
        static var end: String {
            Localized.get("ui.end")
        }

        /// Short error title when the API endpoint is not found (HTTP 404)
        static var endpointNotFound: String {
            Localized.get("ui.endpoint-not-found")
        }

        /// Badge label for experimental features
        static var experimental: String {
            Localized.get("ui.experimental")
        }

        /// Speed tier label — fast model option
        static var fast: String {
            Localized.get("ui.fast")
        }

        /// Section label for structured data fields
        static var fields: String {
            Localized.get("ui.fields")
        }

        /// Tab or section label for the food tracking feature
        static var food: String {
            Localized.get("ui.food")
        }

        /// A label showing the number of selected models in a section header. The first argument is
        /// the count of selected models. The second argument is the total count of models in the
        /// section.
        static func fractionFormat(_ p1: String, _ p2: String) -> String {
            String(format: Localized.get("ui.fractionFormat"), p1, p2)
        }

        /// Display name for the Gemma 4 E2B CoreML on-device model
        static var gemma4E2bCoreml: String {
            Localized.get("ui.gemma-4-e2b-coreml")
        }

        /// Success message shown after a data import completes
        static var importSuccessful: String {
            Localized.get("ui.import-successful")
        }

        /// Field label for the agent instruction input
        static var instruction: String {
            Localized.get("ui.instruction")
        }

        /// Label for a single agent intent
        static var intent: String {
            Localized.get("ui.intent")
        }

        /// Short error title when the entered URL is invalid
        static var invalidUrl: String {
            Localized.get("ui.invalid-url")
        }

        /// Settings item label for the language selector
        static var language: String {
            Localized.get("ui.language")
        }

        /// Button label to load newer messages in a paginated chat
        static var loadNewerMessages: String {
            Localized.get("ui.load-newer-messages")
        }

        /// Button label to load older messages in a paginated chat
        static var loadOlderMessages: String {
            Localized.get("ui.load-older-messages")
        }

        /// Settings toggle label for file-based logging
        static var logToFile: String {
            Localized.get("ui.log-to-file")
        }

        /// Section or tab label for the MCP servers list
        static var mcpServers: String {
            Localized.get("ui.mcp-servers")
        }

        /// Tab or section label for the memory feature
        static var memory: String {
            Localized.get("ui.memory")
        }

        /// Generic label for a message item
        static var message: String {
            Localized.get("ui.message")
        }

        /// Button label to move a chat into a space
        static var moveToSpace: String {
            Localized.get("ui.move-to-space")
        }

        /// Generic field label for a name input
        static var name: String {
            Localized.get("ui.name")
        }

        /// Empty state label shown in a chat with no messages
        static var noMessagesYet: String {
            Localized.get("ui.no-messages-yet")
        }

        /// Generic 'None' option label
        static var none: String {
            Localized.get("ui.none")
        }

        /// Placeholder shown when a value has not been configured
        static var notSet: String {
            Localized.get("ui.not-set")
        }

        /// Settings section or tab label for notification settings
        static var notifications: String {
            Localized.get("ui.notifications")
        }

        /// Field label for the organization/team identifier input
        static var organization: String {
            Localized.get("ui.organization")
        }

        /// Generic 'Other' grouping label
        static var other: String {
            Localized.get("ui.other")
        }

        /// A label showing the percentage of the download that has completed.
        static func percentageFormat(_ p1: String) -> String {
            String(format: Localized.get("ui.percentageFormat"), p1)
        }

        /// A toggle switch label that indicates whether a space is private or public.
        static var privateLabel: String {
            Localized.get("ui.privateLabel")
        }

        /// Label for the proactive agent mode
        static var proactive: String {
            Localized.get("ui.proactive")
        }

        /// Label for a single provider item
        static var provider: String {
            Localized.get("ui.provider")
        }

        /// Tab or section label for the providers list
        static var providers: String {
            Localized.get("ui.providers")
        }

        /// Short error title when the provider returns HTTP 429
        static var rateLimited: String {
            Localized.get("ui.rate-limited")
        }

        /// Button label to re-run the OAuth authorization flow
        static var reAuthorize: String {
            Localized.get("ui.re-authorize")
        }

        /// Label for the reactive (no proactivity) agent mode
        static var reactive: String {
            Localized.get("ui.reactive")
        }

        /// Badge or label for recommended options
        static var recommended: String {
            Localized.get("ui.recommended")
        }

        /// Label for the reinforced memory strength level
        static var reinforced: String {
            Localized.get("ui.reinforced")
        }

        /// Section label for relationship facts
        static var relationships: String {
            Localized.get("ui.relationships")
        }

        /// Generic remove button label
        static var remove: String {
            Localized.get("ui.remove")
        }

        /// Generic rename button label
        static var rename: String {
            Localized.get("ui.rename")
        }

        /// Generic reset button label
        static var reset: String {
            Localized.get("ui.reset")
        }

        /// Status label shown while the app is scanning for available tools or servers
        static var scanning: String {
            Localized.get("ui.scanning")
        }

        /// Section label for scheduling/calendar features
        static var scheduling: String {
            Localized.get("ui.scheduling")
        }

        /// Placeholder text for the model search field
        static var searchModels: String {
            Localized.get("ui.search-models")
        }

        /// Placeholder text for the provider search field
        static var searchProviders: String {
            Localized.get("ui.search-providers")
        }

        /// Settings section label for security options
        static var security: String {
            Localized.get("ui.security")
        }

        /// Label showing how many items are selected; %lld is substituted with the count
        static func selectedCount(_ p1: String) -> String {
            String(format: Localized.get("ui.selectedCount"), p1)
        }

        /// A label at the top of the model selection view that shows the number of models currently
        /// selected.
        static func selectedCountStr(_ p1: String) -> String {
            String(format: Localized.get("ui.selectedCountStr"), p1)
        }

        /// Permission category label for tools that allow the agent to modify itself
        static var selfModification: String {
            Localized.get("ui.self-modification")
        }

        /// Short error title when DNS resolution fails for the server hostname
        static var serverNotFound: String {
            Localized.get("ui.server-not-found")
        }

        /// Field label for the server URL input (e.g. MCP server)
        static var serverUrl: String {
            Localized.get("ui.server-url")
        }

        /// Tab or navigation label for the settings screen
        static var settings: String {
            Localized.get("ui.settings")
        }

        /// A button that lets the user view all facts of a particular type. The number in
        /// parentheses is replaced with the actual number of facts of that type.
        static func showAll(_ p1: String) -> String {
            String(format: Localized.get("ui.showAll"), p1)
        }

        /// Speed tier label — slow but powerful model option
        static var slow: String {
            Localized.get("ui.slow")
        }

        /// Label for the source/origin of a knowledge item
        static var source: String {
            Localized.get("ui.source")
        }

        /// Label for a single space item
        static var space: String {
            Localized.get("ui.space")
        }

        /// Field placeholder or label for the space name input
        static var spaceName: String {
            Localized.get("ui.space-name")
        }

        /// Tab or section label for the spaces list
        static var spaces: String {
            Localized.get("ui.spaces")
        }

        /// A section header for the connection status of an MCP server.
        static var status: String {
            Localized.get("ui.status")
        }

        /// Label for the memory strength indicator
        static var strength: String {
            Localized.get("ui.strength")
        }

        /// Section label for item tags
        static var tags: String {
            Localized.get("ui.tags")
        }

        /// Settings item label for the theme selector
        static var theme: String {
            Localized.get("ui.theme")
        }

        /// A heading that describes the content of the timeline section in the transcript view.
        static func timeline(_ p1: String) -> String {
            String(format: Localized.get("ui.timeline"), p1)
        }

        /// Label showing how many times something has occurred; %lld is substituted with the count
        static func timesCount(_ p1: String) -> String {
            String(format: Localized.get("ui.timesCount"), p1)
        }

        /// A label describing how many times a given intent has been reinforced. The argument is
        /// the number of times the intent has been reinforced.
        static func timesCountStr(_ p1: String) -> String {
            String(format: Localized.get("ui.timesCountStr"), p1)
        }

        /// A label within the checkout view displaying the title of a notification that was
        /// presented to the user.
        static func titleLabel(_ p1: String) -> String {
            String(format: Localized.get("ui.titleLabel"), p1)
        }

        /// Label showing how many tools are available; %lld is substituted with the count
        static func toolsCount(_ p1: String) -> String {
            String(format: Localized.get("ui.toolsCount"), p1)
        }

        /// A label showing the number of tools available on a given server. The argument is the
        /// count of tools available on the server.
        static func toolsCountStr(_ p1: String) -> String {
            String(format: Localized.get("ui.toolsCountStr"), p1)
        }

        /// Label showing how many tools were used; %lld is substituted with the count
        static func toolsUsedCount(_ p1: String) -> String {
            String(format: Localized.get("ui.toolsUsedCount"), p1)
        }

        /// A label at the bottom of the collapsed tool group, showing the total number of tools
        /// used.
        static func toolsUsedCountStr(_ p1: String) -> String {
            String(format: Localized.get("ui.toolsUsedCountStr"), p1)
        }

        /// Generic 'Total' summary label
        static var total: String {
            Localized.get("ui.total")
        }

        /// Generic field label for a type/category selector
        static var type: String {
            Localized.get("ui.type")
        }

        /// Short error title when the server response cannot be decoded
        static var unexpectedResponse: String {
            Localized.get("ui.unexpected-response")
        }

        /// Generic field label for a URL input
        static var url: String {
            Localized.get("ui.url")
        }

        /// Settings toggle label to enable or disable MCP server usage
        static var useMcpServers: String {
            Localized.get("ui.use-mcp-servers")
        }

        /// Speed tier label — warm (mid-tier) model option
        static var warm: String {
            Localized.get("ui.warm")
        }

        /// Tab or section label for web-related features
        static var web: String {
            Localized.get("ui.web")
        }

        /// Generic 'Yes' confirmation label
        static var yes: String {
            Localized.get("ui.yes")
        }
    }

    enum Voice {
        /// Download description for the Danish voice model size
        static var danishDescription: String {
            Localized.get("voice.danishDescription")
        }

        /// Display name for the Danish (Plapre Pico) voice model
        static var danishName: String {
            Localized.get("voice.danishName")
        }

        /// Download description for the enhanced voice model size
        static var enhancedDescription: String {
            Localized.get("voice.enhancedDescription")
        }

        /// Display name for the enhanced (Pocket TTS) voice model
        static var enhancedName: String {
            Localized.get("voice.enhancedName")
        }

        /// A footer text that encourages users to install more voices if they haven't already.
        static var installHint: String {
            Localized.get("voice.installHint")
        }

        /// Status label shown while the microphone is active and listening
        static var listening: String {
            Localized.get("voice.listening")
        }

        /// Status label shown while the TTS engine is speaking
        static var speaking: String {
            Localized.get("voice.speaking")
        }
    }
}
