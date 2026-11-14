import Foundation

public struct ConversationTurn: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public var createdAt: Date
    public var windowTitle: String
    public var ownerName: String
    public var ocrHash: String
    public var ocrExcerpt: String
    public var userQuestion: String
    public var assistantResponse: String

    public init(
        id: UUID = UUID(),
        createdAt: Date = Date(),
        windowTitle: String,
        ownerName: String,
        ocrHash: String,
        ocrExcerpt: String,
        userQuestion: String,
        assistantResponse: String
    ) {
        self.id = id
        self.createdAt = createdAt
        self.windowTitle = windowTitle
        self.ownerName = ownerName
        self.ocrHash = ocrHash
        self.ocrExcerpt = ocrExcerpt
        self.userQuestion = userQuestion
        self.assistantResponse = assistantResponse
    }

    public var storedCharacterCount: Int {
        ocrExcerpt.count + userQuestion.count + assistantResponse.count
    }

    public func truncated(to budget: Int) -> ConversationTurn {
        var copy = self
        var remaining = max(0, budget)
        copy.userQuestion = Self.prefix(copy.userQuestion, budget: &remaining)
        copy.ocrExcerpt = Self.prefix(copy.ocrExcerpt, budget: &remaining)
        copy.assistantResponse = Self.prefix(copy.assistantResponse, budget: &remaining)
        return copy
    }

    private static func prefix(_ value: String, budget: inout Int) -> String {
        if value.count <= budget {
            budget -= value.count
            return value
        }
        if budget <= 1 {
            budget = 0
            return ""
        }
        let end = value.index(value.startIndex, offsetBy: budget - 1)
        budget = 0
        return String(value[..<end]) + "…"
    }
}

public enum HistoryTrimmer {
    public static func trim(_ turns: [ConversationTurn], maxTurns: Int, maxCharacters: Int) -> [ConversationTurn] {
        guard maxTurns > 0, maxCharacters > 0 else { return [] }
        var kept = Array(turns.suffix(maxTurns))
        while kept.count > 1 && totalCharacters(kept) > maxCharacters {
            kept.removeFirst()
        }
        if kept.count == 1, let only = kept.first, only.storedCharacterCount > maxCharacters {
            kept[0] = only.truncated(to: maxCharacters)
        }
        return kept
    }

    public static func excerpt(_ text: String, limit: Int) -> String {
        guard limit > 0 else { return "" }
        if text.count <= limit { return text }
        if limit == 1 { return "…" }
        let end = text.index(text.startIndex, offsetBy: limit - 1)
        return String(text[..<end]) + "…"
    }

    public static func totalCharacters(_ turns: [ConversationTurn]) -> Int {
        turns.reduce(0) { $0 + $1.storedCharacterCount }
    }
}
