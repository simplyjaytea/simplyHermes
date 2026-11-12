import Testing

@testable import HermesKit

struct OutboxResumeTests {
    @Test func aChatThatComesBackOnlineDrainsOnce() {
        #expect(OutboxResume.shouldDrain(from: .unreachable, to: .connected))
        #expect(OutboxResume.shouldDrain(from: .reconnecting, to: .connected))
        #expect(OutboxResume.shouldDrain(from: .connecting, to: .connected))
        #expect(OutboxResume.shouldDrain(from: nil, to: .connected))
    }

    @Test func aChatThatStaysOnlineDoesNotDrainAgain() {
        #expect(!OutboxResume.shouldDrain(from: .connected, to: .connected))
    }

    @Test func goingOfflineNeverDrains() {
        #expect(!OutboxResume.shouldDrain(from: .connected, to: .unreachable))
        #expect(!OutboxResume.shouldDrain(from: .connected, to: .reconnecting))
        #expect(!OutboxResume.shouldDrain(from: .unreachable, to: .unreachable))
    }

    @Test func aLocalChatNeverComesBackThroughTheServer() {
        // A local chat's pill never becomes .connected, so the server's recovery cannot send its messages.
        #expect(!OutboxResume.shouldDrain(from: .noServer, to: .localReady(.apple)))
        #expect(!OutboxResume.shouldDrain(from: .localOff, to: .localReady(.apple)))
    }

    // Row 108: the pill watcher's whole decision.
    @Test func aLiveChatThatComesBackAttachesOrDrains() {
        #expect(
            OutboxResume.reaction(from: .unreachable, to: .connected, isRetired: false, isAttached: false) == .attach)
        #expect(
            OutboxResume.reaction(from: .unreachable, to: .connected, isRetired: false, isAttached: true) == .drain)
    }

    @Test func aRetiredChatNeverReactsEvenWhenItsPillComesBack() {
        for attached in [false, true] {
            #expect(
                OutboxResume.reaction(from: .unreachable, to: .connected, isRetired: true, isAttached: attached)
                    == .nothing)
            #expect(
                OutboxResume.reaction(from: nil, to: .connected, isRetired: true, isAttached: attached) == .nothing)
        }
    }

    @Test func aPillThatDidNotComeBackOnlineDoesNothingWhetherRetiredOrNot() {
        for retired in [false, true] {
            #expect(
                OutboxResume.reaction(from: .connected, to: .connected, isRetired: retired, isAttached: true)
                    == .nothing)
            #expect(
                OutboxResume.reaction(from: .connected, to: .unreachable, isRetired: retired, isAttached: true)
                    == .nothing)
        }
    }
}
