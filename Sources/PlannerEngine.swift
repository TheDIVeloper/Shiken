import Foundation

// Pure, deterministic planner core. No SwiftData here — unit-testable in isolation.
// Everything the UI does about "what should I study this week" comes from these
// two functions.

struct TopicPlan: Equatable, Sendable {
    let topicID: UUID
    let title: String
    let weight: Int
}

struct ScheduledBlock: Equatable, Sendable {
    let weekIndex: Int // 0 = exam week, 1 = the week before, ...
    let topicID: UUID
    let minutes: Int // planned focused minutes for that week
}

enum PlannerEngine {
    /// Whole weeks between two day-boundaries, counting the exam week itself as 1.
    /// Examples: exam today → 1; exam in 6 days → 1; exam in exactly 1 week → 2.
    static func weeksBetween(_ examDate: Date, from today: Date = .now, calendar: Calendar = .current) -> Int {
        let startOfExam = calendar.startOfDay(for: examDate)
        let startOfToday = calendar.startOfDay(for: today)
        let days = calendar.dateComponents([.day], from: startOfToday, to: startOfExam).day ?? 0
        let weeks = Int((Double(max(0, days) + 1) / 7.0).rounded(.up))
        return min(max(1, weeks), 26)
    }

    /// Builds one `ScheduledBlock` per topic per week, weighted by topic weight.
    /// Weekly minutes = dailyMinutes x 7, split across topics by weight; remainder
    /// goes to the largest fractional leftovers so every week sums exactly.
    static func schedule(topics: [TopicPlan], examDate: Date, dailyMinutes: Int, from today: Date = .now) -> [ScheduledBlock] {
        guard !topics.isEmpty else { return [] }
        let weights = topics.map { max(1, $0.weight) }
        let totalWeight = weights.reduce(0, +)
        let weeklyTotal = max(1, dailyMinutes) * 7

        var blocks: [ScheduledBlock] = []
        for week in 0..<weeksBetween(examDate, from: today, calendar: .current) {
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
            for (idx, topic) in topics.enumerated() {
                blocks.append(ScheduledBlock(weekIndex: week, topicID: topic.topicID, minutes: minutes[idx]))
            }
        }
        return blocks
    }
}