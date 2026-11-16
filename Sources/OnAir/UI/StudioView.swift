import HaishinKit
import OnAirCore
import SwiftUI

/// The single studio window: preview, layouts, sources and the go-live controls.
struct StudioView: View {
    @Bindable var controller: SessionController
    @Bindable var engine: HaishinKitEngine

    var body: some View {
        VStack(spacing: 16) {
            preview
            LayoutBar(controller: controller)
            HStack(alignment: .top, spacing: 24) {
                SourcesPanel(engine: engine, isEnabled: controller.state.showsPreview)
                Divider()
                BroadcastPanel(controller: controller, engine: engine)
            }
            .frame(maxHeight: 130)
            if let message = visibleMessage {
                MessageBanner(message: message, showsBackButton: canGoBack) {
                    controller.backToRehearsal()
                }
            }
        }
        .padding(20)
        .task { await controller.startRehearsal() }
    }

    private var preview: some View {
        ZStack(alignment: .topLeading) {
            Rectangle().fill(.black)
            if controller.state != .idle {
                MTHKViewRepresentable(previewSource: engine)
            } else {
                VStack(spacing: 12) {
                    Text("Preview is off").foregroundStyle(.secondary)
                    Button("Start rehearsal") { Task { await controller.startRehearsal() } }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            StatusBadge(state: controller.state).padding(12)
        }
        .aspectRatio(16 / 9, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var visibleMessage: String? {
        if case .failed(let reason) = controller.state { return reason }
        if controller.state == .ended { return controller.errorMessage ?? "The stream has ended." }
        return controller.errorMessage
    }

    private var canGoBack: Bool {
        if case .failed = controller.state { return true }
        return controller.state == .ended
    }
}

private struct LayoutBar: View {
    let controller: SessionController

    var body: some View {
        HStack(spacing: 8) {
            ForEach(StreamLayout.allCases) { layout in
                Button {
                    Task { await controller.select(layout) }
                } label: {
                    Label(layout.title, systemImage: layout.symbol)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.bordered)
                .tint(controller.layout == layout ? .accentColor : .secondary)
                .disabled(!controller.state.showsPreview)
            }
        }
    }
}

private struct SourcesPanel: View {
    @Bindable var engine: HaishinKitEngine
    let isEnabled: Bool

    var body: some View {
        Form {
            Picker("Camera", selection: Binding(
                get: { engine.cameraID ?? "" },
                set: { id in Task { await engine.selectCamera(id: id) } }
            )) {
                ForEach(engine.cameras, id: \.uniqueID) { Text($0.localizedName).tag($0.uniqueID) }
            }
            Picker("Microphone", selection: Binding(
                get: { engine.microphoneID ?? "" },
                set: { id in Task { await engine.selectMicrophone(id: id) } }
            )) {
                ForEach(engine.microphones, id: \.uniqueID) { Text($0.localizedName).tag($0.uniqueID) }
            }
            LabeledContent("Screen + system audio") {
                HStack {
                    Button(engine.isSharingScreen ? "Change…" : "Share screen…") { engine.chooseScreen() }
                    if engine.isSharingScreen {
                        Button("Stop") { Task { await engine.stopSharingScreen() } }
                    }
                }
            }
        }
        .disabled(!isEnabled)
        .frame(maxWidth: 420)
    }
}

private struct BroadcastPanel: View {
    @Bindable var controller: SessionController
    @Bindable var engine: HaishinKitEngine

    var body: some View {
        Form {
            Group {
                SecureField("YouTube stream key", text: $controller.streamKey)
                Picker("Quality", selection: $engine.videoBitRate) {
                    Text("1080p · 4.5 Mbps (slow upload)").tag(4_500_000)
                    Text("1080p · 6 Mbps").tag(6_000_000)
                    Text("1080p · 8 Mbps (fast upload)").tag(8_000_000)
                }
            }
            .disabled(controller.state.locksSettings)
            HStack {
                Spacer()
                goLiveButton
            }
        }
    }

    @ViewBuilder
    private var goLiveButton: some View {
        switch controller.state {
        case .live:
            Button("End stream", role: .destructive) { Task { await controller.endStream() } }
                .buttonStyle(.borderedProminent).tint(.red).controlSize(.large)
        case .connecting:
            Button("Cancel") { Task { await controller.endStream() } }
                .controlSize(.large)
        default:
            Button("Go live") { Task { await controller.goLive() } }
                .buttonStyle(.borderedProminent).controlSize(.large)
                .disabled(controller.state != .rehearsing)
        }
    }
}

private struct StatusBadge: View {
    let state: SessionState

    var body: some View {
        if let (text, color) = label {
            Text(text)
                .font(.caption.bold())
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(color, in: Capsule())
                .foregroundStyle(.white)
        }
    }

    private var label: (String, Color)? {
        switch state {
        case .rehearsing: ("REHEARSAL", .gray)
        case .connecting: ("CONNECTING…", .orange)
        case .live: ("● LIVE", .red)
        case .ended: ("ENDED", .gray)
        case .failed: ("OFF AIR", .gray)
        case .idle: nil
        }
    }
}

private struct MessageBanner: View {
    let message: String
    let showsBackButton: Bool
    let onBack: () -> Void

    var body: some View {
        HStack {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            Text(message).textSelection(.enabled)
            Spacer()
            if showsBackButton {
                Button("Back to rehearsal", action: onBack)
            }
        }
        .padding(10)
        .background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
    }
}

private extension StreamLayout {
    var symbol: String {
        switch self {
        case .cameraOnly: "person.crop.rectangle"
        case .screenOnly: "display"
        case .pictureInPicture: "pip"
        case .sideBySide: "rectangle.split.2x1"
        }
    }
}
