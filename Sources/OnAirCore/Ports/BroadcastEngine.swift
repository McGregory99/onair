import Foundation

/// Port to the media pipeline (capture, compositing, encoding, publishing).
/// The macOS app implements it with ScreenCaptureKit, AVFoundation and HaishinKit.
public protocol BroadcastEngine: AnyObject, Sendable {
    /// Starts capture and the composed preview. Throws `EngineError` with a user-facing message.
    func startPreview() async throws
    /// Shows the given placements (back to front); sources not listed are hidden.
    func apply(_ placements: [Placement]) async
    /// Connects and publishes. `onDisconnect` is called (from any thread) if the connection drops.
    func startBroadcast(to destinations: [StreamDestination], onDisconnect: @escaping @Sendable (String) -> Void) async throws
    /// Stops publishing; capture and preview keep running.
    func stopBroadcast() async
}

/// Persists the stream key between launches.
@MainActor
public protocol StreamKeyStore: AnyObject {
    func load() -> String?
    func save(_ key: String)
}

/// An error whose message can be shown to the streamer as is.
public struct EngineError: Error, LocalizedError, Sendable, Equatable {
    public let message: String

    public init(_ message: String) {
        self.message = message
    }

    public var errorDescription: String? { message }
}
