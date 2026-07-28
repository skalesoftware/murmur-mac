import Foundation
import SwiftData
import Observation
import CoreMedia

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
    var liveNotes: String = ""
    var liveTitle: String = "Untitled meeting"
    var selectedMeeting: Meeting?
    var ollamaModel: String = "llama3.1:8b"

    // Live A/V feedback during recording
    var micLevel: Float = 0
    var systemLevel: Float = 0
    var latestVideoFrame: CMSampleBuffer?

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

    init(context: ModelContext) { self.context = context }

    // MARK: - Recording lifecycle

    func startRecording() async {
        guard phase == .idle || isErrorPhase else { return }

        guard await MicrophoneCapturer.requestPermission() else {
            phase = .error("Microphone access denied. Enable it in System Settings › Privacy & Security › Microphone.")
            return
        }

        meetingID = UUID()
        startDate = .now
        elapsed = 0
        liveNotes = ""
        liveTitle = "Meeting \(Self.dateFormatter.string(from: startDate))"
        micLevel = 0
        systemLevel = 0
        latestVideoFrame = nil

        // Wire audio-level and video-frame callbacks before starting capture.
        mic.levelHandler = { @Sendable [weak self] level in
            Task { @MainActor [weak self] in self?.micLevel = level }
        }
        system.levelHandler = { @Sendable [weak self] level in
            Task { @MainActor [weak self] in self?.systemLevel = level }
        }
        system.videoFrameHandler = { @Sendable [weak self] frame in
            Task { @MainActor [weak self] in self?.latestVideoFrame = frame }
        }

        do {
            let folder = try meetingFolder(for: meetingID)
            let mURL = folder.appendingPathComponent("mic.wav")
            let sURL = folder.appendingPathComponent("system.wav")
            micURL = mURL
            systemURL = sURL

            try mic.start(writer: AudioFileWriter(url: mURL, label: "mic"))
            try await system.start(writer: AudioFileWriter(url: sURL, label: "system"))

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
        micLevel = 0
        systemLevel = 0

        let duration = elapsed
        let notes = liveNotes
        let title = liveTitle
        guard let micURL, let systemURL else { phase = .idle; return }

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

        phase = .transcribing
        do {
            let segments = try await transcriber.mergedTranscript(micURL: micURL, systemURL: systemURL)
            meeting.transcript = TranscriptionManager.format(segments)
            try? context.save()

            phase = .enhancing
            enhancer.updateModel(ollamaModel)
            if await enhancer.isReachable() {
                meeting.enhancedNotes = try await enhancer.enhance(
                    rawNotes: notes, transcript: meeting.transcript)
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

    func regenerate(_ meeting: Meeting) async {
        phase = .enhancing
        enhancer.updateModel(ollamaModel)
        do {
            guard await enhancer.isReachable() else {
                phase = .error("Ollama not reachable on localhost:11434.")
                return
            }
            meeting.enhancedNotes = try await enhancer.enhance(
                rawNotes: meeting.rawNotes, transcript: meeting.transcript)
            try? context.save()
            phase = .idle
        } catch {
            phase = .error("Enhancement failed: \(error.localizedDescription)")
        }
    }

    func delete(_ meeting: Meeting) {
        if let name = meeting.audioFolderName {
            try? FileManager.default.removeItem(at: Self.supportRoot.appendingPathComponent(name))
        }
        if selectedMeeting?.id == meeting.id { selectedMeeting = nil }
        context.delete(meeting)
        try? context.save()
    }

    // MARK: - Helpers

    private var isErrorPhase: Bool {
        if case .error = phase { return true } else { return false }
    }

    private func startTimer() {
        timerTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                guard let self, self.phase == .recording else { break }
                self.elapsed += 1
            }
        }
    }

    private func stopTimer() { timerTask?.cancel(); timerTask = nil }

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
