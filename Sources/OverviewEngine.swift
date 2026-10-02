import Foundation

// Pure, deterministic cross-subject planning. No SwiftData, no views — the same
// convention as PlannerEngine: if it decides anything, it gets a unit test.
//
// Two questions this answers that no single subject's plan can:
//   1. What am I doing *today*, across everything?
//   2. What does the week look like across everything?
//
// Subject budgets stay independent (each subject keeps its own dailyMinutes).
// This aggregates them; it never re-weights them.

struct SubjectPlanInput: Equatable, Sendable {
    let id: UUID
    let name: String
    let accentHex: String
    let examDate: Date?
    let dailyMinutes: Int
    let topics: [TopicPlan]

    init(
        id: UUID,
        name: String,
        accentHex: String,
        examDate: Date?,
        dailyMinutes: Int,
        topics: [TopicPlan]
    ) {
        self.id = id
        self.name = name
        self.accentHex = accentHex
        self.examDate = examDate
        self.dailyMinutes = dailyMinutes
        self.topics = topics
    }
}

struct PlannedEntry: Equatable, Sendable, Identifiable {
    var id: UUID { topicID }
    let topicID: UUID
    let title: String
    let minutes: Int
    let isSynthetic: Bool
}

struct PlannedSubject: Equatable, Sendable, Identifiable {
    var id: UUID { subjectID }
    let subjectID: UUID
    let name: String
    let accentHex: String
    let examDate: Date
    let totalMinutes: Int
    /// One row per planned topic. `minutes` is whatever this day/week column holds.
    let entries: [PlannedEntry]
    /// Minutes for the whole current week, for the weekly ✓ aggregate.
    let weekMinutes: Int
    let isDone: Bool?
}

struct OverviewDay: Equatable, Sendable, Identifiable {
    var id: Int { dayIndex }
    let dayIndex: Int
    let date: Date
    let subjects: [PlannedSubject]
    let totalMinutes: Int
}

struct Overview: Equatable, Sendable {
    let days: [OverviewDay]
    /// Subjects left out because they have no exam date, so no plan exists.
    /// Surfaced rather than silently dropped — an under-reported total that
    /// looks complete is worse than an obviously incomplete one.
    let excluded: [String]

    var today: OverviewDay? { days.first }
    var weekTotalMinutes: Int { days.reduce(0) { $0 + $1.totalMinutes } }
}

enum OverviewEngine {
    static func overview(
        subjects: [SubjectPlanInput],
        days: Int = 7,
        from today: Date = .now,
        calendar: Calendar = .current,
        isDone: (UUID, Int) -> Bool? = { _, _ in nil }
    ) -> Overview {
        let clampedDays = max(1, min(7, days))

        let planned = subjects.compactMap { subject -> SubjectPlanInput? in
            guard subject.examDate != nil else { return nil }
            return subject
        }
        let excluded = subjects.filter { $0.examDate == nil }.map(\.name)

        let dayDates = (0..<clampedDays).compactMap {
            calendar.date(byAdding: .day, value: $0, to: today)
        }

        let byDay: [[PlannedSubject]] = dayDates.indices.map { dayIndex in
            planned.compactMap { subject in
                subjectSlice(subject, dayIndex: dayIndex, today: today, calendar: calendar,
                             totalDays: clampedDays, isDone: isDone)
            }
        }

        let overviewDays = dayDates.indices.map { index in
            OverviewDay(
                dayIndex: index,
                date: dayDates[index],
                subjects: byDay[index],
                totalMinutes: byDay[index].reduce(0) { $0 + $1.totalMinutes }
            )
        }

        return Overview(days: overviewDays, excluded: excluded)
    }

    /// Days this subject can still be revised on, counting today: its own exam
    /// date caps the week, so we never plan revision for a past exam.
    static func remainingDays(subject: SubjectPlanInput, today: Date, calendar: Calendar) -> Int {
        guard let exam = subject.examDate else { return 0 }
        let days = calendar.dateComponents(
            [.day],
            from: calendar.startOfDay(for: today),
            to: calendar.startOfDay(for: exam)
        ).day ?? 0
        return max(1, min(7, days + 1))
    }

    private static func subjectSlice(
        _ subject: SubjectPlanInput,
        dayIndex: Int,
        today: Date,
        calendar: Calendar,
        totalDays: Int,
        isDone: (UUID, Int) -> Bool?
    ) -> PlannedSubject? {
        guard let exam = subject.examDate else { return nil }

        let topics = PlannerEngine.effectiveTopics(
            subjectID: subject.id, subjectName: subject.name, topics: subject.topics
        )
        guard !topics.isEmpty else { return nil }

        let weekIndex = PlannerEngine.weeksBetween(exam, from: today, calendar: calendar) - 1
        let blocks = PlannerEngine.schedule(
            topics: topics, examDate: exam, dailyMinutes: subject.dailyMinutes,
            from: today, calendar: calendar
        )
        let weekly = blocks.filter { $0.weekIndex == weekIndex }
        guard !weekly.isEmpty else { return nil }

        let available = min(remainingDays(subject: subject, today: today, calendar: calendar), totalDays)
        let spread = PlannerEngine.dailyBreakdown(
            weeklyMinutes: weekly.map(\.minutes), days: max(1, available)
        )

        let entries = topics.indices.compactMap { index -> PlannedEntry? in
            guard index < spread.count else { return nil }
            let minutes = dayIndex < spread[index].count ? spread[index][dayIndex] : 0
            guard minutes > 0 else { return nil }
            return PlannedEntry(
                topicID: topics[index].topicID,
                title: topics[index].title,
                minutes: minutes,
                isSynthetic: topics[index].isSynthetic
            )
        }
        guard !entries.isEmpty else { return nil }

        let weekMinutes = weekly.reduce(0) { $0 + $1.minutes }

        // Only real topics have a checkbox to tick, so only they can be done.
        // Asking about a stand-in would report a completion the user never made.
        let tickable = entries.filter { !$0.isSynthetic }
        let doneFlags = tickable.map { entry in
            isDone(entry.topicID, weekIndex) ?? false
        }
        let hasTicks = doneFlags.contains { $0 }
        let isDone: Bool? = if tickable.isEmpty {
            nil
        } else if doneFlags.allSatisfy({ $0 }) {
            true
        } else if hasTicks {
            false
        } else {
            nil
        }

        return PlannedSubject(
            subjectID: subject.id,
            name: subject.name,
            accentHex: subject.accentHex,
            examDate: exam,
            totalMinutes: entries.reduce(0) { $0 + $1.minutes },
            entries: entries,
            weekMinutes: weekMinutes,
            isDone: isDone
        )
    }
}