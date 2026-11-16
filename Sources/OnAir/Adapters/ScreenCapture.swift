import CoreMedia
import Foundation
@preconcurrency import ScreenCaptureKit

/// Captures a display or window plus the Mac's system audio with ScreenCaptureKit
/// and hands every sample buffer, in order, to `onSample`.
final class ScreenCapture: NSObject, @unchecked Sendable {
    /// Called on a single serial queue, in capture order.
    private let onSample: @Sendable (CMSampleBuffer) -> Void
    private let onStop: @Sendable (String) -> Void
    private let queue = DispatchQueue(label: "app.onair.screen-capture")
    private var stream: SCStream?

    init(onSample: @escaping @Sendable (CMSampleBuffer) -> Void, onStop: @escaping @Sendable (String) -> Void) {
        self.onSample = onSample
        self.onStop = onStop
    }

    var isRunning: Bool { stream != nil }

    /// Starts (or retargets) capture for the content chosen in the system picker.
    func start(filter: SCContentFilter, maxWidth: Int = 1920) async throws {
        let configuration = Self.configuration(for: filter, maxWidth: maxWidth)
        if let stream {
            try await stream.updateContentFilter(filter)
            try await stream.updateConfiguration(configuration)
            return
        }
        let stream = SCStream(filter: filter, configuration: configuration, delegate: self)
        try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: queue)
        try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: queue)
        do {
            try await stream.startCapture()
        } catch {
            throw EngineErrorFactory.screenCapture(error)
        }
        self.stream = stream
    }

    func stop() async {
        guard let stream else { return }
        self.stream = nil
        try? await stream.stopCapture()
    }

    private static func configuration(for filter: SCContentFilter, maxWidth: Int) -> SCStreamConfiguration {
        let configuration = SCStreamConfiguration()
        // Capture at native pixels, capped to the output width, keeping the aspect ratio.
        let rect = filter.contentRect
        let scale = CGFloat(filter.pointPixelScale)
        let pixelWidth = max(rect.width * scale, 1)
        let pixelHeight = max(rect.height * scale, 1)
        let factor = min(1, CGFloat(maxWidth) / pixelWidth)
        configuration.width = Int((pixelWidth * factor).rounded())
        configuration.height = Int((pixelHeight * factor).rounded())
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: 30)
        configuration.pixelFormat = kCVPixelFormatType_32BGRA
        configuration.queueDepth = 5
        configuration.showsCursor = true
        // System audio, without OnAir's own sound to avoid echo.
        configuration.capturesAudio = true
        configuration.excludesCurrentProcessAudio = true
        configuration.sampleRate = 48_000
        configuration.channelCount = 2
        return configuration
    }
}

extension ScreenCapture: SCStreamOutput {
    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard sampleBuffer.isValid else { return }
        switch type {
        case .screen:
            // Skip idle/blank frames: only complete frames carry an image.
            guard Self.isCompleteFrame(sampleBuffer) else { return }
            onSample(sampleBuffer)
        case .audio:
            onSample(sampleBuffer)
        default:
            break
        }
    }

    private static func isCompleteFrame(_ sampleBuffer: CMSampleBuffer) -> Bool {
        guard
            let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
            let rawStatus = attachments.first?[.status] as? Int,
            let status = SCFrameStatus(rawValue: rawStatus)
        else { return false }
        return status == .complete
    }
}

extension ScreenCapture: SCStreamDelegate {
    func stream(_ stream: SCStream, didStopWithError error: any Error) {
        self.stream = nil
        onStop(EngineErrorFactory.screenCapture(error).message)
    }
}
