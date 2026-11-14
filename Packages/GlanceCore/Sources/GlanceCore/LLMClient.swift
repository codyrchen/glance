import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public struct LLMConfiguration: Equatable, Sendable {
    public var baseURL: URL
    public var model: String
    public var apiKey: String
    public var temperature: Double?

    public init(baseURL: URL, model: String, apiKey: String, temperature: Double? = nil) {
        self.baseURL = baseURL
        self.model = model
        self.apiKey = apiKey
        self.temperature = temperature
    }

    /// API root such as `https://api.openai.com/v1`, or a full chat-completions URL.
    public var chatCompletionsURL: URL {
        let absolute = baseURL.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let stripped: String
        if absolute.hasSuffix("/chat/completions") {
            stripped = String(absolute.dropLast("/chat/completions".count))
        } else {
            stripped = absolute
        }
        guard var root = URL(string: stripped) else { return baseURL }
        root.appendPathComponent("chat")
        root.appendPathComponent("completions")
        return root
    }
}

public enum LLMClientError: Error, Equatable, Sendable {
    case badURL
    case http(status: Int, body: String)
    case stream(String)
}

public final class LLMClient: @unchecked Sendable {
    private let session: URLSession
    public let maxStreamCharacters: Int

    public init(session: URLSession = .shared, maxStreamCharacters: Int = 100_000) {
        self.session = session
        self.maxStreamCharacters = max(1, maxStreamCharacters)
    }

    public func stream(
        configuration: LLMConfiguration,
        messages: [ChatMessage]
    ) -> AsyncThrowingStream<String, Error> {
        let session = self.session
        let limit = self.maxStreamCharacters
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    try await Self.run(
                        session: session,
                        configuration: configuration,
                        messages: messages,
                        maxStreamCharacters: limit,
                        continuation: continuation
                    )
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish()
                } catch let error as URLError where error.code == .cancelled {
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { @Sendable _ in
                task.cancel()
            }
        }
    }

    private static func run(
        session: URLSession,
        configuration: LLMConfiguration,
        messages: [ChatMessage],
        maxStreamCharacters: Int,
        continuation: AsyncThrowingStream<String, Error>.Continuation
    ) async throws {
        let url = configuration.chatCompletionsURL
        guard url.scheme == "http" || url.scheme == "https" else {
            throw LLMClientError.badURL
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        if !configuration.apiKey.isEmpty {
            request.setValue("Bearer \(configuration.apiKey)", forHTTPHeaderField: "Authorization")
        }
        let body = ChatCompletionBody(
            model: configuration.model,
            messages: messages,
            stream: true,
            temperature: configuration.temperature
        )
        request.httpBody = try JSONEncoder().encode(body)

        let opened = try await open(session: session, request: request)
        let status = (opened.response as? HTTPURLResponse)?.statusCode ?? -1
        guard (200..<300).contains(status) else {
            var errorBody = ""
            for try await line in opened.lines {
                try Task.checkCancellation()
                errorBody += line
                if errorBody.count > 2_000 { break }
            }
            throw LLMClientError.http(status: status, body: errorBody)
        }

        var parser = SSEParser()
        var emitted = 0
        var stoppedEarly = false

        func emit(_ text: String) {
            guard !stoppedEarly else { return }
            let room = maxStreamCharacters - emitted
            if room <= 0 {
                stoppedEarly = true
                return
            }
            if text.count <= room {
                emitted += text.count
                continuation.yield(text)
            } else {
                let end = text.index(text.startIndex, offsetBy: max(0, room))
                let prefix = String(text[..<end])
                continuation.yield(prefix + "…")
                emitted = maxStreamCharacters
                stoppedEarly = true
            }
        }

        for try await line in opened.lines {
            try Task.checkCancellation()
            if stoppedEarly { break }
            if let event = parser.feed(line) {
                try consume(event, emit: emit)
            }
        }
        if !stoppedEarly, let event = parser.finish() {
            try consume(event, emit: emit)
        }
    }

    /// macOS uses `URLSession.bytes(for:)`, which streams SSE as it arrives.
    /// swift-corelibs-foundation does not implement `bytes(for:)` yet, so Linux tests read `data(for:)` and split lines.
    private static func open(session: URLSession, request: URLRequest) async throws -> (response: URLResponse, lines: AsyncThrowingStream<String, Error>) {
        #if os(macOS) || os(iOS) || os(tvOS) || os(watchOS)
        let (bytes, response) = try await session.bytes(for: request)
        let lines = AsyncThrowingStream<String, Error> { continuation in
            let task = Task {
                do {
                    for try await line in bytes.lines {
                        continuation.yield(line)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { @Sendable _ in
                task.cancel()
            }
        }
        return (response, lines)
        #else
        let (data, response) = try await session.data(for: request)
        let text = String(decoding: data, as: UTF8.self)
        let parts = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        let lines = AsyncThrowingStream<String, Error> { continuation in
            for part in parts {
                continuation.yield(part)
            }
            continuation.finish()
        }
        return (response, lines)
        #endif
    }

    private static func consume(_ event: SSEEvent, emit: (String) -> Void) throws {
        let delta = try ChatStreamDecoder.decode(event.data)
        if delta.isDone { return }
        if let content = delta.content, !content.isEmpty {
            emit(content)
        }
    }
}

private struct ChatCompletionBody: Encodable {
    var model: String
    var messages: [ChatMessage]
    var stream: Bool
    var temperature: Double?

    enum CodingKeys: String, CodingKey {
        case model
        case messages
        case stream
        case temperature
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(model, forKey: .model)
        try container.encode(messages, forKey: .messages)
        try container.encode(stream, forKey: .stream)
        try container.encodeIfPresent(temperature, forKey: .temperature)
    }
}
