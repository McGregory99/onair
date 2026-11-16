/// Lifecycle of a streaming session.
public enum SessionState: Sendable, Equatable {
    case idle
    case rehearsing
    case connecting
    case live
    case ended
    case failed(String)

    public enum Event: Sendable, Equatable {
        case startRehearsal
        case goLive
        case connected
        case failed(String)
        case endStream
    }

    /// Returns the next state, or `nil` when the event is not allowed in this state.
    public func handling(_ event: Event) -> SessionState? {
        switch (self, event) {
        case (.idle, .startRehearsal), (.ended, .startRehearsal), (.failed, .startRehearsal):
            return .rehearsing
        case (.rehearsing, .goLive):
            return .connecting
        case (.connecting, .connected):
            return .live
        case (.connecting, .failed(let reason)), (.live, .failed(let reason)):
            return .failed(reason)
        case (.connecting, .endStream):
            return .rehearsing
        case (.live, .endStream):
            return .ended
        default:
            return nil
        }
    }

    /// The composed preview is visible.
    public var showsPreview: Bool {
        switch self {
        case .rehearsing, .connecting, .live: true
        case .idle, .ended, .failed: false
        }
    }

    /// The audience is receiving the stream.
    public var isOnAir: Bool { self == .live }

    /// Stream settings (key, encoder) cannot change.
    public var locksSettings: Bool { self == .connecting || self == .live }
}
