#if canImport(UIKit)
    import Foundation
    import HermesKit
    import Observation

    /// The Report a bug form: the draft, the diagnostics, and sending it to GitHub.
    ///
    /// With a GitHub token the report is filed straight away through the API. Without one the model hands back a
    /// prefilled new-issue page for Safari, so reporting always works.
    @MainActor
    @Observable
    public final class BugReportModel {
        /// Where the form is.
        public enum Phase: Equatable {
            case editing
            case sending
            /// Filed through the API.
            case sent(CreatedGitHubIssue)
            /// Opened as a prefilled page in the browser; the user submits it there.
            case openedInBrowser
            /// The last send failed; the form stays filled in.
            case failed(String)
        }

        public var draft = BugReportDraft()
        public private(set) var diagnostics: BugReportDiagnostics?
        public private(set) var phase: Phase = .editing

        @ObservationIgnored private let redactor: DiagnosticsRedactor
        @ObservationIgnored private let client: GitHubIssueClient
        @ObservationIgnored private let repository: GitHubRepository
        @ObservationIgnored private let token: @MainActor () -> String?

        /// Creates the model. `token` returns the saved GitHub token, or nil to send through the browser.
        public init(
            diagnostics: BugReportDiagnostics?,
            redactor: DiagnosticsRedactor,
            client: GitHubIssueClient,
            repository: GitHubRepository = .simplyHermes,
            token: @escaping @MainActor () -> String? = { nil }
        ) {
            self.diagnostics = diagnostics
            self.redactor = redactor
            self.client = client
            self.repository = repository
            self.token = token
            sendsInApp = !(token() ?? "").isEmpty
        }

        /// True when sending files the issue in the app rather than opening the browser. Read once, when the form opens.
        public let sendsInApp: Bool

        /// Adds log lines read after the form opened.
        public func attachLog(_ lines: [String]) {
            diagnostics?.logLines = lines
        }

        /// The issue exactly as it will be posted.
        public var preview: GitHubIssueDraft {
            issue(logBudget: sendsInApp ? BugReportComposer.apiLogBudget : BugReportComposer.webLogBudget)
        }

        public var canSend: Bool { draft.isComplete && phase != .sending }

        /// Files the report. `openURL` opens the prefilled page when there is no token.
        public func send(openURL: (URL) -> Void) async {
            guard canSend else { return }
            guard let token = token(), !token.isEmpty else {
                openURL(repository.newIssueURL(for: issue(logBudget: BugReportComposer.webLogBudget)))
                phase = .openedInBrowser
                return
            }
            phase = .sending
            do {
                let created = try await client.create(issue(logBudget: BugReportComposer.apiLogBudget), token: token)
                phase = .sent(created)
            } catch let error as GitHubIssueError {
                phase = .failed(error.message)
            } catch {
                phase = .failed("Couldn't reach GitHub. Check your connection and try again.")
            }
        }

        /// Clears the form for another report.
        public func reset() {
            draft = BugReportDraft()
            phase = .editing
        }

        private func issue(logBudget: Int) -> GitHubIssueDraft {
            BugReportComposer.issue(draft: draft, diagnostics: diagnostics, redactor: redactor, logBudget: logBudget)
        }
    }
#endif
