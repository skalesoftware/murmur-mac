import SwiftUI

/// The main view while a meeting is being captured.
/// Left column: live screen-capture preview + audio level meters.
/// Right column: freeform notes editor.
struct LiveRecordingView: View {
    @Environment(RecordingController.self) private var controller

    var body: some View {
        @Bindable var controller = controller
        VStack(spacing: 0) {
            // ── Header ────────────────────────────────────────────────────────
            HStack(alignment: .center, spacing: 12) {
                TextField("Meeting title", text: $controller.liveTitle)
                    .textFieldStyle(.plain)
                    .font(.title2.bold())
                Spacer()
                recordingBadge
                Button {
                    Task { await controller.stopRecording() }
                } label: {
                    Text("Stop")
                        .fontWeight(.semibold)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 5)
                        .background(.red, in: Capsule())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .background(.windowBackground)

            Divider()

            // ── Body ──────────────────────────────────────────────────────────
            HStack(spacing: 0) {
                // Left: video + levels
                VStack(spacing: 16) {
                    // Screen-capture preview
                    VideoPreviewView(frame: controller.latestVideoFrame)
                        .aspectRatio(16 / 9, contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .overlay {
                            RoundedRectangle(cornerRadius: 10)
                                .strokeBorder(.quaternary, lineWidth: 0.5)
                        }
                        .shadow(color: .black.opacity(0.15), radius: 6, y: 3)
                        .frame(maxWidth: .infinity)

                    // Audio levels
                    VStack(spacing: 10) {
                        AudioLevelView(
                            level: controller.micLevel,
                            color: .green,
                            icon: "mic.fill",
                            label: "Mic")
                        AudioLevelView(
                            level: controller.systemLevel,
                            color: .blue,
                            icon: "speaker.wave.2.fill",
                            label: "System")
                    }
                    .padding(.horizontal, 4)

                    Spacer()
                }
                .padding(18)
                .frame(width: 360)

                Divider()

                // Right: notes
                VStack(alignment: .leading, spacing: 0) {
                    Text("Notes")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 18)
                        .padding(.top, 18)
                        .padding(.bottom, 8)

                    TextEditor(text: $controller.liveNotes)
                        .font(.body)
                        .lineSpacing(3)
                        .scrollContentBackground(.hidden)
                        .padding(.horizontal, 14)
                        .overlay(alignment: .topLeading) {
                            if controller.liveNotes.isEmpty {
                                Text("Jot anything that matters — the rest gets filled in from the transcript when you stop.")
                                    .font(.body)
                                    .foregroundStyle(.tertiary)
                                    .padding(.horizontal, 18)
                                    .padding(.vertical, 4)
                                    .allowsHitTesting(false)
                            }
                        }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(maxHeight: .infinity)
        }
    }

    private var recordingBadge: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(.red)
                .frame(width: 7, height: 7)
            Text(timeString)
                .font(.system(.callout, design: .monospaced).weight(.medium))
                .foregroundStyle(.red)
        }
    }

    private var timeString: String {
        let t = Int(controller.elapsed)
        return String(format: "%d:%02d", t / 60, t % 60)
    }
}
