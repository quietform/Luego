import Foundation

@MainActor
final class SeenItemTracker {
    private let storageKey: String
    private let resetThreshold: Double
    private var seenHashes: Set<UInt64> = []
    private var didLoadHistory = false
    private var generation = UUID()

    init(storageKey: String, resetThreshold: Double = 0.8) {
        self.storageKey = storageKey
        self.resetThreshold = resetThreshold
    }

    func filterUnseen<Item: Sendable>(_ items: [Item], identifierFor: @Sendable @escaping (Item) -> String) async -> [Item] {
        await loadHistoryIfNeeded()
        return await Self.unseenItems(items, hashes: seenHashes, identifierFor: identifierFor)
    }

    func markAsSeen(_ identifier: String) async {
        await loadHistoryIfNeeded()
        seenHashes.insert(Self.stableHash(identifier))
        generation = UUID()
        await saveHistory()
    }

    func resetIfNeeded(totalCount: Int, unseenCount: Int) async -> Bool {
        let seenRatio = Double(totalCount - unseenCount) / Double(totalCount)
        guard seenRatio >= resetThreshold || unseenCount == 0 else { return false }
        seenHashes.removeAll()
        generation = UUID()
        await saveHistory()
        return true
    }

    func clear() {
        generation = UUID()
        didLoadHistory = true
        seenHashes.removeAll()
        UserDefaults.standard.removeObject(forKey: storageKey)
    }

    var seenCount: Int { seenHashes.count }

    private func loadHistoryIfNeeded() async {
        guard !didLoadHistory else { return }
        let data = UserDefaults.standard.data(forKey: storageKey)
        let previousGeneration = generation
        let hashes = await Self.decodeHistory(data)
        guard previousGeneration == generation, !didLoadHistory else { return }
        seenHashes = hashes
        didLoadHistory = true
    }

    private func saveHistory() async {
        let previousGeneration = generation
        let data = await Self.encodeHistory(seenHashes)
        guard let data, previousGeneration == generation else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }

    @concurrent
    private static func unseenItems<Item: Sendable>(_ items: [Item], hashes: Set<UInt64>, identifierFor: @Sendable (Item) -> String) async -> [Item] {
        items.filter { !hashes.contains(stableHash(identifierFor($0))) }
    }

    private nonisolated static func stableHash(_ string: String) -> UInt64 {
        var hash: UInt64 = 5381
        for byte in string.utf8 {
            hash = ((hash << 5) &+ hash) &+ UInt64(byte)
        }
        return hash
    }

    @concurrent
    private static func decodeHistory(_ data: Data?) async -> Set<UInt64> {
        guard let data else { return [] }
        return (try? JSONDecoder().decode(Set<UInt64>.self, from: data)) ?? []
    }

    @concurrent
    private static func encodeHistory(_ hashes: Set<UInt64>) async -> Data? {
        try? JSONEncoder().encode(hashes)
    }
}
