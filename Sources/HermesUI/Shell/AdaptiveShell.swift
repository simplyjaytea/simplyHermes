#if canImport(UIKit)
    import Foundation
    import HermesKit
    import SwiftUI

    /// The app shell. Picks a layout from the screen and posture and keeps chat state in `ShellModel`,
    /// so folding and unfolding never lose the session, scroll position or draft (WP-21).
    public struct AdaptiveShell: View {
        @Bindable private var model: ShellModel
        private let connections: ConnectionsModel?
        private let sessionsList: SessionsListModel?
        private let showsDebugLayoutMenu: Bool

        @Environment(\.horizontalSizeClass) private var horizontalSizeClass
        @Environment(\.hermesPosture) private var forcedPosture
        @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
        @Environment(\.hermesReduceMotion) private var reduceMotionOverride
        @Environment(\.hermesPalette) private var palette
        @Environment(\.scenePhase) private var scenePhase
        /// Undo for chat delete, shared by both lists (feature C).
        private var deletes: ChatDeletes { .shared }
        @State private var postureMonitor = DevicePostureMonitor()
        @State private var profiles: ProfilesModel?
        @State private var bots: BotsModel?
        @State private var rooms: RoomsModel?
        @State private var terminals = TerminalModel()
        @State private var columnVisibility: NavigationSplitViewVisibility = .all
        @State private var botSettingsEntryForChat: BotRosterEntry?
        /// Search on the chat list shown when no server is active (#116 follow-up).
        @State private var localChatSearch = ""
        @State private var isLocalChatSearchPresented = false
        /// Search on the unfolded sidebar's chats (row 122). It filters what the sidebar lists, with or without a server.
        @State private var sidebarChatSearch = ""
        @State private var isSidebarSearchPresented = false

        /// `connections` fills Settings > Servers and the server switcher (WP-22). Nil shows placeholders.
        /// `sessionsList` lists the active server's chats (WP-40). Nil keeps the sample chats.
        public init(
            model: ShellModel, connections: ConnectionsModel? = nil, sessionsList: SessionsListModel? = nil,
            showsDebugLayoutMenu: Bool = false
        ) {
            self.model = model
            self.connections = connections
            self.sessionsList = sessionsList
            let liveChats = connections.map(LiveChatStore.init)
            model.liveChats = liveChats
            // Kept across re-renders: a new one would lose the folder on screen and leave views holding the old one.
            if model.workspaceBrowser == nil { model.workspaceBrowser = connections.map(WorkspaceBrowserModel.init) }
            if let connections {
                model.startServerChat = { try await connections.startChat() }
                model.placeholderStripSource = {
                    guard let server = connections.active else { return .noServer }
                    return PlaceholderStrip.derive(
                        serverName: server.name, phase: connections.phases[server.id], path: NetworkMonitor.shared.path)
                }
                model.handOffFirstMessage = { id, text, files in
                    liveChats?.chat(for: id)?.queueFirstMessage(text, attachments: files)
                }
            }
            let profileList = connections.map { ProfilesModel(connections: $0) }
            _profiles = State(initialValue: profileList)
            _bots = State(
                initialValue: connections.map { BotsModel(connections: $0, profiles: profileList, shell: model) })
            _rooms = State(initialValue: connections.map { RoomsModel(connections: $0) })
            self.showsDebugLayoutMenu = showsDebugLayoutMenu
        }

        /// A posture forced from outside (launch argument or preview) wins; otherwise the hinge decides (WP-02).
        private var posture: DevicePosture { postureMonitor.posture }

        private var reduceMotion: Bool {
            HermesMotion.resolveReduceMotion(system: systemReduceMotion, override: reduceMotionOverride)
        }

        public var body: some View {
            if UserDefaults.standard.string(forKey: "HermesScreen") == "postureDebug" {
                NavigationStack { PostureDebugView(monitor: postureMonitor) }
                    .hermesPostureSource(postureMonitor)
                    .task(id: forcedPosture) { applyForcedPosture() }
            } else if UserDefaults.standard.string(forKey: "HermesScreen") == "memory" {
                MemoryJourneyRoute(connections: connections, layoutOverride: model.layoutOverride)
                    .hermesPostureSource(postureMonitor)
                    .environment(\.hermesPosture, posture)
                    .task(id: forcedPosture) { applyForcedPosture() }
            } else {
                shell
                    .hermesPostureSource(postureMonitor)
                    .environment(\.hermesPosture, posture)
                    .task(id: forcedPosture) { applyForcedPosture() }
                    .task(id: sessionScopeKey) { await attachSessions() }
                    .task(id: connections?.active?.id) {
                        await bots?.reload()
                        await rooms?.reload()
                    }
                    .onChange(of: connections?.active?.id) { _, _ in model.forgetServerChats() }
                    // `.task(id:)` also runs on appear, so a request from before the shell existed isn't lost.
                    .task(id: model.chatSearchRequest) { presentChatSearchIfRequested() }
                    .task(id: model.pendingSessionReference) { await openPendingSession() }
                    // Leaving the foreground cancels every pending delete: nothing is deleted the user can't see undone.
                    .onChange(of: scenePhase) { _, phase in
                        if phase == .background { deletes.cancelAll() }
                    }
            }
        }

        /// Changes when the active server or the profile chosen on it changes. The chat list follows it (WP-40, WP-41).
        private var sessionScopeKey: String {
            "\(connections?.active?.id.uuidString ?? "")|\(profiles?.selection.chosen ?? "")"
        }

        /// Lists the active profile's chats in the shell (WP-40), again when the server or the profile changes.
        private func attachSessions() async {
            await model.loadLocalChats()
            guard let sessionsList else { return }
            sessionsList.observeItems { model.syncSessions($0) }
            await sessionsList.attach(profile: profiles?.selection.chosen)
        }

        /// Opens the chat an `@session:` link names, and shows a calm message when it cannot (WP-40).
        private func openPendingSession() async {
            guard let reference = model.pendingSessionReference else { return }
            defer { model.pendingSessionReference = nil }
            guard let sessionsList, let profiles else {
                model.sessionNotice = "Connect to a server first."
                return
            }
            if let notice = await sessionsList.open(reference, in: model, profiles: profiles) {
                model.sessionNotice = notice
            }
        }

        private func applyForcedPosture() {
            postureMonitor.override = forcedPosture == .flat ? nil : forcedPosture
        }

        private var shell: some View {
            GeometryReader { proxy in
                let layout =
                    model.layoutOverride
                    ?? DisplayLayout.resolve(
                        horizontalSizeClass: horizontalSizeClass,
                        size: proxy.size,
                        posture: posture
                    )
                content(for: layout)
                    .environment(\.hermesDisplayLayout, layout)
                    .sheet(isPresented: $model.isBugReportPresented, onDismiss: clearBugReportScreenshot) {
                        NavigationStack {
                            BugReportScreen(connections: connections, screenshot: model.bugReportScreenshot)
                                .toolbar {
                                    ToolbarItem(placement: .cancellationAction) {
                                        Button("Close") { model.isBugReportPresented = false }
                                    }
                                }
                        }
                        .environment(\.hermesDisplayLayout, layout)
                        .environment(\.hermesPosture, posture)
                    }
                    .overlay(alignment: .leading) {
                        if showsDebugLayoutMenu {
                            VStack(alignment: .leading, spacing: 4) {
                                debugLayoutMenu(current: layout)
                                debugScrollAnchor
                                debugPaletteProbe
                            }
                        }
                    }
                    .overlay(alignment: .top) {
                        // The tent posture already shows the approval on its glance screen.
                        if layout != .tent, let alert = model.approvalAlerts.first {
                            ApprovalAlertBanner(
                                alert: alert,
                                onApprove: { model.answer(alert, approved: true) },
                                onOpen: { model.open(alert.sessionID) }
                            )
                            .transition(reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity))
                        }
                    }
                    .animation(
                        HermesMotion.animation(HermesMotion.snappy, reduceMotion: reduceMotion),
                        value: model.approvalAlerts.first?.id
                    )
            }
            .background { KeyboardShortcuts(model: model) }
            .alert(
                "Chat not started",
                isPresented: Binding(
                    get: { model.newChatError != nil },
                    set: { if !$0 { model.newChatError = nil } })
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(model.newChatError ?? "")
            }
            .onDeviceShake { screenshot in
                guard !model.isBugReportPresented, !model.isPalettePresented else { return }
                model.bugReportScreenshot = screenshot
                model.isBugReportPresented = true
            }
            .sheet(isPresented: $model.isPalettePresented, onDismiss: openPendingBugReport) {
                CommandPalette(model: model)
            }
            .alert(
                "Chat not opened",
                isPresented: Binding(
                    get: { model.sessionNotice != nil },
                    set: { if !$0 { model.sessionNotice = nil } })
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(model.sessionNotice ?? "")
            }
        }

        private func clearBugReportScreenshot() {
            model.bugReportScreenshot = nil
        }

        private func openPendingBugReport() {
            guard model.opensBugReportAfterPalette else { return }
            model.opensBugReportAfterPalette = false
            model.isBugReportPresented = true
        }

        @ViewBuilder
        private func content(for layout: DisplayLayout) -> some View {
            switch layout {
            case .compact:
                compactTabs
            case .innerPortrait, .innerLandscape:
                splitView(showsRail: layout == .innerLandscape)
            case .halfFold:
                NavigationStack {
                    if let id = model.selectedSessionID {
                        chat(id, style: .halfFold)
                    } else {
                        NoChatSelected { model.newChat() }
                    }
                }
            case .tent:
                GlanceView(model: model)
            }
        }

        // MARK: Outer screen: chat-first tabs (plan Q4, Q6)

        private var compactTabs: some View {
            TabView(selection: $model.selectedSection) {
                Tab(AppSection.chats.title, systemImage: AppSection.chats.systemImage, value: AppSection.chats) {
                    NavigationStack {
                        chatList
                            .safeAreaInset(edge: .top, spacing: 0) { AppUpdateBanner() }
                            .safeAreaInset(edge: .bottom, spacing: 0) { ChatDeleteToast() }
                            .navigationTitle("Chats")
                            .toolbar {
                                serverSwitcher
                                profileSwitcher
                                newChatButton
                            }
                            .navigationDestination(item: $model.selectedSessionID) { id in
                                chat(id, style: .standard)
                            }
                    }
                }
                ForEach(AppSection.allCases.filter { $0 != .chats }) { section in
                    Tab(section.title, systemImage: section.systemImage, value: section) {
                        NavigationStack { sectionContent(section) }
                    }
                }
            }
        }

        /// The shell's chats without those inside their Undo window or being deleted.
        private var visibleSessions: [ChatSessionSummary] {
            let hidden = deletes.hiddenIDs
            return hidden.isEmpty ? model.sessions : model.sessions.filter { !hidden.contains($0.id) }
        }

        @ViewBuilder
        private var chatList: some View {
            if let sessionsList, connections?.active != nil {
                SessionsListView(model: sessionsList, needsApproval: model.needsApproval) { model.show($0) }
            } else {
                List(searchedSessions) { session in
                    Button {
                        model.open(session.id)
                    } label: {
                        SessionRow(
                            session: session,
                            serverName: model.serverName(of: session),
                            isStreaming: model.isStreaming(session.id),
                            needsApproval: model.needsApproval(session.id)
                        )
                    }
                    .tint(palette.primaryText)
                    .listRowBackground(palette.card)
                    .modifier(LocalChatDeleteActions(id: session.id, model: model))
                }
                .scrollContentBackground(.hidden)
                .background(palette.groupedBackground)
                .toolbarBackground(palette.groupedBackground, for: .navigationBar)
                .searchable(text: $localChatSearch, isPresented: $isLocalChatSearchPresented, prompt: "Search chats")
            }
        }

        // MARK: Inner screen: sidebar, chat and preview rail (plan Q3, Q6)

        private func splitView(showsRail: Bool) -> some View {
            NavigationSplitView(columnVisibility: $columnVisibility, preferredCompactColumn: .constant(.detail)) {
                List(selection: sidebarSelection) {
                    if let tip = [InlineTipKind.unfold, .shake].first { InlineTipStore.isPending($0) } {
                        Section { InlineTipCard(kind: tip) }
                    }
                    Section("Chats") {
                        ForEach(sessions(matching: sidebarChatSearch)) { session in
                            SessionRow(
                                session: session,
                                serverName: model.serverName(of: session),
                                isStreaming: model.isStreaming(session.id),
                                needsApproval: model.needsApproval(session.id)
                            )
                            .tag(SidebarItem.session(session.id))
                            .modifier(LocalChatDeleteActions(id: session.id, model: model))
                        }
                    }
                    Section {
                        ForEach(AppSection.allCases.filter { $0 != .chats }) { section in
                            Label(section.title, systemImage: section.systemImage)
                                .tag(SidebarItem.section(section))
                        }
                    }
                }
                .searchable(
                    text: $sidebarChatSearch, isPresented: $isSidebarSearchPresented, placement: .sidebar,
                    prompt: "Search chats"
                )
                .safeAreaInset(edge: .top, spacing: 0) { AppUpdateBanner() }
                .safeAreaInset(edge: .bottom, spacing: 0) { ChatDeleteToast() }
                .navigationTitle("simplyHermes")
                .toolbar {
                    serverSwitcher
                    profileSwitcher
                    newChatButton
                }
            } detail: {
                NavigationStack {
                    if model.selectedSection != .chats {
                        sectionContent(model.selectedSection)
                    } else if let id = model.selectedSessionID {
                        chat(id, style: .standard)
                            .safeAreaInset(edge: .top, spacing: 0) {
                                ChatTabStrip(model: model)
                            }
                            .inspector(isPresented: railBinding(showsRail: showsRail)) {
                                PreviewRail(model: model, sessionID: id)
                                    .inspectorColumnWidth(min: 260, ideal: 300, max: 360)
                            }
                    } else {
                        NoChatSelected { model.newChat() }
                    }
                }
            }
        }

        private enum SidebarItem: Hashable {
            case session(String)
            case section(AppSection)
        }

        private var sidebarSelection: Binding<SidebarItem?> {
            Binding(
                get: {
                    if model.selectedSection == .chats {
                        return model.selectedSessionID.map(SidebarItem.session)
                    }
                    return .section(model.selectedSection)
                },
                set: { item in
                    switch item {
                    case .session(let id): model.open(id)
                    case .section(let section): model.selectedSection = section
                    case nil: break
                    }
                }
            )
        }

        /// The rail shows only in inner landscape. In a compact width an inspector becomes a sheet, so it stays off.
        private func railBinding(showsRail: Bool) -> Binding<Bool> {
            Binding(
                get: { showsRail && horizontalSizeClass == .regular && model.showsPreviewRail },
                set: { model.showsPreviewRail = $0 }
            )
        }

        // MARK: Shared pieces

        private func chat(_ id: String, style: ChatScreen.Style) -> some View {
            ChatScreen(model: model, sessionID: id, style: style)
                .navigationTitle(model.session(id: id)?.title ?? "Chat")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    if model.botChatIDs.contains(id) {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button {
                                botSettingsEntryForChat = botEntry(for: id)
                            } label: {
                                Label("Bot Settings", systemImage: "slider.horizontal.3")
                            }
                            .accessibilityIdentifier("chat.botSettings")
                        }
                    }
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            model.isPalettePresented = true
                        } label: {
                            Label("Commands", systemImage: "command")
                        }
                    }
                }
                .sheet(item: $botSettingsEntryForChat) { entry in
                    if let connections {
                        BotSettingsScreen(entry: entry, connections: connections, rosterModel: bots)
                    }
                }
        }

        private func botEntry(for sessionID: String) -> BotRosterEntry? {
            if let entry = bots?.entries.first(where: { $0.canonicalSessionID == sessionID }) {
                return entry
            }
            let sessionTitle = model.session(id: sessionID)?.title
            if let sessionTitle, let entry = bots?.entries.first(where: { $0.title == sessionTitle }) {
                return entry
            }
            if let chosen = profiles?.selection.chosen {
                if let entry = bots?.entries.first(where: { $0.profile == chosen }) {
                    return entry
                }
            }
            guard let connection = connections?.active else { return nil }
            let profile = profiles?.selection.chosen ?? "default"
            let title = sessionTitle ?? ProfileSelection.title(of: profiles?.selection.current) ?? profile
            return BotRosterEntry(
                connectionID: connection.id,
                sourceLabel: connection.name,
                profile: profile,
                handle: profile,
                title: title,
                monogram: BotMonogram.text(for: title),
                tint: BotTint.name(for: profile),
                avatar: nil,
                status: .ready,
                isRetained: true,
                isPinned: false,
                isHidden: false,
                isDefault: profile == "default",
                role: nil,
                preview: nil,
                lastActive: nil,
                workerActiveAt: nil,
                canonicalSessionID: sessionID,
                activity: Date().timeIntervalSince1970 * 1000
            )
        }

        @ViewBuilder
        private func sectionContent(_ section: AppSection) -> some View {
            if section == .settings, let connections {
                SettingsHome(connections: connections)
            } else if section == .bots, let bots, let rooms {
                BotsHomeView(model: bots, rooms: rooms)
            } else if section == .automations, let connections {
                AutomationsScreen(connections: connections)
            } else if section == .tools {
                ToolsView(connections: connections, terminals: terminals, addToChat: addToChat)
            } else {
                SectionPlaceholder(section: section)
            }
        }

        /// Appends a block to the selected chat's draft, as the Tools tab's "Add to chat" does.
        private func addToChat(_ text: String) {
            guard let id = model.selectedSessionID else { return }
            let draft = model.drafts[id, default: ""]
            model.drafts[id] = draft.isEmpty ? text : draft + "\n" + text
        }

        @ToolbarContentBuilder
        private var serverSwitcher: some ToolbarContent {
            if let connections {
                ToolbarItem(placement: .topBarLeading) {
                    ServerSwitcher(connections: connections) { model.selectedSection = .settings }
                }
            }
        }

        @ToolbarContentBuilder
        private var profileSwitcher: some ToolbarContent {
            if let connections, let profiles {
                ToolbarItem(placement: .topBarLeading) {
                    ProfileSwitcher(profiles: profiles, connections: connections, bots: bots)
                }
            }
        }

        private var newChatButton: some ToolbarContent {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    model.newChat()
                } label: {
                    Label("New chat", systemImage: "square.and.pencil")
                }
                // A long press offers both kinds, so a Local chat is one press away while the server is down.
                .contextMenu {
                    ForEach(NewChatChoice.allCases, id: \.self) { choice in
                        Button {
                            model.newChat(mode: choice.mode)
                        } label: {
                            Label(choice.menuTitle(localModelName: model.localModelName), systemImage: choice.symbol)
                        }
                    }
                }
                .accessibilityIdentifier("shell.newChat")
            }
        }

        /// The selected chat's scroll anchor, so the fold UI test can check it survives a layout change.
        private var debugScrollAnchor: some View {
            Text(model.selectedSessionID.flatMap { model.scrollAnchors[$0] } ?? "none")
                .font(HermesFont.codeSmall)
                .padding(.leading, 8)
                .accessibilityIdentifier("debug.scrollAnchor")
        }

        /// The inherited environment palette preset, exposed only when debug UI tests are active.
        private var debugPaletteProbe: some View {
            Text(palette.preset.rawValue)
                .font(HermesFont.codeSmall)
                .padding(.leading, 8)
                .accessibilityIdentifier("debug.activePreset")
        }

        private func debugLayoutMenu(current: DisplayLayout) -> some View {
            Menu {
                Button("Automatic") { model.layoutOverride = nil }
                ForEach(DisplayLayout.allCases, id: \.self) { layout in
                    Button(layout.rawValue) { model.layoutOverride = layout }
                }
            } label: {
                Text(current.rawValue)
                    .font(HermesFont.codeSmall)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .glassEffect(.regular, in: Capsule())
            }
            .accessibilityIdentifier("debugLayoutMenu")
            .padding(.leading, 4)
        }
    }

    /// Hardware keyboard shortcuts. Invisible buttons, so they work in every layout.
    private struct KeyboardShortcuts: View {
        let model: ShellModel

        var body: some View {
            ZStack {
                Button("New chat") { model.newChat() }
                    .keyboardShortcut("n")
                Button("Command palette") { model.isPalettePresented.toggle() }
                    .keyboardShortcut("k")
                Button("Close chat") { model.closeSelected() }
                    .keyboardShortcut("w")
                Button("Reopen closed chat") { model.reopenLastClosed() }
                    .keyboardShortcut("t", modifiers: [.command, .shift])
                Button("Toggle preview rail") { model.showsPreviewRail.toggle() }
                    .keyboardShortcut("0", modifiers: [.command, .option])
                ForEach(Array(AppSection.allCases.enumerated()), id: \.element) { index, section in
                    Button(section.title) { model.selectedSection = section }
                        .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")))
                }
            }
            .opacity(0)
            .frame(width: 0, height: 0)
            .accessibilityHidden(true)
        }
    }

    /// A second window with one chat, opened from the command palette (Split View on the inner screen).
    public struct ChatWindow: View {
        @Bindable private var model: ShellModel
        private let sessionID: String?

        public init(model: ShellModel, sessionID: String?) {
            self.model = model
            self.sessionID = sessionID
        }

        public var body: some View {
            NavigationStack {
                if let sessionID, model.session(id: sessionID) != nil {
                    ChatScreen(model: model, sessionID: sessionID)
                        .navigationTitle(model.session(id: sessionID)?.title ?? "Chat")
                        .navigationBarTitleDisplayMode(.inline)
                } else {
                    ContentUnavailableView("Chat not found", systemImage: "bubble.left")
                }
            }
        }
    }

    /// Delete for a local chat row (feature C): swipe and the context menu, with Undo on the toast. Server chats are
    /// deleted from the server list, which has its own Delete.
    struct LocalChatDeleteActions: ViewModifier {
        let id: String
        let model: ShellModel

        func body(content: Content) -> some View {
            if id.hasPrefix("local-") {
                content
                    .swipeActions(edge: .trailing) {
                        Button("Delete", systemImage: "trash", role: .destructive) { model.deleteLocalChat(id) }
                            .accessibilityIdentifier("session.delete")
                    }
                    .contextMenu {
                        Button("Delete", systemImage: "trash", role: .destructive) { model.deleteLocalChat(id) }
                    }
            } else {
                content
            }
        }
    }

    // MARK: Chat search (#125, row 122)

    extension AdaptiveShell {

        /// Opens the search field of whichever chat list is showing: the server's, or the local one when no server is
        /// active. The request is consumed on the model (set back to 0), so it is answered once even when the app swaps
        /// this shell for the welcome screen and back: a new shell finds no request waiting. A request made before the
        /// shell appeared, as on a cold launch from the home-screen action, is still waiting and is answered on appear.
        private func presentChatSearchIfRequested() {
            guard model.chatSearchRequest > 0 else { return }
            model.chatSearchRequest = 0
            if let sessionsList, connections?.active != nil {
                sessionsList.isSearchPresented = true
            } else {
                isLocalChatSearchPresented = true
            }
            // Only one layout is on screen; the other's flag is harmless. The unfolded layout shows its sidebar first.
            columnVisibility = .all
            isSidebarSearchPresented = true
        }

        /// ``visibleSessions`` matching the local list's search, by title or subtitle.
        private var searchedSessions: [ChatSessionSummary] {
            sessions(matching: localChatSearch)
        }

        /// ``visibleSessions`` whose row matches `query` (``ChatSearchFilter``: every word, any order, any case).
        private func sessions(matching query: String) -> [ChatSessionSummary] {
            visibleSessions.filter { ChatSearchFilter.matches(query, in: [$0.title, $0.subtitle, $0.serverName]) }
        }
    }
#endif
