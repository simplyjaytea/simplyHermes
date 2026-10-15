import Foundation
import Testing

@testable import HermesKit

@Suite struct SubagentPanelTests {
    private let now = Date(timeIntervalSince1970: 1_000_000)

    private func state(
        _ id: String, status: SubagentStatus?, tool: String? = nil, thinking: String? = nil, duration: Double? = nil,
        depth: Int? = nil
    ) throws -> SubagentState {
        var json = #"{"goal":"goal \#(id)","task_count":1,"task_index":0"#
        if let duration { json += #","duration_seconds":\#(duration)"# }
        if let depth { json += #","depth":\#(depth)"# }
        let event = try JSONDecoder().decode(SubagentEvent.self, from: Data((json + "}").utf8))
        return SubagentState(
            id: id, goal: event.goal, status: status, thinking: thinking, currentTool: tool, summary: nil,
            latest: event)
    }

    private func snapshot(_ id: String, started: Double? = nil, steer: Bool? = nil) throws -> SubagentSnapshot {
        var json = #"{"subagent_id":"\#(id)""#
        if let started { json += #","started_at":\#(started)"# }
        if let steer { json += #","accepting_steer":\#(steer)"# }
        return try JSONDecoder().decode(SubagentSnapshot.self, from: Data((json + "}").utf8))
    }

    @Test func runningChildrenComeFirstInTheirOriginalOrder() throws {
        let states = [
            try state("a", status: .completed, duration: 5), try state("b", status: .running),
            try state("c", status: .failed), try state("d", status: .queued),
        ]
        #expect(SubagentPanel.rows(states, now: now).map(\.id) == ["b", "d", "a", "c"])
        #expect(SubagentPanel.activeCount(states) == 2)
    }

    @Test func elapsedUsesTheSnapshotStartThenFirstSeen() throws {
        let states = [try state("a", status: .running), try state("b", status: .running)]
        let rows = SubagentPanel.rows(
            states, snapshots: [try snapshot("a", started: 999_940)],
            firstSeen: ["a": now.addingTimeInterval(-10), "b": now.addingTimeInterval(-30)], now: now)
        #expect(rows.first { $0.id == "a" }?.elapsed == 60)
        #expect(rows.first { $0.id == "b" }?.elapsed == 30)
    }

    @Test func finishedChildrenShowTheirFinalDuration() throws {
        let rows = SubagentPanel.rows([try state("a", status: .completed, duration: 12.5)], now: now)
        #expect(rows.first?.elapsed == 12.5 && rows.first?.isActive == false)
    }

    @Test func unknownElapsedStaysNil() throws {
        let rows = SubagentPanel.rows([try state("a", status: .running)], now: now)
        #expect(rows.first?.elapsed == nil)
    }

    @Test func steerAndStopOnlyForActiveChildren() throws {
        let states = [
            try state("a", status: .running), try state("b", status: .completed), try state("c", status: nil),
        ]
        let rows = SubagentPanel.rows(states, snapshots: [try snapshot("c", steer: false)], now: now)
        let byID = Dictionary(uniqueKeysWithValues: rows.map { ($0.id, $0) })
        #expect(byID["a"]?.canSteer == true && byID["a"]?.canStop == true)
        #expect(byID["b"]?.canSteer == false && byID["b"]?.canStop == false)
        #expect(byID["c"]?.canSteer == false && byID["c"]?.canStop == true)
    }

    @Test func activityPrefersTheToolInUse() throws {
        let rows = SubagentPanel.rows(
            [
                try state("a", status: .running, tool: "read_file", thinking: "planning"),
                try state("b", status: .running, thinking: "planning"),
            ], now: now)
        #expect(rows.map(\.activity) == ["read_file", "planning"])
    }

    @Test func depthDefaultsToZero() throws {
        let rows = SubagentPanel.rows(
            [try state("a", status: .running, depth: 2), try state("b", status: .running)], now: now)
        #expect(rows.map(\.depth) == [2, 0])
    }

    @Test func clockFormats() {
        #expect(SubagentPanel.clock(5) == "0:05")
        #expect(SubagentPanel.clock(65.9) == "1:05")
        #expect(SubagentPanel.clock(3723) == "1:02:03")
        #expect(SubagentPanel.clock(-4) == "0:00")
    }

    @Test func steerAndInterruptParamsUseTheWireKeys() throws {
        let steer = try JSONValue(encoding: SubagentSteerParams(sessionID: "s", subagentID: "c", text: "hi"))
        #expect(steer == .object(["session_id": "s", "subagent_id": "c", "text": "hi"]))
        let stop = try JSONValue(encoding: SubagentInterruptParams(sessionID: "s", subagentID: "c", profile: "ops"))
        #expect(stop == .object(["session_id": "s", "subagent_id": "c", "profile": "ops"]))
    }

    @Test func steerResultReportsWhetherItWasQueued() throws {
        let queued = try JSONDecoder().decode(
            SubagentSteerResult.self, from: Data(#"{"status":"queued","subagent_id":"c","text":"hi"}"#.utf8))
        let rejected = try JSONDecoder().decode(
            SubagentSteerResult.self, from: Data(#"{"status":"rejected","subagent_id":"c","text":"hi"}"#.utf8))
        #expect(queued.isQueued && !rejected.isQueued)
    }
}
