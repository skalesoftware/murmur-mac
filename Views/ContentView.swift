import SwiftUI
import SwiftData

/// Root window: sidebar of past meetings + detail pane, with a record bar on top.
struct ContentView: View {
    @Environment(RecordingController.self) private var controller
    @Environment(\.modelContext) private var context
    @Query(sort: \Meeting.startedAt, order: .reverse) private var meetings: [Meeting]

    var body: some View {
        @Bindable var controller = controller
        NavigationSplitView {
            List(selection: $controller.selectedMeeting) {
                ForEach(meetings) { meeting in
                    MeetingRow(meeting: meeting)
                        .tag(meeting)
                        .contextMenu {
                            Button("Delete", role: .destructive) { controller.delete(meeting) }
                        }
                }
            }
            .navigationTitle("Murmur")
            .navigationSplitViewColumnWidth(min: 220, ideal: 260)
            .safeAreaInset(edge: .bottom) { RecordBar() }
        } detail: {
            if controller.isRecording {
                LiveRecordingView()
            } else if let meeting = controller.selectedMeeting {
                MeetingDetailView(meeting: meeting)
            } else {
                ContentUnavailableView(
                    "No meeting selected",
                    systemImage: "waveform",
                    description: Text("Hit Record to capture a meeting, or pick one from the list.")
                )
            }
        }
    }
}

private struct MeetingRow: View {
    let meeting: Meeting
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(meeting.title).font(.headline).lineLimit(1)
            HStack(spacing: 6) {
                Text(meeting.startedAt, format: .dateTime.month().day().hour().minute())
                Text("· \(meeting.formattedDuration)")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}

/// The record / stop control + status, pinned to the sidebar bottom.
struct RecordBar: View {
    @Environment(RecordingController.self) private var controller

    var body: some View {
        VStack(spacing: 6) {
            Divider()
            HStack {
                Button {
                    Task {
                        if controller.isRecording { await controller.stopRecording() }
                        else { await controller.startRecording() }
                    }
                } label: {
                    Label(
                        controller.isRecording ? "Stop" : "Record",
                        systemImage: controller.isRecording ? "stop.circle.fill" : "record.circle"
                    )
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(controller.isRecording ? .red : .accentColor)
                .disabled(controller.isBusy)
            }
            statusLine
        }
        .padding(8)
    }

    @ViewBuilder private var statusLine: some View {
        switch controller.phase {
        case .recording:
            Label(timeString, systemImage: "record.circle.fill")
                .foregroundStyle(.red).font(.caption.monospacedDigit())
        case .transcribing:
            Label("Transcribing…", systemImage: "waveform").font(.caption).foregroundStyle(.secondary)
        case .enhancing:
            Label("Writing notes…", systemImage: "sparkles").font(.caption).foregroundStyle(.secondary)
        case .error(let msg):
            Label(msg, systemImage: "exclamationmark.triangle")
                .font(.caption).foregroundStyle(.orange).lineLimit(3)
        case .idle:
            EmptyView()
        }
    }

    private var timeString: String {
        let t = Int(controller.elapsed)
        return String(format: "%d:%02d", t / 60, t % 60)
    }
}
