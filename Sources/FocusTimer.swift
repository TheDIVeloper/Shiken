import Foundation
import Observation

struct CompletedSession: Equatable {
    let focusedSeconds: Int
    let awaySeconds: Int
    let startedAt: Date
}

/// Owns the focus countdown and interruption tracking. Lives above the views
/// (injected from ContentView) so switching rooms never kills a running timer.
/// It deliberately knows nothing about SwiftData — views turn a CompletedSession
/// into a persisted StudySession.
@MainActor
@Observable
final class FocusTimer {
    enum Phase { case idle, running, paused }

    private(set) var phase: Phase = .idle
    private(set) var elapsedSeconds: Int = 0
    private(set) var awaySeconds: Int = 0
    private(set) var startedAt: Date?
    var lengthMinutes: Int = 50

    /// Set when a session reaches zero; FocusView records it then clears this.
    var lastCompleted: CompletedSession?

    private var task: Task<Void, Never>?
    private var awaySince: Date?

    var isActive: Bool { phase == .running || phase == .paused }
    var remainingSeconds: Int { max(0, lengthMinutes * 60 - elapsedSeconds) }
    var focusedSeconds: Int { max(0, elapsedSeconds - awaySeconds) }

    func start() {
        reset()
        startedAt = Date()
        phase = .running
        schedule()
    }

    func pause() {
        guard phase == .running else { return }
        stopTask()
        phase = .paused
    }

    func resume() {
        guard phase == .paused else { return }
        phase = .running
        schedule()
    }

    @discardableResult
    func stop() -> CompletedSession? {
        let summary = makeSummary()
        stopTask()
        reset()
        return summary
    }

    func awayBegin() {
        guard phase == .running, awaySince == nil else { return }
        awaySince = Date()
    }

    func awayEnd() {
        awaySince = nil
    }

    private func makeSummary() -> CompletedSession? {
        guard let startedAt else { return nil }
        return CompletedSession(focusedSeconds: focusedSeconds, awaySeconds: awaySeconds, startedAt: startedAt)
    }

    private func reset() {
        elapsedSeconds = 0
        awaySeconds = 0
        startedAt = nil
        awaySince = nil
        phase = .idle
    }

    private func stopTask() {
        task?.cancel()
        task = nil
    }

    private func schedule() {
        stopTask()
        task = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                guard let self, !Task.isCancelled else { return }
                self.tick()
            }
        }
    }

    private func tick() {
        guard phase == .running else { return }
        elapsedSeconds += 1
        if awaySince != nil { awaySeconds += 1 }
        if elapsedSeconds >= lengthMinutes * 60 {
            lastCompleted = makeSummary()
            stopTask()
            reset()
        }
    }
}