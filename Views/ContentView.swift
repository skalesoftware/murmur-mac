import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(RecordingController.self) private var controller
    @Query(sort: \Meeting.startedAt, order: .reverse) private var meetings: [Meeting]

    var body: some View {
        @Bindable var controller = controller
        NavigationSplitView {
            SidebarView(meetings: meetings)
                .navigationSplitViewColumnWidth(min: 220, ideal: 248)
        } detail: {
            switch controller.phase {
            case .recording, .transcribing, .enhancing:
                LiveRecordingView()
            case .idle, .error:
                if let meeting = controller.selectedMeeting {
                    MeetingDetailView(meeting: meeting)
                } else {
                    emptyState
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "waveform.and.mic")
                .font(.system(size: 48, weight: .ultraLight))
                .foregroundStyle(.tertiary)
            Text("No meeting selected")
                .font(.title3.weight(.medium))
            Text("Hit Record to start capturing, or pick a past meeting.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: 320)
    }
}

// MARK: - Sidebar

private struct SidebarView: View {
    @Environment(RecordingController.self) private var controller
    let meetings: [Meeting]

    var body: some View {
        @Bindable var controller = controller
        VStack(spacing: 0) {
            List(meetings, selection: $controller.selectedMeeting) { meeting in
                MeetingRow(meeting: meeting)
                    .tag(meeting)
                    .contextMenu {
                        Button("Delete", role: .destructive) { controller.delete(meeting) }
                    }
            }
            .listStyle(.sidebar)

            Divider()
            RecordBar()
        }
        .navigationTitle("Murmur")
    }
}

private struct MeetingRow: View {
    let meeting: Meeting

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(meeting.title)
                .font(.subheadline.weight(.medium))
                .lineLimit(1)
            HStack(spacing: 4) {
                Text(meeting.startedAt, format: .dateTime.month(.abbreviated).day().hour().minute())
                Text("·")
                Text(meeting.formattedDuration)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 3)
    }
}

// MARK: - Record bar

struct RecordBar: View {
    @Environment(RecordingController.self) private var controller

    var body: some View {
        VStack(spacing: 6) {
            Button {
                Task {
                    if controller.isRecording { await controller.stopRecording() }
                    else { await controller.startRecording() }
                }
            } label: {
                Label(
                    controller.isRecording ? "Stop recording" : "Record",
                    systemImage: controller.isRecording ? "stop.circle.fill" : "record.circle"
                )
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(controller.isRecording ? .red : .accentColor)
            .disabled(controller.isBusy)

            statusLine
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    @ViewBuilder private var statusLine: some View {
        switch controller.phase {
        case .recording:
            Label(timeString, systemImage: "record.circle.fill")
                .foregroundStyle(.red)
                .font(.caption.monospacedDigit())
        case .transcribing:
            Label("Transcribing…", systemImage: "waveform")
                .font(.caption).foregroundStyle(.secondary)
        case .enhancing:
            Label("Writing notes…", systemImage: "sparkles")
                .font(.caption).foregroundStyle(.secondary)
        case .error(let msg):
            Label(msg, systemImage: "exclamationmark.triangle")
                .font(.caption).foregroundStyle(.orange).lineLimit(3)
        case .idle:
            Color.clear.frame(height: 16)
        }
    }

    private var timeString: String {
        let t = Int(controller.elapsed)
        return String(format: "%d:%02d", t / 60, t % 60)
    }
}
