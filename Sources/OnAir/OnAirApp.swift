import OnAirCore
import SwiftUI

@main
struct OnAirApp: App {
    @State private var engine: HaishinKitEngine
    @State private var controller: SessionController

    init() {
        let engine = HaishinKitEngine(canvas: .fullHD)
        let controller = SessionController(engine: engine, keyStore: KeychainStreamKeyStore(), canvas: .fullHD)
        engine.onError = { [weak controller] message in controller?.errorMessage = message }
        _engine = State(initialValue: engine)
        _controller = State(initialValue: controller)
    }

    var body: some Scene {
        Window("OnAir", id: "studio") {
            StudioView(controller: controller, engine: engine)
                .frame(minWidth: 960, minHeight: 760)
        }
        .windowResizability(.contentMinSize)
    }
}
