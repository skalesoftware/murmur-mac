import Foundation

/// Talks to a local Ollama server (default http://localhost:11434). 100% offline.
///
/// Setup:
///   brew install ollama         # or download from ollama.com
///   ollama pull llama3.1:8b
///   ollama serve                # usually already running as a login item
final class OllamaClient: NoteEnhancer {
    struct Config {
        var baseURL = URL(string: "http://localhost:11434")!
        var model = "llama3.1:8b"
    }

    private var config: Config
    private let session: URLSession

    init(config: Config = Config()) {
        self.config = config
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest = 300   // local LLMs can be slow on first token
        self.session = URLSession(configuration: cfg)
    }

    func updateModel(_ model: String) { config.model = model }

    /// True if an Ollama server answers on the configured host.
    func isReachable() async -> Bool {
        var req = URLRequest(url: config.baseURL.appendingPathComponent("api/tags"))
        req.timeoutInterval = 3
        do {
            let (_, resp) = try await session.data(for: req)
            return (resp as? HTTPURLResponse)?.statusCode == 200
        } catch {
            return false
        }
    }

    // MARK: NoteEnhancer

    func enhance(rawNotes: String, transcript: String) async throws -> String {
        let body = ChatRequest(
            model: config.model,
            stream: false,
            messages: [
                .init(role: "system", content: EnhancementPrompt.system),
                .init(role: "user", content: EnhancementPrompt.user(rawNotes: rawNotes, transcript: transcript))
            ]
        )

        var req = URLRequest(url: config.baseURL.appendingPathComponent("api/chat"))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONEncoder().encode(body)

        let (data, resp) = try await session.data(for: req)
        guard let http = resp as? HTTPURLResponse, http.statusCode == 200 else {
            let text = String(data: data, encoding: .utf8) ?? ""
            throw OllamaError.server(status: (resp as? HTTPURLResponse)?.statusCode ?? -1, body: text)
        }
        let decoded = try JSONDecoder().decode(ChatResponse.self, from: data)
        return decoded.message.content
    }

    // MARK: - Wire types

    private struct ChatRequest: Encodable {
        struct Message: Encodable { let role: String; let content: String }
        let model: String
        let stream: Bool
        let messages: [Message]
    }

    private struct ChatResponse: Decodable {
        struct Message: Decodable { let role: String; let content: String }
        let message: Message
    }

    enum OllamaError: LocalizedError {
        case server(status: Int, body: String)
        var errorDescription: String? {
            switch self {
            case .server(let status, let body):
                return "Ollama returned \(status): \(body)"
            }
        }
    }
}
