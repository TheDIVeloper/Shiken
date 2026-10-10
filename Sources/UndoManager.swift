import Foundation
import SwiftData

/// Reversible destructive actions.
///
/// Deleting a subject takes its topics, assessments, plan blocks and study
/// sessions with it, and that is a lot to lose to a stray click. Undo exists so
/// that action costs nothing: press it, see it go, press it back.
///
/// The destructive step runs immediately, because a delete that has not visibly
/// happened looks broken. The reversal works from a value-type snapshot taken
/// beforehand, so re-inserting rebuilds the graph rather than undeleting a
/// dangling reference.
///
/// Undo snapshots live in memory only. There is no reason to survive a relaunch:
/// a pending undo is at most seconds old, and persisting it would mean a
/// half-deleted subject surviving a crash.
@MainActor
final class ActionUndo: ObservableObject {
    /// A pending action. `revert` is the reversal, held until it is either used
    /// or the window closes.
    struct PendingAction {
        let label: String
        let revert: () -> Void
    }

    @Published private(set) var pending: PendingAction?
    @Published var message: String?

    private var expiry: Task<Void, Never>?

    /// Runs the destructive step now and keeps its reversal available. Only the
    /// most recent action is undoable, which matches how every other tool behaves
    /// and avoids a queue of stale restore buttons.
    func record(label: String, perform: @escaping () -> Void, revert: @escaping () -> Void) {
        expiry?.cancel()
        perform()
        pending = PendingAction(label: label, revert: revert)
        message = "\(label)"
        startExpiry()
    }

    func undo() {
        guard let action = pending else { return }
        expiry?.cancel()
        expiry = nil
        action.revert()
        pending = nil
        message = "Undone: \(action.label)"
        startExpiry()
    }

    /// Dismiss the banner without undoing. The action already happened; this only
    /// stops the offer.
    func clearPending() {
        expiry?.cancel()
        expiry = nil
        pending = nil
        message = nil
    }

    private func startExpiry() {
        let text = message
        expiry = Task { [weak self] in
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled else { return }
            if self?.message == text {
                self?.message = nil
                self?.pending = nil
            }
        }
    }

    func clear() {
        expiry?.cancel()
        expiry = nil
        pending = nil
        message = nil
    }

    deinit {
        expiry?.cancel()
    }
}

/// The destructive operations in the app, each paired with its exact reversal.
///
/// Kept in one place because the reversal is the part that is easy to get wrong
/// and hard to notice: a delete that is not fully undone leaves the user with a
/// subject whose sessions have silently vanished.
enum Undoable {
    /// Snapshot of a subject and everything hanging off it, taken before delete.
    struct SubjectSnapshot {
        let subject: Subject
        let position: Int
        let topics: [TopicSnapshot]
        let assessments: [AssessmentSnapshot]
        let sessions: [SessionSnapshot]
        let blocks: [BlockSnapshot]
        let dayTasks: [DayTaskSnapshot]
    }

    struct DayTaskSnapshot {
        let id: UUID
        let date: Date
        let title: String
        let isDone: Bool
        let topicID: UUID?
        let plannedMinutesHint: Int
        let isAdHoc: Bool
        let position: Int
        let createdAt: Date
    }

    struct TopicSnapshot {
        let id: UUID
        let title: String
        let weight: Int
        let position: Int
        let createdAt: Date
    }

    struct AssessmentSnapshot {
        let title: String
        let date: Date
        let position: Int
    }

    struct SessionSnapshot {
        /// Which topic this session belonged to, so it reattaches on restore.
        let topicID: UUID
        let startedAt: Date
        let focusedMinutes: Int
        let awayMinutes: Int
        let note: String?
    }

    struct BlockSnapshot {
        /// Which topic this block belonged to, by id. Restoring blocks requires
        /// knowing their owner; a flat list of blocks cannot be reattached.
        let topicID: UUID
        let weekIndex: Int
        let weekStart: Date
        let targetMinutes: Int
        let isDone: Bool
    }

    static func snapshot(_ subject: Subject) -> SubjectSnapshot {
        SubjectSnapshot(
            subject: subject,
            position: subject.position,
            topics: subject.topics.map {
                TopicSnapshot(
                    id: $0.id, title: $0.title, weight: $0.weight,
                    position: $0.position, createdAt: $0.createdAt
                )
            },
            assessments: subject.assessments.map {
                AssessmentSnapshot(title: $0.title, date: $0.date, position: $0.position)
            },
            // Sessions hang off topics, not the subject, so they are gathered
            // from the topic list rather than from `subject`.
            sessions: subject.topics.flatMap { topic in
                topic.sessions.map {
                    SessionSnapshot(
                        topicID: topic.id, startedAt: $0.startedAt,
                        focusedMinutes: $0.focusedMinutes,
                        awayMinutes: $0.awayMinutes, note: $0.note
                    )
                }
            },
            blocks: subject.topics.flatMap { topic in
                topic.planBlocks.map {
                    BlockSnapshot(
                        topicID: topic.id, weekIndex: $0.weekIndex, weekStart: $0.weekStart,
                        targetMinutes: $0.targetMinutes, isDone: $0.isDone
                    )
                }
            },
            dayTasks: subject.dayTasks.map {
                DayTaskSnapshot(
                    id: $0.id, date: $0.date, title: $0.title, isDone: $0.isDone,
                    topicID: $0.topicID, plannedMinutesHint: $0.plannedMinutesHint,
                    isAdHoc: $0.isAdHoc, position: $0.position, createdAt: $0.createdAt
                )
            }
        )
    }

    /// Re-inserts a deleted subject with its full graph, rebuilt from the
    /// snapshot. Ids are preserved so any selection or tick still points at the
    /// right row.
    static func restore(
        _ snapshot: SubjectSnapshot, in ctx: ModelContext
    ) {
        let subject = Subject(
            name: snapshot.subject.name,
            accentHex: snapshot.subject.accentHex,
            dailyMinutes: snapshot.subject.dailyMinutes,
            periodsPerWeek: snapshot.subject.periodsPerWeek,
            isEnrichment: snapshot.subject.isEnrichment,
            dayModeRaw: snapshot.subject.dayModeRaw,
            position: snapshot.position
        )
        subject.id = snapshot.subject.id
        subject.createdAt = snapshot.subject.createdAt
        subject.dailyMinutesIsDerived = snapshot.subject.dailyMinutesIsDerived
        ctx.insert(subject)

        // Ids are restored so plan blocks can reattach and any selection still
        // points at the row the user was looking at.
        var topicsByID: [UUID: Topic] = [:]
        for topicSnapshot in snapshot.topics {
            let topic = Topic(title: topicSnapshot.title, weight: topicSnapshot.weight)
            topic.id = topicSnapshot.id
            topic.position = topicSnapshot.position
            topic.createdAt = topicSnapshot.createdAt
            topic.subject = subject
            ctx.insert(topic)
            topicsByID[topic.id] = topic
        }

        for assessmentSnapshot in snapshot.assessments {
            let assessment = Assessment(
                title: assessmentSnapshot.title,
                date: assessmentSnapshot.date,
                position: assessmentSnapshot.position
            )
            assessment.subject = subject
            ctx.insert(assessment)
        }

        for blockSnapshot in snapshot.blocks {
            guard let topic = topicsByID[blockSnapshot.topicID] else { continue }
            let block = PlanBlock(
                weekIndex: blockSnapshot.weekIndex,
                weekStart: blockSnapshot.weekStart,
                targetMinutes: blockSnapshot.targetMinutes,
                isDone: blockSnapshot.isDone,
                topic: topic
            )
            ctx.insert(block)
        }

        for sessionSnapshot in snapshot.sessions {
            guard let topic = topicsByID[sessionSnapshot.topicID] else { continue }
            let session = StudySession(startedAt: sessionSnapshot.startedAt)
            session.focusedMinutes = sessionSnapshot.focusedMinutes
            session.awayMinutes = sessionSnapshot.awayMinutes
            session.note = sessionSnapshot.note
            session.subject = subject
            session.topic = topic
            ctx.insert(session)
        }

        for taskSnapshot in snapshot.dayTasks {
            let task = DayTask(
                date: taskSnapshot.date,
                title: taskSnapshot.title,
                isDone: taskSnapshot.isDone,
                topicID: taskSnapshot.topicID,
                plannedMinutesHint: taskSnapshot.plannedMinutesHint,
                isAdHoc: taskSnapshot.isAdHoc,
                position: taskSnapshot.position,
                subject: subject
            )
            task.id = taskSnapshot.id
            task.createdAt = taskSnapshot.createdAt
            ctx.insert(task)
        }

        try? ctx.save()
    }
}