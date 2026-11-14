import XCTest
@testable import ContextAssistantCore

final class TokenBucketTests: XCTestCase {
    func testBurstThenDeny() async {
        let start = Date(timeIntervalSince1970: 1_000)
        let bucket = TokenBucket(capacity: 2, refillPerSecond: 1, now: start)
        let first = await bucket.tryConsume(at: start)
        let second = await bucket.tryConsume(at: start)
        let third = await bucket.tryConsume(at: start)
        XCTAssertTrue(first.allowed)
        XCTAssertTrue(second.allowed)
        XCTAssertFalse(third.allowed)
        XCTAssertEqual(third.retryAfter, 1, accuracy: 0.0001)
        XCTAssertEqual(third.remainingTokens, 0, accuracy: 0.0001)
    }

    func testRefillAllowsAnotherToken() async {
        let start = Date(timeIntervalSince1970: 1_000)
        let bucket = TokenBucket(capacity: 1, refillPerSecond: 2, now: start)
        let spent = await bucket.tryConsume(at: start)
        XCTAssertTrue(spent.allowed)
        let later = start.addingTimeInterval(0.5)
        let again = await bucket.tryConsume(at: later)
        XCTAssertTrue(again.allowed)
    }

    func testDoesNotExceedCapacity() async {
        let start = Date(timeIntervalSince1970: 1_000)
        let bucket = TokenBucket(capacity: 2, refillPerSecond: 10, now: start)
        _ = await bucket.tryConsume(at: start)
        let later = await bucket.tryConsume(1, at: start.addingTimeInterval(10))
        XCTAssertTrue(later.allowed)
        XCTAssertEqual(later.remainingTokens, 1, accuracy: 0.0001)
    }
}

final class ResponseCacheTests: XCTestCase {
    func testInsertAndFetch() async {
        let cache = ResponseCache(capacity: 2)
        let date = Date(timeIntervalSince1970: 50)
        await cache.insert("answer", for: "key", at: date)
        let entry = await cache.value(for: "key")
        XCTAssertEqual(entry, ResponseCache.Entry(response: "answer", storedAt: date))
        let missing = await cache.value(for: "other")
        XCTAssertNil(missing)
    }

    func testLeastRecentlyUsedIsEvicted() async {
        let cache = ResponseCache(capacity: 2)
        await cache.insert("a", for: "a")
        await cache.insert("b", for: "b")
        _ = await cache.value(for: "a")
        await cache.insert("c", for: "c")
        let count = await cache.count()
        XCTAssertEqual(count, 2)
        let kept = await cache.value(for: "a")
        let evicted = await cache.value(for: "b")
        let newest = await cache.value(for: "c")
        XCTAssertEqual(kept?.response, "a")
        XCTAssertNil(evicted)
        XCTAssertEqual(newest?.response, "c")
    }

    func testReplaceRefreshesRecency() async {
        let cache = ResponseCache(capacity: 2)
        await cache.insert("a1", for: "a")
        await cache.insert("b", for: "b")
        await cache.insert("a2", for: "a")
        await cache.insert("c", for: "c")
        let a = await cache.value(for: "a")
        let b = await cache.value(for: "b")
        XCTAssertEqual(a?.response, "a2")
        XCTAssertNil(b)
    }
}
