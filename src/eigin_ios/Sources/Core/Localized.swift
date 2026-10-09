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

    enum Actions {
        /// Title of the action sheet shown from the chat input bar.
        static var title: String {
            Localized.get("actions.title")
        }
    }

    enum Agent {
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

        /// Status label shown while the agent is processing a response
        static var thinking: String {
            Localized.get("agent.thinking")
        }

        /// A heading for the user section of the agent's core.
        static var userLabel: String {
            Localized.get("agent.userLabel")
        }

        enum EmptyState {
            /// A description text displayed when there is no agent set up in the Agent tab.
            static var setupHint: String {
                Localized.get("agent.emptyState.setupHint")
            }
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
            /// Section header for voice selection
            static var voice: String {
                Localized.get("agent.profile.voice")
            }

            enum Section {
                /// Section header and navigation title for the agent's advanced settings
                /// (identity/user/soul documents, knowledge, intents, skills)
                static var advanced: String {
                    Localized.get("agent.profile.section.advanced")
                }

                /// Section header in the agent advanced view grouping knowledge, intents, and
                /// skills
                static var behaviour: String {
                    Localized.get("agent.profile.section.behaviour")
                }

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

            enum Voice {
                /// Footer hint for installing more voices
                static var installHint: String {
                    Localized.get("agent.profile.voice.installHint")
                }
            }
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
    }

    enum Asset {
        static func durationHours(_ p1: String, _ p2: String) -> String {
            String(format: Localized.get("asset.durationHours"), p1, p2)
        }

        static func durationMinutes(_ p1: String) -> String {
            String(format: Localized.get("asset.durationMinutes"), p1)
        }

        static func durationSeconds(_ p1: String) -> String {
            String(format: Localized.get("asset.durationSeconds"), p1)
        }

        static var installed: String {
            Localized.get("asset.installed")
        }

        static var notInstalled: String {
            Localized.get("asset.notInstalled")
        }

        static var preparing: String {
            Localized.get("asset.preparing")
        }

        static var queued: String {
            Localized.get("asset.queued")
        }

        static var readyToUse: String {
            Localized.get("asset.readyToUse")
        }

        static func timeLeft(_ p1: String) -> String {
            String(format: Localized.get("asset.timeLeft"), p1)
        }

        /// Button in the download sheet while a download runs: dismisses the sheet, the asset
        /// switches on by itself once ready.
        static var useWhenReady: String {
            Localized.get("asset.useWhenReady")
        }
    }

    enum Attachment {
        /// Action sheet button label to attach an image from the photo library.
        static var attachImage: String {
            Localized.get("attachment.attachImage")
        }

        /// Body of the sheet shown when the user switches to a non-vision model with a staged
        /// image.
        static var imageStagedOnNonVisionMessage: String {
            Localized.get("attachment.imageStagedOnNonVisionMessage")
        }

        /// Title of the sheet shown when the user switches to a non-vision model with a staged
        /// image.
        static var imageStagedOnNonVisionTitle: String {
            Localized.get("attachment.imageStagedOnNonVisionTitle")
        }

        /// Title shown in the full-screen viewer for a chat image attachment, in place of its
        /// on-disk filename.
        static var previewTitle: String {
            Localized.get("attachment.previewTitle")
        }

        /// Accessibility label for the remove-image button on a staged attachment thumbnail.
        static var removeImage: String {
            Localized.get("attachment.removeImage")
        }

        /// Action sheet button label to take a new photo with the camera.
        static var takePhoto: String {
            Localized.get("attachment.takePhoto")
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

    enum Browsing {
        /// Title of the sheet shown while the agent is browsing a web page.
        static var title: String {
            Localized.get("browsing.title")
        }
    }

    enum Capability {
        /// The Aula capability, e.g. a connected Aula account.
        static var aula: String {
            Localized.get("capability.aula")
        }

        /// The email capability, e.g. a connected Google or IMAP account.
        static var email: String {
            Localized.get("capability.email")
        }
    }

    enum Chat {
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

        /// Status label shown by the thinking figure while something outside the chat turn is being
        /// prepared
        static var gettingThingsReady: String {
            Localized.get("chat.gettingThingsReady")
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

        enum Thinking {
            /// Shown by the thinking indicator when a response is close
            static var almostThere: String {
                Localized.get("chat.thinking.almostThere")
            }

            /// Shown by the thinking indicator for very long waits
            static var sorryForTheWait: String {
                Localized.get("chat.thinking.sorryForTheWait")
            }

            /// Shown by the thinking indicator after a longer wait
            static var stillThinking: String {
                Localized.get("chat.thinking.stillThinking")
            }

            /// Shown by the thinking indicator when the wait is unusually long
            static var takingAWhile: String {
                Localized.get("chat.thinking.takingAWhile")
            }

            /// Shown by the thinking indicator after a short wait
            static var thinking: String {
                Localized.get("chat.thinking.thinking")
            }

            /// Status label shown by the thinking figure while the turn waits for the user to act
            static var waitingForYou: String {
                Localized.get("chat.thinking.waitingForYou")
            }
        }

        enum Working {
            /// Shown by the thinking indicator while the agent runs tools, for very long waits
            static var sorryForTheWait: String {
                Localized.get("chat.working.sorryForTheWait")
            }

            /// Shown by the thinking indicator while the agent runs tools, after a longer wait
            static var stillWorking: String {
                Localized.get("chat.working.stillWorking")
            }

            /// Shown by the thinking indicator while the agent runs tools, when the wait is
            /// unusually long
            static var takingAWhile: String {
                Localized.get("chat.working.takingAWhile")
            }

            /// Shown by the thinking indicator while the agent runs tools, after a short wait
            static var working: String {
                Localized.get("chat.working.working")
            }
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

            /// Generic done button label, e.g. on a keyboard toolbar.
            static var done: String {
                Localized.get("common.actions.done")
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

            /// Generic confirmation button.
            static var ok: String {
                Localized.get("common.actions.ok")
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
            /// Field label for a connected integration's account (e.g. email address) in its detail
            /// view
            static var account: String {
                Localized.get("common.fields.account")
            }

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

    enum Credits {
        /// A label showing the number of credits in a wallet.
        static func count(_ p1: String) -> String {
            String(format: Localized.get("credits.count"), p1)
        }

        /// A label displaying the credit count and product identifier for a store product.
        static func countAndProduct(_ p1: String, _ p2: String) -> String {
            String(format: Localized.get("credits.countAndProduct"), p1, p2)
        }

        /// A button label that triggers a diagnostic of the StoreKit framework.
        static var diagnose: String {
            Localized.get("credits.diagnose")
        }

        /// A button label that refreshes the user's credit wallet balances.
        static var refreshBalances: String {
            Localized.get("credits.refreshBalances")
        }
    }

    enum DataCard {
        /// Accessibility hint that a data card branch collapses
        static func collapseHint(_ p1: String) -> String {
            String(format: Localized.get("dataCard.collapseHint"), p1)
        }

        /// Word a data card shows for an empty string value
        static var empty: String {
            Localized.get("dataCard.empty")
        }

        /// Accessibility hint that a data card branch expands
        static func expandHint(_ p1: String) -> String {
            String(format: Localized.get("dataCard.expandHint"), p1)
        }

        /// Fallback name for an unnamed item of an array in a data card
        static func itemLabel(_ p1: String) -> String {
            String(format: Localized.get("dataCard.itemLabel"), p1)
        }

        /// Summary of a collapsed list in a data card
        static func itemsCount(_ p1: String) -> String {
            String(format: Localized.get("dataCard.itemsCount"), p1)
        }

        /// Word a data card shows for a false value
        static var no: String {
            Localized.get("dataCard.no")
        }

        /// Word a data card shows for a JSON null value
        static var none: String {
            Localized.get("dataCard.none")
        }

        /// Button to reveal the rest of a long list in a data card
        static func showAll(_ p1: String) -> String {
            String(format: Localized.get("dataCard.showAll"), p1)
        }

        /// Button to reveal the rest of a long value in a data card
        static var showMore: String {
            Localized.get("dataCard.showMore")
        }

        /// Summary of a collapsed object in a data card
        static func valuesCount(_ p1: String) -> String {
            String(format: Localized.get("dataCard.valuesCount"), p1)
        }

        /// Word a data card shows for a true value
        static var yes: String {
            Localized.get("dataCard.yes")
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

        enum Section {
            /// Section header for model storage
            static var onDeviceModelStorage: String {
                Localized.get("debug.section.onDeviceModelStorage")
            }
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

        enum Credits {
            /// Credits section title and its navigation row in the development menu.
            static var title: String {
                Localized.get("development.credits.title")
            }
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
    }

    enum Emoji {
        /// TextField placeholder for custom emoji input
        static var custom: String {
            Localized.get("emoji.custom")
        }
    }

    enum Errors {
        /// Short error title when a feature or resource is not available
        static var notAvailable: String {
            Localized.get("errors.notAvailable")
        }

        enum Access {
            /// Short error title when the server returns HTTP 403
            static var denied: String {
                Localized.get("errors.access.denied")
            }
        }

        enum Account {
            /// Short error title when the provider account is locked or suspended (HTTP 423)
            static var locked: String {
                Localized.get("errors.account.locked")
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

        enum Aula {
            /// Error shown when an Aula request fails. The argument is the reason.
            static func requestFailed(_ p1: String) -> String {
                String(format: Localized.get("errors.aula.requestFailed"), p1)
            }

            /// Error shown when Aula rejects the login session during connection.
            static var sessionRejected: String {
                Localized.get("errors.aula.sessionRejected")
            }

            /// Error shown when Aula returns a response we can't read during connection.
            static var unexpectedResponse: String {
                Localized.get("errors.aula.unexpectedResponse")
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

        enum Billing {
            /// Short error title when a 400 response suggests a possible billing or credits issue
            static var checkRequired: String {
                Localized.get("errors.billing.checkRequired")
            }

            /// Short error title when the provider requires billing or credits (HTTP 402)
            static var required: String {
                Localized.get("errors.billing.required")
            }
        }

        enum Chatgpt {
            /// Suggestion when the ChatGPT sign-in is no longer valid
            static var invalidUserSuggestion: String {
                Localized.get("errors.chatgpt.invalidUserSuggestion")
            }

            /// Error title when the ChatGPT sign-in is no longer valid
            static var invalidUserTitle: String {
                Localized.get("errors.chatgpt.invalidUserTitle")
            }

            /// Notice body when the user declined ChatGPT plan usage during sign-in
            static var planUsageNotGranted: String {
                Localized.get("errors.chatgpt.planUsageNotGranted")
            }

            /// Suggestion when the signed-in account is not ChatGPT Plus or Pro
            static var plusRequiredSuggestion: String {
                Localized.get("errors.chatgpt.plusRequiredSuggestion")
            }

            /// Error title when the signed-in account is not ChatGPT Plus or Pro
            static var plusRequiredTitle: String {
                Localized.get("errors.chatgpt.plusRequiredTitle")
            }

            /// Suggestion when ChatGPT sign-in could not be completed — causes vary (e.g. an
            /// ineligible subscription)
            static var signinFailedSuggestion: String {
                Localized.get("errors.chatgpt.signinFailedSuggestion")
            }

            /// Title when ChatGPT sign-in could not be completed (may have multiple causes)
            static var signinFailedTitle: String {
                Localized.get("errors.chatgpt.signinFailedTitle")
            }

            /// Suggestion when ChatGPT plan usage is temporarily unavailable
            static var unavailableSuggestion: String {
                Localized.get("errors.chatgpt.unavailableSuggestion")
            }

            /// Error title when ChatGPT plan usage is temporarily unavailable
            static var unavailableTitle: String {
                Localized.get("errors.chatgpt.unavailableTitle")
            }

            /// Suggestion when the request uses something the ChatGPT plan flow doesn't support.
            /// The argument names the unsupported capability.
            static var unsupportedCapabilitySuggestion: String {
                Localized.get("errors.chatgpt.unsupportedCapabilitySuggestion")
            }

            /// Error title when the request uses something the ChatGPT plan flow doesn't support
            static var unsupportedCapabilityTitle: String {
                Localized.get("errors.chatgpt.unsupportedCapabilityTitle")
            }

            /// Suggestion when the ChatGPT plan's usage limit is reached
            static var usageLimitSuggestion: String {
                Localized.get("errors.chatgpt.usageLimitSuggestion")
            }

            /// Error title when the ChatGPT plan's usage limit is reached
            static var usageLimitTitle: String {
                Localized.get("errors.chatgpt.usageLimitTitle")
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

        enum Imap {
            /// Error shown when IMAP login fails during account verification. The argument is the
            /// server's reason.
            static func authFailed(_ p1: String) -> String {
                String(format: Localized.get("errors.imap.authFailed"), p1)
            }

            /// Error shown when connecting to the IMAP server fails during account verification.
            /// The argument is the failure reason.
            static func connectionFailed(_ p1: String) -> String {
                String(format: Localized.get("errors.imap.connectionFailed"), p1)
            }

            /// Error shown when SMTP login fails during account verification. The argument is the
            /// server's reason.
            static func smtpAuthFailed(_ p1: String) -> String {
                String(format: Localized.get("errors.imap.smtpAuthFailed"), p1)
            }

            /// Error shown when connecting to the SMTP server fails during account verification.
            /// The argument is the failure reason.
            static func smtpConnectionFailed(_ p1: String) -> String {
                String(format: Localized.get("errors.imap.smtpConnectionFailed"), p1)
            }

            /// Error shown when TLS negotiation fails during account verification. The argument is
            /// the failure reason.
            static func tlsFailed(_ p1: String) -> String {
                String(format: Localized.get("errors.imap.tlsFailed"), p1)
            }

            /// Generic fallback error shown during IMAP account verification when the failure
            /// doesn't fit a more specific case. The argument is the failure reason.
            static func unknown(_ p1: String) -> String {
                String(format: Localized.get("errors.imap.unknown"), p1)
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
            /// Recovery suggestion when the provider account is locked or suspended (HTTP 423)
            static var accountLocked: String {
                Localized.get("errors.provider.accountLocked")
            }

            /// Error message when the token exchange step of OAuth fails; %@ is substituted with
            /// the underlying reason
            static func apiKeyRetrievalFailed(_ p1: String) -> String {
                String(format: Localized.get("errors.provider.apiKeyRetrievalFailed"), p1)
            }

            /// Recovery suggestion when the provider base URL is rejected as invalid
            static var baseUrlHint: String {
                Localized.get("errors.provider.baseUrlHint")
            }

            /// Recovery suggestion when a 400 response may indicate a billing or credits issue
            static var billingCheckRequired: String {
                Localized.get("errors.provider.billingCheckRequired")
            }

            /// Recovery suggestion when the provider returns HTTP 402 (insufficient credits)
            static var billingRequired: String {
                Localized.get("errors.provider.billingRequired")
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

            /// Recovery suggestion when the provider rejects a request due to invalid parameters
            /// (HTTP 422)
            static var invalidRequest: String {
                Localized.get("errors.provider.invalidRequest")
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

            /// Recovery suggestion when the request payload exceeds the provider's limit (HTTP 413)
            static var requestTooLarge: String {
                Localized.get("errors.provider.requestTooLarge")
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

            /// Short error title when the provider rejects a request due to invalid parameters
            /// (HTTP 422)
            static var invalid: String {
                Localized.get("errors.request.invalid")
            }

            /// Short error title when the request payload is too large for the provider (HTTP 413)
            static var tooLarge: String {
                Localized.get("errors.request.tooLarge")
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
            /// Placeholder text for unset values
            static var notSet: String {
                Localized.get("fact.detail.notSet")
            }

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

    enum ImageCard {
        /// Accessibility label for tapping a linked image card: follows the link in the browser.
        static func a11yOpenHost(_ p1: String) -> String {
            String(format: Localized.get("imageCard.a11yOpenHost"), p1)
        }

        /// Accessibility label for tapping a withheld image card, when its host is unknown.
        static var a11yShowImage: String {
            Localized.get("imageCard.a11yShowImage")
        }

        /// Accessibility label for tapping a withheld image card. The argument is the image's host.
        static func a11yShowImageFrom(_ p1: String) -> String {
            String(format: Localized.get("imageCard.a11yShowImageFrom"), p1)
        }

        /// Accessibility label for tapping a loaded, unlinked image card: opens the full-screen
        /// viewer. The argument is the image's alt text.
        static func a11yViewImage(_ p1: String) -> String {
            String(format: Localized.get("imageCard.a11yViewImage"), p1)
        }

        /// Headline on the cover of an image card whose load failed.
        static var failedHeadline: String {
            Localized.get("imageCard.failedHeadline")
        }

        /// Headline on the cover of a withheld image card, when its host is unknown.
        static var fromAnotherSite: String {
            Localized.get("imageCard.fromAnotherSite")
        }

        /// Headline on the cover of a withheld image card, naming its host.
        static func fromHost(_ p1: String) -> String {
            String(format: Localized.get("imageCard.fromHost"), p1)
        }

        /// Body of the sheet shown before following a link the model chose. The argument is the
        /// link's host, or the whole link where there is none.
        static func leaveDescription(_ p1: String) -> String {
            String(format: Localized.get("imageCard.leaveDescription"), p1)
        }

        /// Title of the sheet shown before following a link the model chose: the check before a
        /// link leaves Eigin.
        static var leaveTitle: String {
            Localized.get("imageCard.leaveTitle")
        }

        /// Accessibility label for an image card whose load is under way.
        static var loading: String {
            Localized.get("imageCard.loading")
        }

        /// Button on the sheet that confirms following the link in the browser.
        static var openLink: String {
            Localized.get("imageCard.openLink")
        }

        /// Button on the sheet that declines following the link.
        static var stayHere: String {
            Localized.get("imageCard.stayHere")
        }

        /// Detail under the withheld headline, telling the user tapping will load the image.
        static var tapToLoad: String {
            Localized.get("imageCard.tapToLoad")
        }

        /// Accessibility label for tapping a loaded, unlinked image card, when it has no alt text:
        /// opens the full-screen viewer.
        static var viewImage: String {
            Localized.get("imageCard.viewImage")
        }
    }

    enum Integration {
        /// Alert title after a partial OAuth consent. First argument is the account, second the
        /// capability names.
        static func partialGrant(_ p1: String, _ p2: String) -> String {
            String(format: Localized.get("integration.partialGrant"), p1, p2)
        }

        /// Alert body after a partial OAuth consent.
        static var partialGrantBody: String {
            Localized.get("integration.partialGrantBody")
        }

        enum Add {
            /// Footnote under the connect-by-address row.
            static var addressFootnote: String {
                Localized.get("integration.add.addressFootnote")
            }

            /// Label over the category rows.
            static var browseLabel: String {
                Localized.get("integration.add.browseLabel")
            }

            /// Row connecting any service by MCP address.
            static var connectByAddress: String {
                Localized.get("integration.add.connectByAddress")
            }

            /// Description of the add-integration sheet.
            static var description: String {
                Localized.get("integration.add.description")
            }

            /// Info notice body for a category with no entries yet.
            static var emptyCategoryBody: String {
                Localized.get("integration.add.emptyCategoryBody")
            }

            /// Info notice title for a category with no entries yet.
            static var emptyCategoryTitle: String {
                Localized.get("integration.add.emptyCategoryTitle")
            }

            /// Label over the search results list.
            static var matchesLabel: String {
                Localized.get("integration.add.matchesLabel")
            }

            /// Label over the default catalogue list.
            static var recommendedLabel: String {
                Localized.get("integration.add.recommendedLabel")
            }

            /// Search field placeholder in the add-integration sheet.
            static var searchPlaceholder: String {
                Localized.get("integration.add.searchPlaceholder")
            }

            /// Title of the add-integration catalogue sheet.
            static var title: String {
                Localized.get("integration.add.title")
            }

            /// Info notice body when a search finds nothing.
            static var unknownBody: String {
                Localized.get("integration.add.unknownBody")
            }

            /// Info notice title when a search finds nothing.
            static var unknownTitle: String {
                Localized.get("integration.add.unknownTitle")
            }
        }

        enum Connect {
            /// Sheet description for the address route.
            static var addressDescription: String {
                Localized.get("integration.connect.addressDescription")
            }

            /// Field: the MCP server address.
            static var addressField: String {
                Localized.get("integration.connect.addressField")
            }

            /// Sheet title while connecting an MCP server by address.
            static var addressTitle: String {
                Localized.get("integration.connect.addressTitle")
            }

            /// Field: the IMAP app password.
            static var appPasswordField: String {
                Localized.get("integration.connect.appPasswordField")
            }

            /// Secondary button on a failure step, returning to the catalogue.
            static var chooseAnother: String {
                Localized.get("integration.connect.chooseAnother")
            }

            /// Sheet title on the connected step.
            static var connectedTitle: String {
                Localized.get("integration.connect.connectedTitle")
            }

            /// Button that hands over to a service sign-in. The argument is the service name.
            static func continueWith(_ p1: String) -> String {
                String(format: Localized.get("integration.connect.continueWith"), p1)
            }

            /// Field: the IMAP account address.
            static var emailField: String {
                Localized.get("integration.connect.emailField")
            }

            /// Field: the incoming mail host.
            static var imapField: String {
                Localized.get("integration.connect.imapField")
            }

            /// Failure text when an address cannot be parsed.
            static var invalidAddress: String {
                Localized.get("integration.connect.invalidAddress")
            }

            /// Identity header kind line on the connected step.
            static var kindLabel: String {
                Localized.get("integration.connect.kindLabel")
            }

            /// Field on the connected step: the inferred display name, editable.
            static var nameField: String {
                Localized.get("integration.connect.nameField")
            }

            /// Field: the outgoing mail host.
            static var smtpField: String {
                Localized.get("integration.connect.smtpField")
            }

            enum Credentials {
                /// Info notice body when an MCP server needs client credentials.
                static var body: String {
                    Localized.get("integration.connect.credentials.body")
                }

                /// Info notice title when an MCP server needs client credentials.
                static var title: String {
                    Localized.get("integration.connect.credentials.title")
                }
            }

            enum Description {
                /// Sheet description for the browser sign-in route (Aula). The argument is the
                /// service name.
                static func browserSignIn(_ p1: String) -> String {
                    String(
                        format: Localized.get("integration.connect.description.browserSignIn"),
                        p1
                    )
                }

                /// Sheet description for the mail-account route.
                static var mailAccount: String {
                    Localized.get("integration.connect.description.mailAccount")
                }

                /// Sheet description for the OAuth route. The argument is the service name.
                static func signIn(_ p1: String) -> String {
                    String(format: Localized.get("integration.connect.description.signIn"), p1)
                }
            }

            enum Failed {
                /// Error notice body for a failed MCP address.
                static var addressBody: String {
                    Localized.get("integration.connect.failed.addressBody")
                }

                /// Error notice title for a failed MCP address.
                static var addressTitle: String {
                    Localized.get("integration.connect.failed.addressTitle")
                }

                /// Error notice body for a failed mail account.
                static var mailBody: String {
                    Localized.get("integration.connect.failed.mailBody")
                }

                /// Error notice title for a failed mail account.
                static var mailTitle: String {
                    Localized.get("integration.connect.failed.mailTitle")
                }

                /// Error notice body for a failed sign-in. The argument is the service name.
                static func signInBody(_ p1: String) -> String {
                    String(format: Localized.get("integration.connect.failed.signInBody"), p1)
                }

                /// Error notice title for a failed sign-in.
                static var signInTitle: String {
                    Localized.get("integration.connect.failed.signInTitle")
                }
            }

            enum Status {
                /// Status line on the connected step.
                static var connectedLabel: String {
                    Localized.get("integration.connect.status.connectedLabel")
                }
            }

            enum Working {
                /// Info notice body while a connection is verified.
                static var checkingBody: String {
                    Localized.get("integration.connect.working.checkingBody")
                }

                /// Info notice title while a connection is verified.
                static var checkingTitle: String {
                    Localized.get("integration.connect.working.checkingTitle")
                }

                /// Info notice body during sign-in. The argument is the service name.
                static func waitingBody(_ p1: String) -> String {
                    String(format: Localized.get("integration.connect.working.waitingBody"), p1)
                }

                /// Info notice title while a browser sign-in is in flight.
                static var waitingTitle: String {
                    Localized.get("integration.connect.working.waitingTitle")
                }
            }
        }

        enum Offers {
            /// Footnote under the offers list.
            static var footnote: String {
                Localized.get("integration.offers.footnote")
            }

            /// Empty state when the offers search finds nothing. The argument is the query.
            static func noMatches(_ p1: String) -> String {
                String(format: Localized.get("integration.offers.noMatches"), p1)
            }

            /// Search field placeholder. First argument is the item count, second the noun.
            static func searchPlaceholder(_ p1: String, _ p2: String) -> String {
                String(format: Localized.get("integration.offers.searchPlaceholder"), p1, p2)
            }

            /// Title of the read-only offers list.
            static var title: String {
                Localized.get("integration.offers.title")
            }
        }

        enum Screen {
            /// Row title of the active-provider switch. The argument is the capability name.
            static func activeForRow(_ p1: String) -> String {
                String(format: Localized.get("integration.screen.activeForRow"), p1)
            }

            /// Section label over the per-capability active-provider switches.
            static var activeLabel: String {
                Localized.get("integration.screen.activeLabel")
            }

            /// Category label under an integration's name on its screen, the way provider screens
            /// say AI provider.
            static var kindLabel: String {
                Localized.get("integration.screen.kindLabel")
            }

            /// Section label over a built-in account’s capabilities.
            static var offersLabel: String {
                Localized.get("integration.screen.offersLabel")
            }

            /// Footnote when some capabilities were skipped at sign-in.
            static var partialFootnote: String {
                Localized.get("integration.screen.partialFootnote")
            }

            /// Destructive row that removes the integration. The argument is the integration name.
            static func remove(_ p1: String) -> String {
                String(format: Localized.get("integration.screen.remove"), p1)
            }

            /// Removal confirmation alert title. The argument is the integration name.
            static func removeTitle(_ p1: String) -> String {
                String(format: Localized.get("integration.screen.removeTitle"), p1)
            }

            /// Removal confirmation message for a built-in integration.
            static var removeWarning: String {
                Localized.get("integration.screen.removeWarning")
            }

            /// Muted row that opens the full tools list. The argument is the tool count.
            static func showAllTools(_ p1: String) -> String {
                String(format: Localized.get("integration.screen.showAllTools"), p1)
            }

            /// Footnote when the tools list is capped. The argument is the total tool count.
            static func toolsFootnote(_ p1: String) -> String {
                String(format: Localized.get("integration.screen.toolsFootnote"), p1)
            }

            /// Fact value: the integration is a built-in account.
            static var viaBuiltin: String {
                Localized.get("integration.screen.viaBuiltin")
            }

            /// Fact value: the integration is an MCP server. The only place the word MCP appears.
            static var viaServer: String {
                Localized.get("integration.screen.viaServer")
            }

            enum Facts {
                /// Fact row: the MCP server address.
                static var address: String {
                    Localized.get("integration.screen.facts.address")
                }

                /// Fact row: the mechanism behind the integration.
                static var connectsVia: String {
                    Localized.get("integration.screen.facts.connectsVia")
                }
            }

            enum Notice {
                /// Warning notice body for an expired sign-in. The argument is the integration
                /// name.
                static func expiredBody(_ p1: String) -> String {
                    String(format: Localized.get("integration.screen.notice.expiredBody"), p1)
                }

                /// Warning notice title for an expired sign-in.
                static var expiredTitle: String {
                    Localized.get("integration.screen.notice.expiredTitle")
                }

                /// Error notice title for an MCP server error.
                static var serverTitle: String {
                    Localized.get("integration.screen.notice.serverTitle")
                }
            }

            enum Status {
                /// Status line when the integration works.
                static var connected: String {
                    Localized.get("integration.screen.status.connected")
                }

                /// Status line when the integration needs a fresh sign-in.
                static var reconnectNeeded: String {
                    Localized.get("integration.screen.status.reconnectNeeded")
                }
            }
        }
    }

    enum Integrations {
        enum Action {
            /// Button label to disconnect a connected integration
            static var disconnect: String {
                Localized.get("integrations.action.disconnect")
            }

            /// Button label to reconnect a connected integration in place
            static var reconnect: String {
                Localized.get("integrations.action.reconnect")
            }
        }

        enum AddSheet {
            /// Description shown atop the Add Integration sheet's browse screen
            static var description: String {
                Localized.get("integrations.addSheet.description")
            }
        }

        enum Attention {
            /// Body of the 'reconnect needed' warning card on the integration detail screen
            static var body: String {
                Localized.get("integrations.attention.body")
            }

            /// Title of the 'reconnect needed' warning card on the integration detail screen
            static var title: String {
                Localized.get("integrations.attention.title")
            }
        }

        enum Aula {
            /// Subtitle for the Aula integration type in the connect picker
            static var description: String {
                Localized.get("integrations.aula.description")
            }

            /// Display name for the Aula school/daycare integration
            static var displayName: String {
                Localized.get("integrations.aula.displayName")
            }
        }

        enum Category {
            enum Email {
                /// Display name for the Email integration category (browse grid)
                static var displayName: String {
                    Localized.get("integrations.category.email.displayName")
                }
            }

            enum FamilyAndSchool {
                /// Display name for the Family & School integration category (browse grid and
                /// connected-list header)
                static var displayName: String {
                    Localized.get("integrations.category.familyAndSchool.displayName")
                }
            }

            enum Health {
                /// Display name for the Health integration category (browse grid) — no provider yet
                static var displayName: String {
                    Localized.get("integrations.category.health.displayName")
                }
            }

            enum Music {
                /// Display name for the Music integration category (browse grid) — no provider yet
                static var displayName: String {
                    Localized.get("integrations.category.music.displayName")
                }
            }
        }

        enum Filter {
            /// Accessibility hint for the removable category filter chip in Add Integration
            static var clear: String {
                Localized.get("integrations.filter.clear")
            }
        }

        enum Google {
            /// Subtitle for the Google integration type in the connect picker
            static var description: String {
                Localized.get("integrations.google.description")
            }
        }

        enum Imap {
            /// Section header for the account (email/password) fields in the IMAP connect form
            static var accountSection: String {
                Localized.get("integrations.imap.accountSection")
            }

            /// Subtitle for the IMAP email integration type in the connect picker
            static var description: String {
                Localized.get("integrations.imap.description")
            }

            /// Display name for the generic IMAP/SMTP email integration
            static var displayName: String {
                Localized.get("integrations.imap.displayName")
            }

            /// Field label for the account's email address in the IMAP connect form
            static var emailField: String {
                Localized.get("integrations.imap.emailField")
            }

            /// Field label for a mail server hostname in the IMAP connect form
            static var hostField: String {
                Localized.get("integrations.imap.hostField")
            }

            /// Section header for IMAP server settings in the connect form
            static var incomingSection: String {
                Localized.get("integrations.imap.incomingSection")
            }

            /// Section header for SMTP server settings in the connect form
            static var outgoingSection: String {
                Localized.get("integrations.imap.outgoingSection")
            }

            /// Field label for the account password (often an app-specific password) in the IMAP
            /// connect form
            static var passwordField: String {
                Localized.get("integrations.imap.passwordField")
            }

            /// Helper text under the password field in the IMAP connect form
            static var passwordHint: String {
                Localized.get("integrations.imap.passwordHint")
            }

            /// Field label for a mail server port in the IMAP connect form
            static var portField: String {
                Localized.get("integrations.imap.portField")
            }

            /// Field label for an optional server username, defaulting to the email address, in the
            /// IMAP connect form
            static var usernameField: String {
                Localized.get("integrations.imap.usernameField")
            }
        }

        enum Microsoft {
            /// Subtitle for the Microsoft integration type in the connect picker
            static var description: String {
                Localized.get("integrations.microsoft.description")
            }
        }

        enum Search {
            /// Empty state shown when a search in Add Integration matches nothing
            static var noResults: String {
                Localized.get("integrations.search.noResults")
            }

            /// Placeholder text for the integration search field in Add Integration
            static var placeholder: String {
                Localized.get("integrations.search.placeholder")
            }
        }

        enum Status {
            /// Pill label shown next to an already-connected integration in search/browse results
            static var connected: String {
                Localized.get("integrations.status.connected")
            }

            /// Accessibility label for the warning icon on an integration row that needs
            /// reconnecting
            static var reconnectNeeded: String {
                Localized.get("integrations.status.reconnectNeeded")
            }
        }
    }

    enum Intent {
        /// A message displayed when dismissing an intent.
        static var dismissWarning: String {
            Localized.get("intent.dismissWarning")
        }

        /// Section header listing an intent's dated events.
        static var events: String {
            Localized.get("intent.events")
        }

        /// Section header listing an intent's recurring schedules.
        static var schedules: String {
            Localized.get("intent.schedules")
        }

        /// Section header listing an intent's tasks.
        static var tasks: String {
            Localized.get("intent.tasks")
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

        enum DictationChat {
            /// App intent description: start a fresh chat with dictation armed.
            static var description: String {
                Localized.get("intents.dictationChat.description")
            }

            /// App intent title: start a fresh chat with dictation armed.
            static var title: String {
                Localized.get("intents.dictationChat.title")
            }
        }

        enum LiveCallChat {
            /// App intent description: start a fresh chat in a live call.
            static var description: String {
                Localized.get("intents.liveCallChat.description")
            }

            /// App intent title: start a fresh chat in a live call.
            static var title: String {
                Localized.get("intents.liveCallChat.title")
            }
        }

        enum NewChat {
            /// App intent description: start a fresh chat.
            static var description: String {
                Localized.get("intents.newChat.description")
            }

            /// App intent title: start a fresh chat.
            static var title: String {
                Localized.get("intents.newChat.title")
            }
        }

        enum OpenApp {
            /// App intent description: open the app.
            static var description: String {
                Localized.get("intents.openApp.description")
            }

            /// App intent title: open the app.
            static var title: String {
                Localized.get("intents.openApp.title")
            }
        }

        enum PhotoChat {
            /// App intent description: start a fresh chat with the camera ready.
            static var description: String {
                Localized.get("intents.photoChat.description")
            }

            /// App intent title: start a fresh chat with the camera ready.
            static var title: String {
                Localized.get("intents.photoChat.title")
            }
        }
    }

    enum Knowledge {
        /// A label displayed above the user's knowledge.
        static var sectionTitle: String {
            Localized.get("knowledge.sectionTitle")
        }

        /// Navigation title for knowledge container
        static var title: String {
            Localized.get("knowledge.title")
        }

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
    }

    enum Mcp {
        /// Section or label for MCP server authentication settings
        static var authentication: String {
            Localized.get("mcp.authentication")
        }

        /// A description of how a server connects automatically when used in a chat.
        static var autoConnectHint: String {
            Localized.get("mcp.autoConnectHint")
        }

        /// Empty state when MCP server has no tools
        static var noToolsDiscovered: String {
            Localized.get("mcp.noToolsDiscovered")
        }

        /// Button to re-authorize MCP server
        static var reAuthorize: String {
            Localized.get("mcp.reAuthorize")
        }

        /// Confirmation message before removing an MCP server
        static var removeWarning: String {
            Localized.get("mcp.removeWarning")
        }

        /// Section header for MCP server tools
        static var tools: String {
            Localized.get("mcp.tools")
        }

        enum Authentication {
            /// A heading for the user section of the agent's core.
            static var user: String {
                Localized.get("mcp.authentication.user")
            }
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
    }

    enum Memory {
        /// A message displayed in an alert when deleting a memory.
        static var deleteWarning: String {
            Localized.get("memory.deleteWarning")
        }

        /// A label displayed above the user's memories.
        static var sectionTitle: String {
            Localized.get("memory.sectionTitle")
        }

        enum EmptyState {
            /// A description text displayed when there are no memories.
            static var hint: String {
                Localized.get("memory.emptyState.hint")
            }
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

        /// Suggestion shown in the chat error card when the device lacks the memory to run the
        /// on-device model, pointing the user to cloud providers.
        static var deviceUnsupportedSuggestion: String {
            Localized.get("model.deviceUnsupportedSuggestion")
        }

        /// Title of the chat error card shown when the device cannot run the on-device model.
        static var deviceUnsupportedTitle: String {
            Localized.get("model.deviceUnsupportedTitle")
        }

        /// Button to download a model
        static var download: String {
            Localized.get("model.download")
        }

        /// Label for Gemma 4 E2B model
        static var gemma4e2b: String {
            Localized.get("model.gemma4e2b")
        }

        /// Status text when Gemma model is downloaded
        static var gemmaDownloadedReady: String {
            Localized.get("model.gemmaDownloadedReady")
        }

        /// Error message when the device lacks sufficient RAM for local model inference.
        static var insufficientRAM: String {
            Localized.get("model.insufficientRAM")
        }

        /// Error description when the on-device model files are not present on disk.
        static var notDownloaded: String {
            Localized.get("model.notDownloaded")
        }

        /// Error description when the on-device model is present but couldn't be loaded into
        /// memory.
        static var notLoaded: String {
            Localized.get("model.notLoaded")
        }

        /// Warning message when removing a model
        static var removeStorageWarning: String {
            Localized.get("model.removeStorageWarning")
        }

        /// An alert message that appears when a user deletes a voice engine.
        static var removeWarning: String {
            Localized.get("model.removeWarning")
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

        enum Facts {
            static var goodFor: String {
                Localized.get("model.facts.goodFor")
            }

            static var goodForValue: String {
                Localized.get("model.facts.goodForValue")
            }

            static var limitations: String {
                Localized.get("model.facts.limitations")
            }

            static var limitationsValue: String {
                Localized.get("model.facts.limitationsValue")
            }

            static var sizeOnDevice: String {
                Localized.get("model.facts.sizeOnDevice")
            }
        }

        enum Gemma4e2b {
            /// The name of the machine learning model used in the app.
            static var name: String {
                Localized.get("model.gemma4e2b.name")
            }
        }

        enum NotDownloaded {
            /// Suggestion in the chat error card guiding the user to download the on-device model
            /// from settings.
            static var suggestion: String {
                Localized.get("model.notDownloaded.suggestion")
            }

            /// Title of the chat error card shown when the on-device model isn't downloaded.
            static var title: String {
                Localized.get("model.notDownloaded.title")
            }
        }

        enum NotLoaded {
            /// Suggestion in the chat error card when the on-device model failed to load, guiding
            /// the user to retry or re-download.
            static var suggestion: String {
                Localized.get("model.notLoaded.suggestion")
            }

            /// Title of the chat error card shown when the on-device model failed to load.
            static var title: String {
                Localized.get("model.notLoaded.title")
            }
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

            /// Placeholder shown while the model catalog is being fetched for the first time
            static var loading: String {
                Localized.get("model.picker.loading")
            }

            /// Empty state shown when a provider returns no models at all
            static var noModels: String {
                Localized.get("model.picker.noModels")
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

            enum Auto {
                /// Shows which model automatic selection is currently using
                static func current(_ p1: String) -> String {
                    String(format: Localized.get("model.picker.auto.current"), p1)
                }

                /// Explains what automatic model selection does
                static var description: String {
                    Localized.get("model.picker.auto.description")
                }

                /// Title of the automatic model selection option
                static var title: String {
                    Localized.get("model.picker.auto.title")
                }
            }
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
    }

    enum Onboarding {
        /// A description text displayed below the unavailable view title.
        static var completionHint: String {
            Localized.get("onboarding.completionHint")
        }

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

            /// Title of the first chat created at the end of onboarding.
            static var firstChatTitle: String {
                Localized.get("onboarding.chat.firstChatTitle")
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

        enum Flow {
            enum Inference {
                /// Avatar speech body on the inference screen.
                static var text: String {
                    Localized.get("onboarding.flow.inference.text")
                }

                /// Avatar speech title on the inference screen.
                static var title: String {
                    Localized.get("onboarding.flow.inference.title")
                }
            }

            enum Name {
                /// Avatar speech body on the name screen.
                static var text: String {
                    Localized.get("onboarding.flow.name.text")
                }

                /// Avatar speech title on the name screen.
                static var title: String {
                    Localized.get("onboarding.flow.name.title")
                }
            }

            enum Priority {
                /// Avatar speech body on the priority screen.
                static var text: String {
                    Localized.get("onboarding.flow.priority.text")
                }

                /// Avatar speech title on the priority screen when no name is known.
                static var title: String {
                    Localized.get("onboarding.flow.priority.title")
                }

                /// Avatar speech title on the priority screen when the user’s name is known. %@ is
                /// the name.
                static func titleWithName(_ p1: String) -> String {
                    String(format: Localized.get("onboarding.flow.priority.titleWithName"), p1)
                }
            }

            enum Welcome {
                /// Avatar speech body on the welcome screen.
                static var text: String {
                    Localized.get("onboarding.flow.welcome.text")
                }

                /// Avatar speech title on the welcome screen.
                static var title: String {
                    Localized.get("onboarding.flow.welcome.title")
                }
            }
        }

        enum Inference {
            /// Secondary button label to connect a custom inference provider.
            static var connectOwnButton: String {
                Localized.get("onboarding.inference.connectOwnButton")
            }

            /// Button to dismiss the offline sheet after download has started.
            static var continueButton: String {
                Localized.get("onboarding.inference.continueButton")
            }

            /// Body text in the offline model sheet while the model is already downloading.
            static var offlineDownloadingText: String {
                Localized.get("onboarding.inference.offlineDownloadingText")
            }

            /// Link text to open the offline model download sheet.
            static var offlineLink: String {
                Localized.get("onboarding.inference.offlineLink")
            }

            /// Body text in the offline model sheet when the model has not yet been downloaded.
            static var offlineSheetText: String {
                Localized.get("onboarding.inference.offlineSheetText")
            }

            /// Title of the offline model download sheet.
            static var offlineSheetTitle: String {
                Localized.get("onboarding.inference.offlineSheetTitle")
            }

            /// Primary button label to use the Eigin cloud provider.
            static var useEiginButton: String {
                Localized.get("onboarding.inference.useEiginButton")
            }
        }

        enum LocalModel {
            /// Explanation of the local model option shown on the provider choice screen
            static var description: String {
                Localized.get("onboarding.localModel.description")
            }
        }

        enum ModelSetup {
            /// Subtitle explaining that the model download continues in the background
            static var downloadStatus: String {
                Localized.get("onboarding.modelSetup.downloadStatus")
            }

            /// Status text during model download
            static func downloadingProgress(_ p1: String) -> String {
                String(format: Localized.get("onboarding.modelSetup.downloadingProgress"), p1)
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

            /// Progress percentage label
            static func progressPercent(_ p1: String) -> String {
                String(format: Localized.get("onboarding.modelSetup.progressPercent"), p1)
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

        enum Name {
            /// Button label to proceed past the name screen.
            static var continueButton: String {
                Localized.get("onboarding.name.continueButton")
            }

            /// Label for the name input field.
            static var fieldLabel: String {
                Localized.get("onboarding.name.fieldLabel")
            }

            /// Link text asking why the app needs the user’s name.
            static var privacyLink: String {
                Localized.get("onboarding.name.privacyLink")
            }

            /// Body text in the privacy explanation sheet on the name screen.
            static var privacySheetText: String {
                Localized.get("onboarding.name.privacySheetText")
            }

            /// Sheet title for the privacy explanation on the name screen.
            static var privacySheetTitle: String {
                Localized.get("onboarding.name.privacySheetTitle")
            }
        }

        enum Priority {
            enum Clarity {
                /// Explainer on the ‘think out loud’ priority card.
                static var explainer: String {
                    Localized.get("onboarding.priority.clarity.explainer")
                }

                /// Title on the ‘think out loud’ priority card.
                static var title: String {
                    Localized.get("onboarding.priority.clarity.title")
                }
            }

            enum People {
                /// Explainer on the ‘keep in touch’ priority card.
                static var explainer: String {
                    Localized.get("onboarding.priority.people.explainer")
                }

                /// Title on the ‘keep in touch’ priority card.
                static var title: String {
                    Localized.get("onboarding.priority.people.title")
                }
            }

            enum SomethingElse {
                /// Explainer on the ‘something else’ priority card.
                static var explainer: String {
                    Localized.get("onboarding.priority.somethingElse.explainer")
                }

                /// Title on the ‘something else’ priority card.
                static var title: String {
                    Localized.get("onboarding.priority.somethingElse.title")
                }
            }

            enum StayOnTop {
                /// Explainer on the ‘stay on top of life’ priority card.
                static var explainer: String {
                    Localized.get("onboarding.priority.stayOnTop.explainer")
                }

                /// Title on the ‘stay on top of life’ priority card.
                static var title: String {
                    Localized.get("onboarding.priority.stayOnTop.title")
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

        enum Reveal {
            /// Fallback reveal line when the turn limit ran out before the agent sealed: neutral,
            /// and written in the agent's own voice.
            static var fallbackIntroduction: String {
                Localized.get("onboarding.reveal.fallbackIntroduction")
            }

            /// Avatar speech title in the reveal overlay. %@ is the agent’s name.
            static func title(_ p1: String) -> String {
                String(format: Localized.get("onboarding.reveal.title"), p1)
            }
        }

        enum Welcome {
            /// Button label to begin onboarding from the welcome screen.
            static var beginButton: String {
                Localized.get("onboarding.welcome.beginButton")
            }

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

    enum Options {
        /// Label for a card that lets the user write their own answer instead of picking a preset
        /// option.
        static var somethingElse: String {
            Localized.get("options.somethingElse")
        }

        /// Subtitle explaining that the user can write their own answer.
        static var writeOwnAnswer: String {
            Localized.get("options.writeOwnAnswer")
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

        /// Title of the sheet that asks the user to grant a tool permission.
        static var sheetTitle: String {
            Localized.get("permission.sheetTitle")
        }

        /// A message displayed when a tool's execution is denied by the user's access policy.
        static var toolDeniedByPolicy: String {
            Localized.get("permission.toolDeniedByPolicy")
        }

        /// Permission sheet sentence with a tool-supplied action phrase. First argument is the
        /// agent name, second is the action phrase.
        static func wantsToFormat(_ p1: String, _ p2: String) -> String {
            String(format: Localized.get("permission.wantsToFormat"), p1, p2)
        }

        /// A message explaining that a user has granted or denied permission to use a tool. The
        /// argument is a user-visible name for the tool.
        static func wantsToUseFormat(_ p1: String, _ p2: String) -> String {
            String(format: Localized.get("permission.wantsToUseFormat"), p1, p2)
        }

        enum Disclosure {
            /// Action phrase: add a calendar event. Followed by the title.
            static var addCalendarEvent: String {
                Localized.get("permission.disclosure.addCalendarEvent")
            }

            /// Action phrase: change the agent's name. Followed by the new name.
            static var changeNameTo: String {
                Localized.get("permission.disclosure.changeNameTo")
            }

            /// Action phrase: create a space. Argument is the space name.
            static func createSpaceNamed(_ p1: String) -> String {
                String(format: Localized.get("permission.disclosure.createSpaceNamed"), p1)
            }

            /// A reminder's due date in a disclosure.
            static func dueFormat(_ p1: String) -> String {
                String(format: Localized.get("permission.disclosure.dueFormat"), p1)
            }

            /// Action phrase: fetch a web page. Followed by the URL.
            static var fetchPageFrom: String {
                Localized.get("permission.disclosure.fetchPageFrom")
            }

            /// Action phrase: log a body measurement. Followed by the value.
            static var logBodyMeasurement: String {
                Localized.get("permission.disclosure.logBodyMeasurement")
            }

            /// Action phrase: log a meal. Followed by the meal name.
            static var logMeal: String {
                Localized.get("permission.disclosure.logMeal")
            }

            /// Action phrase: log sleep.
            static var logSleep: String {
                Localized.get("permission.disclosure.logSleep")
            }

            /// Action phrase: look up a food. Followed by the query.
            static var lookUpFood: String {
                Localized.get("permission.disclosure.lookUpFood")
            }

            /// A time or date range shown in a disclosure.
            static func rangeFormat(_ p1: String, _ p2: String) -> String {
                String(format: Localized.get("permission.disclosure.rangeFormat"), p1, p2)
            }

            /// Action phrase: add a reminder. Followed by the title.
            static var reminderAdd: String {
                Localized.get("permission.disclosure.reminderAdd")
            }

            /// Action phrase: complete a reminder.
            static var reminderComplete: String {
                Localized.get("permission.disclosure.reminderComplete")
            }

            /// Action phrase: remove a reminder.
            static var reminderRemove: String {
                Localized.get("permission.disclosure.reminderRemove")
            }

            /// Action phrase: update a reminder.
            static var reminderUpdate: String {
                Localized.get("permission.disclosure.reminderUpdate")
            }

            /// Action phrase: reply to an email.
            static var replyToEmail: String {
                Localized.get("permission.disclosure.replyToEmail")
            }

            /// Action phrase: search email. Followed by the query.
            static var searchEmailFor: String {
                Localized.get("permission.disclosure.searchEmailFor")
            }

            /// Action phrase shown on the permission sheet for a web search. Followed by the search
            /// query.
            static var searchWebFor: String {
                Localized.get("permission.disclosure.searchWebFor")
            }

            /// Action phrase: send an email. Argument is the recipient(s).
            static func sendEmailTo(_ p1: String) -> String {
                String(format: Localized.get("permission.disclosure.sendEmailTo"), p1)
            }

            /// Action phrase: set proactivity. Followed by the level.
            static var setProactivityTo: String {
                Localized.get("permission.disclosure.setProactivityTo")
            }

            /// Action phrase: change the agent's appearance.
            static var updateAppearance: String {
                Localized.get("permission.disclosure.updateAppearance")
            }

            /// Action phrase: the agent edits its own saved memory.
            static var updateMemory: String {
                Localized.get("permission.disclosure.updateMemory")
            }
        }
    }

    enum Provider {
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

        /// Field label for the provider base URL input
        static var baseURL: String {
            Localized.get("provider.baseURL")
        }

        /// OAuth connected success message
        static func connectedTo(_ p1: String) -> String {
            String(format: Localized.get("provider.connectedTo"), p1)
        }

        /// Credits warning with provider name
        static func creditsWarning(_ p1: String) -> String {
            String(format: Localized.get("provider.creditsWarning"), p1)
        }

        /// A label describing the model of an agent.
        static var modelLabel: String {
            Localized.get("provider.modelLabel")
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

        /// Generic retry button label
        static var tryAgain: String {
            Localized.get("provider.tryAgain")
        }

        /// The title of the view that explains the use of cloud AI by Eigin.
        static var typeLabel: String {
            Localized.get("provider.typeLabel")
        }

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

        enum AiScreen {
            /// Inline label while validating a key or sign-in.
            static var checkingConnection: String {
                Localized.get("provider.ai-screen.checkingConnection")
            }

            /// Identity header kind line for a connected AI provider.
            static var kindLabel: String {
                Localized.get("provider.ai-screen.kindLabel")
            }

            /// Footnote under the models group. First argument is enabled count, second is total.
            static func modelsFootnote(_ p1: String, _ p2: String) -> String {
                String(format: Localized.get("provider.ai-screen.modelsFootnote"), p1, p2)
            }

            /// Footnote when no models are enabled. The argument is the provider name.
            static func modelsFootnoteNone(_ p1: String) -> String {
                String(format: Localized.get("provider.ai-screen.modelsFootnoteNone"), p1)
            }

            /// Section label above the provider models group.
            static var modelsLabel: String {
                Localized.get("provider.ai-screen.modelsLabel")
            }

            /// Destructive row that removes the provider. The argument is the provider name.
            static func remove(_ p1: String) -> String {
                String(format: Localized.get("provider.ai-screen.remove"), p1)
            }

            /// Removal confirmation alert title. The argument is the provider name.
            static func removeTitle(_ p1: String) -> String {
                String(format: Localized.get("provider.ai-screen.removeTitle"), p1)
            }

            /// Button that applies a replaced API key.
            static var saveKey: String {
                Localized.get("provider.ai-screen.saveKey")
            }

            /// Muted row that opens the searchable models screen. The argument is the model count.
            static func showAllModels(_ p1: String) -> String {
                String(format: Localized.get("provider.ai-screen.showAllModels"), p1)
            }

            /// Button that reruns the ChatGPT sign-in to replace an expired or rejected credential.
            static var signInAgain: String {
                Localized.get("provider.ai-screen.signInAgain")
            }

            enum Facts {
                /// Fact row: the mechanism (API key or sign-in).
                static var connectsVia: String {
                    Localized.get("provider.ai-screen.facts.connectsVia")
                }

                /// Fact row: the stored API key, masked.
                static var key: String {
                    Localized.get("provider.ai-screen.facts.key")
                }
            }

            enum Status {
                /// Status line when the provider works.
                static var connected: String {
                    Localized.get("provider.ai-screen.status.connected")
                }

                /// Status line when the provider fails its last check.
                static var notWorking: String {
                    Localized.get("provider.ai-screen.status.notWorking")
                }
            }
        }

        enum AppleIntelligence {
            /// Description shown for the Apple Intelligence provider option
            static var description: String {
                Localized.get("provider.appleIntelligence.description")
            }
        }

        enum Connect {
            /// Field: the base URL of a custom provider or MCP server.
            static var addressField: String {
                Localized.get("provider.connect.addressField")
            }

            /// Sheet title while connecting by address, before the address has answered.
            static var addressTitle: String {
                Localized.get("provider.connect.addressTitle")
            }

            /// Secondary button on a failure step, returning to the provider list.
            static var chooseAnother: String {
                Localized.get("provider.connect.chooseAnother")
            }

            /// Footnote on the connected step.
            static var doneFootnote: String {
                Localized.get("provider.connect.doneFootnote")
            }

            /// Link that opens the provider key console.
            static var getApiKey: String {
                Localized.get("provider.connect.getApiKey")
            }

            /// Row value on the connected step: model count.
            static func modelsAvailable(_ p1: String) -> String {
                String(format: Localized.get("provider.connect.modelsAvailable"), p1)
            }

            /// Row title on the connected step: models seen at the address.
            static var modelsRowTitle: String {
                Localized.get("provider.connect.modelsRowTitle")
            }

            /// Field on the connected step: the inferred display name, editable.
            static var nameField: String {
                Localized.get("provider.connect.nameField")
            }

            /// Fact value: provider connects through a pasted API key.
            static var viaApiKey: String {
                Localized.get("provider.connect.viaApiKey")
            }

            /// Fact value: provider connects through account sign-in.
            static var viaSignIn: String {
                Localized.get("provider.connect.viaSignIn")
            }

            enum Working {
                /// Info notice body while credentials are validated.
                static var checkingBody: String {
                    Localized.get("provider.connect.working.checkingBody")
                }

                /// Info notice title while credentials are validated.
                static var checkingTitle: String {
                    Localized.get("provider.connect.working.checkingTitle")
                }

                /// Info notice body during sign-in. The argument is the provider name.
                static func waitingBody(_ p1: String) -> String {
                    String(format: Localized.get("provider.connect.working.waitingBody"), p1)
                }

                /// Info notice title while a browser sign-in is in flight.
                static var waitingTitle: String {
                    Localized.get("provider.connect.working.waitingTitle")
                }
            }
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

        enum Description {
            enum Models {
                /// Hub row description for a provider with one model.
                static func one(_ p1: String) -> String {
                    String(format: Localized.get("provider.description.models.one"), p1)
                }

                /// Hub row description for a provider with several models.
                static func other(_ p1: String) -> String {
                    String(format: Localized.get("provider.description.models.other"), p1)
                }
            }
        }

        enum Disclosure {
            /// Third-party AI disclosure on the credits sheet, where the user commits to Eigin
            /// cloud inference
            static var eiginCloud: String {
                Localized.get("provider.disclosure.eiginCloud")
            }

            /// Third-party AI disclosure on the provider-select sheet, where the user commits to a
            /// provider they connect themselves
            static var ownProvider: String {
                Localized.get("provider.disclosure.ownProvider")
            }

            /// Tappable tail of the third-party AI disclosure, linking to the privacy policy
            static var privacyLink: String {
                Localized.get("provider.disclosure.privacyLink")
            }
        }

        enum Edit {
            /// Confirmation message before removing a provider
            static var removeWarning: String {
                Localized.get("provider.edit.removeWarning")
            }

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

        enum Eigin {
            /// Body of the privacy blurb card
            static var blurbBody: String {
                Localized.get("provider.eigin.blurbBody")
            }

            /// Headline of the privacy blurb card
            static var blurbTitle: String {
                Localized.get("provider.eigin.blurbTitle")
            }

            /// Button to buy a credit option
            static var buy: String {
                Localized.get("provider.eigin.buy")
            }

            /// A purchase option's credit amount. The argument is the number of credits.
            static func creditAmount(_ p1: String) -> String {
                String(format: Localized.get("provider.eigin.creditAmount"), p1)
            }

            /// Info section: what a credit is (body)
            static var creditBody: String {
                Localized.get("provider.eigin.creditBody")
            }

            /// Info section: what a credit is (title)
            static var creditTitle: String {
                Localized.get("provider.eigin.creditTitle")
            }

            /// Caption under the credit balance on the Eigin screen
            static var creditsCaption: String {
                Localized.get("provider.eigin.creditsCaption")
            }

            /// Chat recovery card body shown after credits are added, prompting the user to resend
            static var creditsReadyBody: String {
                Localized.get("provider.eigin.creditsReadyBody")
            }

            /// Chat recovery card title shown after credits are added
            static var creditsReadyTitle: String {
                Localized.get("provider.eigin.creditsReadyTitle")
            }

            /// Info section: European hosting (body)
            static var europeBody: String {
                Localized.get("provider.eigin.europeBody")
            }

            /// Info section: European hosting (title)
            static var europeTitle: String {
                Localized.get("provider.eigin.europeTitle")
            }

            /// Description under the purchase sheet title, framing what credits are for
            static var getCreditsDescription: String {
                Localized.get("provider.eigin.getCreditsDescription")
            }

            /// Title of the purchase sheet
            static var getCreditsTitle: String {
                Localized.get("provider.eigin.getCreditsTitle")
            }

            /// Button that opens the purchase sheet
            static var getMoreCredits: String {
                Localized.get("provider.eigin.getMoreCredits")
            }

            /// High-level description shown under the information sheet title
            static var infoDescription: String {
                Localized.get("provider.eigin.infoDescription")
            }

            /// Title of the information sheet
            static var infoTitle: String {
                Localized.get("provider.eigin.infoTitle")
            }

            /// Button that opens the information sheet
            static var learnHowItWorks: String {
                Localized.get("provider.eigin.learnHowItWorks")
            }

            /// Info section: curated models (body)
            static var modelsBody: String {
                Localized.get("provider.eigin.modelsBody")
            }

            /// Info section: curated models (title)
            static var modelsTitle: String {
                Localized.get("provider.eigin.modelsTitle")
            }

            /// Shown when no purchase options can be loaded
            static var noProducts: String {
                Localized.get("provider.eigin.noProducts")
            }

            /// Shown when recovery finds no previous credit purchases on the Apple ID
            static var nothingToRestore: String {
                Localized.get("provider.eigin.nothingToRestore")
            }

            /// Chat error suggestion shown when the Eigin relay has no credits left
            static var outOfCreditsBody: String {
                Localized.get("provider.eigin.outOfCreditsBody")
            }

            /// Chat error title shown when the Eigin relay has no credits left
            static var outOfCreditsTitle: String {
                Localized.get("provider.eigin.outOfCreditsTitle")
            }

            /// Info section: privacy (body)
            static var privacyBody: String {
                Localized.get("provider.eigin.privacyBody")
            }

            /// Info section: privacy (title)
            static var privacyTitle: String {
                Localized.get("provider.eigin.privacyTitle")
            }

            /// Shown when the app could not reach Eigin Relay during a purchase or restore
            static var purchaseNetwork: String {
                Localized.get("provider.eigin.purchaseNetwork")
            }

            /// Shown when Eigin Relay responded that it is temporarily unavailable during a
            /// purchase or restore
            static var purchaseOutage: String {
                Localized.get("provider.eigin.purchaseOutage")
            }

            /// Shown when a purchase or restore could not be finished; StoreKit retries it
            /// automatically at the next launch
            static var purchasePendingRecovery: String {
                Localized.get("provider.eigin.purchasePendingRecovery")
            }

            /// Neutral failure copy for catalog load and restore, where no new purchase is in
            /// flight
            static var purchaseRetry: String {
                Localized.get("provider.eigin.purchaseRetry")
            }

            /// Shown when purchases could not be loaded because a StoreKit product was not found
            static var purchaseUnavailable: String {
                Localized.get("provider.eigin.purchaseUnavailable")
            }

            /// Shown when a purchase's proof failed StoreKit or relay verification
            static var purchaseVerification: String {
                Localized.get("provider.eigin.purchaseVerification")
            }

            /// Button that re-redeems past purchases so credits survive a reinstall
            static var restoreCredits: String {
                Localized.get("provider.eigin.restoreCredits")
            }

            /// Subtitle on the Eigin provider row in the connections list
            static var rowSubtitle: String {
                Localized.get("provider.eigin.rowSubtitle")
            }

            /// Title of the Eigin Relay provider screen and hub row.
            static var title: String {
                Localized.get("provider.eigin.title")
            }
        }

        enum EmptyState {
            /// A description text displayed below the title of a view that instructs the user to
            /// add a provider in the settings to get started.
            static var addProviderHint: String {
                Localized.get("provider.emptyState.addProviderHint")
            }
        }

        enum Local {
            /// Secondary button that cancels an active download.
            static var cancelDownload: String {
                Localized.get("provider.local.cancelDownload")
            }

            /// Destructive row that deletes the downloaded model.
            static var deleteModel: String {
                Localized.get("provider.local.deleteModel")
            }

            /// Description of the local model info sheet.
            static var infoDescription: String {
                Localized.get("provider.local.infoDescription")
            }

            /// Title of the local model info sheet.
            static var infoTitle: String {
                Localized.get("provider.local.infoTitle")
            }

            /// Identity header kind line for the local model, and its hub row description.
            static var kindLabel: String {
                Localized.get("provider.local.kindLabel")
            }

            /// Title of the local model screen and hub row.
            static var title: String {
                Localized.get("provider.local.title")
            }

            enum Info {
                /// Info row body: deliberate choice.
                static var chosenBody: String {
                    Localized.get("provider.local.info.chosenBody")
                }

                /// Info row: picking the local model deliberately.
                static var chosenTitle: String {
                    Localized.get("provider.local.info.chosenTitle")
                }

                /// Info row body: offline use.
                static var offlineBody: String {
                    Localized.get("provider.local.info.offlineBody")
                }

                /// Info row: when the local model is reached for automatically.
                static var offlineTitle: String {
                    Localized.get("provider.local.info.offlineTitle")
                }

                /// Info row body: trade-offs.
                static var smallerBody: String {
                    Localized.get("provider.local.info.smallerBody")
                }

                /// Info row: trade-offs of the local model.
                static var smallerTitle: String {
                    Localized.get("provider.local.info.smallerTitle")
                }
            }

            enum Status {
                /// Status line when the download failed.
                static var downloadFailed: String {
                    Localized.get("provider.local.status.downloadFailed")
                }

                /// Status line while downloading or preparing.
                static var gettingReady: String {
                    Localized.get("provider.local.status.gettingReady")
                }

                /// Status line before the model is downloaded.
                static var notInstalled: String {
                    Localized.get("provider.local.status.notInstalled")
                }

                /// Status line when the device cannot run the model.
                static var notSupported: String {
                    Localized.get("provider.local.status.notSupported")
                }

                /// Status line when the local model is installed.
                static var ready: String {
                    Localized.get("provider.local.status.ready")
                }
            }
        }

        enum Models {
            /// A message displayed when a provider has no supported models.
            static var empty: String {
                Localized.get("provider.models.empty")
            }

            /// Empty state when the model search finds nothing. The argument is the query.
            static func noMatches(_ p1: String) -> String {
                String(format: Localized.get("provider.models.noMatches"), p1)
            }

            /// A message displayed when no models match a search query.
            static var noSearchResults: String {
                Localized.get("provider.models.noSearchResults")
            }

            /// Group label: recognised models below the ranking cut.
            static var other: String {
                Localized.get("provider.models.other")
            }

            /// Group label: the top of the catalogue ranking.
            static var recommended: String {
                Localized.get("provider.models.recommended")
            }

            /// Search field placeholder. The argument is the model count.
            static func searchPrompt(_ p1: String) -> String {
                String(format: Localized.get("provider.models.searchPrompt"), p1)
            }

            /// Title of the searchable provider models screen.
            static var title: String {
                Localized.get("provider.models.title")
            }

            /// Group label: model IDs the catalogue has never seen.
            static var unknown: String {
                Localized.get("provider.models.unknown")
            }

            /// Footnote under the Unknown group.
            static var unknownFootnote: String {
                Localized.get("provider.models.unknownFootnote")
            }
        }

        enum Picker {
            /// Footnote under the connect-by-address row.
            static var addressFootnote: String {
                Localized.get("provider.picker.addressFootnote")
            }

            /// Row that connects any OpenAI-compatible provider by URL.
            static var connectByAddress: String {
                Localized.get("provider.picker.connectByAddress")
            }

            /// Label for custom provider option
            static var customProvider: String {
                Localized.get("provider.picker.customProvider")
            }

            /// Badge label for experimental providers
            static var experimental: String {
                Localized.get("provider.picker.experimental")
            }

            /// Row label for on-device model in Connections list
            static var onDeviceModel: String {
                Localized.get("provider.picker.onDeviceModel")
            }

            /// Searchable prompt for provider picker
            static var searchPrompt: String {
                Localized.get("provider.picker.searchPrompt")
            }

            /// Info notice body when a search finds no preset.
            static var unknownNoticeBody: String {
                Localized.get("provider.picker.unknownNoticeBody")
            }

            /// Info notice when a search finds no preset.
            static var unknownNoticeTitle: String {
                Localized.get("provider.picker.unknownNoticeTitle")
            }

            enum Group {
                /// Group label: providers connected by pasting a key.
                static var apiKey: String {
                    Localized.get("provider.picker.group.apiKey")
                }

                /// Group label: providers connected through account sign-in.
                static var signIn: String {
                    Localized.get("provider.picker.group.signIn")
                }
            }
        }

        enum Relay {
            /// Footnote under the relay facts card.
            static var factsFootnote: String {
                Localized.get("provider.relay.factsFootnote")
            }

            enum Facts {
                /// Fact row label: whether chats are kept.
                static var conversationsStored: String {
                    Localized.get("provider.relay.facts.conversationsStored")
                }

                /// Fact row value: whether chats are kept.
                static var conversationsStoredValue: String {
                    Localized.get("provider.relay.facts.conversationsStoredValue")
                }

                /// Fact row: the current credit balance.
                static var credits: String {
                    Localized.get("provider.relay.facts.credits")
                }

                /// Fact row label: where the relay runs.
                static var hostedIn: String {
                    Localized.get("provider.relay.facts.hostedIn")
                }

                /// Fact row value: where the relay runs.
                static var hostedInValue: String {
                    Localized.get("provider.relay.facts.hostedInValue")
                }

                /// Muted row that opens the relay info sheet.
                static var howItWorks: String {
                    Localized.get("provider.relay.facts.howItWorks")
                }
            }

            enum Notice {
                /// Warning notice body for an empty balance.
                static var pausedBody: String {
                    Localized.get("provider.relay.notice.pausedBody")
                }

                /// Warning notice title for an empty balance.
                static var pausedTitle: String {
                    Localized.get("provider.relay.notice.pausedTitle")
                }

                /// Info notice body when credits are close to running out.
                static var runningLowBody: String {
                    Localized.get("provider.relay.notice.runningLowBody")
                }

                /// Info notice title when credits are close to running out.
                static var runningLowTitle: String {
                    Localized.get("provider.relay.notice.runningLowTitle")
                }
            }

            enum Status {
                /// Status line when the balance is zero.
                static var outOfCredits: String {
                    Localized.get("provider.relay.status.outOfCredits")
                }

                /// Status line when the relay is usable.
                static var ready: String {
                    Localized.get("provider.relay.status.ready")
                }
            }
        }

        enum Setup {
            /// Alternative link shown below OAuth sign-in to switch to manual API key entry
            static var apiKeyAlternative: String {
                Localized.get("provider.setup.apiKeyAlternative")
            }

            /// Secondary action that returns the user to the provider picker from the connect sheet
            static var changeProvider: String {
                Localized.get("provider.setup.changeProvider")
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

            /// A footer label explaining the purpose of the "Next" button in the edit provider
            /// view.
            static var updateApiKeyHintNext: String {
                Localized.get("provider.setup.updateApiKeyHintNext")
            }

            /// A description of the action to update a provider's API key and refresh its models.
            static var updateApiKeyHintSave: String {
                Localized.get("provider.setup.updateApiKeyHintSave")
            }

            enum Anthropic {
                /// Step-by-step instruction for obtaining an Anthropic API key
                static var instruction: String {
                    Localized.get("provider.setup.anthropic.instruction")
                }
            }

            enum Berget {
                /// Step-by-step instruction for obtaining a Berget API key
                static var instruction: String {
                    Localized.get("provider.setup.berget.instruction")
                }
            }

            enum Chatgpt {
                /// How to connect via ChatGPT subscription sign-in
                static var instruction: String {
                    Localized.get("provider.setup.chatgpt.instruction")
                }
            }

            enum Corti {
                /// Step-by-step instruction for obtaining a Corti API key
                static var instruction: String {
                    Localized.get("provider.setup.corti.instruction")
                }
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

            enum Infercom {
                /// Step-by-step instruction for obtaining an Infercom API key
                static var instruction: String {
                    Localized.get("provider.setup.infercom.instruction")
                }
            }

            enum Mistral {
                /// Step-by-step instruction for obtaining a Mistral API key
                static var instruction: String {
                    Localized.get("provider.setup.mistral.instruction")
                }
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

        /// The text that appears next to the icon in the "Development" section of the settings
        /// menu.
        static var development: String {
            Localized.get("settings.development")
        }

        /// A button label that triggers the export of the app's log file.
        static var exportLog: String {
            Localized.get("settings.exportLog")
        }

        /// A section header in the advanced settings view, describing logging options.
        static var logging: String {
            Localized.get("settings.logging")
        }

        /// A label displayed above the section for managing an agent's proactivity settings.
        static var proactivity: String {
            Localized.get("settings.proactivity")
        }

        /// Settings item label to restart the onboarding flow (debug/admin)
        static var reTriggerOnboarding: String {
            Localized.get("settings.reTriggerOnboarding")
        }

        /// A button that sends a test notification to the user.
        static var sendTestNotification: String {
            Localized.get("settings.sendTestNotification")
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

        enum About {
            /// App version line on the About screen when the build number is known. First argument
            /// is the marketing version, second is the build number, e.g. 'Version 0.16.0 (42).'
            static func appVersionBuildFormat(_ p1: String, _ p2: String) -> String {
                String(format: Localized.get("settings.about.appVersionBuildFormat"), p1, p2)
            }

            /// App version line on the About screen. Argument is the marketing version, e.g.
            /// 'Version 0.16.0'.
            static func appVersionFormat(_ p1: String) -> String {
                String(format: Localized.get("settings.about.appVersionFormat"), p1)
            }

            /// Section header grouping the privacy policy and terms links
            static var legal: String {
                Localized.get("settings.about.legal")
            }

            /// Section header for third-party libraries on the licenses screen
            static var libraries: String {
                Localized.get("settings.about.libraries")
            }

            /// Subtitle on the About screen indicating how many third-party packages are licensed.
            /// Argument is the package count as text.
            static func licenseCountFormat(_ p1: String) -> String {
                String(format: Localized.get("settings.about.licenseCountFormat"), p1)
            }

            /// Title for the third-party licenses screen
            static var licenseListTitle: String {
                Localized.get("settings.about.licenseListTitle")
            }

            /// Label prefix on a license detail page before the package version, e.g. 'Version
            /// 0.7.3'
            static var licenseVersion: String {
                Localized.get("settings.about.licenseVersion")
            }

            /// Section header for downloaded models on the licenses screen
            static var models: String {
                Localized.get("settings.about.models")
            }

            /// Row linking to the privacy policy
            static var privacyPolicy: String {
                Localized.get("settings.about.privacyPolicy")
            }

            /// Row on a license detail page opening the package's upstream repository in the
            /// browser.
            static var repository: String {
                Localized.get("settings.about.repository")
            }

            /// Row linking to the terms of service
            static var termsOfService: String {
                Localized.get("settings.about.termsOfService")
            }
        }

        enum Action {
            /// Button label to add a new integration
            static var addIntegration: String {
                Localized.get("settings.action.addIntegration")
            }

            /// Button label to add a new MCP server
            static var addMcpServer: String {
                Localized.get("settings.action.addMcpServer")
            }

            /// Button label to add a new provider
            static var addProvider: String {
                Localized.get("settings.action.addProvider")
            }
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

        enum Feedback {
            /// Button label that advances from the feedback form to the review screen.
            static var continueButton: String {
                Localized.get("settings.feedback.continueButton")
            }

            /// Button label that copies the feedback report body to the clipboard.
            static var copyButton: String {
                Localized.get("settings.feedback.copyButton")
            }

            /// Placeholder text shown in the feedback description field.
            static var descriptionPlaceholder: String {
                Localized.get("settings.feedback.descriptionPlaceholder")
            }

            /// Description shown in the feedback form sheet header. Warm and encouraging — explains
            /// there is no telemetry so direct feedback is how the team learns.
            static var formDescription: String {
                Localized.get("settings.feedback.formDescription")
            }

            /// Helper text below the feedback report, showing the support email address.
            static func helperText(_ p1: String) -> String {
                String(format: Localized.get("settings.feedback.helperText"), p1)
            }

            /// Toggle label for attaching the log file to the feedback email.
            static var includeLogs: String {
                Localized.get("settings.feedback.includeLogs")
            }

            /// Description in the report sheet header. %@ is the support email address.
            static func reportDescription(_ p1: String) -> String {
                String(format: Localized.get("settings.feedback.reportDescription"), p1)
            }

            /// Navigation title for the feedback review and send screen.
            static var reportTitle: String {
                Localized.get("settings.feedback.reportTitle")
            }

            /// Button label that opens the mail composer pre-filled with the feedback report.
            static var sendButton: String {
                Localized.get("settings.feedback.sendButton")
            }

            /// Settings row label that opens the feedback sheet.
            static var sendFeedback: String {
                Localized.get("settings.feedback.sendFeedback")
            }

            /// Label shown above the Copy/Send buttons. %@ is the support email address.
            static func sendTo(_ p1: String) -> String {
                String(format: Localized.get("settings.feedback.sendTo"), p1)
            }

            /// Navigation title for the feedback form sheet.
            static var sheetTitle: String {
                Localized.get("settings.feedback.sheetTitle")
            }

            /// Label for the feedback type picker row.
            static var typeLabel: String {
                Localized.get("settings.feedback.typeLabel")
            }

            enum Kind {
                /// Feedback type option: bug report.
                static var bug: String {
                    Localized.get("settings.feedback.type.bug")
                }

                /// Feedback type option: feature request.
                static var feature: String {
                    Localized.get("settings.feedback.type.feature")
                }

                /// Feedback type option: general feedback.
                static var general: String {
                    Localized.get("settings.feedback.type.general")
                }
            }
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
            /// Status label when the local model has finished downloading
            static var modelDownloaded: String {
                Localized.get("settings.info.modelDownloaded")
            }

            /// Status label while the local model is downloading
            static var modelDownloading: String {
                Localized.get("settings.info.modelDownloading")
            }

            /// Status label when the local model has not been downloaded
            static var modelNotDownloaded: String {
                Localized.get("settings.info.modelNotDownloaded")
            }

            enum ModelsAvailable {
                /// Describes how many models are available for a provider (one)
                static func one(_ p1: String) -> String {
                    String(format: Localized.get("settings.info.modelsAvailable.one"), p1)
                }

                /// Describes how many models are available for a provider (other)
                static func other(_ p1: String) -> String {
                    String(format: Localized.get("settings.info.modelsAvailable.other"), p1)
                }
            }
        }

        enum Label {
            /// Navigation link label for tool permissions
            static var permissions: String {
                Localized.get("settings.label.permissions")
            }
        }

        enum LocalAssets {
            static var subtitle: String {
                Localized.get("settings.localAssets.subtitle")
            }

            static var title: String {
                Localized.get("settings.localAssets.title")
            }

            static func totalInstalled(_ p1: String) -> String {
                String(format: Localized.get("settings.localAssets.totalInstalled"), p1)
            }
        }

        enum Log {
            /// A message displayed when there are no log entries to display.
            static var empty: String {
                Localized.get("settings.log.empty")
            }
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

            /// Picker label for the minimum log level in advanced settings
            static var minimumLevel: String {
                Localized.get("settings.logging.minimumLevel")
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
            /// Section header and navigation title for the About screen (version, legal links,
            /// licenses)
            static var about: String {
                Localized.get("settings.section.about")
            }

            /// Section header for advanced settings
            static var advanced: String {
                Localized.get("settings.section.advanced")
            }

            /// Section header in settings grouping agent-scoped configuration
            static var agent: String {
                Localized.get("settings.section.agent")
            }

            /// Section header for development tools
            static var development: String {
                Localized.get("settings.section.development")
            }

            /// Section header in settings grouping app-wide preferences
            static var general: String {
                Localized.get("settings.section.general")
            }

            static var storage: String {
                Localized.get("settings.section.storage")
            }

            /// Section header grouping system-level/configuration entries
            static var system: String {
                Localized.get("settings.section.system")
            }
        }
    }

    enum Skills {
        /// Section header for a skill's instruction text
        static var instruction: String {
            Localized.get("skills.instruction")
        }

        /// Navigation title for skills list
        static var title: String {
            Localized.get("skills.title")
        }

        /// Section header for the tools a skill provides
        static var tools: String {
            Localized.get("skills.tools")
        }
    }

    enum Space {
        /// An alert message that appears when the user confirms deleting a space. It explains that
        /// the chats and memories in the deleted space will be moved to the "All Chats" space.
        static var deleteWarning: String {
            Localized.get("space.deleteWarning")
        }

        /// A button label that allows a user to remove their active chat from a space.
        static var removeFromSpace: String {
            Localized.get("space.removeFromSpace")
        }

        /// Navigation title for space list
        static var title: String {
            Localized.get("space.title")
        }

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

        enum Detail {
            /// Navigation title shown while editing a space
            static var title: String {
                Localized.get("space.detail.title")
            }

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

        enum Section {
            /// Section header for space instructions
            static var instructions: String {
                Localized.get("space.section.instructions")
            }
        }
    }

    enum Status {
        /// A status indicating that a tool call has completed successfully.
        static var completed: String {
            Localized.get("status.completed")
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

        /// A tool call that failed, displayed in red text.
        static func failedFormat(_ p1: String) -> String {
            String(format: Localized.get("status.failedFormat"), p1)
        }
    }

    enum Store {
        /// A message displayed when there are no products to show.
        static var noProducts: String {
            Localized.get("store.noProducts")
        }

        /// A button label that refreshes the list of available in-app purchases.
        static var refreshProducts: String {
            Localized.get("store.refreshProducts")
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

        /// Tool category label for calendar tools
        static var calendar: String {
            Localized.get("toolCategory.calendar")
        }

        /// Tool category label for chat-related tools
        static var chats: String {
            Localized.get("toolCategory.chats")
        }

        /// Tool category label for email tools
        static var email: String {
            Localized.get("toolCategory.email")
        }

        /// Tool category label for extension (MCP) tools
        static var extensions: String {
            Localized.get("toolCategory.extensions")
        }

        /// Tool category label for family and school tools
        static var familyAndSchool: String {
            Localized.get("toolCategory.familyAndSchool")
        }

        /// Tool category label for health tools
        static var health: String {
            Localized.get("toolCategory.health")
        }

        /// Tool category label for knowledge tools
        static var knowledge: String {
            Localized.get("toolCategory.knowledge")
        }

        /// Tool category label for reminder tools
        static var reminders: String {
            Localized.get("toolCategory.reminders")
        }

        /// Tool category label for skill tools
        static var skills: String {
            Localized.get("toolCategory.skills")
        }

        /// Tool category label for time and place tools
        static var timeAndPlace: String {
            Localized.get("toolCategory.timeAndPlace")
        }

        /// Tool category label for web tools
        static var web: String {
            Localized.get("toolCategory.web")
        }
    }

    enum ToolDetail {
        /// Status label for a tool call that finished returning nothing
        static var completedNoOutput: String {
            Localized.get("toolDetail.completedNoOutput")
        }

        /// Status label for a tool call the user denied
        static var deniedByUser: String {
            Localized.get("toolDetail.deniedByUser")
        }

        /// Status label for a tool call that failed
        static var failed: String {
            Localized.get("toolDetail.failed")
        }

        /// Section heading above a tool call's input arguments in the tool detail sheet
        static var input: String {
            Localized.get("toolDetail.input")
        }

        /// Section heading above a tool call's result in the tool detail sheet
        static var output: String {
            Localized.get("toolDetail.output")
        }
    }

    enum Tools {
        /// A label displayed above a list of tools discovered on a server.
        static var sectionTitle: String {
            Localized.get("tools.sectionTitle")
        }

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

            /// Display name for the add-intent tool
            static var addIntent: String {
                Localized.get("tools.agent.addIntent")
            }

            /// Display name for the advance-flow tool
            static var advanceFlow: String {
                Localized.get("tools.agent.advanceFlow")
            }

            /// Display name for the list-intents tool
            static var listIntents: String {
                Localized.get("tools.agent.listIntents")
            }

            /// Display name for the resolve-intent tool
            static var resolveIntent: String {
                Localized.get("tools.agent.resolveIntent")
            }

            /// Display name for the search-skills tool
            static var searchSkills: String {
                Localized.get("tools.agent.searchSkills")
            }

            /// Display name for the start-flow tool
            static var startFlow: String {
                Localized.get("tools.agent.startFlow")
            }

            /// Display name for the update-intent tool
            static var updateIntent: String {
                Localized.get("tools.agent.updateIntent")
            }
        }

        enum Aula {
            /// Display name for the Aula calendar tool
            static var calendar: String {
                Localized.get("tools.aula.calendar")
            }

            /// Display name for the Aula children tool
            static var children: String {
                Localized.get("tools.aula.children")
            }

            /// Display name for the list-Aula-messages tool
            static var listMessages: String {
                Localized.get("tools.aula.listMessages")
            }

            /// Display name for the read-Aula-message tool
            static var readMessage: String {
                Localized.get("tools.aula.readMessage")
            }

            /// Display name for the Aula updates digest tool
            static var updates: String {
                Localized.get("tools.aula.updates")
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

        enum Contest {
            /// Display name for the contest-knowledge tool
            static var knowledge: String {
                Localized.get("tools.contest.knowledge")
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

        enum Description {
            /// One-sentence description of the activate_skill tool, shown in the tool detail sheet
            static var activateSkill: String {
                Localized.get("tools.description.activateSkill")
            }

            /// One-sentence description of the add_intent tool, shown in the tool detail sheet
            static var addIntent: String {
                Localized.get("tools.description.addIntent")
            }

            /// One-sentence description of the add_knowledge tool, shown in the tool detail sheet
            static var addKnowledge: String {
                Localized.get("tools.description.addKnowledge")
            }

            /// One-sentence description of the advance_flow tool, shown in the tool detail sheet
            static var advanceFlow: String {
                Localized.get("tools.description.advanceFlow")
            }

            /// One-sentence description of the aula_calendar tool, shown in the tool detail sheet
            static var aulaCalendar: String {
                Localized.get("tools.description.aulaCalendar")
            }

            /// One-sentence description of the aula_children tool, shown in the tool detail sheet
            static var aulaChildren: String {
                Localized.get("tools.description.aulaChildren")
            }

            /// One-sentence description of the aula_message_read tool, shown in the tool detail
            /// sheet
            static var aulaMessageRead: String {
                Localized.get("tools.description.aulaMessageRead")
            }

            /// One-sentence description of the aula_messages_list tool, shown in the tool detail
            /// sheet
            static var aulaMessagesList: String {
                Localized.get("tools.description.aulaMessagesList")
            }

            /// One-sentence description of the aula_updates tool, shown in the tool detail sheet
            static var aulaUpdates: String {
                Localized.get("tools.description.aulaUpdates")
            }

            /// One-sentence description of the background_notify tool, shown in the tool detail
            /// sheet
            static var backgroundNotify: String {
                Localized.get("tools.description.backgroundNotify")
            }

            /// One-sentence description of the contest_knowledge tool, shown in the tool detail
            /// sheet
            static var contestKnowledge: String {
                Localized.get("tools.description.contestKnowledge")
            }

            /// One-sentence description of the create_calendar_event tool, shown in the tool detail
            /// sheet
            static var createCalendarEvent: String {
                Localized.get("tools.description.createCalendarEvent")
            }

            /// One-sentence description of the create_space tool, shown in the tool detail sheet
            static var createSpace: String {
                Localized.get("tools.description.createSpace")
            }

            /// One-sentence description of the delete_knowledge tool, shown in the tool detail
            /// sheet
            static var deleteKnowledge: String {
                Localized.get("tools.description.deleteKnowledge")
            }

            /// One-sentence description of the done tool, shown in the tool detail sheet
            static var done: String {
                Localized.get("tools.description.done")
            }

            /// One-sentence description of the edit_core tool, shown in the tool detail sheet
            static var editCore: String {
                Localized.get("tools.description.editCore")
            }

            /// One-sentence description of the edit_space tool, shown in the tool detail sheet
            static var editSpace: String {
                Localized.get("tools.description.editSpace")
            }

            /// One-sentence description of the email_list tool, shown in the tool detail sheet
            static var emailList: String {
                Localized.get("tools.description.emailList")
            }

            /// One-sentence description of the email_read tool, shown in the tool detail sheet
            static var emailRead: String {
                Localized.get("tools.description.emailRead")
            }

            /// One-sentence description of the email_reply tool, shown in the tool detail sheet
            static var emailReply: String {
                Localized.get("tools.description.emailReply")
            }

            /// One-sentence description of the email_search tool, shown in the tool detail sheet
            static var emailSearch: String {
                Localized.get("tools.description.emailSearch")
            }

            /// One-sentence description of the email_send tool, shown in the tool detail sheet
            static var emailSend: String {
                Localized.get("tools.description.emailSend")
            }

            /// One-sentence description of the finish onboarding tool, shown in the tool detail
            /// sheet
            static var finishOnboarding: String {
                Localized.get("tools.description.finishOnboarding")
            }

            /// One-sentence description of the forget_knowledge tool, shown in the tool detail
            /// sheet
            static var forgetKnowledge: String {
                Localized.get("tools.description.forgetKnowledge")
            }

            /// One-sentence description of the get_calendar_events tool, shown in the tool detail
            /// sheet
            static var getCalendarEvents: String {
                Localized.get("tools.description.getCalendarEvents")
            }

            /// One-sentence description of the get_chat_transcript tool, shown in the tool detail
            /// sheet
            static var getChatTranscript: String {
                Localized.get("tools.description.getChatTranscript")
            }

            /// One-sentence description of the get_directions tool, shown in the tool detail sheet
            static var getDirections: String {
                Localized.get("tools.description.getDirections")
            }

            /// One-sentence description of the get_food_details tool, shown in the tool detail
            /// sheet
            static var getFoodDetails: String {
                Localized.get("tools.description.getFoodDetails")
            }

            /// One-sentence description of the get_health_log tool, shown in the tool detail sheet
            static var getHealthLog: String {
                Localized.get("tools.description.getHealthLog")
            }

            /// One-sentence description of the get_knowledge tool, shown in the tool detail sheet
            static var getKnowledge: String {
                Localized.get("tools.description.getKnowledge")
            }

            /// One-sentence description of the get_presentation tool, shown in the tool detail
            /// sheet
            static var getPresentation: String {
                Localized.get("tools.description.getPresentation")
            }

            /// One-sentence description of the get_reminders tool, shown in the tool detail sheet
            static var getReminders: String {
                Localized.get("tools.description.getReminders")
            }

            /// One-sentence description of the get_time_and_place tool, shown in the tool detail
            /// sheet
            static var getTimeAndPlace: String {
                Localized.get("tools.description.getTimeAndPlace")
            }

            /// One-sentence description of the get_weather tool, shown in the tool detail sheet
            static var getWeather: String {
                Localized.get("tools.description.getWeather")
            }

            /// One-sentence description of the list_chats tool, shown in the tool detail sheet
            static var listChats: String {
                Localized.get("tools.description.listChats")
            }

            /// One-sentence description of the list_intents tool, shown in the tool detail sheet
            static var listIntents: String {
                Localized.get("tools.description.listIntents")
            }

            /// One-sentence description of the list_spaces tool, shown in the tool detail sheet
            static var listSpaces: String {
                Localized.get("tools.description.listSpaces")
            }

            /// One-sentence description of the log_body_measurement tool, shown in the tool detail
            /// sheet
            static var logBodyMeasurement: String {
                Localized.get("tools.description.logBodyMeasurement")
            }

            /// One-sentence description of the log_food tool, shown in the tool detail sheet
            static var logFood: String {
                Localized.get("tools.description.logFood")
            }

            /// One-sentence description of the log_sleep tool, shown in the tool detail sheet
            static var logSleep: String {
                Localized.get("tools.description.logSleep")
            }

            /// One-sentence description of the manage_calendar_event tool, shown in the tool detail
            /// sheet
            static var manageCalendarEvent: String {
                Localized.get("tools.description.manageCalendarEvent")
            }

            /// One-sentence description of the manage_reminder tool, shown in the tool detail sheet
            static var manageReminder: String {
                Localized.get("tools.description.manageReminder")
            }

            /// One-sentence description of the manage_vocabulary tool, shown in the tool detail
            /// sheet
            static var manageVocabulary: String {
                Localized.get("tools.description.manageVocabulary")
            }

            /// One-sentence description of the merge_knowledge tool, shown in the tool detail sheet
            static var mergeKnowledge: String {
                Localized.get("tools.description.mergeKnowledge")
            }

            /// One-sentence description of the move_chat_to_space tool, shown in the tool detail
            /// sheet
            static var moveChatToSpace: String {
                Localized.get("tools.description.moveChatToSpace")
            }

            /// One-sentence description of the present_options tool, shown in the tool detail sheet
            static var presentOptions: String {
                Localized.get("tools.description.presentOptions")
            }

            /// One-sentence description of the read_core tool, shown in the tool detail sheet
            static var readCore: String {
                Localized.get("tools.description.readCore")
            }

            /// One-sentence description of the resolve_intent tool, shown in the tool detail sheet
            static var resolveIntent: String {
                Localized.get("tools.description.resolveIntent")
            }

            /// One-sentence description of the search_food tool, shown in the tool detail sheet
            static var searchFood: String {
                Localized.get("tools.description.searchFood")
            }

            /// One-sentence description of the search_knowledge tool, shown in the tool detail
            /// sheet
            static var searchKnowledge: String {
                Localized.get("tools.description.searchKnowledge")
            }

            /// One-sentence description of the search_places tool, shown in the tool detail sheet
            static var searchPlaces: String {
                Localized.get("tools.description.searchPlaces")
            }

            /// One-sentence description of the search_skills tool, shown in the tool detail sheet
            static var searchSkills: String {
                Localized.get("tools.description.searchSkills")
            }

            /// One-sentence description of the set_presentation tool, shown in the tool detail
            /// sheet
            static var setPresentation: String {
                Localized.get("tools.description.setPresentation")
            }

            /// One-sentence description of the set_proactivity tool, shown in the tool detail sheet
            static var setProactivity: String {
                Localized.get("tools.description.setProactivity")
            }

            /// One-sentence description of the start_flow tool, shown in the tool detail sheet
            static var startFlow: String {
                Localized.get("tools.description.startFlow")
            }

            /// One-sentence description of the supersede_knowledge tool, shown in the tool detail
            /// sheet
            static var supersedeKnowledge: String {
                Localized.get("tools.description.supersedeKnowledge")
            }

            /// One-sentence description of the update_intent tool, shown in the tool detail sheet
            static var updateIntent: String {
                Localized.get("tools.description.updateIntent")
            }

            /// One-sentence description of the update_knowledge tool, shown in the tool detail
            /// sheet
            static var updateKnowledge: String {
                Localized.get("tools.description.updateKnowledge")
            }

            /// One-sentence description of the web_fetch tool, shown in the tool detail sheet
            static var webFetch: String {
                Localized.get("tools.description.webFetch")
            }

            /// One-sentence description of the web_search tool, shown in the tool detail sheet
            static var webSearch: String {
                Localized.get("tools.description.webSearch")
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

        enum Email {
            /// Display name for the list-emails tool
            static var list: String {
                Localized.get("tools.email.list")
            }

            /// Display name for the read-email tool
            static var read: String {
                Localized.get("tools.email.read")
            }

            /// Display name for the reply-email tool
            static var reply: String {
                Localized.get("tools.email.reply")
            }

            /// Display name for the search-emails tool
            static var search: String {
                Localized.get("tools.email.search")
            }

            /// Display name for the send-email tool
            static var send: String {
                Localized.get("tools.email.send")
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
            /// Display name for the forget-knowledge tool
            static var knowledge: String {
                Localized.get("tools.forget.knowledge")
            }

            /// Display name for the forget-memory tool
            static var memory: String {
                Localized.get("tools.forget.memory")
            }
        }

        enum Get {
            /// Display name for the get-presentation tool
            static var presentation: String {
                Localized.get("tools.get.presentation")
            }

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

            enum Health {
                /// Display name for the get-health-log tool
                static var log: String {
                    Localized.get("tools.get.health.log")
                }
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
            /// Display name for the log-body-measurement tool
            static var bodyMeasurement: String {
                Localized.get("tools.log.bodyMeasurement")
            }

            /// Display name for the log-food tool
            static var food: String {
                Localized.get("tools.log.food")
            }

            /// Display name for the log-sleep tool
            static var sleep: String {
                Localized.get("tools.log.sleep")
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

        enum Merge {
            /// Display name for the merge-knowledge tool
            static var knowledge: String {
                Localized.get("tools.merge.knowledge")
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

            enum Active {
                /// Empty state label shown when no intents are currently active
                static var intents: String {
                    Localized.get("tools.no.active.intents")
                }
            }
        }

        enum Other {
            /// Section header for non-primary voice engine options
            static var voices: String {
                Localized.get("tools.other.voices")
            }
        }

        enum Present {
            /// Display name for the present-options tool
            static var options: String {
                Localized.get("tools.present.options")
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

        enum Supersede {
            /// Display name for the supersede-knowledge tool
            static var knowledge: String {
                Localized.get("tools.supersede.knowledge")
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

            /// Display name for the tool the agent calls to seal onboarding
            static var finishOnboarding: String {
                Localized.get("tools.system.finishOnboarding")
            }

            /// Display name for the get-directions system tool
            static var getDirections: String {
                Localized.get("tools.system.getDirections")
            }

            /// Display name for the search-places system tool
            static var searchPlaces: String {
                Localized.get("tools.system.searchPlaces")
            }

            /// Display name for the get-time-and-place system tool
            static var timeAndPlace: String {
                Localized.get("tools.system.timeAndPlace")
            }

            /// Display name for the get-weather system tool
            static var weather: String {
                Localized.get("tools.system.weather")
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

        /// Hub section label above the AI providers group.
        static var aiProviders: String {
            Localized.get("ui.aiProviders")
        }

        /// Generic 'All' filter or tab label
        static var all: String {
            Localized.get("ui.all")
        }

        /// Label for the Aula skill and integration
        static var aula: String {
            Localized.get("ui.aula")
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

        /// Settings entry that groups provider and MCP server configuration
        static var connections: String {
            Localized.get("ui.connections")
        }

        /// Section label for the cooking skill (deciding what to cook and cooking it)
        static var cooking: String {
            Localized.get("ui.cooking")
        }

        /// Button label after copying the raw error response
        static var copied: String {
            Localized.get("ui.copied")
        }

        /// Button to copy the raw error response in the error detail sheet
        static var copyRawError: String {
            Localized.get("ui.copyRawError")
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

        /// Tab or section label for the health tracking feature
        static var health: String {
            Localized.get("ui.health")
        }

        /// Success message shown after a data import completes
        static var importSuccessful: String {
            Localized.get("ui.import-successful")
        }

        /// Field label for the agent instruction input
        static var instruction: String {
            Localized.get("ui.instruction")
        }

        /// Section label for connected integrations
        static var integrations: String {
            Localized.get("ui.integrations")
        }

        /// Label for a single agent intent
        static var intent: String {
            Localized.get("ui.intent")
        }

        /// Display name for the Interaction skill
        static var interaction: String {
            Localized.get("ui.interaction")
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

        /// Section label for the planning skill (trips, holidays, activities)
        static var planning: String {
            Localized.get("ui.planning")
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

        /// Section label for the recommendations skill (finding books, movies, music, and games
        /// worth the user's time)
        static var recommendations: String {
            Localized.get("ui.recommendations")
        }

        /// Badge or label for recommended options
        static var recommended: String {
            Localized.get("ui.recommended")
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

        /// Spoken by the agent during a live call when a non-recoverable error occurs, right before
        /// the call hangs up.
        static var errorFarewell: String {
            Localized.get("voice.errorFarewell")
        }

        /// A footer text that encourages users to install more voices if they haven't already.
        static var installHint: String {
            Localized.get("voice.installHint")
        }

        /// Status label shown while the microphone is active and listening
        static var listening: String {
            Localized.get("voice.listening")
        }

        /// Error shown when the live call cannot recover audio after a route change (e.g. Bluetooth
        /// handover) and has to end.
        static var recoveryFailed: String {
            Localized.get("voice.recoveryFailed")
        }

        /// Status label shown while the TTS engine is speaking
        static var speaking: String {
            Localized.get("voice.speaking")
        }
    }

    enum Wallet {
        /// A button label that deletes all wallets.
        static var deleteAll: String {
            Localized.get("wallet.deleteAll")
        }

        /// A message displayed when there are no wallets to display.
        static var empty: String {
            Localized.get("wallet.empty")
        }

        /// A button label that evicts empty wallets.
        static var evictEmpty: String {
            Localized.get("wallet.evictEmpty")
        }
    }

    enum Watch {
        /// Complication and widget label that opens the watch companion
        static var askEigin: String {
            Localized.get("watch.ask-eigin")
        }

        /// Watch error when the iPhone did not respond
        static var cantReachPhone: String {
            Localized.get("watch.cant-reach-phone")
        }

        /// Watch error when recording failed or microphone access is off
        static var cantRecord: String {
            Localized.get("watch.cant-record")
        }

        static var chatTitle: String {
            Localized.get("watch.chat-title")
        }

        /// Watch complication gallery description
        static var complicationDescription: String {
            Localized.get("watch.complication-description")
        }

        /// Watch reply when the recording had no speech
        static var didntCatch: String {
            Localized.get("watch.didnt-catch")
        }

        /// Watch reply when the turn produced no answer
        static var noReply: String {
            Localized.get("watch.no-reply")
        }

        static var pushToTalk: String {
            Localized.get("watch.push-to-talk")
        }

        static var releaseToSend: String {
            Localized.get("watch.release-to-send")
        }

        /// Prompt under the blob while the question sends and the phone answers
        static var sending: String {
            Localized.get("watch.sending")
        }

        /// Watch reply when transcription failed
        static var transcribeFailed: String {
            Localized.get("watch.transcribe-failed")
        }

        /// Reply when the turn is given up because the background time ran out
        static var turnDelayed: String {
            Localized.get("watch.turn-delayed")
        }
    }

    enum Widgets {
        /// Placeholder text of the widget's faux input pill.
        static var chatPillTitle: String {
            Localized.get("widgets.chatPillTitle")
        }

        /// Description shown in the widget gallery picker.
        static var description: String {
            Localized.get("widgets.description")
        }

        /// Widget button: start a fresh chat with dictation armed.
        static var dictation: String {
            Localized.get("widgets.dictation")
        }

        /// Widget button: start a fresh chat in a live call.
        static var liveCall: String {
            Localized.get("widgets.liveCall")
        }

        /// Name shown in the widget gallery picker.
        static var name: String {
            Localized.get("widgets.name")
        }

        /// Widget button: start a fresh chat.
        static var newChat: String {
            Localized.get("widgets.newChat")
        }

        /// Widget button: open the app.
        static var openApp: String {
            Localized.get("widgets.openApp")
        }

        /// Widget button: start a fresh chat with the camera ready.
        static var photo: String {
            Localized.get("widgets.photo")
        }
    }
}
