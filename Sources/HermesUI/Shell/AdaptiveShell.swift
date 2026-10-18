#if canImport(UIKit)
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
        @State private var postureMonitor = DevicePostureMonitor()
        @State private var profiles: ProfilesModel?
        @State private var columnVisibility: NavigationSplitViewVisibility = .all

        /// `connections` fills Settings > Servers and the server switcher (WP-22). Nil shows placeholders.
        /// `sessionsList` lists the active server's chats (WP-40). Nil keeps the sample chats.
        public init(
            model: ShellModel, connections: ConnectionsModel? = nil, sessionsList: SessionsListModel? = nil,
            showsDebugLayoutMenu: Bool = false
        ) {
            self.model = model
            self.connections = connections
            self.sessionsList = sessionsList
            model.liveChats = connections.map(LiveChatStore.init)
            _profiles = State(initialValue: connections.map { ProfilesModel(connections: $0) })
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
            } else {
                shell
                    .hermesPostureSource(postureMonitor)
                    .environment(\.hermesPosture, posture)
                    .task(id: forcedPosture) { applyForcedPosture() }
                    .task(id: connections?.active?.id) { await attachSessions() }
            }
        }

        /// Lists the active server's chats in the shell (WP-40), again when the active server changes.
        private func attachSessions() async {
            guard let sessionsList else { return }
            sessionsList.observeItems { model.syncSessions($0) }
            await sessionsList.attach()
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
            .onDeviceShake { screenshot in
                guard !model.isBugReportPresented, !model.isPalettePresented else { return }
                model.bugReportScreenshot = screenshot
                model.isBugReportPresented = true
            }
            .sheet(isPresented: $model.isPalettePresented, onDismiss: openPendingBugReport) {
                CommandPalette(model: model)
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

        @ViewBuilder
        private var chatList: some View {
            if let sessionsList, connections?.active != nil {
                SessionsListView(model: sessionsList, needsApproval: model.needsApproval) { model.show($0) }
            } else {
                List(model.sessions) { session in
                    Button {
                        model.open(session.id)
                    } label: {
                        SessionRow(
                            session: session,
                            isStreaming: model.isStreaming(session.id),
                            needsApproval: model.needsApproval(session.id)
                        )
                    }
                    .tint(HermesColor.primaryText)
                }
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
                        ForEach(model.sessions) { session in
                            SessionRow(
                                session: session,
                                isStreaming: model.isStreaming(session.id),
                                needsApproval: model.needsApproval(session.id)
                            )
                            .tag(SidebarItem.session(session.id))
                        }
                    }
                    Section {
                        ForEach(AppSection.allCases.filter { $0 != .chats }) { section in
                            Label(section.title, systemImage: section.systemImage)
                                .tag(SidebarItem.section(section))
                        }
                    }
                }
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
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            model.isPalettePresented = true
                        } label: {
                            Label("Commands", systemImage: "command")
                        }
                    }
                }
        }

        @ViewBuilder
        private func sectionContent(_ section: AppSection) -> some View {
            if section == .settings, let connections {
                SettingsHome(connections: connections)
            } else if section == .tools, let connections {
                ToolsHome(connections: connections)
            } else {
                SectionPlaceholder(section: section)
            }
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
                    ProfileSwitcher(profiles: profiles, connections: connections)
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
            }
        }

        /// The selected chat's scroll anchor, so the fold UI test can check it survives a layout change.
        private var debugScrollAnchor: some View {
            Text(model.selectedSessionID.flatMap { model.scrollAnchors[$0] } ?? "none")
                .font(HermesFont.codeSmall)
                .padding(.leading, 8)
                .accessibilityIdentifier("debug.scrollAnchor")
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
#endif
