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
}
