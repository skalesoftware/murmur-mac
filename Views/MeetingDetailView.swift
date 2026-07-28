import SwiftUI

/// Granola-style document view for a saved meeting.
/// Shows AI-generated notes as the primary content, with the transcript
/// and raw notes in collapsible sections below.
struct MeetingDetailView: View {
    @Environment(RecordingController.self) private var controller
    @Bindable var meeting: Meeting
    @State private var showTranscript = false
    @State private var showRawNotes = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                documentHeader
                Divider().padding(.horizontal, 40)
                notesBody
                transcriptSection
                rawNotesSection
            }
        }
        .toolbar { toolbarItems }
    }

    // MARK: - Header

    private var documentHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Title", text: $meeting.title)
                .textFieldStyle(.plain)
                .font(.system(size: 28, weight: .bold, design: .default))

            HStack(spacing: 6) {
                Text(meeting.startedAt, format: .dateTime.weekday(.wide).month(.wide).day().year())
                Text("·")
                Text(meeting.formattedDuration)
                if controller.isBusy {
                    Divider().frame(height: 12)
                    processingLabel
                }
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 40)
        .padding(.top, 36)
        .padding(.bottom, 24)
    }

    @ViewBuilder private var processingLabel: some View {
        switch controller.phase {
        case .transcribing:
            Label("Transcribing…", systemImage: "waveform")
        case .enhancing:
            Label("Writing notes…", systemImage: "sparkles")
        default:
            EmptyView()
        }
    }

    // MARK: - Notes body

    @ViewBuilder private var notesBody: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !meeting.enhancedNotes.isEmpty {
                renderedNotes
            } else if controller.isBusy {
                ProgressView()
                    .padding(.vertical, 48)
                    .frame(maxWidth: .infinity)
            } else {
                emptyNotesState
            }
        }
        .padding(.horizontal, 40)
        .padding(.top, 28)
        .padding(.bottom, 32)
    }

    private var renderedNotes: some View {
        Group {
            if let attributed = try? AttributedString(
                markdown: meeting.enhancedNotes,
                options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
            ) {
                Text(attributed)
                    .textSelection(.enabled)
                    .font(.body)
                    .lineSpacing(4)
            } else {
                Text(meeting.enhancedNotes)
                    .textSelection(.enabled)
                    .font(.body)
                    .lineSpacing(4)
            }
        }
    }

    private var emptyNotesState: some View {
        VStack(spacing: 16) {
            Image(systemName: "sparkles")
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(.tertiary)
            VStack(spacing: 6) {
                Text("No notes generated")
                    .font(.headline)
                Text("Make sure Ollama is running (`ollama serve`), then hit Re-generate.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            Button("Re-generate") {
                Task { await controller.regenerate(meeting) }
            }
            .buttonStyle(.borderedProminent)
            .disabled(meeting.transcript.isEmpty)
        }
        .frame(maxWidth: 380)
        .padding(.vertical, 32)
        .frame(maxWidth: .infinity)
    }

    // MARK: - Transcript section

    @ViewBuilder private var transcriptSection: some View {
        if !meeting.transcript.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                Divider()
                DisclosureGroup(isExpanded: $showTranscript) {
                    transcriptContent
                } label: {
                    Label("Transcript", systemImage: "text.bubble")
                        .font(.headline)
                        .padding(.vertical, 14)
                }
                .padding(.horizontal, 40)
            }
        }
    }

    private var transcriptContent: some View {
        let lines = meeting.transcript.components(separatedBy: "\n").filter { !$0.isEmpty }
        return VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                transcriptLine(line)
            }
        }
        .padding(.top, 4)
        .padding(.bottom, 24)
    }

    private func transcriptLine(_ line: String) -> some View {
        let isYou = line.hasPrefix("You:")
        return HStack(alignment: .top, spacing: 10) {
            Text(isYou ? "You" : "Them")
                .font(.caption.weight(.semibold))
                .foregroundStyle(isYou ? Color.accentColor : .secondary)
                .frame(width: 36, alignment: .trailing)
                .padding(.top, 1)
            Text(line.dropFirst(isYou ? 4 : 5).trimmingCharacters(in: .whitespaces))
                .font(.callout)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Raw notes section

    @ViewBuilder private var rawNotesSection: some View {
        if !meeting.rawNotes.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                Divider()
                DisclosureGroup(isExpanded: $showRawNotes) {
                    TextEditor(text: $meeting.rawNotes)
                        .font(.body)
                        .frame(minHeight: 120)
                        .scrollContentBackground(.hidden)
                        .padding(.vertical, 8)
                } label: {
                    Label("Your original notes", systemImage: "pencil")
                        .font(.headline)
                        .padding(.vertical, 14)
                }
                .padding(.horizontal, 40)
                .padding(.bottom, 40)
            }
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder private var toolbarItems: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            Button {
                Task { await controller.regenerate(meeting) }
            } label: {
                Label("Re-generate", systemImage: "sparkles")
            }
            .disabled(controller.isBusy || meeting.transcript.isEmpty)

            Button(role: .destructive) {
                controller.delete(meeting)
            } label: {
                Label("Delete", systemImage: "trash")
            }
            .disabled(controller.isBusy)
        }
    }
}
