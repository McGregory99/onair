import Foundation
import OnAirCore
import ScreenCaptureKit

/// Turns low-level failures into messages the streamer can act on.
enum EngineErrorFactory {
    static func permissionDenied(_ what: String, settingsPane: String) -> EngineError {
        EngineError("\(what) access is off. Allow OnAir in System Settings › Privacy & Security › \(settingsPane), then try again.")
    }

    static func screenCapture(_ error: any Error) -> EngineError {
        let nsError = error as NSError
        if nsError.domain == SCStreamErrorDomain, nsError.code == SCStreamError.userDeclined.rawValue {
            return permissionDenied("Screen and system audio recording", settingsPane: "Screen & System Audio Recording")
        }
        if nsError.domain == SCStreamErrorDomain, nsError.code == SCStreamError.userStopped.rawValue {
            return EngineError("Screen sharing was stopped from the menu bar. Choose what to share again.")
        }
        return EngineError("Screen capture stopped: \(nsError.localizedDescription)")
    }

    static func connection(_ error: any Error) -> EngineError {
        EngineError("Could not go live on YouTube. Check the stream key and your internet connection. (\(error.localizedDescription))")
    }
}
