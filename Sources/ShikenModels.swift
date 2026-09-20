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
    var examDate: Date?
    var accentHex: String = "9A8C98"
    var position: Int = 0
    var createdAt: Date = Date.now

    @Relationship(deleteRule: .cascade, inverse: \Topic.subject)
    var topics: [Topic] = []

    init(name: String, examDate: Date? = nil, accentHex: String = "9A8C98", position: Int = 0) {
        self.name = name
        self.examDate = examDate
        self.accentHex = accentHex
        self.position = position
    }
}

@Model
final class Topic {
    var id: UUID = UUID()
    var title: String = ""
    var weight: Int = 1
    var position: Int = 0
    var createdAt: Date = Date.now

    var subject: Subject?

    @Relationship(deleteRule: .cascade, inverse: \PlanBlock.topic)
    var planBlocks: [PlanBlock] = []

    @Relationship(deleteRule: .cascade, inverse: \StudySession.topic)
    var sessions: [StudySession] = []

    init(title: String, weight: Int = 1, position: Int = 0) {
        self.title = title
        self.weight = weight
        self.position = position
    }
}

@Model
final class PlanBlock {
    var id: UUID = UUID()
    var weekIndex: Int = 0
    var targetMinutes: Int = 0
    var isDone: Bool = false

    var topic: Topic?

    init(weekIndex: Int, targetMinutes: Int, topic: Topic? = nil) {
        self.weekIndex = weekIndex
        self.targetMinutes = targetMinutes
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