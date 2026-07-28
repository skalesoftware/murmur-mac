import SwiftUI
import AppKit

/// The compact control shown from the menu-bar icon.
struct MenuBarView: View {
    @Environment(RecordingController.self) private var controller
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Murmur").font(.headline)

            switch controller.phase {
            case .recording:
                Label("Recording · \(timeString)", systemImage: "record.circle.fill")
                    .foregroundStyle(.red).font(.callout.monospacedDigit())
            case .transcribing:
                Label("Transcribing…", systemImage: "waveform").foregroundStyle(.secondary)
            case .enhancing:
                Label("Writing notes…", systemImage: "sparkles").foregroundStyle(.secondary)
            case .error(let msg):
                Label(msg, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange).font(.caption).lineLimit(3)
            case .idle:
                Text("Ready").foregroundStyle(.secondary).font(.callout)
            }

            Button {
                Task {
                    if controller.isRecording { await controller.stopRecording() }
                    else { await controller.startRecording() }
                }
            } label: {
                Label(controller.isRecording ? "Stop recording" : "Start recording",
                      systemImage: controller.isRecording ? "stop.circle.fill" : "record.circle")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(controller.isRecording ? .red : .accentColor)
            .disabled(controller.isBusy)

            Divider()

            Button("Open Murmur") {
                openWindow(id: "main")
                NSApp.activate(ignoringOtherApps: true)
            }
            Button("Quit") { NSApp.terminate(nil) }
        }
        .padding(12)
        .frame(width: 260)
    }

    private var timeString: String {
        let t = Int(controller.elapsed)
        return String(format: "%d:%02d", t / 60, t % 60)
    }
}
