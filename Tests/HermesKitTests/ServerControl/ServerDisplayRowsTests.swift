import Foundation
import HermesKit
import Testing

/// Rows for the answers the OpenAPI leaves untyped.
@Suite struct ServerDisplayRowsTests {
    @Test func statsFlattenNestedObjectsSortedByKey() {
        let json: JSONValue = .object([
            "cpu_percent": .double(12.5),
            "memory": .object(["total_mb": .int(4096), "pressure": .string("ok")]),
            "disks": .array([.object([:]), .object([:])]),
            "psutil": .null,
            "uptime_s": .int(3600),
        ])
        let rows = ServerStatsRows.rows(from: json)
        #expect(
            rows.map(\.label) == ["Cpu percent", "Disks", "Memory pressure", "Memory total mb", "Psutil", "Uptime s"])
        #expect(rows.map(\.value) == ["12.50", "2 items", "ok", "4096", "—", "3600"])
    }

    @Test func aStatsAnswerThatIsNotAnObjectIsOneRow() {
        #expect(ServerStatsRows.rows(from: .int(3)) == [ServerStatsRow(label: "Value", value: "3")])
    }

    @Test func logLinesFromTheCommonShapes() {
        #expect(ServerLogsRows.lines(from: .array([.string("a"), .string("b")])) == ["a", "b"])
        let withLines: JSONValue = .object([
            "file": .string("agent"), "lines": .array([.string("x 1"), .string("x 2")]),
        ])
        #expect(ServerLogsRows.lines(from: withLines) == ["x 1", "x 2"])
        let entries: JSONValue = .object(["entries": .array([.object(["level": .string("INFO")])])])
        #expect(ServerLogsRows.lines(from: entries) == [#"{"level":"INFO"}"#])
        #expect(ServerLogsRows.lines(from: .string("one\ntwo\n")) == ["one", "two"])
    }

    @Test func logAnswerWithoutLinesShowsItsJSON() {
        let lines = ServerLogsRows.lines(from: .object(["total": .int(3)]))
        #expect(lines.first == "{" && lines.last == "}" && lines.count == 3)
    }

    @Test func analyticsSplitTotalsFromPerModelGroups() {
        let json: JSONValue = .object([
            "days": .int(7),
            "totals": .object(["sessions": .int(12), "tokens": .int(9000)]),
            "models": .array([
                .object(["model": .string("a"), "calls": .int(3)]),
                .object(["model": .string("b"), "calls": .int(1)]),
            ]),
        ])
        #expect(ServerAnalyticsRows.totals(from: json).map(\.label) == ["Days", "Totals sessions", "Totals tokens"])
        let groups = ServerAnalyticsRows.groups(from: json)
        #expect(groups.count == 2)
        #expect(groups.first?.map(\.value) == ["3", "a"])
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

    @Test func rowsAreNamedOnlyFromTheServersKeys() {
        #expect(ServerStatsRows.humanize("disk_free_mb") == "Disk free mb")
        #expect(ServerStatsRows.humanize("") == "")
    }
}
