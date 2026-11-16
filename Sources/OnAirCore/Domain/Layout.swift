/// The video sources that can appear in the composed output.
public enum VideoSource: Sendable, Hashable {
    case camera
    case screen
}

/// One-click scene layouts offered to the streamer, in button order.
public enum Layout: String, Sendable, CaseIterable, Identifiable {
    case cameraOnly
    case screenOnly
    case pictureInPicture
    case sideBySide

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .cameraOnly: "Camera"
        case .screenOnly: "Screen"
        case .pictureInPicture: "Screen + camera"
        case .sideBySide: "Side by side"
        }
    }
}

public struct CanvasSize: Sendable, Hashable {
    public var width: Double
    public var height: Double

    public init(width: Double, height: Double) {
        self.width = width
        self.height = height
    }

    public static let fullHD = CanvasSize(width: 1920, height: 1080)
}

/// A rectangle in canvas pixels, top-left origin.
public struct Frame: Sendable, Hashable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    public var maxX: Double { x + width }
    public var maxY: Double { y + height }
}

/// Where a source is drawn. Placements are ordered back to front.
public struct Placement: Sendable, Hashable {
    public var source: VideoSource
    public var frame: Frame

    public init(source: VideoSource, frame: Frame) {
        self.source = source
        self.frame = frame
    }
}
