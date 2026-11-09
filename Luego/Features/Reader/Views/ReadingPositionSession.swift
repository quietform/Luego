import Foundation
import Observation

@MainActor
@Observable
final class ReadingPositionSession {
    private(set) var restoringTo: Double?
    @ObservationIgnored private let save: (Double) async -> Void
    @ObservationIgnored private let settle: () async throws -> Void
    @ObservationIgnored private var pendingSave: Task<Void, Never>?
    @ObservationIgnored private var lastSaved: Double
    @ObservationIgnored private var needsRestore = true
    @ObservationIgnored private var current: Double?
    @ObservationIgnored private var awaitingReload = false

    init(
        savedPosition: Double,
        save: @escaping (Double) async -> Void,
        settle: @escaping () async throws -> Void = { try await Task.sleep(for: .seconds(2)) }
    ) {
        self.save = save
        self.settle = settle
        self.lastSaved = savedPosition
    }

    func pageReported(_ visibleBottom: Double?) {
        pendingSave?.cancel()
        guard let visibleBottom else {
            awaitingReload = false
            return
        }
        guard !awaitingReload else { return }
        if needsRestore {
            needsRestore = false
            if lastSaved > 0 { restoringTo = lastSaved }
        }
        guard restoringTo == nil else { return }
        let position = Self.position(atVisibleBottom: visibleBottom)
        current = position
        guard abs(position - lastSaved) > 0.01 else { return }
        pendingSave = Task {
            try? await settle()
            guard !Task.isCancelled else { return }
            await save(position)
            lastSaved = position
        }
    }

    func leave() {
        pendingSave?.cancel()
        guard let current else { return }
        Task { await save(current) }
    }

    func refresh() {
        leave()
        if let current { lastSaved = current }
        needsRestore = true
        awaitingReload = true
    }

    func pageRestored() {
        restoringTo = nil
    }

    private static func position(atVisibleBottom visibleBottom: Double) -> Double {
        let position = min(1, max(0, visibleBottom))
        return position >= 0.95 ? 1 : position
    }
}
