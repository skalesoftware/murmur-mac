import Foundation
import WhisperKit

/// Wraps WhisperKit for on-device transcription. Loads a Whisper model (downloaded
/// & cached on first use) and transcribes WAV files produced by the capturers.
actor TranscriptionManager {
    private var whisperKit: WhisperKit?
    /// In-flight load, so two concurrent callers don't both download/load the model.
    private var loadTask: Task<WhisperKit, Error>?
    private let modelName: String

    /// `openai_whisper-base.en` is a good speed/accuracy default on Apple Silicon.
    /// Use `openai_whisper-small.en` for better accuracy at some cost.
    init(modelName: String = "openai_whisper-base.en") {
        self.modelName = modelName
    }

    /// Lazily load the model exactly once. First call downloads it (~150 MB for base).
    private func loadIfNeeded() async throws -> WhisperKit {
        if let whisperKit { return whisperKit }
        if let loadTask { return try await loadTask.value }
        let name = modelName
        let task = Task { try await WhisperKit(model: name) }
        loadTask = task
        do {
            let kit = try await task.value
            whisperKit = kit
            return kit
        } catch {
            loadTask = nil   // allow a retry after a failed load
            throw error
        }
    }

    /// Transcribe one audio file, returning segments tagged with the given speaker.
    func transcribe(fileURL: URL, as speaker: TranscriptSegment.Speaker) async throws -> [TranscriptSegment] {
        let kit = try await loadIfNeeded()
        let options = DecodingOptions(
            language: "en",
            temperature: 0.0,
            temperatureFallbackCount: 3
        )
        let results = try await kit.transcribe(audioPath: fileURL.path, decodeOptions: options)

        // WhisperKit returns an array of results (chunked for long audio).
        return results.flatMap { result in
            result.segments.map { seg in
                TranscriptSegment(
                    speaker: speaker,
                    start: Double(seg.start),
                    end: Double(seg.end),
                    text: seg.text.trimmingCharacters(in: .whitespacesAndNewlines)
                )
            }
        }
        .filter { !$0.text.isEmpty }
    }

    /// Transcribe both sources and merge them into one timeline. Runs sequentially
    /// because both passes share a single WhisperKit instance.
    func mergedTranscript(micURL: URL, systemURL: URL) async throws -> [TranscriptSegment] {
        let mic = try await transcribe(fileURL: micURL, as: .you)
        let them = try await transcribe(fileURL: systemURL, as: .them)
        return (mic + them).sorted { $0.start < $1.start }
    }

    /// Render merged segments to a readable "Speaker: text" transcript.
    static func format(_ segments: [TranscriptSegment]) -> String {
        segments.map { seg in
            "\(seg.speaker.rawValue): \(seg.text)"
        }.joined(separator: "\n")
    }
}
