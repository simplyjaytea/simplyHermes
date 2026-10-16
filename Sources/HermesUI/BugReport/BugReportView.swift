#if canImport(UIKit)
    import HermesKit
    import SwiftUI

    /// Settings > Report a bug, also opened from the command palette.
    public struct BugReportView: View {
        @Bindable private var model: BugReportModel
        @Environment(\.openURL) private var openURL
        @FocusState private var focused: Field?

        private enum Field {
            case title, whatHappened, steps, expected
        }

        public init(model: BugReportModel) {
            self.model = model
        }

        public var body: some View {
            Group {
                switch model.phase {
                case .sent(let issue):
                    done(
                        title: "Report #\(issue.number) filed",
                        systemImage: "checkmark.circle.fill",
                        message: "Thanks. It's on GitHub now.",
                        link: issue.url)
                case .openedInBrowser:
                    done(
                        title: "Finish on GitHub",
                        systemImage: "safari",
                        message: "The report is filled in on github.com. Tap Submit new issue there to file it.",
                        link: nil)
                default:
                    form
                }
            }
            .navigationTitle("Report a bug")
            .navigationBarTitleDisplayMode(.inline)
            .sensoryFeedback(trigger: model.phase) { _, phase in
                switch phase {
                case .sent: HermesFeedback.approved.sensoryFeedback
                case .failed: HermesFeedback.error.sensoryFeedback
                default: nil
                }
            }
        }

        private var form: some View {
            Form {
                Section {
                    TextField("Title", text: $model.draft.title)
                        .focused($focused, equals: .title)
                        .submitLabel(.next)
                        .onSubmit { focused = .whatHappened }
                        .accessibilityIdentifier("bugReport.title")
                    TextField("What happened?", text: $model.draft.whatHappened, axis: .vertical)
                        .lineLimit(3...8)
                        .focused($focused, equals: .whatHappened)
                        .accessibilityIdentifier("bugReport.whatHappened")
                } footer: {
                    Text("Reports are public on GitHub.")
                }
                Section("Optional") {
                    TextField("Steps to make it happen again", text: $model.draft.steps, axis: .vertical)
                        .lineLimit(2...6)
                        .focused($focused, equals: .steps)
                    TextField("What you expected", text: $model.draft.expected, axis: .vertical)
                        .lineLimit(1...4)
                        .focused($focused, equals: .expected)
                }
                Section {
                    Toggle("Attach diagnostics", isOn: $model.draft.includesDiagnostics)
                        .accessibilityIdentifier("bugReport.diagnostics")
                    DisclosureGroup("Preview the report") {
                        Text(model.preview.body)
                            .font(HermesFont.codeSmall)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .accessibilityIdentifier("bugReport.preview")
                } footer: {
                    Text(
                        """
                        Diagnostics are the app version, iOS version, device, fold layout, connection state and the \
                        last 30 minutes of app log. Tokens, passwords, keys, server addresses and emails are removed.
                        """
                    )
                }
                if case .failed(let message) = model.phase {
                    Section {
                        Label(message, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(HermesColor.destructive)
                    }
                }
            }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    if model.phase == .sending {
                        ProgressView()
                    } else {
                        Button(model.sendsInApp ? "Send" : "Open in GitHub") {
                            focused = nil
                            Task { await model.send { openURL($0) } }
                        }
                        .disabled(!model.canSend)
                        .accessibilityIdentifier("bugReport.send")
                    }
                }
            }
        }

        private func done(title: String, systemImage: String, message: String, link: URL?) -> some View {
            ContentUnavailableView {
                Label(title, systemImage: systemImage)
            } description: {
                Text(message)
            } actions: {
                if let link {
                    Link("Open on GitHub", destination: link)
                        .buttonStyle(HermesButtonStyle(.primary))
                }
                Button("Report another") { model.reset() }
                    .buttonStyle(HermesButtonStyle(.secondary))
            }
            .accessibilityIdentifier("bugReport.done")
        }
    }

    /// Builds a ``BugReportModel`` for the current screen and loads the recent log in the background.
    public struct BugReportScreen: View {
        private let connections: ConnectionsModel?
        @Environment(\.hermesDisplayLayout) private var layout
        @Environment(\.hermesPosture) private var posture
        @State private var model: BugReportModel?

        public init(connections: ConnectionsModel?) {
            self.connections = connections
        }

        public var body: some View {
            Group {
                if let model {
                    BugReportView(model: model)
                        .task { model.attachLog(await DiagnosticsCollector.recentLogLines()) }
                } else {
                    ProgressView()
                }
            }
            .onAppear {
                if model == nil { model = makeModel() }
            }
        }

        private func makeModel() -> BugReportModel {
            let diagnostics = DiagnosticsCollector.collect(layout: layout, posture: posture, connections: connections)
            return BugReportModel(
                diagnostics: diagnostics,
                redactor: DiagnosticsRedactor(knownValues: DiagnosticsCollector.privateValues(connections)),
                client: GitHubIssueClient(
                    transport: URLSessionHTTPTransport(), userAgent: "simplyHermes/\(diagnostics.appVersion)"))
        }
    }

    #Preview("Report a bug, outer", traits: .fixedLayout(width: 466, height: 678)) {
        NavigationStack { BugReportView(model: .preview) }
    }

    #Preview("Report a bug, inner portrait", traits: .fixedLayout(width: 626, height: 890)) {
        NavigationStack { BugReportView(model: .preview) }
    }

    #Preview("Report a bug, inner landscape", traits: .fixedLayout(width: 890, height: 626)) {
        NavigationStack { BugReportView(model: .preview) }
    }

    #Preview("Report a bug, half-fold", traits: .fixedLayout(width: 890, height: 313)) {
        NavigationStack { BugReportView(model: .preview) }
    }

    extension BugReportModel {
        /// A filled-in form with sample diagnostics, for previews and snapshots.
        public static var preview: BugReportModel {
            let model = BugReportModel(
                diagnostics: BugReportDiagnostics(
                    appVersion: "0.1.0", build: "1", system: "iOS 27.1", device: "iPhone19,1",
                    layout: "innerPortrait", posture: "flat", connectionKind: "gateway", connectionState: "connected",
                    serverVersion: "git.d97007c, 2026.9.24",
                    logLines: ["00:01:02.345 [Gateway] info connected", "00:01:09.010 [LiveActivity] notice started"]),
                redactor: DiagnosticsRedactor(),
                client: GitHubIssueClient(transport: URLSessionHTTPTransport(), userAgent: "simplyHermes/preview"))
            model.draft = BugReportDraft(
                title: "Transcript jumps after unfolding",
                whatHappened: "After unfolding mid-reply, the chat scrolls back to the top.",
                steps: "1. Start a long reply on the outer screen\n2. Unfold")
            return model
        }
    }
#endif
