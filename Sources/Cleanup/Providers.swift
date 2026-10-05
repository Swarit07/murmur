import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// A hosted model behind an OpenAI-compatible chat completions API: Groq, OpenRouter, or any other.
/// The key comes from `key` (the app passes a Keychain lookup, the CLI an environment variable).
public actor OpenAICompatibleCleanupProvider: CleanupProvider {
    public nonisolated let id: String
    let endpoint: URL
    let model: String
    let extraBody: [String: any Sendable]
    /// Reasoning models spend tokens before answering; this is added to the answer's budget.
    let reasoningBudget: Int
    let keyName: String
    let session: URLSession
    let keyProvider: @Sendable () -> String?

    public init(
        id: String, endpoint: URL, model: String, keyName: String,
        extraBody: [String: any Sendable] = [:], reasoningBudget: Int = 0,
        key: @escaping @Sendable () -> String?
    ) {
        self.id = id
        self.endpoint = endpoint
        self.model = model
        self.keyName = keyName
        self.extraBody = extraBody
        self.reasoningBudget = reasoningBudget
        self.keyProvider = key
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 10
        config.httpMaximumConnectionsPerHost = 2
        self.session = URLSession(configuration: config)
    }

    var key: String? { keyProvider().flatMap { $0.isEmpty ? nil : $0 } }

    public func load() async throws {
        guard key != nil else { throw CleanupError.missingKey(keyName) }
        // Warm the TLS connection so the first dictation does not pay for the handshake.
        _ = try? await complete([ChatMessage(.user, "Reply with OK.")], maxTokens: 2)
    }

    public func complete(_ messages: [ChatMessage], maxTokens: Int) async throws -> String {
        guard let key else { throw CleanupError.missingKey(keyName) }
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        var body: [String: Any] = [
            "model": model,
            "messages": messages.map { ["role": $0.role.rawValue, "content": $0.content] },
            "temperature": 0,
            "max_tokens": maxTokens + reasoningBudget,
        ]
        for (k, v) in extraBody { body[k] = v }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else { throw CleanupError.http(status, String(decoding: data, as: UTF8.self)) }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any],
              let content = message["content"] as? String else { throw CleanupError.badResponse }
        return content
    }

    public func unload() async {}

    /// Groq. Default `openai/gpt-oss-20b` with low reasoning effort and the reasoning left out of the
    /// reply (`llama-3.1-8b-instant` moved to sales-only pricing).
    public static func groq(
        model: String = ProcessInfo.processInfo.environment["MURMUR_GROQ_CLEANUP_MODEL"] ?? "openai/gpt-oss-20b",
        key: @escaping @Sendable () -> String?
    ) -> OpenAICompatibleCleanupProvider {
        let isGptOss = model.hasPrefix("openai/gpt-oss")
        return OpenAICompatibleCleanupProvider(
            id: "groq:\(model)", endpoint: URL(string: "https://api.groq.com/openai/v1/chat/completions")!, model: model,
            keyName: "GROQ_API_KEY",
            extraBody: isGptOss ? ["reasoning_effort": "low", "include_reasoning": false] : [:],
            reasoningBudget: isGptOss ? 256 : 0, key: key
        )
    }

    /// OpenRouter: one key for many hosted models (pick any chat model id from openrouter.ai/models).
    public static func openRouter(
        model: String = ProcessInfo.processInfo.environment["MURMUR_OPENROUTER_MODEL"] ?? "meta-llama/llama-3.1-8b-instruct",
        key: @escaping @Sendable () -> String?
    ) -> OpenAICompatibleCleanupProvider {
        OpenAICompatibleCleanupProvider(
            id: "openrouter:\(model)", endpoint: URL(string: "https://openrouter.ai/api/v1/chat/completions")!, model: model,
            keyName: "OPENROUTER_API_KEY", key: key
        )
    }
}

/// Apple's on-device foundation model (macOS 26 and later, Apple Intelligence on). No download.
/// Keeps one session prewarmed with the instructions so a dictation does not pay for reading them.
public actor AppleFoundationCleanupProvider: CleanupProvider {
    public nonisolated let id = "apple-foundation"
    private var spare: AnyObject?
    private var spareInstructions: String?

    public init() {}

    public func load() async throws {
        #if canImport(FoundationModels)
        guard #available(macOS 26.0, *) else { throw CleanupError.unavailable("needs macOS 26") }
        switch SystemLanguageModel.default.availability {
        case .available:
            prepareSpare(Self.split(CleanupPrompt.messages(for: "", level: .light, vocabulary: [])).0)
        case .unavailable(let reason):
            throw CleanupError.unavailable("Apple Intelligence model: \(reason)")
        }
        #else
        throw CleanupError.unavailable("FoundationModels framework not in this SDK")
        #endif
    }

    public func complete(_ messages: [ChatMessage], maxTokens: Int) async throws -> String {
        #if canImport(FoundationModels)
        guard #available(macOS 26.0, *) else { throw CleanupError.unavailable("needs macOS 26") }
        let (instructions, prompt) = Self.split(messages)
        let session = takeSession(instructions)
        defer { prepareSpare(instructions) }
        let response = try await session.respond(
            to: prompt,
            options: GenerationOptions(samplingMode: .greedy, maximumResponseTokens: maxTokens)
        )
        return response.content
        #else
        throw CleanupError.unavailable("FoundationModels framework not in this SDK")
        #endif
    }

    #if canImport(FoundationModels)
    @available(macOS 26.0, *)
    private func takeSession(_ instructions: String) -> LanguageModelSession {
        if let session = spare as? LanguageModelSession, spareInstructions == instructions {
            spare = nil
            return session
        }
        return LanguageModelSession(instructions: instructions)
    }

    @available(macOS 26.0, *)
    private func prepareSpare(_ instructions: String) {
        let session = LanguageModelSession(instructions: instructions)
        session.prewarm()
        spare = session
        spareInstructions = instructions
    }
    #endif

    /// System prompt and worked examples become the instructions; the last user turn is the prompt.
    static func split(_ messages: [ChatMessage]) -> (String, String) {
        var instructions = messages.first(where: { $0.role == .system })?.content ?? ""
        let turns = messages.filter { $0.role != .system }
        let examples = Array(turns.dropLast())
        if !examples.isEmpty {
            instructions += "\n\nExamples:\n"
            var i = 0
            while i < examples.count {
                let input = examples[i].content
                let output = i + 1 < examples.count ? examples[i + 1].content : ""
                instructions += "\nInput:\n\(input)\nOutput:\n\(output)\n"
                i += 2
            }
        }
        return (instructions, turns.last?.content ?? "")
    }

    /// Prewarms a session for these messages' instructions, so the first real call is warm too.
    public func prewarm(_ messages: [ChatMessage]) {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) { prepareSpare(Self.split(messages).0) }
        #endif
    }

    public func unload() async {
        spare = nil
    }
}

/// A provider that never answers and ignores cancellation. Used to prove the time limit (C6).
public struct StalledCleanupProvider: CleanupProvider {
    public let id = "stalled"
    public init() {}
    public func load() async throws {}
    public func complete(_ messages: [ChatMessage], maxTokens: Int) async throws -> String {
        // Deliberately not cancellable.
        let deadline = Date().addingTimeInterval(3)
        while Date() < deadline { usleep(20_000) }
        return "too late"
    }
    public func unload() async {}
}
