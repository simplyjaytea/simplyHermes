import Foundation
import HermesKit
import Testing

/// Rows for the answers the OpenAPI leaves untyped. The inputs use keys the recorder wrote (Fixtures/rest at e3dc403).
@Suite struct ServerDisplayRowsTests {
    @Test func statsFlattenNestedObjectsSortedByKey() {
        // GET_api_system_stats.json, trimmed.
        let json: JSONValue = .object([
            "cpu_percent": .double(12.5),
            "disk": .object(["free": .int(89_523_499_008), "percent": .double(42.2)]),
            "load_avg": .array([.double(1.5), .double(0.5), .double(0.2)]),
            "memory": .object(["percent": .double(12.4), "total": .int(16_766_410_752)]),
            "psutil": .bool(true),
            "uptime_seconds": .int(135),
        ])
        let rows = ServerStatsRows.rows(from: json)
        #expect(
            rows.map(\.label) == [
                "Cpu percent", "Disk free", "Disk percent", "Load avg", "Memory percent", "Memory total", "Psutil",
                "Uptime seconds",
            ])
        #expect(
            rows.map(\.value) == ["12.50", "89523499008", "42.20", "3 items", "12.40", "16766410752", "Yes", "135"])
    }

    @Test func aStatsAnswerThatIsNotAnObjectIsOneRow() {
        #expect(ServerStatsRows.rows(from: .int(3)) == [ServerStatsRow(label: "Value", value: "3")])
    }

    @Test func logLinesComeFromTheRecordedLinesList() {
        // GET_api_logs.json: {file, lines}, with lines a list of strings.
        let answer: JSONValue = .object([
            "file": .string("agent"), "lines": .array([.string("x 1"), .string("x 2")]),
        ])
        #expect(ServerLogsRows.lines(from: answer) == ["x 1", "x 2"])
    }

    @Test func logLinesDropTheNewlineAndKeepTheServersOrder() {
        // A recorded line ends in a newline. The lines keep the order the server sent, whatever it is.
        let answer: JSONValue = .object([
            "file": .string("agent"), "lines": .array([.string("z 9\n"), .string("a 1\n")]),
        ])
        #expect(ServerLogsRows.lines(from: answer) == ["z 9", "a 1"])
    }

    @Test func logAnswerWithoutLinesShowsItsJSON() {
        let lines = ServerLogsRows.lines(from: .object(["total": .int(3)]))
        #expect(lines.first == "{" && lines.last == "}" && lines.count == 3)
    }

    @Test func logLinesLoseTheirSecretsButKeepHostsAndAddresses() {
        // Tokens, keys and bearer values go before the screen shows a line. The host and the addresses stay.
        let answer: JSONValue = .object([
            "file": .string("agent"),
            "lines": .array([
                .string("GET /api/ws?token=abc123def456&ticket=zz9988 200"),
                .string("Request sent with Bearer abcdef1234567890"),
                .string("push with ghp_abcdefghijklmnop1234 done"),
                .string("gateway at home.example.ts.net 192.168.1.20 up"),
            ]),
        ])
        #expect(
            ServerLogsRows.lines(from: answer) == [
                "GET /api/ws?token=[redacted]&ticket=[redacted] 200",
                "Request sent with Bearer [redacted]",
                "push with [redacted token] done",
                "gateway at home.example.ts.net 192.168.1.20 up",
            ])
    }

    @Test func logURLsRemoveCredentials() {
        let answer: JSONValue = .object([
            "lines": .array([.string("before https://user:secret@host/path after")])
        ])
        #expect(ServerLogsRows.lines(from: answer) == ["before https://host/path after"])
    }

    @Test func analyticsSplitTotalsFromPerModelGroups() {
        // GET_api_analytics_models.json and GET_api_analytics_usage.json, trimmed: a scalar, totals, a list of objects.
        let json: JSONValue = .object([
            "period_days": .int(30),
            "totals": .object(["total_input": .int(100), "total_sessions": .int(1)]),
            "models": .array([
                .object(["model": .string("fake-model"), "api_calls": .int(2)]),
                .object(["model": .string("other-model"), "api_calls": .int(1)]),
            ]),
        ])
        #expect(
            ServerAnalyticsRows.totals(from: json).map(\.label) == [
                "Period days", "Totals total input", "Totals total sessions",
            ])
        let groups = ServerAnalyticsRows.groups(from: json)
        #expect(groups.count == 2)
        #expect(groups.first?.map(\.value) == ["2", "fake-model"])
    }

    @Test func logsQueryKeepsOnlyTheFilledFields() {
        let filter = ServerLogsFilter(file: "errors", level: .error, search: " timeout ", lines: 50)
        let pairs = filter.queryItems.map { "\($0.name)=\($0.value ?? "")" }
        #expect(pairs == ["file=errors", "lines=50", "level=ERROR", "search=timeout"])
        #expect(ServerLogsFilter(file: " ").queryItems.map(\.name) == ["lines"])
        #expect(ServerLogsFilter().queryItems.map(\.value) == ["agent", "200"])
    }

    @Test func analyticsWindowsAreTheThreePresets() {
        #expect(ServerAnalyticsWindow.allCases.map(\.rawValue) == [7, 30, 90])
    }

    @Test func logsHeaderShowsOnlyTheFiguresTheAnswerHas() {
        // GET_api_system_stats.json, trimmed. The values change between runs; the labels are what the header reads.
        let json: JSONValue = .object([
            "cpu_percent": .double(3.5), "disk": .object(["free": .int(1), "percent": .double(42.2)]),
            "hostname": .string("host"), "memory": .object(["percent": .double(12.4)]), "uptime_seconds": .int(135),
        ])
        let header = ServerStatsRows.logsHeader(from: json)
        #expect(header.map(\.label) == ["Cpu percent", "Memory percent", "Disk percent", "Uptime seconds"])
        #expect(header.map(\.value) == ["3.50", "12.40", "42.20", "135"])
        #expect(ServerStatsRows.logsHeader(from: .object(["cpu_percent": .double(1)])).map(\.label) == ["Cpu percent"])
    }

    @Test func usageGroupsAreTheByModelRowsOnly() {
        // GET_api_analytics_usage.json lists `by_model` and `daily`. Only the per-model list is grouped.
        let json: JSONValue = .object([
            "by_model": .array([.object(["model": .string("fake-model"), "api_calls": .int(2)])]),
            "daily": .array([.object(["day": .string("2026-10-18"), "api_calls": .int(1)])]),
        ])
        let groups = ServerAnalyticsRows.groups(from: json)
        #expect(groups.count == 1 && groups.first?.map(\.value) == ["2", "fake-model"])
    }

    @Test func rowsAreNamedOnlyFromTheServersKeys() {
        #expect(ServerStatsRows.humanize("disk_free_mb") == "Disk free mb")
        #expect(ServerStatsRows.humanize("") == "")
    }
}
