import Testing
@testable import OnAirCore

@MainActor
final class FakeEngine: BroadcastEngine {
    var previewStarted = false
    var appliedPlacements: [[Placement]] = []
    var broadcastDestinations: [[StreamDestination]] = []
    var stopBroadcastCalls = 0
    var startPreviewError: EngineError?
    var startBroadcastError: EngineError?
    var onDisconnect: (@Sendable (String) -> Void)?

    func startPreview() async throws {
        if let startPreviewError { throw startPreviewError }
        previewStarted = true
    }

    func apply(_ placements: [Placement]) async {
        appliedPlacements.append(placements)
    }

    func startBroadcast(to destinations: [StreamDestination], onDisconnect: @escaping @Sendable (String) -> Void) async throws {
        broadcastDestinations.append(destinations)
        self.onDisconnect = onDisconnect
        if let startBroadcastError { throw startBroadcastError }
    }

    func stopBroadcast() async {
        stopBroadcastCalls += 1
    }
}

@MainActor
final class MemoryKeyStore: StreamKeyStore {
    var stored: String?
    init(_ stored: String? = nil) { self.stored = stored }
    func load() -> String? { stored }
    func save(_ key: String) { stored = key }
}

@MainActor
@Suite("SessionController")
struct SessionControllerTests {
    let engine = FakeEngine()
    let keys = MemoryKeyStore()

    func makeController(layout: Layout = .pictureInPicture) -> SessionController {
        SessionController(engine: engine, keyStore: keys, canvas: .fullHD, layout: layout)
    }

    func rehearsing() async -> SessionController {
        let controller = makeController()
        await controller.startRehearsal()
        return controller
    }

    @Test("starting rehearsal starts the preview and applies the current layout")
    func startRehearsal() async {
        let controller = await rehearsing()
        #expect(controller.state == .rehearsing)
        #expect(engine.previewStarted)
        #expect(engine.appliedPlacements == [LayoutGeometry.placements(for: .pictureInPicture, canvas: .fullHD)])
    }

    @Test("a capture error on rehearsal start is shown and the session stays idle")
    func rehearsalFailure() async {
        engine.startPreviewError = EngineError("Camera access denied. Allow OnAir in System Settings › Privacy & Security › Camera.")
        let controller = makeController()
        await controller.startRehearsal()
        #expect(controller.state == .idle)
        #expect(controller.errorMessage == "Camera access denied. Allow OnAir in System Settings › Privacy & Security › Camera.")
    }

    @Test("selecting a layout applies its placements immediately", arguments: Layout.allCases)
    func selectLayout(layout: Layout) async {
        let controller = await rehearsing()
        await controller.select(layout)
        #expect(controller.layout == layout)
        #expect(engine.appliedPlacements.last == LayoutGeometry.placements(for: layout, canvas: .fullHD))
    }

    @Test("layouts can also be switched while live")
    func selectWhileLive() async {
        let controller = await rehearsing()
        controller.streamKey = "key"
        await controller.goLive()
        await controller.select(.sideBySide)
        #expect(controller.state == .live)
        #expect(engine.appliedPlacements.last == LayoutGeometry.placements(for: .sideBySide, canvas: .fullHD))
    }

    @Test("going live without a stream key shows a message and does not connect")
    func goLiveWithoutKey() async {
        let controller = await rehearsing()
        controller.streamKey = "  "
        await controller.goLive()
        #expect(controller.state == .rehearsing)
        #expect(controller.errorMessage == "Paste your YouTube stream key before going live.")
        #expect(engine.broadcastDestinations.isEmpty)
    }

    @Test("going live streams to YouTube with the trimmed key, remembers it and clears old errors")
    func goLive() async {
        let controller = await rehearsing()
        controller.errorMessage = "old"
        controller.streamKey = " abcd-1234 "
        await controller.goLive()
        #expect(controller.state == .live)
        #expect(engine.broadcastDestinations == [[StreamDestination(url: "rtmps://a.rtmp.youtube.com/live2", streamKey: "abcd-1234")]])
        #expect(keys.stored == "abcd-1234")
        #expect(controller.errorMessage == nil)
    }

    @Test("a rejected connection ends in failed with the engine's reason")
    func goLiveFailure() async {
        engine.startBroadcastError = EngineError("YouTube rejected the stream key.")
        let controller = await rehearsing()
        controller.streamKey = "bad"
        await controller.goLive()
        #expect(controller.state == .failed("YouTube rejected the stream key."))
    }

    @Test("losing the connection while live moves to failed")
    func disconnectWhileLive() async {
        let controller = await rehearsing()
        controller.streamKey = "key"
        await controller.goLive()
        engine.onDisconnect?("Connection to YouTube lost.")
        await controller.waitForPendingEvents()
        #expect(controller.state == .failed("Connection to YouTube lost."))
    }

    @Test("ending the stream stops the broadcast but keeps the preview")
    func endStream() async {
        let controller = await rehearsing()
        controller.streamKey = "key"
        await controller.goLive()
        await controller.endStream()
        #expect(controller.state == .ended)
        #expect(engine.stopBroadcastCalls == 1)
        #expect(engine.previewStarted)
    }

    @Test("back to rehearsal after an ended stream or a failure")
    func backToRehearsal() async {
        engine.startBroadcastError = EngineError("x")
        let controller = await rehearsing()
        controller.streamKey = "key"
        await controller.goLive()
        controller.backToRehearsal()
        #expect(controller.state == .rehearsing)
        #expect(controller.errorMessage == nil)
    }

    @Test("the saved stream key is loaded on start")
    func loadsSavedKey() {
        keys.stored = "saved-key"
        #expect(makeController().streamKey == "saved-key")
    }
}
