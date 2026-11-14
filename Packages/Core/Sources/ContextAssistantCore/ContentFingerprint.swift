import Foundation

public struct ContentFingerprint: Equatable, Sendable {
    public var hash: String
    public var normalized: String

    public init(hash: String, normalized: String) {
        self.hash = hash
        self.normalized = normalized
    }

    public static func make(_ text: String) -> ContentFingerprint {
        let normalized = normalize(text)
        return ContentFingerprint(hash: TextHash.sha256Hex(normalized), normalized: normalized)
    }

    public static func normalize(_ text: String) -> String {
        text.lowercased()
            .split { $0.isWhitespace || $0.isNewline }
            .map(String.init)
            .joined(separator: " ")
    }
}

public enum CacheKey {
    /// Stable key for an OCR string plus the question asked about it.
    public static func make(ocrText: String, question: String) -> String {
        let basis = ContentFingerprint.normalize(ocrText) + "\n---\n" + ContentFingerprint.normalize(question)
        return TextHash.sha256Hex(basis)
    }
}

public enum ResponseReuse: Equatable, Sendable {
    case useCache
    case usePreviousAnswer
    case requestModel
}

public enum ResponseReusePlanner {
    public static func decide(
        ocrText: String,
        question: String,
        previousOCR: String?,
        previousQuestion: String?,
        hasCache: Bool,
        bypassCache: Bool,
        similarityThreshold: Double = 0.92
    ) -> ResponseReuse {
        if bypassCache {
            return .requestModel
        }
        if hasCache {
            return .useCache
        }
        if let previousOCR,
           ContentFingerprint.normalize(previousQuestion ?? "") == ContentFingerprint.normalize(question),
           Similarity.score(previousOCR, ocrText) >= similarityThreshold {
            return .usePreviousAnswer
        }
        return .requestModel
    }
}
