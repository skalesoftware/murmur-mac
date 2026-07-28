import Foundation
import SwiftData
import Observation

/// The single source of truth for recording state and the orchestrator of the
/// capture -> transcribe -> enhance -> persist pipeline.
@MainActor
@Observable
final class RecordingController {

    enum Phase: Equatable {
        case idle
        case recording
        case transcribing
        case enhancing
        case error(String)
    }

    // MARK: Observable state
    var phase: Phase = .idle
    var elapsed: TimeInterval = 0
    /// Live notes the user types while recording.
    var liveNotes: String = ""
    var liveTitle: String = "Untitled meeting"
    /// The meeting currently selected in the UI (nil = none).
    var selectedMeeting: Meeting?
    /// Ollama model to use for enhancement.
    var ollamaModel: String = "llama3.1:8b"

    var isRecording: Bool { phase == .recording }
    var isBusy: Bool { phase == .transcribing || phase == .enhancing }

    // MARK: Collaborators
    private let context: ModelContext
    private let mic = MicrophoneCapturer()
    private let system: SystemAudioCapturer = ScreenCaptureAudioCapturer()
    private let transcriber = TranscriptionManager()
    private let enhancer = OllamaClient()

    // MARK: Per-recording state
    private var meetingID = UUID()
    private var startDate = Date.now
    private var timerTask: Task<Void, Never>?
    private var micURL: URL?
    private var systemURL: URL?

    init(context: ModelContext) {
        self.context = context
    }

    // MARK: - Recording lifecycle

    func startRecording() async {
        guard phase == .idle || isErrorPhase else { return }

        // Permissions.
        guard await MicrophoneCapturer.requestPermission() else {
            phase = .error("Microphone access denied. Enable it in System Settings › Privacy & Security › Microphone.")
            return
        }

        meetingID = UUID()
        startDate = .now
        elapsed = 0
        liveNotes = ""
        liveTitle = "Meeting \(Self.dateFormatter.string(from: startDate))"

        do {
            let folder = try meetingFolder(for: meetingID)
            let micURL = folder.appendingPathComponent("mic.wav")
            let systemURL = folder.appendingPathComponent("system.wav")
            self.micURL = micURL
            self.systemURL = systemURL

            let micWriter = AudioFileWriter(url: micURL, label: "mic")
            let systemWriter = AudioFileWriter(url: systemURL, label: "system")

            try mic.start(writer: micWriter)
            // ScreenCaptureKit prompts for Screen Recording permission here on first run.
            try await system.start(writer: systemWriter)

            phase = .recording
            startTimer()
        } catch {
            mic.stop()
            system.stop()
            phase = .error("Couldn't start capture: \(error.localizedDescription)")
        }
    }

    func stopRecording() async {
        guard phase == .recording else { return }
        stopTimer()
        mic.stop()
        system.stop()

        let duration = elapsed
        let notes = liveNotes
        let title = liveTitle
        guard let micURL, let systemURL else { phase = .idle; return }

        // Create + persist the meeting shell immediately so it appears in the list.
        let meeting = Meeting(
            id: meetingID,
            title: title,
            startedAt: startDate,
            duration: duration,
            rawNotes: notes,
            audioFolderName: meetingID.uuidString
        )
        context.insert(meeting)
        try? context.save()
        selectedMeeting = meeting

        // Transcribe.
        phase = .transcribing
        do {
            let segments = try await transcriber.mergedTranscript(micURL: micURL, systemURL: systemURL)
            meeting.transcript = TranscriptionManager.format(segments)
            try? context.save()

            // Enhance (best-effort — a missing Ollama shouldn't lose the transcript).
            phase = .enhancing
            enhancer.updateModel(ollamaModel)
            if await enhancer.isReachable() {
                meeting.enhancedNotes = try await enhancer.enhance(
                    rawNotes: notes, transcript: meeting.transcript
                )
            } else {
                meeting.enhancedNotes = "_Ollama not reachable on localhost:11434. Start it (`ollama serve`) and click Re-generate._"
            }
            try? context.save()
            phase = .idle
        } catch {
            try? context.save()
            phase = .error("Transcription/enhancement failed: \(error.localizedDescription)")
        }
    }

    /// Re-run enhancement for an existing meeting (e.g. after starting Ollama or
    /// editing raw notes).
    func regenerate(_ meeting: Meeting) async {
        phase = .enhancing
        enhancer.updateModel(ollamaModel)
        do {
            guard await enhancer.isReachable() else {
                phase = .error("Ollama not reachable on localhost:11434.")
                return
            }
            meeting.enhancedNotes = try await enhancer.enhance(
                rawNotes: meeting.rawNotes, transcript: meeting.transcript
            )
            try? context.save()
            phase = .idle
        } catch {
            phase = .error("Enhancement failed: \(error.localizedDescription)")
        }
    }

    func delete(_ meeting: Meeting) {
        if let name = meeting.audioFolderName {
            let folder = Self.supportRoot.appendingPathComponent(name)
            try? FileManager.default.removeItem(at: folder)
        }
        if selectedMeeting?.id == meeting.id { selectedMeeting = nil }
        context.delete(meeting)
        try? context.save()
    }

    // MARK: - Helpers

    private var isErrorPhase: Bool { if case .error = phase { return true } else { return false } }

    private func startTimer() {
        timerTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                guard let self, self.phase == .recording else { break }
                self.elapsed += 1
            }
        }
    }

    private func stopTimer() {
        timerTask?.cancel()
        timerTask = nil
    }

    private static let supportRoot: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("Murmur", isDirectory: true)
    }()

    private func meetingFolder(for id: UUID) throws -> URL {
        let folder = Self.supportRoot.appendingPathComponent(id.uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM d, h:mm a"
        return f
    }()
}
