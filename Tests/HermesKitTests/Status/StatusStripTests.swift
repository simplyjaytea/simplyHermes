import Foundation
import Testing

@testable import HermesKit

@Suite struct StatusStripTests {
    private func usage(_ extra: String = "") throws -> Usage {
        let json = """
            {"model":"m","input":200,"output":12,"reasoning":0,"prompt":200,"completion":12,"total":212,"calls":2\(extra)}
            """
        return try JSONDecoder().decode(Usage.self, from: Data(json.utf8))
    }

    @Test func contextPercentComesFromUsedAndMaxNotTheRoundedServerFigure() throws {
        let strip = StatusStrip(
            usage: try usage(#","context_used":100,"context_max":256000,"context_percent":0"#), connection: .online)
        #expect(strip.contextPercent! > 0.03 && strip.contextPercent! < 0.04)
        #expect(strip.reading(.context)?.value == "<1%")
    }

    @Test func serverPercentIsUsedWhenUsedOrMaxIsMissing() throws {
        let strip = StatusStrip(usage: try usage(#","context_percent":42.4"#), connection: .online)
        #expect(strip.reading(.context)?.value == "42%")
    }

    @Test func contextLevelsCrossAtSeventyFiveAndNinety() throws {
        func level(_ used: Int) throws -> ContextLevel? {
            StatusStrip(
                usage: try usage(#","context_used":\#(used),"context_max":100"#), connection: .online
            ).contextLevel
        }
        #expect(try level(74) == .normal)
        #expect(try level(75) == .warning)
        #expect(try level(89) == .warning)
        #expect(try level(90) == .critical)
        #expect(try level(150) == .critical)
    }

    @Test func estimatedContextIsMarked() throws {
        let strip = StatusStrip(
            usage: try usage(#","context_used":50,"context_max":100,"context_estimated":true"#), connection: .online)
        #expect(strip.reading(.context)?.estimated == true)
    }

    @Test func noUsageLeavesOnlyTheConnection() {
        let strip = StatusStrip(usage: nil, connection: .offline)
        let readings = strip.readings(StatusItem.allCases)
        #expect(readings.map(\.item) == [.connection])
        #expect(readings.first?.value == "Offline")
        #expect(strip.breakdown == nil && strip.contextLevel == nil)
    }

    @Test func readingsFollowTheChosenOrder() throws {
        let strip = StatusStrip(
            usage: try usage(#","cache_hit_pct":87.6,"avg_tps":115.8,"active_subagents":2,"cost_usd":0.004"#),
            connection: .reconnecting)
        let readings = strip.readings([.speed, .connection, .cache, .subagents, .cost, .tokens])
        #expect(
            readings.map(\.value) == ["116 tok/s", "Reconnecting", "88%", "2", "<$0.01", "212"])
    }

    @Test func zeroSubagentsAndZeroSpeedAreHidden() throws {
        let strip = StatusStrip(usage: try usage(#","active_subagents":0,"avg_tps":0"#), connection: .online)
        #expect(strip.reading(.subagents) == nil && strip.reading(.speed) == nil)
    }

    @Test func costIsMarkedEstimatedUnlessActual() throws {
        let estimated = StatusStrip(
            usage: try usage(#","cost_usd":1.5,"cost_status":"estimated""#), connection: .online)
        #expect(estimated.reading(.cost)?.estimated == true && estimated.reading(.cost)?.value == "$1.50")
        let actual = StatusStrip(usage: try usage(#","cost_usd":1.5,"cost_status":"actual""#), connection: .online)
        #expect(actual.reading(.cost)?.estimated == false)
    }

    @Test func compactCounts() {
        #expect(StatusStrip.compact(999) == "999")
        #expect(StatusStrip.compact(1000) == "1k")
        #expect(StatusStrip.compact(1250) == "1.2k")
        #expect(StatusStrip.compact(15_400) == "15k")
        #expect(StatusStrip.compact(1_400_000) == "1.4M")
    }

    @Test func breakdownCarriesTheTokenFigures() throws {
        let strip = StatusStrip(
            usage: try usage(
                #","cache_read":150,"cache_write":10,"compressions":1,"context_used":100,"context_max":1000"#),
            connection: .online)
        #expect(
            strip.breakdown
                == TokenBreakdown(
                    prompt: 200, completion: 12, reasoning: 0, cacheRead: 150, cacheWrite: 10, contextUsed: 100,
                    contextMax: 1000, compressions: 1))
    }

    @Test func gatewayStatesMapToStripStates() {
        #expect(StripConnection(.connected) == .online)
        #expect(StripConnection(.connecting(attempt: 0)) == .reconnecting)
        #expect(StripConnection(.waitingToReconnect(attempt: 1, delay: 2)) == .reconnecting)
        #expect(StripConnection(.idle) == .offline && StripConnection(.stopped) == .offline)
    }

    @Test func defaultItemsAreInTheCaseList() {
        #expect(Set(StatusStrip.defaultItems).isSubset(of: Set(StatusItem.allCases)))
        #expect(StatusItem.allCases.count == 7)
    }
}
