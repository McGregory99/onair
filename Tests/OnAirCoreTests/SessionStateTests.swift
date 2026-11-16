import Testing
@testable import OnAirCore

@Suite("SessionState")
struct SessionStateTests {
    @Test("happy path: idle → rehearsing → connecting → live → ended")
    func happyPath() {
        var state = SessionState.idle
        state = state.handling(.startRehearsal)!
        #expect(state == .rehearsing)
        state = state.handling(.goLive)!
        #expect(state == .connecting)
        state = state.handling(.connected)!
        #expect(state == .live)
        state = state.handling(.endStream)!
        #expect(state == .ended)
    }

    @Test("a failed connection keeps the reason so the UI can show it")
    func connectionFailure() {
        let state = SessionState.connecting.handling(.failed("Stream key rejected"))
        #expect(state == .failed("Stream key rejected"))
    }

    @Test("dropping while live is a failure, not a clean end")
    func dropWhileLive() {
        #expect(SessionState.live.handling(.failed("Connection lost")) == .failed("Connection lost"))
    }

    @Test("cancelling while connecting goes back to rehearsal")
    func cancelConnecting() {
        #expect(SessionState.connecting.handling(.endStream) == .rehearsing)
    }

    @Test("after an error or an ended stream you can rehearse again")
    func recoverToRehearsal() {
        #expect(SessionState.failed("x").handling(.startRehearsal) == .rehearsing)
        #expect(SessionState.ended.handling(.startRehearsal) == .rehearsing)
    }

    @Test("you cannot go live without rehearsing first")
    func cannotSkipRehearsal() {
        #expect(SessionState.idle.handling(.goLive) == nil)
        #expect(SessionState.live.handling(.goLive) == nil)
    }

    @Test("only rehearsing and live show the preview; only connecting and live lock the stream key")
    func derivedFlags() {
        #expect(SessionState.rehearsing.showsPreview)
        #expect(SessionState.live.showsPreview)
        #expect(!SessionState.idle.showsPreview)
        #expect(SessionState.connecting.isOnAir == false)
        #expect(SessionState.live.isOnAir)
        #expect(SessionState.connecting.locksSettings)
        #expect(SessionState.live.locksSettings)
        #expect(!SessionState.rehearsing.locksSettings)
    }
}

@Suite("StreamDestination")
struct StreamDestinationTests {
    @Test("YouTube destination uses RTMPS ingest and trims the pasted key")
    func youtube() throws {
        let destination = try StreamDestination.youtube(streamKey: "  abcd-1234-efgh \n")
        #expect(destination.url == "rtmps://a.rtmp.youtube.com/live2")
        #expect(destination.streamKey == "abcd-1234-efgh")
    }

    @Test("an empty or blank key is rejected with a clear message")
    func emptyKey() {
        #expect(throws: StreamDestinationError.missingStreamKey) {
            try StreamDestination.youtube(streamKey: "   ")
        }
        #expect(StreamDestinationError.missingStreamKey.message == "Paste your YouTube stream key before going live.")
    }
}
