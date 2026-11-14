import XCTest
@testable import GlanceCore

final class TextHashTests: XCTestCase {
    func testEmptyString() {
        XCTAssertEqual(
            TextHash.sha256Hex(""),
            "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
        )
    }

    func testABC() {
        XCTAssertEqual(
            TextHash.sha256Hex("abc"),
            "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
        )
    }

    func testLongVector() {
        XCTAssertEqual(
            TextHash.sha256Hex("abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq"),
            "248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1"
        )
    }
}

final class DedupTests: XCTestCase {
    func testNormalizeCollapsesCaseAndWhitespace() {
        XCTAssertEqual(
            ContentFingerprint.normalize("  Hello\nWorld  "),
            ContentFingerprint.normalize("hello world")
        )
    }

    func testIdenticalTextHashesEqual() {
        XCTAssertEqual(ContentFingerprint.make("Hello").hash, ContentFingerprint.make("hello").hash)
    }

    func testDifferentTextHashesDiffer() {
        XCTAssertNotEqual(ContentFingerprint.make("alpha").hash, ContentFingerprint.make("beta").hash)
    }

    func testSimilarityIdentity() {
        XCTAssertEqual(Similarity.score("Same text", "same   text"), 1, accuracy: 0.0001)
    }

    func testSimilarityEmpty() {
        XCTAssertEqual(Similarity.score("", ""), 1, accuracy: 0.0001)
        XCTAssertEqual(Similarity.score("hello", ""), 0, accuracy: 0.0001)
    }

    func testSmallEditStaysAboveThreshold() {
        let original = """
        The quick brown fox jumps over the lazy dog near the river bank while the class reviews \
        pointers, stacks, and the difference between a copy and a reference in this week's lab.
        """
        let edited = """
        The quick brown fox jumps over the lazy dog near the river bank while the class reviews \
        pointers, stacks, and the difference between a copy and a reference in this week's lab!
        """
        XCTAssertGreaterThan(Similarity.score(original, edited), 0.92)
        XCTAssertTrue(Similarity.isUnchanged(original, edited))
    }

    func testUnrelatedTextIsLow() {
        XCTAssertLessThan(Similarity.score("invoice total 42", "recipe for bread"), 0.5)
    }

    func testCacheKeyDependsOnQuestion() {
        let ocr = "Chapter 3. Pointers."
        XCTAssertNotEqual(
            CacheKey.make(ocrText: ocr, question: "Summarize"),
            CacheKey.make(ocrText: ocr, question: "Quiz me")
        )
        XCTAssertEqual(
            CacheKey.make(ocrText: "  Pointers ", question: "Summarize"),
            CacheKey.make(ocrText: "pointers", question: "summarize")
        )
    }

    func testReusePlannerPrefersCacheThenSimilarityThenNetwork() {
        XCTAssertEqual(
            ResponseReusePlanner.decide(
                ocrText: "alpha beta",
                question: "Explain",
                previousOCR: "alpha beta",
                previousQuestion: "Explain",
                hasCache: true,
                bypassCache: false
            ),
            .useCache
        )
        let paragraph = "Chapter four covers memory layout, alignment, padding, and why a struct's size is not the sum of its fields when the compiler inserts padding."
        XCTAssertEqual(
            ResponseReusePlanner.decide(
                ocrText: paragraph,
                question: "Explain",
                previousOCR: paragraph + " ",
                previousQuestion: "Explain",
                hasCache: false,
                bypassCache: false
            ),
            .usePreviousAnswer
        )
        XCTAssertEqual(
            ResponseReusePlanner.decide(
                ocrText: "alpha",
                question: "A new question",
                previousOCR: "alpha",
                previousQuestion: "Explain",
                hasCache: false,
                bypassCache: false
            ),
            .requestModel
        )
        XCTAssertEqual(
            ResponseReusePlanner.decide(
                ocrText: "alpha",
                question: "Explain",
                previousOCR: "alpha",
                previousQuestion: "Explain",
                hasCache: true,
                bypassCache: true
            ),
            .requestModel
        )
    }
}
