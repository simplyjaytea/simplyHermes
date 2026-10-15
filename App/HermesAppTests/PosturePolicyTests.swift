import Foundation
import HermesUI
import Testing

struct PosturePolicyTests {
    private let policy = PosturePolicy()

    private func reading(_ status: HingeStatus, degrees: Double) -> HingeReading {
        HingeReading(status: status, angleRadians: degrees * .pi / 180)
    }

    @Test func noHingeMeansFlat() {
        #expect(policy.posture(for: nil) == .flat)
    }

    @Test func closedAndFullyOpenAreFlat() {
        #expect(policy.posture(for: reading(.closed, degrees: 0)) == .flat)
        #expect(policy.posture(for: reading(.fullyOpen, degrees: 180)) == .flat)
        #expect(policy.posture(for: reading(.unknown, degrees: 90)) == .flat)
    }

    @Test func partlyOpenIsHalfFoldedUnlessTight() {
        #expect(policy.posture(for: reading(.partiallyOpen, degrees: 110)) == .halfFolded)
        #expect(policy.posture(for: reading(.partiallyOpen, degrees: 76)) == .halfFolded)
        #expect(policy.posture(for: reading(.partiallyOpen, degrees: 75)) == .tent)
        #expect(policy.posture(for: reading(.partiallyOpen, degrees: 40)) == .tent)
    }

    @Test func tentThresholdIsTunable() {
        var custom = PosturePolicy()
        custom.tentMaxDegrees = 100
        #expect(custom.posture(for: reading(.partiallyOpen, degrees: 90)) == .tent)
    }

    @Test func degreesConvertFromRadians() {
        #expect(abs(reading(.partiallyOpen, degrees: 90).angleDegrees - 90) < 0.0001)
    }
}
