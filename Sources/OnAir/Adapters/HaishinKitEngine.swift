import AVFoundation
import CoreMedia
import HaishinKit
import Observation
import OnAirCore
import RTMPHaishinKit
@preconcurrency import ScreenCaptureKit
import VideoToolbox

/// Mixer track numbers. Audio and video tracks are numbered independently.
private let cameraTrack: UInt8 = 0
private let screenTrack: UInt8 = 1
/// HaishinKit always draws the mixer's main video track full-frame underneath every
/// screen object. Pointing it at a track nobody feeds keeps that layer empty, so the
/// layout is fully controlled by our own camera and screen objects.
private let unusedMainVideoTrack: UInt8 = 9
private let microphoneTrack: UInt8 = 0
private let systemAudioTrack: UInt8 = 1

/// `BroadcastEngine` built on HaishinKit (compositing, encoding, RTMPS),
/// AVFoundation (camera, microphone) and ScreenCaptureKit (screen, system audio).
@MainActor
@Observable
final class HaishinKitEngine: BroadcastEngine, MTHKViewRepresentable.PreviewSource {
    private(set) var cameras: [AVCaptureDevice] = []
    private(set) var microphones: [AVCaptureDevice] = []
    private(set) var cameraID: String?
    private(set) var microphoneID: String?
    private(set) var isSharingScreen = false
    /// Video bitrate for the next broadcast, in bits per second.
    var videoBitRate = 6_000_000
    /// Reports problems that happen outside a controller action (e.g. screen sharing stopped).
    @ObservationIgnored var onError: ((String) -> Void)?

    @ObservationIgnored nonisolated let mixer = MediaMixer(captureSessionMode: .single, multiTrackAudioMixingEnabled: true)
    @ObservationIgnored private let canvas: CanvasSize
    @ObservationIgnored private let compositor = Compositor()
    @ObservationIgnored private let picker = ScreenPicker()
    @ObservationIgnored private var screenCapture: ScreenCapture!
    @ObservationIgnored private var forwardTask: Task<Void, Never>?
    @ObservationIgnored private var sessions: [any StreamSession] = []
    @ObservationIgnored private var isPreviewing = false
    @ObservationIgnored private static var factoriesRegistered = false

    init(canvas: CanvasSize) {
        self.canvas = canvas
        let (samples, continuation) = AsyncStream.makeStream(of: CMSampleBuffer.self, bufferingPolicy: .bufferingNewest(30))
        screenCapture = ScreenCapture(
            onSample: { continuation.yield($0) },
            onStop: { [weak self] message in Task { @MainActor in self?.screenSharingStopped(message) } }
        )
        // One consumer keeps screen frames and system audio in capture order.
        forwardTask = Task { [mixer] in
            for await sample in samples {
                await mixer.append(sample, track: screenTrack)
            }
        }
        picker.onPick = { [weak self] filter in Task { @MainActor in await self?.share(filter) } }
        picker.onFail = { [weak self] message in Task { @MainActor in self?.onError?(message) } }
    }

    // MARK: - BroadcastEngine

    func startPreview() async throws {
        guard !isPreviewing else { return }
        try await Self.requireAccess(.video, name: "Camera", pane: "Camera")
        try await Self.requireAccess(.audio, name: "Microphone", pane: "Microphone")
        refreshDevices()

        await mixer.setVideoMixerSettings(VideoMixerSettings(mode: .offscreen, mainTrack: unusedMainVideoTrack))
        var audio = await mixer.audioMixerSettings
        // The microphone is the main audio track: it clocks the mix, so it must always be attached.
        audio.mainTrack = microphoneTrack
        audio.tracks = [
            microphoneTrack: AudioMixerTrackSettings(volume: 1.0),
            systemAudioTrack: AudioMixerTrackSettings(volume: 0.8),
        ]
        await mixer.setAudioMixerSettings(audio)

        try await attachCamera(id: cameraID)
        try await attachMicrophone(id: microphoneID)
        await compositor.setUp(mixer: mixer, canvas: canvas)
        await mixer.startRunning()
        try? await mixer.setFrameRate(30)
        isPreviewing = true
    }

    func apply(_ placements: [Placement]) async {
        await compositor.apply(placements, mixer: mixer)
    }

    func startBroadcast(to destinations: [StreamDestination], onDisconnect: @escaping @Sendable (String) -> Void) async throws {
        await Self.registerFactories()
        do {
            for destination in destinations {
                guard let url = URL(string: "\(destination.url)/\(destination.streamKey)") else {
                    throw EngineError("The stream key contains characters that are not allowed.")
                }
                guard let session = try await StreamSessionBuilderFactory.shared.make(url).setMode(.publish).build() else {
                    throw EngineError("Streaming to \(destination.url) is not supported.")
                }
                let stream = await session.stream
                try await stream.setVideoSettings(VideoCodecSettings(
                    videoSize: CGSize(width: canvas.width, height: canvas.height),
                    bitRate: videoBitRate,
                    profileLevel: kVTProfileLevel_H264_High_AutoLevel as String,
                    maxKeyFrameIntervalDuration: 2,
                    expectedFrameRate: 30
                ))
                try await stream.setAudioSettings(AudioCodecSettings(bitRate: 128_000, sampleRate: 44_100))
                await mixer.addOutput(stream)
                sessions.append(session)
                try await session.connect { [weak self] in
                    Task { @MainActor in
                        // Ignore the close we caused ourselves in stopBroadcast().
                        guard let self, !self.sessions.isEmpty else { return }
                        onDisconnect("The connection to YouTube was lost.")
                    }
                }
            }
        } catch let error as EngineError {
            throw error
        } catch {
            throw EngineErrorFactory.connection(error)
        }
    }

    func stopBroadcast() async {
        let current = sessions
        sessions = []
        for session in current {
            await mixer.removeOutput(await session.stream)
            try? await session.close()
        }
    }

    // MARK: - Preview

    nonisolated func connect(to view: MTHKView) {
        Task { await mixer.addOutput(view) }
    }

    // MARK: - Sources

    func refreshDevices() {
        cameras = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera, .external, .continuityCamera],
            mediaType: .video, position: .unspecified
        ).devices
        microphones = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.microphone, .external],
            mediaType: .audio, position: .unspecified
        ).devices
    }

    func selectCamera(id: String) async {
        do { try await attachCamera(id: id) } catch { onError?(error.localizedDescription) }
    }

    func selectMicrophone(id: String) async {
        do { try await attachMicrophone(id: id) } catch { onError?(error.localizedDescription) }
    }

    /// Opens the macOS picker to choose a display, window or app to share.
    func chooseScreen() {
        picker.present()
    }

    func stopSharingScreen() async {
        await screenCapture.stop()
        isSharingScreen = false
    }

    private func share(_ filter: SCContentFilter) async {
        do {
            try await screenCapture.start(filter: filter, maxWidth: Int(canvas.width))
            isSharingScreen = true
        } catch {
            isSharingScreen = false
            onError?(error.localizedDescription)
        }
    }

    private func screenSharingStopped(_ message: String) {
        isSharingScreen = false
        onError?(message)
    }

    private func attachCamera(id: String?) async throws {
        let chosen = cameras.first { $0.uniqueID == id } ?? AVCaptureDevice.default(for: .video) ?? cameras.first
        guard let chosen else { return } // No camera: screen-only layouts still work.
        let (uniqueID, name) = (chosen.uniqueID, chosen.localizedName)
        do {
            try await Self.attach(.video, uniqueID: uniqueID, to: mixer)
        } catch {
            throw EngineError("Could not use the camera “\(name)”. It may be in use by another app.")
        }
        cameraID = uniqueID
    }

    private func attachMicrophone(id: String?) async throws {
        let chosen = microphones.first { $0.uniqueID == id } ?? AVCaptureDevice.default(for: .audio) ?? microphones.first
        guard let chosen else {
            throw EngineError("No microphone found. Connect one: the stream needs a microphone to carry any sound.")
        }
        let (uniqueID, name) = (chosen.uniqueID, chosen.localizedName)
        do {
            try await Self.attach(.audio, uniqueID: uniqueID, to: mixer)
        } catch {
            throw EngineError("Could not use the microphone “\(name)”.")
        }
        microphoneID = uniqueID
    }

    /// Looks the device up again outside the main actor so it can be handed to the mixer actor
    /// (`AVCaptureDevice` is not `Sendable`).
    nonisolated private static func attach(_ media: AVMediaType, uniqueID: String, to mixer: MediaMixer) async throws {
        guard let device = AVCaptureDevice(uniqueID: uniqueID) else {
            throw EngineError("The device is no longer connected.")
        }
        if media == .video {
            try await mixer.attachVideo(device, track: cameraTrack)
        } else {
            try await mixer.attachAudio(device, track: microphoneTrack)
        }
    }

    private static func requireAccess(_ media: AVMediaType, name: String, pane: String) async throws {
        switch AVCaptureDevice.authorizationStatus(for: media) {
        case .authorized:
            return
        case .notDetermined:
            if await AVCaptureDevice.requestAccess(for: media) { return }
        default:
            break
        }
        throw EngineErrorFactory.permissionDenied(name, settingsPane: pane)
    }

    private static func registerFactories() async {
        guard !factoriesRegistered else { return }
        factoriesRegistered = true
        await StreamSessionBuilderFactory.shared.register(RTMPSessionFactory())
    }
}

/// Owns the camera and screen layers of the composed canvas. HaishinKit requires
/// screen objects to be mutated on `ScreenActor`.
@ScreenActor
final class Compositor {
    private var objects: [VideoSource: VideoScreenObject] = [:]
    /// Current back-to-front order of the layers.
    private var order: [VideoSource] = []

    nonisolated init() {}

    func setUp(mixer: MediaMixer, canvas: CanvasSize) async {
        guard objects.isEmpty else { return }
        let screen = await mixer.screen
        screen.size = CGSize(width: canvas.width, height: canvas.height)
        screen.backgroundColor = CGColor(gray: 0, alpha: 1)
        for (source, track) in [(VideoSource.screen, screenTrack), (.camera, cameraTrack)] {
            let object = VideoScreenObject()
            object.track = track
            object.videoGravity = .resizeAspect // .resizeAspectFill is not clipped to the frame.
            object.horizontalAlignment = .left
            object.verticalAlignment = .top
            object.isVisible = false
            try? screen.addChild(object)
            objects[source] = object
            order.append(source)
        }
    }

    func apply(_ placements: [Placement], mixer: MediaMixer) async {
        let screen = await mixer.screen
        let shown = placements.map(\.source)
        let newOrder = order.filter { !shown.contains($0) } + shown
        if newOrder != order {
            for source in order { screen.removeChild(objects[source]) }
            for source in newOrder { try? screen.addChild(objects[source]) }
            order = newOrder
        }
        for (source, object) in objects {
            guard let frame = placements.first(where: { $0.source == source })?.frame else {
                object.isVisible = false
                continue
            }
            object.layoutMargin = NSEdgeInsets(top: frame.y, left: frame.x, bottom: 0, right: 0)
            object.size = CGSize(width: frame.width, height: frame.height)
            object.isVisible = true
            object.invalidateLayout()
        }
    }
}

/// Wraps the system content-sharing picker (display, window or app).
final class ScreenPicker: NSObject, SCContentSharingPickerObserver, @unchecked Sendable {
    var onPick: (@Sendable (SCContentFilter) -> Void)?
    var onFail: (@Sendable (String) -> Void)?
    private var isObserving = false

    @MainActor
    func present() {
        let picker = SCContentSharingPicker.shared
        if !isObserving {
            var configuration = SCContentSharingPickerConfiguration()
            configuration.allowedPickerModes = [.singleDisplay, .singleWindow, .singleApplication]
            picker.defaultConfiguration = configuration
            picker.add(self)
            isObserving = true
        }
        picker.isActive = true
        picker.present()
    }

    func contentSharingPicker(_ picker: SCContentSharingPicker, didCancelFor stream: SCStream?) {}

    func contentSharingPicker(_ picker: SCContentSharingPicker, didUpdateWith filter: SCContentFilter, for stream: SCStream?) {
        onPick?(filter)
    }

    func contentSharingPickerStartDidFailWithError(_ error: any Error) {
        onFail?("The screen picker could not start: \(error.localizedDescription)")
    }
}
