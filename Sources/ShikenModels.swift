import Foundation
import SwiftData

// CloudKit-safe rules (enforced from day one so iCloud sync is a config flip later):
// - Every non-optional attribute has a default value.
// - Enums stored as raw-value String; no @Attribute(.unique), no unsupported types.
// Flip point: change the ModelContainer to `.cloudKitDatabase(.automatic)` and add the
// iCloud + CloudKit entitlement + an Apple Developer account.

@Model
final class Subject {
    var id: UUID = UUID()
    var name: String = ""
    var accentHex: String = "9A8C98"
    /// The subject's whole daily budget. Deliberately NOT divided between
    /// assessments: the user sets one daily figure and keeps to it across every
    /// assessment in the subject. Assessments are deadlines the plan points at.
    var dailyMinutes: Int = 60
    /// Lessons a week on the school timetable. Used only to suggest a daily
    /// figure, because five periods of Physics and one of Italian are not the
    /// same amount of weekly revision.
    var periodsPerWeek: Int = 5
    /// Enrichment drops (Art, Music, Health, PE). Gets a floor rather than zero:
    /// dropping them completely is how you lose a subject you are examined on.
    var isEnrichment: Bool = false
    /// False once the user has moved the daily stepper themselves. The derivation
    /// only ever fills a default; an explicit choice always wins.
    var dailyMinutesIsDerived: Bool = false
    var position: Int = 0
    var createdAt: Date = Date.now

    @Relationship(deleteRule: .cascade, inverse: \Topic.subject)
    var topics: [Topic] = []

    @Relationship(deleteRule: .cascade, inverse: \Assessment.subject)
    var assessments: [Assessment] = []

    init(
        name: String,
        accentHex: String = "9A8C98",
        dailyMinutes: Int = 60,
        periodsPerWeek: Int = 5,
        isEnrichment: Bool = false,
        position: Int = 0
    ) {
        self.name = name
        self.accentHex = accentHex
        self.dailyMinutes = dailyMinutes
        self.periodsPerWeek = periodsPerWeek
        self.isEnrichment = isEnrichment
        self.position = position
    }

    var sortedAssessments: [Assessment] {
        assessments.sorted { $0.position < $1.position }
    }
}

/// One dated thing you're revising for: an SAC, a trial paper, a practical, the
/// exam itself. A subject has several, because school does not give you one shot.
@Model
final class Assessment {
    var id: UUID = UUID()
    var title: String = "Assessment"
    var date: Date = Date.now
    var position: Int = 0

    var subject: Subject?

    init(title: String = "Assessment", date: Date = .now, position: Int = 0) {
        self.title = title
        self.date = date
        self.position = position
    }
}

@Model
final class Topic {
    var id: UUID = UUID()
    var title: String = ""
    // Relative share of the week's study time (1–100). The planner splits the
    // dailyMinutes x 7 week across topics by this share; it is not exact minutes.
    var weight: Int = 20
    var position: Int = 0
    var createdAt: Date = Date.now

    var subject: Subject?

    @Relationship(deleteRule: .cascade, inverse: \PlanBlock.topic)
    var planBlocks: [PlanBlock] = []

    @Relationship(deleteRule: .cascade, inverse: \StudySession.topic)
    var sessions: [StudySession] = []

    init(title: String, weight: Int = 20, position: Int = 0) {
        self.title = title
        self.weight = weight
        self.position = position
    }
}

@Model
final class PlanBlock {
    var id: UUID = UUID()
    var weekIndex: Int = 0
    /// The Monday (or start of week) this block covers. This — not `weekIndex` —
    /// is the block's identity, because weekIndex 0 means "the week of whatever
    /// assessment is driving the plan" and that moves when an earlier assessment
    /// passes. Keying on the date means a tick stays on the calendar week the user
    /// ticked instead of silently jumping to a different week.
    var weekStart: Date = Date.now
    var targetMinutes: Int = 0
    var isDone: Bool = false

    var topic: Topic?

    init(weekIndex: Int = 0, weekStart: Date = .now, targetMinutes: Int = 0, isDone: Bool = false, topic: Topic? = nil) {
        self.weekIndex = weekIndex
        self.weekStart = weekStart
        self.targetMinutes = targetMinutes
        self.isDone = isDone
        self.topic = topic
    }
}

@Model
final class StudySession {
    var id: UUID = UUID()
    var startedAt: Date = Date.now
    var focusedMinutes: Int = 0
    var awayMinutes: Int = 0
    var note: String?

    var subject: Subject?
    var topic: Topic?

    init(startedAt: Date = .now, focusedMinutes: Int = 0, awayMinutes: Int = 0, note: String? = nil, subject: Subject? = nil, topic: Topic? = nil) {
        self.startedAt = startedAt
        self.focusedMinutes = focusedMinutes
        self.awayMinutes = awayMinutes
        self.note = note
        self.subject = subject
        self.topic = topic
    }
}