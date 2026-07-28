import Foundation
import SwiftData

/// A single recorded meeting: raw notes the user typed, the merged transcript,
/// and the AI-enhanced summary. Persisted locally via SwiftData.
@Model
final class Meeting {
    var id: UUID
    var title: String
    var startedAt: Date
    /// Duration in seconds.
    var duration: TimeInterval
    /// Sparse notes the user typed during the call.
    var rawNotes: String
    /// Full "You / Them" transcript, merged by timestamp.
    var transcript: String
    /// LLM-polished notes (summary, decisions, action items).
    var enhancedNotes: String
    /// Folder (under Application Support) holding this meeting's WAV files, if kept.
    var audioFolderName: String?

    init(
        id: UUID = UUID(),
        title: String = "Untitled meeting",
        startedAt: Date = .now,
        duration: TimeInterval = 0,
        rawNotes: String = "",
        transcript: String = "",
        enhancedNotes: String = "",
        audioFolderName: String? = nil
    ) {
        self.id = id
        self.title = title
        self.startedAt = startedAt
        self.duration = duration
        self.rawNotes = rawNotes
        self.transcript = transcript
        self.enhancedNotes = enhancedNotes
        self.audioFolderName = audioFolderName
    }
}

extension Meeting {
    var formattedDuration: String {
        let total = Int(duration)
        let m = total / 60, s = total % 60
        return String(format: "%d:%02d", m, s)
    }
}

/// A single transcribed utterance from one speaker source, with timing.
struct TranscriptSegment: Identifiable, Sendable {
    enum Speaker: String, Sendable { case you = "You", them = "Them" }
    let id = UUID()
    let speaker: Speaker
    let start: Double   // seconds from recording start
    let end: Double
    let text: String
}
