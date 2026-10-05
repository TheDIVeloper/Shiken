import Foundation

// Pure, deterministic planner core. No SwiftData here — unit-testable in isolation.
// Everything the UI does about "what should I study this week" comes from these
// functions.
//
// A subject has several assessments, but only one of them drives the plan at a
// time: the next one still ahead of you. Revising for a SAC three weeks out beats
// pretending it's two months away, and waiting until the day after it to start
// planning for the exam is worse than useless. Later assessments are markers, not
// drivers.

struct TopicPlan: Equatable, Sendable, Identifiable {
    let topicID: UUID
    let title: String
    let weight: Int
    /// A stand-in row standing in for "this subject as a whole". Never persisted,
    /// so it has no `Topic` to tick off — the UI must not pretend otherwise.
    var isSynthetic: Bool = false

    var id: UUID { topicID }
}

struct ScheduledBlock: Equatable, Sendable {
    let weekIndex: Int // 0 = the driver's week, 1 = the week before, ...
    let topicID: UUID
    let minutes: Int // planned focused minutes for that week
    /// The calendar week this block covers. PlanBlock stores this rather than
    /// weekIndex so a tick survives the driver moving to a different assessment.
    let weekStart: Date
}

/// A dated assessment, mapped out of SwiftData by the views.
struct AssessmentRef: Equatable, Sendable, Identifiable {
    let id: UUID
    let title: String
    let date: Date

    init(id: UUID = UUID(), title: String, date: Date) {
        self.id = id
        self.title = title
        self.date = date
    }
}

enum PlannerEngine {
    /// Whole weeks between two day-boundaries, counting the driver's week as 1.
    /// Examples: today → 1; in 6 days → 1; in exactly 1 week → 2.
    /// A date already past clamps to 1 rather than going to zero or negative, so
    /// callers get a usable plan instead of an empty one.
    static func weeksBetween(_ driver: Date, from today: Date = .now, calendar: Calendar = .current) -> Int {
        let startOfDriver = calendar.startOfDay(for: driver)
        let startOfToday = calendar.startOfDay(for: today)
        let days = calendar.dateComponents([.day], from: startOfToday, to: startOfDriver).day ?? 0
        let weeks = Int((Double(max(0, days) + 1) / 7.0).rounded(.up))
        return min(max(1, weeks), 26)
    }

    // MARK: - Choosing the driver

    /// The next assessment still ahead of the user, earliest first. This is what
    /// the plan is built against. Nil means everything is in the past, so there is
    /// nothing left to revise for.
    static func nextAssessment(
        _ assessments: [AssessmentRef],
        now: Date = .now,
        calendar: Calendar = .current
    ) -> AssessmentRef? {
        let startOfToday = calendar.startOfDay(for: now)
        return assessments
            .filter { calendar.startOfDay(for: $0.date) >= startOfToday }
            .min { lhs, rhs in
                let l = calendar.startOfDay(for: lhs.date)
                let r = calendar.startOfDay(for: rhs.date)
                return l == r ? lhs.title < rhs.title : l < r
            }
    }

    /// Everything after the driver, so the UI can show what is coming without
    /// letting it reshape the plan.
    static func upcomingAfter(
        _ driver: AssessmentRef,
        in assessments: [AssessmentRef],
        now: Date = .now,
        calendar: Calendar = .current
    ) -> [AssessmentRef] {
        let startOfToday = calendar.startOfDay(for: now)
        return assessments
            .filter { $0.id != driver.id && calendar.startOfDay(for: $0.date) >= startOfToday }
            .sorted { lhs, rhs in
                let l = calendar.startOfDay(for: lhs.date)
                let r = calendar.startOfDay(for: rhs.date)
                return l == r ? lhs.title < rhs.title : l < r
            }
    }

    /// True once every assessment is behind us. The subject then leaves the Plan
    /// view but stays in the sidebar with its history intact.
    ///
    /// An empty list is NOT finished. No assessments means nothing has been set
    /// up, which the UI reports differently from "all done" — collapsing the two
    /// would quietly archive a subject the user still means to use.
    static func isFinished(
        _ assessments: [AssessmentRef],
        now: Date = .now,
        calendar: Calendar = .current
    ) -> Bool {
        guard !assessments.isEmpty else { return false }
        return nextAssessment(assessments, now: now, calendar: calendar) == nil
    }

    // MARK: - Week anchoring

    /// Start of the calendar week containing `date`. Week boundaries come from the
    /// calendar, so this respects whatever locale the user is in.
    static func weekStart(containing date: Date, calendar: Calendar = .current) -> Date {
        let comps = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        return calendar.date(from: comps) ?? calendar.startOfDay(for: date)
    }

    /// The calendar week `weekIndex` steps back from the driver's week.
    static func weekStart(
        forWeekIndex weekIndex: Int,
        driver: Date,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> Date {
        let driverWeek = weekStart(containing: driver, calendar: calendar)
        return calendar.date(byAdding: .day, value: -7 * weekIndex, to: driverWeek) ?? driverWeek
    }

    // MARK: - Scheduling

    /// Builds one `ScheduledBlock` per topic per week, weighted by topic weight.
    /// Weekly minutes = dailyMinutes x 7, split across topics by weight; remainder
    /// goes to the largest fractional leftovers so every week sums exactly.
    ///
    /// Note the weekly total is deliberately flat across weeks: dailyMinutes is the
    /// user's stated figure for the subject and it does not ramp up as an
    /// assessment approaches. Assessments decide how long the ladder is, not how
    /// heavy any single week is.
    static func schedule(
        topics: [TopicPlan],
        driver: Date,
        dailyMinutes: Int,
        from today: Date = .now,
        calendar: Calendar = .current
    ) -> [ScheduledBlock] {
        guard !topics.isEmpty else { return [] }
        let weights = topics.map { max(1, $0.weight) }
        let totalWeight = weights.reduce(0, +)
        let weeklyTotal = max(1, dailyMinutes) * 7

        var blocks: [ScheduledBlock] = []
        for week in 0..<weeksBetween(driver, from: today, calendar: calendar) {
            let exact = weights.map { Double(weeklyTotal) * Double($0) / Double(totalWeight) }
            var minutes = exact.map { Int($0.rounded(.down)) }
            let remainder = weeklyTotal - minutes.reduce(0, +)
            let order = exact.indices.sorted { lhs, rhs in
                let lhsFrac = exact[lhs] - Double(minutes[lhs])
                let rhsFrac = exact[rhs] - Double(minutes[rhs])
                return lhsFrac == rhsFrac ? lhs < rhs : lhsFrac > rhsFrac
            }
            for i in 0..<min(remainder, order.count) {
                minutes[order[i]] += 1
            }
            let anchor = weekStart(forWeekIndex: week, driver: driver, now: today, calendar: calendar)
            for (idx, topic) in topics.enumerated() {
                blocks.append(
                    ScheduledBlock(
                        weekIndex: week,
                        topicID: topic.topicID,
                        minutes: minutes[idx],
                        weekStart: anchor
                    )
                )
            }
        }
        return blocks
    }

    /// A subject nobody has broken into topics yet still deserves a plan: one
    /// block standing for the subject as a whole. The stand-in borrows the
    /// subject's own UUID, so its identity is stable across re-renders without
    /// persisting anything or hashing a name.
    static func effectiveTopics(subjectID: UUID, subjectName: String, topics: [TopicPlan]) -> [TopicPlan] {
        guard topics.isEmpty else { return topics }
        return [TopicPlan(topicID: subjectID, title: subjectName, weight: 1, isSynthetic: true)]
    }

    /// Splits one day's target across topics by weight, preserving the exact total.
    ///
    /// This is the daily counterpart to `schedule`. It exists because spreading a
    /// week's total over the few days left before an assessment inflates the daily
    /// figure: a 60m subject with an assessment in three days would jump to 105m/day.
    /// A deadline should shorten the ladder, not change how heavy each day is.
    static func dailyTopicSplit(
        topics: [TopicPlan], dailyMinutes: Int
    ) -> [Int] {
        guard !topics.isEmpty else { return [] }
        let weights = topics.map { max(1, $0.weight) }
        let totalWeight = weights.reduce(0, +)
        let total = max(0, dailyMinutes)

        let exact = weights.map { Double(total) * Double($0) / Double(totalWeight) }
        var minutes = exact.map { Int($0.rounded(.down)) }
        let remainder = total - minutes.reduce(0, +)
        let order = exact.indices.sorted { lhs, rhs in
            let lhsFrac = exact[lhs] - Double(minutes[lhs])
            let rhsFrac = exact[rhs] - Double(minutes[rhs])
            return lhsFrac == rhsFrac ? lhs < rhs : lhsFrac > rhsFrac
        }
        for i in 0..<min(remainder, order.count) {
            minutes[order[i]] += 1
        }
        return minutes
    }

    /// Splits each topic's weekly minutes across `days` (default 7) as evenly as
    /// possible: floor(W/days) plus the remainder spread one minute at a time onto
    /// the earliest days. Totals are preserved exactly.
    static func dailyBreakdown(weeklyMinutes: [Int], days: Int = 7) -> [[Int]] {
        guard days > 0 else { return weeklyMinutes.map { [$0] } }
        return weeklyMinutes.map { weekly in
            guard weekly > 0 else { return Array(repeating: 0, count: days) }
            let base = weekly / days
            let remainder = weekly % days
            return (0..<days).map { $0 < remainder ? base + 1 : base }
        }
    }
}