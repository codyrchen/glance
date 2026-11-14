import Foundation

public enum Similarity {
    /// 1 means the normalized strings are identical. The score mixes token Jaccard and character-trigram Dice.
    public static func score(_ lhs: String, _ rhs: String) -> Double {
        let left = ContentFingerprint.normalize(lhs)
        let right = ContentFingerprint.normalize(rhs)
        if left == right { return 1 }
        if left.isEmpty || right.isEmpty { return 0 }
        let jaccard = tokenJaccard(left, right)
        let dice = trigramDice(left, right)
        return (jaccard + dice) / 2
    }

    public static func isUnchanged(_ lhs: String, _ rhs: String, threshold: Double = 0.92) -> Bool {
        score(lhs, rhs) >= threshold
    }

    private static func tokenJaccard(_ lhs: String, _ rhs: String) -> Double {
        let left = Set(lhs.split(separator: " ").map(String.init))
        let right = Set(rhs.split(separator: " ").map(String.init))
        let union = left.union(right)
        guard !union.isEmpty else { return 1 }
        return Double(left.intersection(right).count) / Double(union.count)
    }

    private static func trigramDice(_ lhs: String, _ rhs: String) -> Double {
        let left = trigrams(lhs)
        let right = trigrams(rhs)
        if left.isEmpty && right.isEmpty { return 1 }
        if left.isEmpty || right.isEmpty { return 0 }
        let rightCounts = right
        var overlap = 0
        for (gram, count) in left {
            let shared = min(count, rightCounts[gram] ?? 0)
            overlap += shared
        }
        let leftTotal = left.values.reduce(0, +)
        let rightTotal = right.values.reduce(0, +)
        return (2 * Double(overlap)) / Double(leftTotal + rightTotal)
    }

    private static func trigrams(_ text: String) -> [String: Int] {
        let scalars = Array(text)
        guard scalars.count >= 3 else {
            return scalars.isEmpty ? [:] : [String(scalars): 1]
        }
        var counts: [String: Int] = [:]
        for index in 0...(scalars.count - 3) {
            let gram = String(scalars[index..<(index + 3)])
            counts[gram, default: 0] += 1
        }
        return counts
    }
}
