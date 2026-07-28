import SwiftUI

/// Detail for a saved meeting: tabs for the AI summary, the transcript, and the
/// user's raw notes.
struct MeetingDetailView: View {
    @Environment(RecordingController.self) private var controller
    @Bindable var meeting: Meeting
    @State private var tab: Tab = .summary

    enum Tab: String, CaseIterable { case summary = "Summary", transcript = "Transcript", notes = "Notes" }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Picker("", selection: $tab) {
                ForEach(Tab.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal)
            .padding(.bottom, 8)

            Divider()

            ScrollView {
                Group {
                    switch tab {
                    case .summary:    summaryView
                    case .transcript: transcriptView
                    case .notes:      notesView
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
            }
        }
        .navigationTitle(meeting.title)
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading) {
                Text(meeting.title).font(.title2.bold())
                Text(meeting.startedAt, format: .dateTime.month().day().year().hour().minute())
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                Task { await controller.regenerate(meeting) }
            } label: {
                Label("Re-generate", systemImage: "sparkles")
            }
            .disabled(controller.isBusy || meeting.transcript.isEmpty)
        }
        .padding()
    }

    @ViewBuilder private var summaryView: some View {
        if meeting.enhancedNotes.isEmpty {
            ContentUnavailableView("No summary yet", systemImage: "sparkles",
                                   description: Text("Run Re-generate once Ollama is running."))
        } else if let attributed = try? AttributedString(
            markdown: meeting.enhancedNotes,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        ) {
            Text(attributed).textSelection(.enabled)
        } else {
            Text(meeting.enhancedNotes).textSelection(.enabled)
        }
    }

    @ViewBuilder private var transcriptView: some View {
        if meeting.transcript.isEmpty {
            ContentUnavailableView("No transcript", systemImage: "waveform")
        } else {
            Text(meeting.transcript)
                .font(.callout)
                .textSelection(.enabled)
        }
    }

    private var notesView: some View {
        TextEditor(text: $meeting.rawNotes)
            .font(.body)
            .frame(minHeight: 400)
            .scrollContentBackground(.hidden)
    }
}
