import SwiftData
import SwiftUI

enum ChatListDestination: Hashable {
    case manageSpaces
}

/// The main chat list screen, showing all conversations filtered by space.
struct ChatListView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colors) private var colors
    @Query(sort: \Chat.updatedAt, order: .reverse) private var chats: [Chat]
    @Query(filter: #Predicate<Agent> { $0.bootstrapComplete })
    private var agents: [Agent]
    @Query(sort: \Space.name) private var spaces: [Space]

    @AppStorage(PendingInitiative.userDefaultsKey) private var pendingInitiativeID: String?
    @AppStorage(StorageKey.pendingOnboardingChat) private var pendingOnboardingChat: String?
    private var agent: Agent? {
        agents.first
    }

    @State private var path = NavigationPath()
    @State private var chatToDelete: Chat?
    @State private var showDeleteConfirmation = false
    @State private var chatToRename: Chat?
    @State private var showRenameAlert = false
    @State private var renameText = ""
    @State private var selectedSpaceID: UUID?

    private var filteredChats: [Chat] {
        if let spaceID = selectedSpaceID {
            return chats.filter { $0.spaceID == spaceID }
        }
        return chats
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
                        AppBrandAvatar(image: Iconography.Brand.avatar, action: {})
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
                if let requestIDString = pendingInitiativeID,
                   let requestID = UUID(uuidString: requestIDString)
                {
                    handlePendingInitiative(requestID: requestID)
                }
                openPendingOnboardingChat()
            }
            .onChange(of: pendingInitiativeID) { _, newValue in
                if let requestIDString = newValue,
                   let requestID = UUID(uuidString: requestIDString)
                {
                    handlePendingInitiative(requestID: requestID)
                }
            }
            .alert(Localized.Common.Alert.deleteChatTitle, isPresented: $showDeleteConfirmation) {
                Button(Localized.Common.Actions.cancel, role: .cancel) {}
                Button(Localized.Common.Actions.delete, role: .destructive) {
                    Haptics.error()
                    if let chat = chatToDelete {
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
        path.append(chat.id)
    }

    /// Opens the chat the onboarding conversation became, once, on first load.
    private func openPendingOnboardingChat() {
        guard let idString = pendingOnboardingChat,
              let id = UUID(uuidString: idString)
        else { return }
        pendingOnboardingChat = nil
        path.append(id)
    }

    private func handlePendingInitiative(requestID: UUID) {
        PendingInitiative.clear()

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

        path.append(chat.id)
    }
}

#Preview {
    ChatListView()
        .previewEnvironment()
}
