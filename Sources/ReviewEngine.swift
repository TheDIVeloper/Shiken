import Foundation

// Pure planned-vs-actual analysis. No SwiftData — views map models into these
// value types. This is where the app earns its name: the honest gap between
// what was scheduled and what actually happened.

struct SessionRecord: Equatable, Sendable {
    let subjectID: UUID?
    let topicID: UUID?
    let focusedMinutes: Int
    let startedAt: Date
}

struct TopicReview: Equatable, Sendable {
    let topicID: UUID
    let title: String
    let plannedMinutes: Int
    let actualMinutes: Int
    var gapMinutes: Int { actualMinutes - plannedMinutes }
}

struct SubjectReview: Equatable, Sendable {
    let subjectID: UUID
    let name: String
    let accentHex: String
    let plannedMinutes: Int
    let actualMinutes: Int
    let topics: [TopicReview]
    var gapMinutes: Int { actualMinutes - plannedMinutes }
    var completionPercent: Int {
        guard plannedMinutes > 0 else { return 0 }
        return Int((Double(actualMinutes) / Double(plannedMinutes) * 100).rounded())
    }
}

enum ReviewEngine {
    static let windowDays = 7

    /// The plan-column closest to now (exam week is 0).
    static func currentWeekIndex(examDate: Date, now: Date = .now, calendar: Calendar = .current) -> Int {
        PlannerEngine.weeksBetween(examDate, from: now, calendar: calendar) - 1
    }

    /// Sessions for one subject inside the trailing window (today inclusive).
    static func sessionsInWindow(_ sessions: [SessionRecord], subjectID: UUID, now: Date = .now, calendar: Calendar = .current) -> [SessionRecord] {
        let windowStart = calendar.date(byAdding: .day, value: -(windowDays - 1), to: now) ?? now
        let start = calendar.startOfDay(for: windowStart)
        return sessions.filter {
            $0.subjectID == subjectID && $0.startedAt >= start && $0.startedAt <= now
        }
    }

    static func review(
        subjectID: UUID,
        name: String,
        accentHex: String,
        topics: [TopicPlan],
        plan: [ScheduledBlock],
        sessions: [SessionRecord],
        examDate: Date,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> SubjectReview {
        let week = currentWeekIndex(examDate: examDate, now: now, calendar: calendar)
        let inWindow = sessionsInWindow(sessions, subjectID: subjectID, now: now, calendar: calendar)

        let topicReviews = topics.map { topic -> TopicReview in
            let planned = plan.first { $0.topicID == topic.topicID && $0.weekIndex == week }?.minutes ?? 0
            let actual = inWindow.filter { $0.topicID == topic.topicID }.map(\.focusedMinutes).reduce(0, +)
            return TopicReview(topicID: topic.topicID, title: topic.title, plannedMinutes: planned, actualMinutes: actual)
        }

        let planned = plan.filter { $0.weekIndex == week }.map(\.minutes).reduce(0, +)
        let actual = inWindow.map(\.focusedMinutes).reduce(0, +)

        return SubjectReview(
            subjectID: subjectID,
            name: name,
            accentHex: accentHex,
            plannedMinutes: planned,
            actualMinutes: actual,
            topics: topicReviews
        )
    }

    /// One honest sentence. Reaches, never punishes.
    static func verdict(planned: Int, actual: Int) -> String {
        guard planned > 0 else { return "No targets planned for this week." }
        let ratio = Double(actual) / Double(planned)
        let gap = abs(actual - planned)
        switch ratio {
        case 1...:
            return "Plan met — \(actual)m done against \(planned)m planned."
        case 0.8..<1:
            return "Close: \(gap)m short of the plan."
        case 0.5..<0.8:
            return "\(gap)m short — noticeable drift."
        default:
            return "Well behind: \(gap)m short. Cut the plan or protect the time."
        }
    }

    static func letter(for review: SubjectReview, weekOf: Date = .now) -> String {
        var lines: [String] = []
        lines.append("## \(review.name)")
        lines.append("Planned **\(review.plannedMinutes)m** · Actual **\(review.actualMinutes)m** · \(verdict(planned: review.plannedMinutes, actual: review.actualMinutes))")
        if !review.topics.isEmpty {
            lines.append("")
            for topic in review.topics {
                let gap = topic.gapMinutes
                let suffix = gap < 0 ? " (−\(-gap)m)" : (gap > 0 ? " (+\(gap)m)" : "")
                lines.append("- \(topic.title): \(topic.actualMinutes)m / \(topic.plannedMinutes)m planned\(suffix)")
            }
        }
        return lines.joined(separator: "\n")
    }

    static func markdown(for reviews: [SubjectReview], weekOf: Date = .now) -> String {
        var lines: [String] = []
        lines.append("# Shiken — weekly review")
        lines.append("Week of \(weekOf.formatted(date: .abbreviated, time: .omitted))")
        lines.append("")
        if reviews.isEmpty {
            lines.append("No subjects with exam dates yet.")
        } else {
            for review in reviews {
                lines.append(letter(for: review, weekOf: weekOf))
                lines.append("")
            }
        }
        lines.append("_Generated by Shiken._")
        return lines.joined(separator: "\n")
    }
}