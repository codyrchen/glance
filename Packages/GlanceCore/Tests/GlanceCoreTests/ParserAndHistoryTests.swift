import XCTest
@testable import GlanceCore

final class SSEParserTests: XCTestCase {
    func testSplitsDataEventsAndIgnoresComments() {
        var parser = SSEParser()
        var events: [SSEEvent] = []
        let lines = [
            ": ping",
            "event: delta",
            "data: {\"choices\":[{\"delta\":{\"content\":\"Hi\"}}]}",
            "",
            "data: [DONE]",
            ""
        ]
        for line in lines {
            if let event = parser.feed(line) {
                events.append(event)
            }
        }
        XCTAssertEqual(events.count, 2)
        XCTAssertEqual(events[0].event, "delta")
        XCTAssertEqual(events[0].data, "{\"choices\":[{\"delta\":{\"content\":\"Hi\"}}]}")
        XCTAssertEqual(events[1].data, "[DONE]")
    }

    func testJoinsMultilineData() {
        var parser = SSEParser()
        XCTAssertNil(parser.feed("data: hello"))
        XCTAssertNil(parser.feed("data: world"))
        let event = parser.feed("")
        XCTAssertEqual(event?.data, "hello\nworld")
    }

    func testFinishFlushesTrailingEvent() {
        var parser = SSEParser()
        XCTAssertNil(parser.feed("data: tail"))
        XCTAssertEqual(parser.finish()?.data, "tail")
        XCTAssertNil(parser.finish())
    }

    func testDecoderReadsDeltaAndDone() throws {
        let delta = try ChatStreamDecoder.decode(#"{"choices":[{"delta":{"content":"Hello"},"finish_reason":null}]}"#)
        XCTAssertEqual(delta.content, "Hello")
        XCTAssertFalse(delta.isDone)
        let done = try ChatStreamDecoder.decode("[DONE]")
        XCTAssertTrue(done.isDone)
        XCTAssertNil(done.content)
    }

    func testDecoderThrowsProviderError() {
        XCTAssertThrowsError(try ChatStreamDecoder.decode(#"{"error":{"message":"nope"}}"#)) { error in
            XCTAssertEqual(error as? LLMClientError, .stream("nope"))
        }
    }
}

final class PromptAndHistoryTests: XCTestCase {
    func testPromptIncludesCurrentQuestionAndDropsOldHistory() {
        let old = ConversationTurn(
            windowTitle: "Old",
            ownerName: "Notes",
            ocrHash: "1",
            ocrExcerpt: "ancient",
            userQuestion: "old question",
            assistantResponse: "old answer"
        )
        let recent = ConversationTurn(
            windowTitle: "New",
            ownerName: "Notes",
            ocrHash: "2",
            ocrExcerpt: "recent text",
            userQuestion: "recent question",
            assistantResponse: "recent answer"
        )
        let builder = PromptBuilder(limits: PromptLimits(
            maxHistoryTurns: 1,
            maxHistoryCharacters: 10_000,
            maxOCRCharacters: 100,
            maxQuestionCharacters: 100
        ))
        let messages = builder.build(
            history: [old, recent],
            windowTitle: "Paper",
            ownerName: "Preview",
            ocrText: "current page",
            userQuestion: "Explain this"
        )
        XCTAssertEqual(messages.first?.role, "system")
        XCTAssertTrue(messages[0].content.contains("untrusted data"))
        let joined = messages.map(\.content).joined(separator: "\n")
        XCTAssertFalse(joined.contains("old question"))
        XCTAssertTrue(joined.contains("recent question"))
        XCTAssertTrue(joined.contains("Explain this"))
        XCTAssertTrue(joined.contains("current page"))
        XCTAssertTrue(joined.contains("<<<"))
    }

    func testHistoryTrimDropsOldestThenTruncatesTheLastTurn() {
        let turns = [
            ConversationTurn(windowTitle: "W", ownerName: "O", ocrHash: "a", ocrExcerpt: "aaaa", userQuestion: "q", assistantResponse: "1111"),
            ConversationTurn(windowTitle: "W", ownerName: "O", ocrHash: "b", ocrExcerpt: "bbbb", userQuestion: "q", assistantResponse: "2222"),
            ConversationTurn(windowTitle: "W", ownerName: "O", ocrHash: "c", ocrExcerpt: "cccc", userQuestion: "q", assistantResponse: "3333")
        ]
        let trimmed = HistoryTrimmer.trim(turns, maxTurns: 2, maxCharacters: 100)
        XCTAssertEqual(trimmed.count, 2)
        XCTAssertEqual(trimmed.first?.assistantResponse, "2222")

        let huge = ConversationTurn(
            windowTitle: "W",
            ownerName: "O",
            ocrHash: "z",
            ocrExcerpt: "excerpt-text",
            userQuestion: "ask",
            assistantResponse: String(repeating: "x", count: 50)
        )
        let one = HistoryTrimmer.trim([huge], maxTurns: 4, maxCharacters: 12)
        XCTAssertEqual(one.count, 1)
        XCTAssertLessThanOrEqual(one[0].storedCharacterCount, 12)
        XCTAssertTrue(one[0].userQuestion.hasPrefix("ask") || one[0].userQuestion.isEmpty)
    }

    func testExcerptAddsEllipsis() {
        XCTAssertEqual(HistoryTrimmer.excerpt("hello", limit: 10), "hello")
        XCTAssertEqual(HistoryTrimmer.excerpt("hello", limit: 4), "hel…")
        XCTAssertEqual(HistoryTrimmer.excerpt("hello", limit: 0), "")
    }

    func testZeroTurnBudgetIsEmpty() {
        let turn = ConversationTurn(windowTitle: "W", ownerName: "O", ocrHash: "h", ocrExcerpt: "e", userQuestion: "q", assistantResponse: "a")
        XCTAssertTrue(HistoryTrimmer.trim([turn], maxTurns: 0, maxCharacters: 100).isEmpty)
    }
}
