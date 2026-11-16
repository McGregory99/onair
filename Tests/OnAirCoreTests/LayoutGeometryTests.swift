import Testing
@testable import OnAirCore

@Suite("LayoutGeometry")
struct LayoutGeometryTests {
    let canvas = CanvasSize(width: 1920, height: 1080)

    @Test("camera only shows the camera full frame and hides the screen")
    func cameraOnly() {
        let placements = LayoutGeometry.placements(for: .cameraOnly, canvas: canvas)
        #expect(placements == [Placement(source: .camera, frame: Frame(x: 0, y: 0, width: 1920, height: 1080))])
    }

    @Test("screen only shows the screen full frame and hides the camera")
    func screenOnly() {
        let placements = LayoutGeometry.placements(for: .screenOnly, canvas: canvas)
        #expect(placements == [Placement(source: .screen, frame: Frame(x: 0, y: 0, width: 1920, height: 1080))])
    }

    @Test("picture-in-picture puts a 16:9 camera at a quarter width in the bottom-right corner, above the screen")
    func pictureInPicture() {
        let placements = LayoutGeometry.placements(for: .pictureInPicture, canvas: canvas)
        #expect(placements.count == 2)
        // Back-to-front order: screen first, camera drawn on top.
        #expect(placements[0] == Placement(source: .screen, frame: Frame(x: 0, y: 0, width: 1920, height: 1080)))
        #expect(placements[1].source == .camera)
        let camera = placements[1].frame
        #expect(camera.width == 480)
        #expect(camera.height == 270)
        #expect(camera.maxX < 1920)
        #expect(camera.maxY < 1080)
        // Same margin from the right and bottom edges.
        #expect(1920 - camera.maxX == 1080 - camera.maxY)
    }

    @Test("side by side splits the canvas: screen left, camera right, both 16:9 and vertically centered")
    func sideBySide() {
        let placements = LayoutGeometry.placements(for: .sideBySide, canvas: canvas)
        #expect(placements == [
            Placement(source: .screen, frame: Frame(x: 0, y: 270, width: 960, height: 540)),
            Placement(source: .camera, frame: Frame(x: 960, y: 270, width: 960, height: 540)),
        ])
    }

    @Test("every layout keeps all frames inside the canvas", arguments: StreamLayout.allCases)
    func framesInsideCanvas(layout: StreamLayout) {
        for placement in LayoutGeometry.placements(for: layout, canvas: canvas) {
            #expect(placement.frame.x >= 0 && placement.frame.y >= 0)
            #expect(placement.frame.maxX <= canvas.width && placement.frame.maxY <= canvas.height)
        }
    }

    @Test("geometry scales with the canvas size")
    func scalesWithCanvas() {
        let small = CanvasSize(width: 1280, height: 720)
        let placements = LayoutGeometry.placements(for: .sideBySide, canvas: small)
        #expect(placements[1].frame == Frame(x: 640, y: 180, width: 640, height: 360))
    }

    @Test("all four layouts are offered, in button order")
    func layoutOrder() {
        #expect(StreamLayout.allCases == [.cameraOnly, .screenOnly, .pictureInPicture, .sideBySide])
    }
}
