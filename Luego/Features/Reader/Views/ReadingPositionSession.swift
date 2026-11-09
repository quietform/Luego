import Foundation
import Observation

@MainActor
@Observable
final class ReadingPositionSession {
    private var phase: Phase
    @ObservationIgnored private let save: (Double) async -> Bool
    @ObservationIgnored private let settle: () async throws -> Void
    @ObservationIgnored private var pendingSave: Task<Void, Never>?
    @ObservationIgnored private var lastSaved: Double
    @ObservationIgnored private var current: Double?
    @ObservationIgnored private var pageShowsText = false

    init(
        savedPosition: Double,
        save: @escaping (Double) async -> Bool,
        settle: @escaping () async throws -> Void = { try await Task.sleep(for: .seconds(2)) }
    ) {
        self.save = save
        self.settle = settle
        self.lastSaved = savedPosition
        self.phase = .opening(returnTo: savedPosition)
    }

    var restoringTo: Double? {
        if case .restoring(let place) = phase { place } else { nil }
    }

    func pageReported(_ visibleBottom: Double?) {
        pendingSave?.cancel()
        pageShowsText = visibleBottom != nil
        guard let visibleBottom else {
            if case .reloading(let place) = phase { phase = .opening(returnTo: place) }
            return
        }
        switch phase {
        case .reloading, .restoring:
            return
        case .opening(let place) where place > 0:
            phase = .restoring(place)
            return
        case .opening:
            phase = .reading
        case .reading:
            break
        }
        record(Self.position(atVisibleBottom: visibleBottom))
    }

    func pageRestored(at visibleBottom: Double?) {
        if case .restoring = phase { phase = .reading }
        pageReported(visibleBottom)
    }

    func leave() {
        pendingSave?.cancel()
        guard let current else { return }
        Task {
            if await save(current) { lastSaved = current }
        }
    }

    func refresh() {
        leave()
        let place = current ?? lastSaved
        phase = pageShowsText ? .reloading(returnTo: place) : .opening(returnTo: place)
    }

    private func record(_ position: Double) {
        current = position
        guard abs(position - lastSaved) > 0.01 else { return }
        pendingSave = Task {
            try? await settle()
            guard !Task.isCancelled else { return }
            let saved = await save(position)
            guard saved, !Task.isCancelled else { return }
            lastSaved = position
        }
    }

    private static func position(atVisibleBottom visibleBottom: Double) -> Double {
        let position = min(1, max(0, visibleBottom))
        return position >= 0.95 ? 1 : position
    }

    private enum Phase: Equatable {
        case opening(returnTo: Double)
        case restoring(Double)
        case reading
        case reloading(returnTo: Double)
    }
}
