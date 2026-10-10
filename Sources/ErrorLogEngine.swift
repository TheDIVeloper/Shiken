import Foundation

enum ErrorCategory: String, CaseIterable, Sendable {
    case carelessSlip = "careless_slip"
    case contentGap = "content_gap"
    case methodStrategy = "method_strategy"
    case misreading = "misreading"
    case timePressure = "time_pressure"
    case other = "other"

    var label: String {
        switch self {
        case .carelessSlip: return "Careless slip"
        case .contentGap: return "Content gap"
        case .methodStrategy: return "Method or strategy"
        case .misreading: return "Misreading"
        case .timePressure: return "Time pressure"
        case .other: return "Other"
        }
    }
}

/// Pure domain value type for a revision error.
struct ErrorRecord: Equatable, Sendable, Identifiable {
    let id: UUID
    let subjectID: UUID
    let subjectName: String
    let subjectAccentHex: String
    let topicID: UUID?
    let topicTitle: String?
    let category: ErrorCategory
    let errorDescription: String
    let date: Date
    let stage: Int
    let lastReviewedAt: Date?
    let nextReviewDate: Date
    let isResolved: Bool

    init(
        id: UUID = UUID(),
        subjectID: UUID,
        subjectName: String,
        subjectAccentHex: String = "9A8C98",
        topicID: UUID? = nil,
        topicTitle: String? = nil,
        category: ErrorCategory,
        errorDescription: String,
        date: Date = .now,
        stage: Int = 0,
        lastReviewedAt: Date? = nil,
        nextReviewDate: Date = .now,
        isResolved: Bool = false
    ) {
        self.id = id
        self.subjectID = subjectID
        self.subjectName = subjectName
        self.subjectAccentHex = subjectAccentHex
        self.topicID = topicID
        self.topicTitle = topicTitle
        self.category = category
        self.errorDescription = errorDescription
        self.date = date
        self.stage = stage
        self.lastReviewedAt = lastReviewedAt
        self.nextReviewDate = nextReviewDate
        self.isResolved = isResolved
    }
}

enum ErrorFilterStatus: String, CaseIterable, Sendable, Identifiable {
    case all = "all"
    case due = "due"
    case active = "active"
    case resolved = "resolved"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .all: return "All"
        case .due: return "Due today"
        case .active: return "Active"
        case .resolved: return "Resolved"
        }
    }
}

struct ErrorFilter: Equatable, Sendable {
    var subjectID: UUID? = nil
    var topicID: UUID? = nil
    var category: ErrorCategory? = nil
    var status: ErrorFilterStatus = .all
}

struct ErrorSummary: Equatable, Sendable {
    let total: Int
    let active: Int
    let dueToday: Int
    let resolved: Int
    let countsByCategory: [ErrorCategory: Int]
}

/// Pure, deterministic spaced review engine for revision errors.
///
/// Intervals:
/// - Stage 0 (initial): next review in 1 day.
/// - Stage 1 (passed once): next review in 3 days.
/// - Stage 2 (passed twice): next review in 7 days.
/// - Stage 3 (passed three times): resolved.
///
/// If a review fails ("still rusty"), the interval drops back to 1 day
/// so the mistake is retested promptly without losing track of it.
enum ErrorLogEngine {
    static let initialIntervalDays = 1
    static let stage1IntervalDays = 3
    static let stage2IntervalDays = 7
    static let resolutionStage = 3

    static func normalizeDate(_ date: Date, calendar: Calendar = .current) -> Date {
        calendar.startOfDay(for: date)
    }

    /// Calculates initial next review date for a newly recorded error.
    static func initialNextReviewDate(from date: Date, calendar: Calendar = .current) -> Date {
        let base = normalizeDate(date, calendar: calendar)
        return calendar.date(byAdding: .day, value: initialIntervalDays, to: base) ?? base
    }

    /// Evaluates whether an error is due on or before the target date.
    static func isDue(
        nextReviewDate: Date,
        isResolved: Bool,
        on date: Date = .now,
        calendar: Calendar = .current
    ) -> Bool {
        guard !isResolved else { return false }
        let target = normalizeDate(date, calendar: calendar)
        let reviewDay = normalizeDate(nextReviewDate, calendar: calendar)
        return reviewDay <= target
    }

    /// Calculates the next review step when reviewing an error.
    ///
    /// - If `passed` is true: advances stage (0 -> 1 -> 2 -> 3 resolved).
    /// - If `passed` is false: resets stage to 0 (+1 day).
    static func recordReview(
        currentStage: Int,
        passed: Bool,
        reviewedAt: Date = .now,
        calendar: Calendar = .current
    ) -> (nextStage: Int, nextReviewDate: Date, isResolved: Bool) {
        let base = normalizeDate(reviewedAt, calendar: calendar)
        if passed {
            let nextStage = currentStage + 1
            if nextStage >= resolutionStage {
                return (resolutionStage, base, true)
            } else if nextStage == 2 {
                let nextDate = calendar.date(byAdding: .day, value: stage2IntervalDays, to: base) ?? base
                return (nextStage, nextDate, false)
            } else {
                let nextDate = calendar.date(byAdding: .day, value: stage1IntervalDays, to: base) ?? base
                return (nextStage, nextDate, false)
            }
        } else {
            let nextDate = calendar.date(byAdding: .day, value: initialIntervalDays, to: base) ?? base
            return (0, nextDate, false)
        }
    }

    /// Filters and sorts a list of error records.
    static func filter(
        errors: [ErrorRecord],
        filter: ErrorFilter,
        on date: Date = .now,
        calendar: Calendar = .current
    ) -> [ErrorRecord] {
        errors.filter { record in
            if let subjectID = filter.subjectID, record.subjectID != subjectID {
                return false
            }
            if let topicID = filter.topicID, record.topicID != topicID {
                return false
            }
            if let category = filter.category, record.category != category {
                return false
            }
            switch filter.status {
            case .all:
                return true
            case .due:
                return isDue(
                    nextReviewDate: record.nextReviewDate,
                    isResolved: record.isResolved,
                    on: date,
                    calendar: calendar
                )
            case .active:
                return !record.isResolved
            case .resolved:
                return record.isResolved
            }
        }
    }

    /// Generates summary statistics across a set of error records.
    static func summary(
        errors: [ErrorRecord],
        on date: Date = .now,
        calendar: Calendar = .current
    ) -> ErrorSummary {
        var activeCount = 0
        var dueCount = 0
        var resolvedCount = 0
        var categoryMap: [ErrorCategory: Int] = [:]

        for category in ErrorCategory.allCases {
            categoryMap[category] = 0
        }

        for record in errors {
            if record.isResolved {
                resolvedCount += 1
            } else {
                activeCount += 1
                if isDue(
                    nextReviewDate: record.nextReviewDate,
                    isResolved: record.isResolved,
                    on: date,
                    calendar: calendar
                ) {
                    dueCount += 1
                }
            }
            categoryMap[record.category, default: 0] += 1
        }

        return ErrorSummary(
            total: errors.count,
            active: activeCount,
            dueToday: dueCount,
            resolved: resolvedCount,
            countsByCategory: categoryMap
        )
    }

    /// Human readable label for an error's stage.
    static func stageLabel(stage: Int, isResolved: Bool) -> String {
        if isResolved { return "Resolved" }
        switch stage {
        case 0: return "Initial (due in 1d)"
        case 1: return "Review 1 (due in 3d)"
        case 2: return "Review 2 (due in 7d)"
        default: return "Resolved"
        }
    }
}
