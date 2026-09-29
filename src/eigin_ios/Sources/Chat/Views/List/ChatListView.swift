import Factory
import SwiftData
import SwiftUI

enum ChatListDestination: Hashable {
    case manageSpaces
}

/// The main chat list screen, showing all conversations filtered by space.
struct ChatListView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colors) private var colors
    @Environment(\.scenePhase) private var scenePhase
    @Injected(\.chatAttachmentStore) private var attachmentStore
    @Query(sort: \Chat.updatedAt, order: .reverse) private var chats: [Chat]
    @Query private var agents: [Agent]
    @Query(sort: \Space.name) private var spaces: [Space]

    @AppStorage(PendingDestination.storageKey) private var pendingDestination: String?
    private var agent: Agent? {
        agents.primary
    }

    @State private var path = NavigationPath()
    @State private var chatToDelete: Chat?
    @State private var showDeleteConfirmation = false
    @State private var chatToRename: Chat?
    @State private var showRenameAlert = false
    @State private var renameText = ""
    @State private var selectedSpaceID: UUID?

    private var filteredChats: [Chat] {
        ChatListFilter.visibleChats(chats, spaces: spaces, selectedSpaceID: selectedSpaceID)
    }

    var body: some View {
        NavigationStack(path: $path) {
            VStack(spacing: 0) {
                AppNavigationHeader(
                    leading: {
                        SpaceFilterMenu(
                            spaces: spaces,
                            selectedSpaceID: $selectedSpaceID,
                            onManageSpaces: { path.append(ChatListDestination.manageSpaces) }
                        )
                    },
                    center: {
                        AppBrandAvatar(emoji: agent?.emoji)
                    },
                    trailing: {
                        AppActionButton(
                            icon: Iconography.Functional.plus,
                            variant: .open,
                            size: .medium,
                            action: createNewChat
                        )
                        .disabled(agent == nil)
                    }
                )

                Group {
                    if filteredChats.isEmpty {
                        ContentUnavailableView(
                            Localized.Chat.EmptyState.title,
                            systemImage: "bubble",
                            description: Text(Localized.Chat.EmptyState.hint)
                        )
                    } else {
                        chatList
                    }
                }
                .scrollContentBackground(.hidden)
            }
            .background(colors.surface.standard.base.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: UUID.self) { chatID in
                ChatView(chatID: chatID)
                    .hidesTabBar()
            }
            .navigationDestination(for: ChatLaunch.self) { launch in
                ChatView(chatID: launch.chatID, opening: launch.opening)
                    // A ChatLaunch → ChatLaunch swap reuses the destination's
                    // @State, so key on the chat to force a fresh view.
                    .id(launch.chatID)
                    .hidesTabBar()
            }
            .navigationDestination(for: ChatListDestination.self) { destination in
                switch destination {
                case .manageSpaces:
                    SpaceListView()
                        .hidesTabBar()
                }
            }
            .alert(Localized.Chat.Alert.renameTitle, isPresented: $showRenameAlert) {
                TextField(Localized.Common.Fields.chatName, text: $renameText)
                Button(Localized.Common.Actions.cancel, role: .cancel) {}
                Button(Localized.Common.Actions.rename) {
                    let trimmed = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty, let chat = chatToRename {
                        chat.title = trimmed
                        chat.updatedAt = .now
                        Haptics.light()
                    }
                }
            }
            .onAppear {
                // Must run before handling a pending destination — the incoming
                // chat only exists after consumption, so nothing to protect.
                sweepOrphanedEmptyChats()
                handlePendingDestination()
            }
            .onChange(of: pendingDestination) { _, _ in
                handlePendingDestination()
            }
            // Navigation during a scene transition gets swallowed, and widget
            // taps land in that window. Re-run once the scene is active.
            .onChange(of: scenePhase) { _, phase in
                guard phase == .active else { return }
                handlePendingDestination()
            }
            .alert(Localized.Common.Alert.deleteChatTitle, isPresented: $showDeleteConfirmation) {
                Button(Localized.Common.Actions.cancel, role: .cancel) {}
                Button(Localized.Common.Actions.delete, role: .destructive) {
                    Haptics.error()
                    if let chat = chatToDelete {
                        let attachments = chat.messages.flatMap { $0.attachments ?? [] }
                        attachmentStore.deleteAll(attachments)
                        modelContext.delete(chat)
                    }
                }
            } message: {
                Text(Localized.Chat.deleteWarning)
            }
            .tabBarPadding()
        }
        .ignoresSafeArea(.container, edges: .bottom)
    }

    private var groupedChats: [(String, [Chat])] {
        let calendar = Calendar.current
        let now = Date.now

        let lastWeekStart = calendar.date(
            byAdding: .weekOfYear,
            value: -1,
            to: calendar.startOfDay(for: now)
        )!
        let startOfThisWeek = calendar.dateInterval(of: .weekOfYear, for: now)!.start

        var today: [Chat] = []
        var yesterday: [Chat] = []
        var thisWeek: [Chat] = []
        var lastWeek: [Chat] = []
        var thisMonth: [Chat] = []
        var older: [Chat] = []

        for chat in filteredChats {
            if calendar.isDateInToday(chat.updatedAt) {
                today.append(chat)
            } else if calendar.isDateInYesterday(chat.updatedAt) {
                yesterday.append(chat)
            } else if calendar.isDate(chat.updatedAt, equalTo: now, toGranularity: .weekOfYear) {
                thisWeek.append(chat)
            } else if chat.updatedAt >= lastWeekStart, chat.updatedAt < startOfThisWeek {
                lastWeek.append(chat)
            } else if calendar.isDate(chat.updatedAt, equalTo: now, toGranularity: .month) {
                thisMonth.append(chat)
            } else {
                older.append(chat)
            }
        }

        var groups: [(String, [Chat])] = []
        if !today
            .isEmpty { groups.append((Localized.Timestamp.today, today)) }
        if !yesterday.isEmpty { groups.append((
            Localized.Timestamp.yesterday,
            yesterday
        )) }
        if !thisWeek.isEmpty { groups.append((
            Localized.Timestamp.thisWeek,
            thisWeek
        )) }
        if !lastWeek.isEmpty { groups.append((
            Localized.Timestamp.lastWeek,
            lastWeek
        )) }
        if !thisMonth.isEmpty { groups.append((
            Localized.Timestamp.thisMonth,
            thisMonth
        )) }
        if !older
            .isEmpty { groups.append((Localized.Timestamp.older, older)) }
        return groups
    }

    private var chatList: some View {
        List {
            ForEach(groupedChats, id: \.0) { title, sectionChats in
                Section(header: Text(title).typography(Typography.miniLabel)) {
                    ForEach(Array(sectionChats.enumerated()), id: \.element.id) { index, chat in
                        NavigationLink(value: chat.id) {
                            VStack(alignment: .leading, spacing: 0) {
                                if index > 0 {
                                    Divider()
                                        .padding(.leading, 36 + Spacing.n16)
                                }
                                ChatRowView(
                                    chat: chat,
                                    spaces: spaces
                                )
                                .padding(.vertical, Spacing.n8)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .swipeActions(edge: .leading) {
                            Button {
                                renameText = chat.title
                                chatToRename = chat
                                showRenameAlert = true
                            } label: {
                                Label(Localized.Common.Actions.rename, systemImage: "pencil")
                            }
                        }
                        .swipeActions(edge: .trailing) {
                            Button {
                                chatToDelete = chat
                                showDeleteConfirmation = true
                            } label: {
                                Label(Localized.Common.Actions.delete, systemImage: "trash")
                            }
                            .tint(.red)
                        }
                    }
                }
            }
        }
        .listStyle(.grouped)
        .listSectionSeparator(.hidden)
        .animation(Animations.smooth, value: filteredChats.map(\.id))
        .scrollContentBackground(.hidden)
    }

    private func createNewChat() {
        guard let agent else { return }
        let chat = Chat(agentID: agent.id, spaceID: selectedSpaceID)
        modelContext.insert(chat)
        path.append(ChatLaunch(chatID: chat.id))
    }

    /// Deletes chats with no messages. A conversation only becomes real once it
    /// holds a message; widget- or shortcut-launched chats the user abandoned
    /// (left the app before sending anything) leave these behind, and there is
    /// no view lifecycle to clean them up — the list's appearance is the one
    /// place that always sees them.
    private func sweepOrphanedEmptyChats() {
        let orphans = chats.filter { $0.messages.isEmpty }
        guard !orphans.isEmpty else { return }
        for chat in orphans {
            modelContext.delete(chat)
        }
        try? modelContext.save()
    }

    /// Opens whatever ``PendingDestination`` holds, once the chat list is
    /// alive and the scene is active; the widget, notifications, and onboarding
    /// all funnel through here. External launches replace whatever is on the
    /// stack — an incoming chat is always the one layer above the list, never
    /// stacked on a previous chat the user would then have to back through.
    ///
    /// Must not run while the scene is inactive: consuming here would clear
    /// the store and mutate the navigation path mid-transition, where the
    /// push can be silently dropped — leaving the destination lost.
    private func handlePendingDestination() {
        guard scenePhase == .active else { return }
        guard let destination = PendingDestination.get() else { return }
        PendingDestination.clear()
        switch destination {
        case .initiative(let requestID):
            openInitiativeChat(requestID: requestID)
        case .chat(let chatID):
            replacePath(ChatLaunch(chatID: chatID))
        case .newChat(let route):
            startChat(route: route)
        }
    }

    /// Writes the whole path in one assignment — clearing first and appending
    /// after works, but the two-step mutation can lose the push when handled
    /// during a scene transition.
    private func replacePath(_ launch: ChatLaunch) {
        var newPath = NavigationPath()
        newPath.append(launch)
        path = newPath
    }

    private func startChat(route: EiginRoute) {
        guard let agent else { return }
        let chat = Chat(agentID: agent.id, spaceID: selectedSpaceID)
        modelContext.insert(chat)
        replacePath(ChatLaunch(chatID: chat.id, opening: ChatOpening(route: route)))
    }

    private func openInitiativeChat(requestID: UUID) {
        let descriptor = FetchDescriptor<AgentInitiativeRequest>(
            predicate: #Predicate { $0.id == requestID }
        )

        guard let request = try? modelContext.fetch(descriptor).first else {
            return
        }

        let chat = Chat(agentID: request.agentID, spaceID: selectedSpaceID)
        if let title = request.title, !title.isEmpty {
            chat.title = title
            chat.titleOrigin = .edited
        }
        modelContext.insert(chat)

        if let summary = request.summary, !summary.isEmpty {
            let summaryMessage = Message(
                role: "system",
                content: "Summary of earlier conversation:\n\n\(summary)"
            )
            summaryMessage.isCompactionSummary = true
            summaryMessage.chat = chat
            modelContext.insert(summaryMessage)
        }

        let message = Message(role: "assistant", content: request.message)
        message.chat = chat
        modelContext.insert(message)

        request.handledAt = Date()
        try? modelContext.save()

        replacePath(ChatLaunch(chatID: chat.id))
    }
}

#Preview {
    ChatListView()
        .previewEnvironment()
}
