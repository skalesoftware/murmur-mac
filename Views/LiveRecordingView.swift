import SwiftUI

/// Shown while a meeting is being recorded: a big notepad the user types into,
/// plus a running timer. These notes feed the LLM after the call.
struct LiveRecordingView: View {
    @Environment(RecordingController.self) private var controller

    var body: some View {
        @Bindable var controller = controller
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                TextField("Meeting title", text: $controller.liveTitle)
                    .textFieldStyle(.plain)
                    .font(.title2.bold())
                Spacer()
                Label(timeString, systemImage: "record.circle.fill")
                    .foregroundStyle(.red)
                    .font(.body.monospacedDigit())
            }

            Text("Your notes")
                .font(.caption).foregroundStyle(.secondary)

            TextEditor(text: $controller.liveNotes)
                .font(.body)
                .scrollContentBackground(.hidden)
                .padding(8)
                .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 8))
                .overlay(alignment: .topLeading) {
                    if controller.liveNotes.isEmpty {
                        Text("Jot down whatever matters — the rest gets filled in from the transcript when you stop.")
                            .foregroundStyle(.tertiary)
                            .padding(14)
                            .allowsHitTesting(false)
                    }
                }
        }
        .padding()
        .navigationTitle("Recording")
    }

    private var timeString: String {
        let t = Int(controller.elapsed)
        return String(format: "%d:%02d", t / 60, t % 60)
    }
}
