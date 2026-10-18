import Testing

@testable import HermesKit

@Suite struct VoiceConversationTests {
    /// A conversation that has been started and is listening.
    private func listening() -> VoiceConversation {
        var conversation = VoiceConversation()
        _ = conversation.handle(.start)
        return conversation
    }

    @Test func oneTurnListensSendsSpeaksAndListensAgain() {
        var conversation = VoiceConversation()
        #expect(conversation.handle(.start) == [.listen])
        #expect(conversation.handle(.speechEnded) == [.pause, .transcribe])
        #expect(conversation.phase == .transcribing)

        #expect(conversation.handle(.transcribed("  Summarize the log. ")) == [.send("Summarize the log.")])
        #expect(conversation.phase == .waitingForReply)

        #expect(conversation.handle(.reply("Done.")) == [.listen, .speak("Done.")])
        #expect(conversation.phase == .speaking)

        #expect(conversation.handle(.playbackFinished).isEmpty)
        #expect(conversation.phase == .listening)
    }

    @Test func silenceReopensTheMicrophoneWithoutSending() {
        var conversation = listening()
        _ = conversation.handle(.speechEnded)

        #expect(conversation.handle(.transcribed("   ")) == [.listen])
        #expect(conversation.phase == .listening)
    }

    @Test func speechWhileReplyPlaysInterruptsIt() {
        var conversation = listening()
        _ = conversation.handle(.reply("A long answer."))
        #expect(conversation.phase == .speaking)

        #expect(conversation.handle(.speechStarted) == [.stopSpeaking])
        #expect(conversation.phase == .listening)
        #expect(conversation.handle(.speechEnded) == [.pause, .transcribe])
    }

    @Test func newReplyReplacesTheOneBeingSpoken() {
        var conversation = listening()
        _ = conversation.handle(.reply("First."))

        #expect(conversation.handle(.reply("Second.")) == [.stopSpeaking, .speak("Second.")])
        #expect(conversation.phase == .speaking)
    }

    @Test func failedTranscriptionShowsTheErrorAndKeepsListening() {
        var conversation = listening()
        _ = conversation.handle(.speechEnded)

        #expect(conversation.handle(.failed("Transcription failed")) == [.showError("Transcription failed"), .listen])
        #expect(conversation.phase == .listening)
    }

    @Test func failedRequestWhileWaitingKeepsTheConversationGoing() {
        var conversation = listening()
        _ = conversation.handle(.speechEnded)
        _ = conversation.handle(.transcribed("Hello"))

        #expect(conversation.handle(.failed("Hermes is busy")) == [.showError("Hermes is busy"), .listen])
        #expect(conversation.phase == .listening)
    }

    @Test func failedSpeechShowsTheErrorAndStaysListening() {
        var conversation = listening()
        _ = conversation.handle(.reply("Hi."))

        #expect(conversation.handle(.failed("No speech provider")) == [.showError("No speech provider")])
        #expect(conversation.phase == .listening)
    }

    @Test func emptyReplyWhileWaitingReopensTheMicrophone() {
        var conversation = listening()
        _ = conversation.handle(.speechEnded)
        _ = conversation.handle(.transcribed("Hello"))

        #expect(conversation.handle(.reply("  ")) == [.listen])
        #expect(conversation.phase == .listening)
    }

    @Test func stopClosesEverythingOnce() {
        var conversation = listening()
        _ = conversation.handle(.reply("Talking."))

        #expect(conversation.handle(.stop) == [.pause, .stopSpeaking])
        #expect(conversation.phase == .idle)
        #expect(conversation.handle(.stop).isEmpty)
    }

    @Test func inputsThatDoNotFitThePhaseChangeNothing() {
        var conversation = VoiceConversation()
        #expect(conversation.handle(.speechEnded).isEmpty)
        #expect(conversation.handle(.reply("Hi.")).isEmpty)
        #expect(conversation.phase == .idle)

        _ = conversation.handle(.start)
        #expect(conversation.handle(.start).isEmpty)
        #expect(conversation.handle(.transcribed("Hello")).isEmpty)
        #expect(conversation.phase == .listening)
    }
}
