import Foundation

public actor ResponseCache {
    public struct Entry: Equatable, Sendable {
        public var response: String
        public var storedAt: Date

        public init(response: String, storedAt: Date) {
            self.response = response
            self.storedAt = storedAt
        }
    }

    private let capacity: Int
    private var store: [String: Entry] = [:]
    /// Oldest key is at the front.
    private var order: [String] = []

    public init(capacity: Int) {
        self.capacity = max(1, capacity)
    }

    public func value(for key: String) -> Entry? {
        guard let entry = store[key] else { return nil }
        touch(key)
        return entry
    }

    public func insert(_ response: String, for key: String, at date: Date = Date()) {
        if store[key] != nil {
            store[key] = Entry(response: response, storedAt: date)
            touch(key)
            return
        }
        store[key] = Entry(response: response, storedAt: date)
        order.append(key)
        evictIfNeeded()
    }

    public func count() -> Int { store.count }

    public func contains(_ key: String) -> Bool { store[key] != nil }

    private func touch(_ key: String) {
        order.removeAll { $0 == key }
        order.append(key)
    }

    private func evictIfNeeded() {
        while order.count > capacity {
            let oldest = order.removeFirst()
            store.removeValue(forKey: oldest)
        }
    }
}
