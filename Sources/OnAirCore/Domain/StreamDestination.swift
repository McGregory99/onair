import Foundation

/// An RTMP(S) ingest endpoint. The output layer takes a list of these so that
/// multistreaming is an additive change later.
public struct StreamDestination: Sendable, Hashable {
    public var url: String
    public var streamKey: String

    public init(url: String, streamKey: String) {
        self.url = url
        self.streamKey = streamKey
    }

    public static let youtubeIngestURL = "rtmps://a.rtmp.youtube.com/live2"

    public static func youtube(streamKey: String) throws(StreamDestinationError) -> StreamDestination {
        let key = streamKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { throw .missingStreamKey }
        return StreamDestination(url: youtubeIngestURL, streamKey: key)
    }
}

public enum StreamDestinationError: Error, Sendable, Equatable {
    case missingStreamKey

    public var message: String {
        switch self {
        case .missingStreamKey: "Paste your YouTube stream key before going live."
        }
    }
}
