import Foundation
import Observation

/// Drives a streaming session: rehearsal, layout switching, going live and errors.
/// The UI binds to it; the media work is delegated to a `BroadcastEngine`.
@MainActor
@Observable
public final class SessionController {
    public private(set) var state: SessionState = .idle
    public private(set) var layout: Layout
    public var streamKey: String
    /// Message to show the streamer; cleared when an action succeeds.
    public var errorMessage: String?

    public let canvas: CanvasSize
    private let engine: BroadcastEngine
    private let keyStore: StreamKeyStore

    public init(engine: BroadcastEngine, keyStore: StreamKeyStore, canvas: CanvasSize = .fullHD, layout: Layout = .pictureInPicture) {
        self.engine = engine
        self.keyStore = keyStore
        self.canvas = canvas
        self.layout = layout
        self.streamKey = keyStore.load() ?? ""
    }

    public func startRehearsal() async {
        do {
            try await engine.startPreview()
        } catch {
            errorMessage = Self.message(for: error)
            return
        }
        errorMessage = nil
        transition(.startRehearsal)
        await engine.apply(LayoutGeometry.placements(for: layout, canvas: canvas))
    }

    public func select(_ layout: Layout) async {
        self.layout = layout
        await engine.apply(LayoutGeometry.placements(for: layout, canvas: canvas))
    }

    public func goLive() async {
        guard state == .rehearsing else { return }
        let destination: StreamDestination
        do {
            destination = try StreamDestination.youtube(streamKey: streamKey)
        } catch {
            errorMessage = error.message
            return
        }
        errorMessage = nil
        keyStore.save(destination.streamKey)
        transition(.goLive)

        let onDisconnect: @Sendable (String) -> Void = { [weak self] reason in
            Task { @MainActor in self?.connectionLost(reason) }
        }
        do {
            try await engine.startBroadcast(to: [destination], onDisconnect: onDisconnect)
            transition(.connected)
        } catch {
            await engine.stopBroadcast()
            transition(.failed(Self.message(for: error)))
        }
    }

    public func endStream() async {
        guard state.locksSettings else { return }
        await engine.stopBroadcast()
        transition(.endStream)
    }

    /// Returns to rehearsal after an ended or failed stream (the preview keeps running).
    public func backToRehearsal() {
        errorMessage = nil
        transition(.startRehearsal)
    }

    func connectionLost(_ reason: String) {
        transition(.failed(reason))
    }

    /// Test hook: lets queued main-actor events (like a disconnect) run.
    func waitForPendingEvents() async {
        await Task { @MainActor in }.value
    }

    /// Applies an event; events that are not valid in the current state are ignored
    /// (e.g. a late disconnect after the streamer already ended the stream).
    private func transition(_ event: SessionState.Event) {
        if let next = state.handling(event) {
            state = next
        }
    }

    private static func message(for error: Error) -> String {
        (error as? EngineError)?.message ?? error.localizedDescription
    }
}
