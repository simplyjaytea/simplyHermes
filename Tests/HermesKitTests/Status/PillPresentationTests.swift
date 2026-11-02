import Foundation
import Testing

@testable import HermesKit

struct PillPresentationTests {
    private static let server = "hermes-box"
    private static let gemma = ModelIdentity.downloaded(id: "gemma-3-1b-4bit", displayName: "Gemma 3 1B")

    /// Every pill state the app can show: O1–O6 (with each attention reason) and L1–L5.
    private static let all: [PillState] = [
        .connected, .connecting, .reconnecting, .unreachable,
        .needsAttention(.signIn), .needsAttention(.serverUpdate), .needsAttention(.hostKey), .needsAttention(.settings),
        .noServer,
        .localReady(gemma), .localLoading(gemma), .localNoModel,
        .localFailed(gemma, reason: .runtimeUnavailable), .localOff,
    ]

    @Test func everyStateHasWordsSymbolAndVoiceOver() {
        for pill in Self.all {
            #expect(!PillPresentation.shortTitle(pill, serverName: Self.server).isEmpty, "\(pill)")
            #expect(!PillPresentation.fullTitle(pill, serverName: Self.server).isEmpty, "\(pill)")
            #expect(!PillPresentation.symbol(pill).isEmpty, "\(pill)")
            #expect(!PillPresentation.voiceOverLabel(pill, serverName: Self.server).isEmpty, "\(pill)")
        }
    }

    @Test func onlineStatesNameTheServerAndLocalStatesNameTheModel() {
        for pill in Self.all {
            let label = PillPresentation.voiceOverLabel(pill, serverName: Self.server)
            switch pill {
            case .connected, .connecting, .reconnecting, .unreachable, .needsAttention, .noServer:
                #expect(label.hasPrefix("Online chat."), "\(pill): \(label)")
            default:
                #expect(label.hasPrefix("Local chat."), "\(pill): \(label)")
            }
        }
        #expect(PillPresentation.fullTitle(.unreachable, serverName: Self.server) == "Can't reach hermes-box")
        #expect(PillPresentation.fullTitle(.localReady(Self.gemma), serverName: Self.server) == "Local · Gemma 3 1B")
        #expect(PillPresentation.shortTitle(.localReady(Self.gemma), serverName: Self.server) == "Gemma 3 1B")
    }

    @Test func onlyUnreachableNoModelAndLoadFailureAnnounceOnEntry() {
        let announced = Self.all.filter(PillPresentation.announcesOnEntry)
        #expect(announced == [.unreachable, .localNoModel, .localFailed(Self.gemma, reason: .runtimeUnavailable)])
        let warned = Self.all.filter(PillPresentation.warnsOnEntry)
        #expect(warned == [.unreachable, .localFailed(Self.gemma, reason: .runtimeUnavailable)])
    }

    @Test func inkFollowsTheSpecFamilies() {
        #expect(PillPresentation.ink(.connected) == .online)
        #expect(PillPresentation.ink(.reconnecting) == .warning)
        #expect(PillPresentation.ink(.unreachable) == .problem)
        #expect(PillPresentation.ink(.noServer) == .neutral)
        #expect(PillPresentation.ink(.localReady(Self.gemma)) == .local)
        #expect(PillPresentation.ink(.localNoModel) == .problem)
        #expect(PillPresentation.ink(.localOff) == .neutral)
    }

    @Test func aPillMapsToTheStripConnectionDot() {
        #expect(StripConnection(pill: .connected) == .online)
        #expect(StripConnection(pill: .reconnecting) == .reconnecting)
        #expect(StripConnection(pill: .unreachable) == .offline)
        #expect(StripConnection(pill: .needsAttention(.signIn)) == .needsAttention)
        #expect(StripConnection(pill: .localReady(Self.gemma)) == .offline)
    }
}

struct OutageBannerTests {
    @Test func aMissingNetworkPathShowsTheBannerAtOnce() {
        // With no network path the deriver answers "unreachable" at once, whatever the connection last said.
        let status = ChatStatusDeriver.derive(
            backend: .server(connectionID: UUID(), profile: nil, sessionID: "s"), phase: .connecting,
            path: .unsatisfied, local: .off)
        #expect(OutageBanner.shows(status))
    }

    @Test func showsOnlyWhenTheServerCannotBeReached() {
        #expect(OutageBanner.shows(ChatStatus(pill: .unreachable, canSend: true, sendPath: .askUser)))
        #expect(!OutageBanner.shows(ChatStatus(pill: .connected, canSend: true, sendPath: .server)))
        #expect(!OutageBanner.shows(ChatStatus(pill: .reconnecting, canSend: true, sendPath: .hold)))
        #expect(!OutageBanner.shows(ChatStatus(pill: .needsAttention(.signIn), canSend: false, sendPath: .askUser)))
    }

    @Test func titleNamesTheServerAndTheActionsAreFixed() {
        #expect(OutageBanner.title(serverName: "hermes-box") == "Can't reach hermes-box")
        #expect(OutageBanner.actions == [.tryAgain, .continueInNewLocalChat])
        #expect(OutageAction.continueInNewLocalChat.title == "Continue in a new Local chat")
        #expect(OutageAction.tryAgain.title == "Try again")
    }
}

struct NewChatChoiceTests {
    @Test func eachChoiceStartsItsOwnMode() {
        #expect(NewChatChoice.online.mode == .online)
        #expect(NewChatChoice.local.mode == .local)
        #expect(NewChatChoice.allCases.map(\.title) == ["New Online chat", "New Local chat"])
    }
}

struct ChatModeDefaultSaveTests {
    @Test func theDefaultIsSavedAndLoadedBack() throws {
        let suite = try #require(UserDefaults(suiteName: "chatModeDefault-\(UUID().uuidString)"))
        #expect(ChatModeDefault.load(from: suite) == .online)
        ChatModeDefault.save(.local, to: suite)
        #expect(ChatModeDefault.load(from: suite) == .local)
        ChatModeDefault.save(.online, to: suite)
        #expect(ChatModeDefault.load(from: suite) == .online)
    }
}
