import Audio
import Foundation

/// Whisper Large v3 Turbo on Groq. Off unless `GROQ_API_KEY` is set. Audio leaves the Mac only when
/// this engine is chosen.
public actor GroqWhisperEngine: SpeechEngine {
    public nonisolated let id = "groq-whisper"
    public nonisolated let isLocal = false
    let model: String
    let session: URLSession

    public init(model: String = "whisper-large-v3-turbo") {
        self.model = model
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 15
        self.session = URLSession(configuration: config)
    }

    var key: String? { ProcessInfo.processInfo.environment["GROQ_API_KEY"].flatMap { $0.isEmpty ? nil : $0 } }

    public func load() async throws {
        guard key != nil else { throw SpeechError.missingKey("GROQ_API_KEY") }
        // Warm the connection.
        _ = try? await transcribe([Float](repeating: 0, count: 8_000), options: TranscribeOptions())
    }

    public func transcribe(_ samples: [Float], options: TranscribeOptions) async throws -> String {
        guard let key else { throw SpeechError.missingKey("GROQ_API_KEY") }
        let boundary = "murmur-\(UUID().uuidString)"
        var body = Data()
        func field(_ name: String, _ value: String) {
            body.append("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(name)\"\r\n\r\n\(value)\r\n".data(using: .utf8)!)
        }
        field("model", model)
        field("response_format", "json")
        field("temperature", "0")
        if let language = options.language { field("language", language) }
        if !options.vocabulary.isEmpty { field("prompt", options.vocabulary.joined(separator: ", ")) }
        body.append("--\(boundary)\r\nContent-Disposition: form-data; name=\"file\"; filename=\"clip.wav\"\r\nContent-Type: audio/wav\r\n\r\n".data(using: .utf8)!)
        body.append(Self.wavData(samples))
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)

        var request = URLRequest(url: URL(string: "https://api.groq.com/openai/v1/audio/transcriptions")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else { throw SpeechError.http(status, String(decoding: data, as: UTF8.self)) }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any], let text = json["text"] as? String else {
            throw SpeechError.badResponse
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public func unload() async {}

    /// 16-bit PCM WAV in memory.
    static func wavData(_ samples: [Float]) -> Data {
        var data = Data()
        let rate = UInt32(AudioFormat.sampleRate)
        let byteCount = UInt32(samples.count * 2)
        func u32(_ v: UInt32) { withUnsafeBytes(of: v.littleEndian) { data.append(contentsOf: $0) } }
        func u16(_ v: UInt16) { withUnsafeBytes(of: v.littleEndian) { data.append(contentsOf: $0) } }
        data.append(contentsOf: Array("RIFF".utf8)); u32(36 + byteCount)
        data.append(contentsOf: Array("WAVE".utf8))
        data.append(contentsOf: Array("fmt ".utf8)); u32(16); u16(1); u16(1); u32(rate); u32(rate * 2); u16(2); u16(16)
        data.append(contentsOf: Array("data".utf8)); u32(byteCount)
        data.reserveCapacity(data.count + samples.count * 2)
        for s in samples {
            let v = Int16(max(-1, min(1, s)) * Float(Int16.max))
            u16(UInt16(bitPattern: v))
        }
        return data
    }
}
