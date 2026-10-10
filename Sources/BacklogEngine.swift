import Foundation
import SwiftUI
import SwiftData

/// One topic from a day that has already gone by and was not done.
///
/// Deliberately not a deficit in minutes. A number of minutes to repay is a debt
/// display, and debt displays discourage people from opening the app at all.
/// This is a work list instead: one topic, one small action, and dismissing it
/// costs nothing.
struct BacklogItem: Equatable, Sendable, Identifiable {
    var id: UUID { topicID }
    let topicID: UUID
    let subjectID: UUID
    let subjectName: String
    let subjectAccentHex: String
    let title: String
    /// The day this was planned for and missed.
    let missedOn: Date
    /// False for a stand-in row created for a topicless subject: there is no
    /// real topic to tick, so it must not appear as something to pull forward.
    let isTickable: Bool

    var subtitle: String {
        let day = missedOn.formatted(.dateTime.weekday(.abbreviated))
        return "\(subjectName) · \(day)"
    }
}

enum BacklogEngine {
    /// How far back to look. Two weeks is enough to catch a bad fortnight without
    /// resurfacing a term-old topic that is genuinely no longer relevant.
    static let lookbackDays = 14

    /// Topics planned on days now past that are not ticked, oldest first.
    ///
    /// The plan is read from `PlanBlock`, which already records the topic, the
    /// week and whether it was ticked, so this is mostly a read. One rule holds
    /// it together: a topic that was ticked in *any* later week is not backlog,
    /// because the user has already come back to it.
    static func backlog(
        subjects: [SubjectPlanInput],
        blocks: [BacklogBlock],
        today: Date = .now,
        calendar: Calendar = .current,
        lookbackDays: Int = lookbackDaysDefault
    ) -> [BacklogItem] {
        let startOfToday = calendar.startOfDay(for: today)
        guard let earliest = calendar.date(byAdding: .day, value: -lookbackDays, to: startOfToday) else {
            return []
        }

        // Anything the user has ever ticked for a topic counts as handled.
        let completedTopicIDs = Set(blocks.filter { $0.isDone }.map(\.topicID))

        var seen = Set<UUID>()
        var items: [BacklogItem] = []

        for subject in subjects {
            // Only subjects still being revised for have anything to be behind on.
            guard PlannerEngine.nextAssessment(
                subject.assessments, now: today, calendar: calendar
            ) != nil else { continue }

            let topics = PlannerEngine.effectiveTopics(
                subjectID: subject.id, subjectName: subject.name, topics: subject.topics
            )
            let byID = Dictionary(
                uniqueKeysWithValues: topics.map { ($0.topicID, $0) }
            )

            for block in blocks where block.subjectID == subject.id {
                guard block.weekStart < startOfToday, block.weekStart >= earliest else { continue }
                guard !block.isDone, !completedTopicIDs.contains(block.topicID) else { continue }
                guard let topic = byID[block.topicID] else { continue }
                // A stand-in row is a rendering device for a topicless subject,
                // not real work, so it is never offered as something to do.
                guard !topic.isSynthetic else { continue }
                guard seen.insert(block.topicID).inserted else { continue }

                items.append(BacklogItem(
                    topicID: block.topicID,
                    subjectID: subject.id,
                    subjectName: subject.name,
                    subjectAccentHex: subject.accentHex,
                    title: topic.title,
                    missedOn: block.weekStart,
                    isTickable: true
                ))
            }
        }

        return items.sorted { $0.missedOn < $1.missedOn }
    }

    static let lookbackDaysDefault = 14

    /// Blocks as the backlog needs them: who owns it, when, and whether ticked.
    struct BacklogBlock: Equatable, Sendable {
        let subjectID: UUID
        let topicID: UUID
        let weekStart: Date
        let isDone: Bool
    }
}

/// Backs the backlog UI: dismiss without doing, or pull one topic forward.
@MainActor
@Observable
final class BacklogModel {
    private(set) var items: [BacklogItem] = []
    /// Topics the user has hidden for now. Kept in memory only: dismissing is a
    /// "not today", not a decision to never mention it again, and a permanent
    /// record of what someone was avoiding would be the exact opposite of the
    /// tone this app wants.
    private var dismissed: Set<UUID> = []

    func load(
        subjects: [SubjectPlanInput],
        blocks: [BacklogEngine.BacklogBlock],
        today: Date = .now
    ) {
        items = BacklogEngine.backlog(subjects: subjects, blocks: blocks, today: today)
            .filter { !dismissed.contains($0.topicID) }
    }

    /// Mark the topic done now: the recovery action. This writes a tick against
    /// today's week, so the topic visibly moves forward instead of a debt
    /// counter ticking down.
    func complete(_ item: BacklogItem, in ctx: ModelContext) {
        guard let topic = fetchTopic(item.topicID, in: ctx) else { return }
        let today = Date.now
        let block = PlanBlock(
            weekIndex: 0,
            weekStart: Calendar.current.startOfDay(for: today),
            targetMinutes: 0,
            isDone: true,
            topic: topic
        )
        ctx.insert(block)
        try? ctx.save()
        items.removeAll { $0.topicID == item.topicID }
    }

    func dismiss(_ item: BacklogItem) {
        dismissed.insert(item.topicID)
        items.removeAll { $0.topicID == item.topicID }
    }

    private func fetchTopic(_ id: UUID, in ctx: ModelContext) -> Topic? {
        let descriptor = FetchDescriptor<Topic>()
        return (try? ctx.fetch(descriptor))?.first { $0.id == id }
    }
}