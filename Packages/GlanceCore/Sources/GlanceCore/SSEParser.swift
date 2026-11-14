import Foundation

public struct SSEEvent: Equatable, Sendable {
    public var event: String?
    public var data: String

    public init(event: String?, data: String) {
        self.event = event
        self.data = data
    }
}

/// Incremental Server-Sent Events parser. Blank lines dispatch one event.
public struct SSEParser: Sendable {
    private var dataLines: [String] = []
    private var eventName: String?
    private var hasField = false

    public init() {}

    public mutating func feed(_ rawLine: String) -> SSEEvent? {
        var line = rawLine
        if line.hasSuffix("\r") {
            line.removeLast()
        }
        if line.isEmpty {
            return flush()
        }
        if line.hasPrefix(":") {
            return nil
        }
        hasField = true
        if line.hasPrefix("data:") {
            var value = String(line.dropFirst(5))
            if value.hasPrefix(" ") { value.removeFirst() }
            dataLines.append(value)
            return nil
        }
        if line.hasPrefix("event:") {
            var value = String(line.dropFirst(6))
            if value.hasPrefix(" ") { value.removeFirst() }
            eventName = value
            return nil
        }
        return nil
    }

    public mutating func finish() -> SSEEvent? {
        flush()
    }

    private mutating func flush() -> SSEEvent? {
        guard hasField else { return nil }
        let event = SSEEvent(event: eventName, data: dataLines.joined(separator: "\n"))
        dataLines.removeAll(keepingCapacity: true)
        eventName = nil
        hasField = false
        return event
    }
}

public struct ChatStreamDelta: Equatable, Sendable {
    public var content: String?
    public var finishReason: String?
    public var isDone: Bool

    public init(content: String?, finishReason: String?, isDone: Bool) {
        self.content = content
        self.finishReason = finishReason
        self.isDone = isDone
    }
}

public enum ChatStreamDecoder {
    public static func decode(_ payload: String) throws -> ChatStreamDelta {
        let trimmed = payload.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed == "[DONE]" {
            return ChatStreamDelta(content: nil, finishReason: "stop", isDone: true)
        }
        guard let data = trimmed.data(using: .utf8) else {
            throw LLMClientError.stream("Event was not valid UTF-8.")
        }
        let object: StreamPayload
        do {
            object = try JSONDecoder().decode(StreamPayload.self, from: data)
        } catch {
            throw LLMClientError.stream("Could not read a stream event.")
        }
        if let message = object.error?.message, !message.isEmpty {
            throw LLMClientError.stream(message)
        }
        let choice = object.choices?.first
        return ChatStreamDelta(
            content: choice?.delta?.content,
            finishReason: choice?.finishReason,
            isDone: false
        )
    }
}

private struct StreamPayload: Decodable {
    struct Choice: Decodable {
        struct Delta: Decodable {
            var content: String?
        }

        var delta: Delta?
        var finishReason: String?

        enum CodingKeys: String, CodingKey {
            case delta
            case finishReason = "finish_reason"
        }
    }

    struct APIError: Decodable {
        var message: String?
    }

    var choices: [Choice]?
    var error: APIError?
}
