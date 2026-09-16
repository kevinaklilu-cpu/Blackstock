import Foundation

public actor TTLCache<Key: Hashable & Sendable, Value: Sendable> {
    private struct Entry: Sendable { let value: Value; let expiresAt: Date }
    private var storage: [Key: Entry] = [:]
    public init() {}
    public func value(for key: Key) -> Value? {
        guard let entry = storage[key] else { return nil }
        if entry.expiresAt <= Date() { storage.removeValue(forKey: key); return nil }
        return entry.value
    }
    public func insert(_ value: Value, for key: Key, ttl: TimeInterval) { storage[key] = Entry(value: value, expiresAt: Date().addingTimeInterval(ttl)) }
    public func removeAll() { storage.removeAll() }
}
