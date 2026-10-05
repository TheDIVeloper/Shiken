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
    let dailyMinutes: Int
    let topics: [TopicPlan]
    /// Every dated thing this subject is revised for. The plan is driven by the
    /// next one still ahead; the rest show up as markers only.
    let assessments: [AssessmentRef]

    init(
        id: UUID,
        name: String,
        accentHex: String,
        dailyMinutes: Int,
        topics: [TopicPlan],
        assessments: [AssessmentRef]
    ) {
        self.id = id
        self.name = name
        self.accentHex = accentHex
        self.dailyMinutes = dailyMinutes
        self.topics = topics
        self.assessments = assessments
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
    /// The assessment this subject's plan is currently built around.
    let driver: AssessmentRef
    /// Anything after the driver. Markers only: these do not reshape the plan.
    let upcoming: [AssessmentRef]
    let totalMinutes: Int
    /// One row per planned topic. `minutes` is whatever this day/week column holds.
    let entries: [PlannedEntry]
    /// Minutes for the whole current week, for the weekly ✓ aggregate.
    let weekMinutes: Int
    let isDone: Bool?
    /// Minutes actually logged against this subject on this day.
    let actualMinutes: Int

    /// This subject's own target for this day is met.
    var isMet: Bool { totalMinutes > 0 && actualMinutes >= totalMinutes }
    var remainingMinutes: Int { max(0, totalMinutes - actualMinutes) }
    var completionPercent: Int {
        guard totalMinutes > 0 else { return 0 }
        return min(100, Int((Double(actualMinutes) / Double(totalMinutes) * 100).rounded()))
    }
}

struct OverviewDay: Equatable, Sendable, Identifiable {
    var id: Int { dayIndex }
    let dayIndex: Int
    let date: Date
    let subjects: [PlannedSubject]
    let totalMinutes: Int

    /// Focused minutes actually logged on this day across every subject.
    /// Zero for future days — you cannot have done tomorrow yet.
    let actualMinutes: Int

    /// The target is met. Reaching it is the point, so this is the one place
    /// the app celebrates; it never nags about the days you missed.
    var isMet: Bool { totalMinutes > 0 && actualMinutes >= totalMinutes }
    var completionPercent: Int {
        guard totalMinutes > 0 else { return 0 }
        return min(100, Int((Double(actualMinutes) / Double(totalMinutes) * 100).rounded()))
    }
    var remainingMinutes: Int { max(0, totalMinutes - actualMinutes) }
}

struct Overview: Equatable, Sendable {
    let days: [OverviewDay]
    /// Subjects with no assessment dated today or later, so no plan exists for
    /// them. Surfaced rather than silently dropped — an under-reported total that
    /// looks complete is worse than an obviously incomplete one.
    let excluded: [String]
    /// Subjects whose assessments have all passed. These leave the Plan entirely
    /// but keep their sidebar row and their history.
    let finished: [String]

    var today: OverviewDay? { days.first }
    var weekTotalMinutes: Int { days.reduce(0) { $0 + $1.totalMinutes } }
}

enum OverviewEngine {
    /// One focused session, mapped into the engine by the view. Keeps the engine
    /// free of SwiftData while still letting it answer "did I hit today's target".
    struct ActualRecord: Equatable, Sendable {
        let subjectID: UUID?
        let topicID: UUID?
        let focusedMinutes: Int
        let startedAt: Date
    }

    static func overview(
        subjects: [SubjectPlanInput],
        days: Int = 7,
        from today: Date = .now,
        calendar: Calendar = .current,
        isDone: (UUID, Date) -> Bool? = { _, _ in nil },
        actuals: [ActualRecord] = []
    ) -> Overview {
        let clampedDays = max(1, min(7, days))

        // A subject joins the plan only if it has an assessment still ahead of
        // it. Two ways to miss out, and the view reports them differently:
        // nothing set up at all, versus everything already sat.
        let live = subjects.compactMap { subject -> (SubjectPlanInput, AssessmentRef)? in
            guard let next = PlannerEngine.nextAssessment(subject.assessments, now: today, calendar: calendar)
            else { return nil }
            return (subject, next)
        }
        let liveIDs = Set(live.map { $0.0.id })
        let offPlan = subjects.filter { !liveIDs.contains($0.id) }
        let excluded = offPlan.filter { $0.assessments.isEmpty }.map(\.name)
        let finished = offPlan.filter { !$0.assessments.isEmpty }.map(\.name)

        let dayDates = (0..<clampedDays).compactMap {
            calendar.date(byAdding: .day, value: $0, to: today)
        }

        let byDay: [[PlannedSubject]] = dayDates.indices.map { dayIndex in
            live.compactMap { entry in
                subjectSlice(entry.0, driver: entry.1, dayIndex: dayIndex, today: today, calendar: calendar,
                             totalDays: clampedDays, isDone: isDone, actuals: actuals)
            }
        }

        let overviewDays = dayDates.indices.map { index in
            let dayStart = calendar.startOfDay(for: dayDates[index])
            let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart
            let loggedToday = actuals
                .filter { $0.startedAt >= dayStart && $0.startedAt < dayEnd }
                .reduce(0) { $0 + $1.focusedMinutes }
            return OverviewDay(
                dayIndex: index,
                date: dayDates[index],
                subjects: byDay[index],
                totalMinutes: byDay[index].reduce(0) { $0 + $1.totalMinutes },
                actualMinutes: loggedToday
            )
        }

        return Overview(days: overviewDays, excluded: excluded, finished: finished)
    }

    /// Days this subject can still be revised on, counting today. The assessment
    /// driving the plan caps the week, so we never plan revision past it.
    static func remainingDays(
        driver: AssessmentRef, today: Date, calendar: Calendar
    ) -> Int {
        let days = calendar.dateComponents(
            [.day],
            from: calendar.startOfDay(for: today),
            to: calendar.startOfDay(for: driver.date)
        ).day ?? 0
        return max(1, min(7, days + 1))
    }

    private static func subjectSlice(
        _ subject: SubjectPlanInput,
        driver: AssessmentRef,
        dayIndex: Int,
        today: Date,
        calendar: Calendar,
        totalDays: Int,
        isDone: (UUID, Date) -> Bool?,
        actuals: [ActualRecord]
    ) -> PlannedSubject? {
        let topics = PlannerEngine.effectiveTopics(
            subjectID: subject.id, subjectName: subject.name, topics: subject.topics
        )
        guard !topics.isEmpty else { return nil }

        let weekIndex = PlannerEngine.weeksBetween(driver.date, from: today, calendar: calendar) - 1
        let blocks = PlannerEngine.schedule(
            topics: topics, driver: driver.date, dailyMinutes: subject.dailyMinutes,
            from: today, calendar: calendar
        )
        let weekly = blocks.filter { $0.weekIndex == weekIndex }
        guard !weekly.isEmpty else { return nil }

        let available = min(remainingDays(driver: driver, today: today, calendar: calendar), totalDays)
        // Split the daily target rather than dividing the week's total, so the
        // figure the user set is the figure every day shows, however near the
        // assessment is. Beyond the deadline there is simply nothing planned.
        let dailySplit = PlannerEngine.dailyTopicSplit(topics: topics, dailyMinutes: subject.dailyMinutes)

        let entries = topics.indices.compactMap { index -> PlannedEntry? in
            guard index < dailySplit.count, dayIndex < available else { return nil }
            let minutes = dailySplit[index]
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
        let anchor = PlannerEngine.weekStart(forWeekIndex: weekIndex, driver: driver.date, now: today, calendar: calendar)

        // Only real topics have a checkbox to tick, so only they can be done.
        // Asking about a stand-in would report a completion the user never made.
        let tickable = entries.filter { !$0.isSynthetic }
        let doneFlags = tickable.map { entry in
            isDone(entry.topicID, anchor) ?? false
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

        let dayStart = calendar.startOfDay(for: today)
        let dayOffset = dayIndex
        guard let dayDate = calendar.date(byAdding: .day, value: dayOffset, to: dayStart) else {
            return nil
        }
        let windowEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart
        let actualMinutes = actuals
            .filter {
                $0.subjectID == subject.id
                    && $0.startedAt >= dayDate
                    && $0.startedAt < windowEnd
            }
            .reduce(0) { $0 + $1.focusedMinutes }

        return PlannedSubject(
            subjectID: subject.id,
            name: subject.name,
            accentHex: subject.accentHex,
            driver: driver,
            upcoming: PlannerEngine.upcomingAfter(driver, in: subject.assessments, now: today, calendar: calendar),
            totalMinutes: entries.reduce(0) { $0 + $1.minutes },
            entries: entries,
            weekMinutes: weekMinutes,
            isDone: isDone,
            actualMinutes: actualMinutes
        )
    }
}