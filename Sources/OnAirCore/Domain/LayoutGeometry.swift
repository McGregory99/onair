/// Pure layout math: which sources are visible for a layout and where they go.
/// Sources missing from the result are hidden.
public enum LayoutGeometry {
    static let aspectRatio = 16.0 / 9.0
    /// Picture-in-picture camera width as a fraction of the canvas width.
    static let pipWidthFraction = 0.25
    /// Picture-in-picture margin as a fraction of the canvas height (rounded to whole pixels).
    static let pipMarginFraction = 0.04

    public static func placements(for layout: Layout, canvas: CanvasSize) -> [Placement] {
        let full = Frame(x: 0, y: 0, width: canvas.width, height: canvas.height)
        switch layout {
        case .cameraOnly:
            return [Placement(source: .camera, frame: full)]
        case .screenOnly:
            return [Placement(source: .screen, frame: full)]
        case .pictureInPicture:
            return [
                Placement(source: .screen, frame: full),
                Placement(source: .camera, frame: pipFrame(canvas: canvas)),
            ]
        case .sideBySide:
            let left = Frame(x: 0, y: 0, width: canvas.width / 2, height: canvas.height)
            let right = Frame(x: canvas.width / 2, y: 0, width: canvas.width / 2, height: canvas.height)
            return [
                Placement(source: .screen, frame: fit(in: left)),
                Placement(source: .camera, frame: fit(in: right)),
            ]
        }
    }

    private static func pipFrame(canvas: CanvasSize) -> Frame {
        let width = canvas.width * pipWidthFraction
        let height = width / aspectRatio
        let margin = (canvas.height * pipMarginFraction).rounded()
        return Frame(x: canvas.width - width - margin, y: canvas.height - height - margin, width: width, height: height)
    }

    /// Largest 16:9 frame centered inside `box`.
    private static func fit(in box: Frame) -> Frame {
        var width = box.width
        var height = width / aspectRatio
        if height > box.height {
            height = box.height
            width = height * aspectRatio
        }
        return Frame(x: box.x + (box.width - width) / 2, y: box.y + (box.height - height) / 2, width: width, height: height)
    }
}
