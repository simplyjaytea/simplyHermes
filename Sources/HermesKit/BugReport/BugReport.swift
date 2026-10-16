import Foundation

/// What the user writes in the Report a bug form.
public struct BugReportDraft: Sendable, Equatable {
    /// One line: the issue title.
    public var title: String
    /// What went wrong.
    public var whatHappened: String
    /// How to make it happen again. Optional.
    public var steps: String
    /// What the user expected instead. Optional.
    public var expected: String
    /// Attach the diagnostics block.
    public var includesDiagnostics: Bool

    /// Creates a draft.
    public init(
        title: String = "", whatHappened: String = "", steps: String = "", expected: String = "",
        includesDiagnostics: Bool = true
    ) {
        self.title = title
        self.whatHappened = whatHappened
        self.steps = steps
        self.expected = expected
        self.includesDiagnostics = includesDiagnostics
    }

    /// A report needs a title and a description.
    public var isComplete: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !whatHappened.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

/// Facts about the app and phone attached to a report. The app fills it; ``BugReportComposer`` redacts it.
public struct BugReportDiagnostics: Sendable, Equatable {
    /// `CFBundleShortVersionString`, such as `0.1.0`.
    public var appVersion: String
    /// `CFBundleVersion`.
    public var build: String
    /// Such as `iOS 27.1`.
    public var system: String
    /// Hardware model identifier, such as `iPhone19,1`.
    public var device: String
    /// The shell layout, such as `innerLandscape`.
    public var layout: String?
    /// The fold posture, such as `halfFolded`.
    public var posture: String?
    /// `gateway` or `ssh`, for the active server.
    public var connectionKind: String?
    /// The connection phase, such as `connected` or `reconnecting (attempt 2)`.
    public var connectionState: String?
    /// The Hermes server version, when connected.
    public var serverVersion: String?
    /// Recent app log lines, oldest first.
    public var logLines: [String]

    /// Creates diagnostics.
    public init(
        appVersion: String, build: String, system: String, device: String, layout: String? = nil,
        posture: String? = nil, connectionKind: String? = nil, connectionState: String? = nil,
        serverVersion: String? = nil, logLines: [String] = []
    ) {
        self.appVersion = appVersion
        self.build = build
        self.system = system
        self.device = device
        self.layout = layout
        self.posture = posture
        self.connectionKind = connectionKind
        self.connectionState = connectionState
        self.serverVersion = serverVersion
        self.logLines = logLines
    }

    /// The table rows, in order. Missing values are left out.
    public var rows: [(label: String, value: String)] {
        let all: [(String, String?)] = [
            ("App", "\(appVersion) (\(build))"),
            ("System", system),
            ("Device", device),
            ("Layout", layout),
            ("Posture", posture),
            ("Connection", connectionKind),
            ("State", connectionState),
            ("Server", serverVersion),
        ]
        return all.compactMap { label, value in value.map { (label, $0) } }
    }
}

/// A GitHub issue ready to send.
public struct GitHubIssueDraft: Sendable, Equatable, Codable {
    /// The issue title.
    public var title: String
    /// Markdown body.
    public var body: String
    /// Labels to apply.
    public var labels: [String]

    /// Creates an issue draft.
    public init(title: String, body: String, labels: [String]) {
        self.title = title
        self.body = body
        self.labels = labels
    }
}

/// Turns a draft and diagnostics into an issue. Diagnostics are always redacted; the user's own text is not, because
/// the form shows them exactly what will be posted.
public enum BugReportComposer {
    /// Labels every in-app report gets.
    public static let labels = ["bug", "in-app report"]
    /// GitHub refuses bodies over 65,536 characters; this leaves room for the rest of the issue.
    public static let apiLogBudget = 40_000
    /// A prefilled new-issue URL must stay short enough for GitHub and Safari, so logs shrink a lot.
    public static let webLogBudget = 2_500

    /// Builds the issue. `logBudget` caps the log block in characters, keeping the newest lines.
    public static func issue(
        draft: BugReportDraft, diagnostics: BugReportDiagnostics?, redactor: DiagnosticsRedactor,
        logBudget: Int = apiLogBudget
    ) -> GitHubIssueDraft {
        var sections: [String] = []
        sections.append("### What happened\n\n" + draft.whatHappened.trimmingCharacters(in: .whitespacesAndNewlines))
        let steps = draft.steps.trimmingCharacters(in: .whitespacesAndNewlines)
        if !steps.isEmpty { sections.append("### Steps to reproduce\n\n" + steps) }
        let expected = draft.expected.trimmingCharacters(in: .whitespacesAndNewlines)
        if !expected.isEmpty { sections.append("### Expected\n\n" + expected) }
        if draft.includesDiagnostics, let diagnostics {
            sections.append(diagnosticsSection(diagnostics, redactor: redactor, logBudget: logBudget))
        }
        sections.append("<sub>Sent from simplyHermes</sub>")
        return GitHubIssueDraft(
            title: draft.title.trimmingCharacters(in: .whitespacesAndNewlines),
            body: sections.joined(separator: "\n\n"),
            labels: labels)
    }

    /// The diagnostics block alone, as shown in the form's preview.
    public static func diagnosticsSection(
        _ diagnostics: BugReportDiagnostics, redactor: DiagnosticsRedactor, logBudget: Int = apiLogBudget
    ) -> String {
        var lines = ["### Diagnostics", "", "| | |", "| --- | --- |"]
        for row in diagnostics.rows {
            lines.append("| \(row.label) | \(tableCell(redactor.redact(row.value))) |")
        }
        let log = recentLog(diagnostics.logLines.map(redactor.redact), budget: logBudget)
        if !log.isEmpty {
            lines += [
                "", "<details><summary>Recent log (\(log.count) lines)</summary>", "", "```text",
            ]
            lines += log.map { $0.replacingOccurrences(of: "```", with: "'''") }
            lines += ["```", "", "</details>"]
        }
        return lines.joined(separator: "\n")
    }

    /// The newest lines that fit in `budget` characters, oldest first.
    static func recentLog(_ lines: [String], budget: Int) -> [String] {
        var kept: [String] = []
        var used = 0
        for line in lines.reversed() {
            let clipped = line.count > 500 ? String(line.prefix(500)) + "…" : line
            used += clipped.count + 1
            if used > budget { break }
            kept.append(clipped)
        }
        return kept.reversed()
    }

    private static func tableCell(_ value: String) -> String {
        value.replacingOccurrences(of: "|", with: "\\|").replacingOccurrences(of: "\n", with: " ")
    }
}
