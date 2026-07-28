import Foundation

/// Turns raw notes + transcript into polished meeting notes. Abstracted so the
/// Ollama backend can be swapped for Apple Foundation Models later.
protocol NoteEnhancer {
    func enhance(rawNotes: String, transcript: String) async throws -> String
}

/// The prompt that combines the user's sparse notes with the full transcript.
enum EnhancementPrompt {
    static let system = """
    You are a meticulous meeting-notes assistant. You are given (1) the user's rough, \
    sparse notes taken during a meeting and (2) the full transcript of that meeting, \
    where "You" is the user and "Them" is everyone else. Produce clean, well-structured \
    meeting notes in Markdown with these sections, omitting any that don't apply:

    ## TL;DR
    (2-3 sentence summary)

    ## Key points
    (bulleted)

    ## Decisions
    (bulleted; what was actually decided)

    ## Action items
    (bulleted, each as "- [ ] <task> — <owner> (<due date if mentioned>)")

    ## Open questions
    (bulleted)

    Ground everything in the transcript. Use the user's notes to judge what mattered most. \
    Do not invent facts. Be concise.
    """

    static func user(rawNotes: String, transcript: String) -> String {
        """
        # User's rough notes
        \(rawNotes.isEmpty ? "(none)" : rawNotes)

        # Full transcript
        \(transcript.isEmpty ? "(empty)" : transcript)
        """
    }
}
