import Foundation
import SwiftData

// Translates SwiftData models into the planner's plain value types. Keeping this
// in one place means the engines stay free of SwiftData and every view agrees on
// what "the next assessment" means.

extension Subject {
    var assessmentRefs: [AssessmentRef] {
        sortedAssessments.map { AssessmentRef(id: $0.id, title: $0.title, date: $0.date) }
    }

    /// The assessment the plan is currently built around: the next one dated today
    /// or later. Nil once they're all in the past.
    var nextAssessment: Assessment? {
        let startOfToday = Calendar.current.startOfDay(for: .now)
        return sortedAssessments
            .filter { Calendar.current.startOfDay(for: $0.date) >= startOfToday }
            .min { lhs, rhs in
                let l = Calendar.current.startOfDay(for: lhs.date)
                let r = Calendar.current.startOfDay(for: rhs.date)
                return l == r ? lhs.position < rhs.position : l < r
            }
    }

    /// Everything after the driver, earliest first.
    var upcomingAssessments: [Assessment] {
        guard let next = nextAssessment else { return [] }
        let driverDate = Calendar.current.startOfDay(for: next.date)
        return sortedAssessments
            .filter { Calendar.current.startOfDay(for: $0.date) > driverDate }
    }

    /// True once every assessment is behind us. The subject leaves the Plan view
    /// but stays in the sidebar, so its topics and history remain reachable.
    var isFinished: Bool {
        !assessmentRefs.isEmpty && nextAssessment == nil
    }

    var topicPlans: [TopicPlan] {
        topics
            .sorted { $0.position < $1.position }
            .map { TopicPlan(topicID: $0.id, title: $0.title, weight: max(1, $0.weight)) }
    }

    var planInput: SubjectPlanInput {
        SubjectPlanInput(
            id: id,
            name: name,
            accentHex: accentHex,
            dailyMinutes: dailyMinutes,
            topics: topicPlans,
            assessments: assessmentRefs
        )
    }
}

/// An assessment being edited, before it is committed to the store.
struct AssessmentDraft: Identifiable, Equatable {
    let id: UUID
    var title: String
    var date: Date
    /// True for rows this session created, so the UI can label them and so a
    /// never-saved row can be discarded without touching the store.
    var isNew: Bool

    init(id: UUID = UUID(), title: String, date: Date, isNew: Bool = false) {
        self.id = id
        self.title = title
        self.date = date
        self.isNew = isNew
    }

    /// A row with no name is not worth storing. Falls back to a readable default
    /// rather than saving a blank row the user would have to notice and fix.
    var resolvedTitle: String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Assessment" : trimmed
    }
}

/// Turns a list of drafts into stored assessments: update, insert, delete.
enum AssessmentSync {
    /// Returns how many assessments were saved, and how many rows were dropped
    /// for having no name at all. Dropping is deliberate but worth reporting, so
    /// the UI can say so rather than losing a row silently.
    @discardableResult
    static func apply(
        _ drafts: [AssessmentDraft],
        to subject: Subject,
        in ctx: ModelContext
    ) -> (saved: Int, dropped: Int) {
        var survivors: Set<UUID> = []
        var saved = 0
        var dropped = 0

        for (position, draft) in drafts.enumerated() {
            let name = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else {
                dropped += 1
                continue
            }
            survivors.insert(draft.id)
            saved += 1

            if let existing = subject.assessments.first(where: { $0.id == draft.id }) {
                existing.title = name
                existing.date = draft.date
                existing.position = position
            } else {
                let created = Assessment(title: name, date: draft.date, position: position)
                // Carry the draft's identity onto the stored row. Without this the
                // new Assessment gets a fresh UUID, the survivor set never matches
                // it, and the deletion sweep below removes the row it just made —
                // which is exactly how adding an assessment silently did nothing.
                created.id = draft.id
                created.subject = subject
                ctx.insert(created)
            }
        }

        for existing in subject.assessments where !survivors.contains(existing.id) {
            ctx.delete(existing)
        }

        return (saved, dropped)
    }
}