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
            OutboxResume.reaction(
                from: .unreachable, to: .connected, isRetired: false, isAttached: false, isOnAnotherServer: false)
                == .attach)
        #expect(
            OutboxResume.reaction(
                from: .unreachable, to: .connected, isRetired: false, isAttached: true, isOnAnotherServer: false)
                == .drain)
    }

    @Test func aRetiredChatNeverReactsEvenWhenItsPillComesBack() {
        for attached in [false, true] {
            #expect(
                OutboxResume.reaction(
                    from: .unreachable, to: .connected, isRetired: true, isAttached: attached, isOnAnotherServer: false)
                    == .nothing)
            #expect(
                OutboxResume.reaction(
                    from: nil, to: .connected, isRetired: true, isAttached: attached, isOnAnotherServer: false
                ) == .nothing)
        }
    }

    @Test func aPillThatDidNotComeBackOnlineDoesNothingWhetherRetiredOrNot() {
        for retired in [false, true] {
            #expect(
                OutboxResume.reaction(
                    from: .connected, to: .connected, isRetired: retired, isAttached: true, isOnAnotherServer: false)
                    == .nothing)
            #expect(
                OutboxResume.reaction(
                    from: .connected, to: .unreachable, isRetired: retired, isAttached: true, isOnAnotherServer: false)
                    == .nothing)
        }
    }

    // Row 140: the old chat is not retired yet, but its server is no longer the active one.
    @Test func aChatOnAnotherServerThanTheActiveOneNeverReactsEvenBeforeItIsRetired() {
        for attached in [false, true] {
            #expect(
                OutboxResume.reaction(
                    from: .unreachable, to: .connected, isRetired: false, isAttached: attached,
                    isOnAnotherServer: OutboxResume.isOnAnotherServer(chatServer: "A", activeServer: "B")) == .nothing)
        }
        // With no active server at all, a chat bound to A is not on the active server either.
        #expect(
            OutboxResume.reaction(
                from: .unreachable, to: .connected, isRetired: false, isAttached: false,
                isOnAnotherServer: OutboxResume.isOnAnotherServer(chatServer: "A", activeServer: nil)) == .nothing)
    }

    @Test func aChatOnTheActiveServerStillReacts() {
        #expect(
            OutboxResume.reaction(
                from: .unreachable, to: .connected, isRetired: false, isAttached: false,
                isOnAnotherServer: OutboxResume.isOnAnotherServer(chatServer: "B", activeServer: "B")) == .attach)
    }

    @Test func aChatWithNoRecordedServerHasNothingToCompare() {
        #expect(!OutboxResume.isOnAnotherServer(chatServer: nil, activeServer: "B"))
        #expect(OutboxResume.isOnAnotherServer(chatServer: "A", activeServer: "B"))
        #expect(!OutboxResume.isOnAnotherServer(chatServer: "A", activeServer: "A"))
    }
}
