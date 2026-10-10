import Foundation

enum DayMode: String, CaseIterable, Sendable {
    case time = "time"
    case tasks = "tasks"

    var label: String {
        switch self {
        case .time: return "Time budget"
        case .tasks: return "Task checklist"
        }
    }
}

/// Pure, deterministic day-task derivation engine.
///
/// In task mode, daily completion is measured by ticking off concrete tasks
/// rather than logging focused minutes. Topic tasks derive live from the
/// planner's daily topic split, carrying the minutes as a hint rather than a
/// completion rule. Ad hoc tasks added by the user merge into the day.
struct DerivedDayTask: Equatable, Sendable, Identifiable {
    var id: UUID
    let taskRecordID: UUID?
    let subjectID: UUID
    let subjectName: String
    let subjectAccentHex: String
    let topicID: UUID?
    let title: String
    let plannedMinutesHint: Int
    let isAdHoc: Bool
    let isSynthetic: Bool
    let isDone: Bool
    let date: Date
}

struct DayTaskRecord: Equatable, Sendable {
    let id: UUID
    let subjectID: UUID
    let topicID: UUID?
    let date: Date
    let title: String
    let isDone: Bool
    let isAdHoc: Bool
    let position: Int

    init(
        id: UUID = UUID(),
        subjectID: UUID,
        topicID: UUID? = nil,
        date: Date,
        title: String,
        isDone: Bool = false,
        isAdHoc: Bool = false,
        position: Int = 0
    ) {
        self.id = id
        self.subjectID = subjectID
        self.topicID = topicID
        self.date = date
        self.title = title
        self.isDone = isDone
        self.isAdHoc = isAdHoc
        self.position = position
    }
}

struct DayTaskSummary: Equatable, Sendable {
    let totalTasks: Int
    let completedTasks: Int

    var isComplete: Bool {
        totalTasks > 0 && completedTasks >= totalTasks
    }

    var remainingTasks: Int {
        max(0, totalTasks - completedTasks)
    }

    var completionPercent: Int {
        guard totalTasks > 0 else { return 0 }
        return min(100, Int((Double(completedTasks) / Double(totalTasks) * 100).rounded()))
    }

    var percent: Int {
        completionPercent
    }
}

enum DayTaskEngine {
    static func normalizeDate(_ date: Date, calendar: Calendar = .current) -> Date {
        calendar.startOfDay(for: date)
    }

    /// Derives the day's task list for a subject on a calendar date.
    ///
    /// Every topic receives one task on the day. Ticks are matched against
    /// persisted records by (subjectID, topicID, date) so ticks survive
    /// weight edits or re-planning. Ad hoc tasks for the date are appended.
    static func tasksForDay(
        subject: SubjectPlanInput,
        driver: AssessmentRef,
        date: Date,
        persisted: [DayTaskRecord],
        calendar: Calendar = .current
    ) -> [DerivedDayTask] {
        let dayStart = normalizeDate(date, calendar: calendar)
        let topics = PlannerEngine.effectiveTopics(
            subjectID: subject.id, subjectName: subject.name, topics: subject.topics
        )
        guard !topics.isEmpty else { return [] }

        let split = PlannerEngine.dailyTopicSplit(topics: topics, dailyMinutes: subject.dailyMinutes)

        let subjectRecords = persisted.filter {
            $0.subjectID == subject.id && calendar.isDate($0.date, inSameDayAs: dayStart)
        }

        let byTopicID = Dictionary(
            subjectRecords.compactMap { r -> (UUID, DayTaskRecord)? in
                guard let t = r.topicID else { return nil }
                return (t, r)
            },
            uniquingKeysWith: { first, _ in first }
        )

        var result: [DerivedDayTask] = []

        for (idx, topic) in topics.enumerated() {
            let hint = idx < split.count ? split[idx] : 0
            let matched = byTopicID[topic.topicID]
            let isDone = matched?.isDone ?? false

            result.append(
                DerivedDayTask(
                    id: topic.topicID,
                    taskRecordID: matched?.id,
                    subjectID: subject.id,
                    subjectName: subject.name,
                    subjectAccentHex: subject.accentHex,
                    topicID: topic.topicID,
                    title: topic.title,
                    plannedMinutesHint: hint,
                    isAdHoc: false,
                    isSynthetic: topic.isSynthetic,
                    isDone: isDone,
                    date: dayStart
                )
            )
        }

        let adHocRecords = subjectRecords
            .filter { $0.isAdHoc }
            .sorted { $0.position < $1.position }

        for record in adHocRecords {
            result.append(
                DerivedDayTask(
                    id: record.id,
                    taskRecordID: record.id,
                    subjectID: subject.id,
                    subjectName: subject.name,
                    subjectAccentHex: subject.accentHex,
                    topicID: nil,
                    title: record.title,
                    plannedMinutesHint: 0,
                    isAdHoc: true,
                    isSynthetic: false,
                    isDone: record.isDone,
                    date: dayStart
                )
            )
        }

        return result
    }

    /// Evaluates summary progress across a set of day tasks.
    static func summary(tasks: [DerivedDayTask]) -> DayTaskSummary {
        let tickable = tasks.filter { !$0.isSynthetic }
        guard !tickable.isEmpty else {
            return DayTaskSummary(totalTasks: 0, completedTasks: 0)
        }
        let completed = tickable.filter(\.isDone).count
        return DayTaskSummary(totalTasks: tickable.count, completedTasks: completed)
    }

    /// Aggregates task progress for a subject over a trailing day window.
    static func windowSummary(
        subject: SubjectPlanInput,
        driver: AssessmentRef,
        persisted: [DayTaskRecord],
        from date: Date = .now,
        days: Int = 7,
        calendar: Calendar = .current
    ) -> DayTaskSummary {
        var total = 0
        var completed = 0

        for offset in 0..<days {
            guard let dayDate = calendar.date(byAdding: .day, value: -offset, to: date) else { continue }
            let dayTasks = tasksForDay(
                subject: subject,
                driver: driver,
                date: dayDate,
                persisted: persisted,
                calendar: calendar
            )
            let s = summary(tasks: dayTasks)
            total += s.totalTasks
            completed += s.completedTasks
        }

        return DayTaskSummary(totalTasks: total, completedTasks: completed)
    }
}
