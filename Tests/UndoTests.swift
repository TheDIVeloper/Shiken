import XCTest
import SwiftData
@testable import ShikenMac

/// Undo is only worth having if it puts everything back. These tests check the
/// whole graph survives a delete, not just the subject row.
@MainActor
final class UndoTests: XCTestCase {
    private var container: ModelContainer!
    private var ctx: ModelContext!
    private var undo: ActionUndo!

    override func setUp() async throws {
        try await super.setUp()
        container = try ModelContainer(
            for: Schema([Subject.self, Topic.self, PlanBlock.self, StudySession.self, Assessment.self]),
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        ctx = ModelContext(container)
        undo = ActionUndo()
    }

    override func tearDown() async throws {
        undo = nil
        ctx = nil
        container = nil
        try await super.tearDown()
    }

    /// A subject with one of everything, so a lossy restore is visible.
    @discardableResult
    private func makeRichSubject(name: String = "Chemistry") throws -> Subject {
        let subject = Subject(name: name, dailyMinutes: 60, periodsPerWeek: 5)
        ctx.insert(subject)

        let assessment = Assessment(title: "Exam", date: Date())
        assessment.subject = subject
        ctx.insert(assessment)

        let topic = Topic(title: "Equilibria", weight: 20)
        topic.subject = subject
        ctx.insert(topic)

        let block = PlanBlock(
            weekIndex: 0,
            weekStart: Calendar.current.startOfDay(for: .now),
            targetMinutes: 60,
            isDone: true,
            topic: topic
        )
        ctx.insert(block)

        let session = StudySession(startedAt: .now)
        session.focusedMinutes = 50
        session.awayMinutes = 3
        session.note = "solid session"
        session.subject = subject
        session.topic = topic
        ctx.insert(session)

        try ctx.save()
        return subject
    }

    private func count<T: PersistentModel>(_ type: T.Type) throws -> Int {
        try ctx.fetch(FetchDescriptor<T>()).count
    }

    // MARK: Round trip

    func testUndoingADeleteRestoresTheSubjectItself() throws {
        let subject = try makeRichSubject()
        let id = subject.id
        let snapshot = Undoable.snapshot(subject)

        undo.record(
            label: "Deleted \(subject.name)",
            perform: { self.ctx.delete(subject); try? self.ctx.save() },
            revert: { Undoable.restore(snapshot, in: self.ctx) }
        )
        XCTAssertEqual(try count(Subject.self), 0, "the delete happened immediately")

        undo.undo()
        XCTAssertEqual(try count(Subject.self), 1)
        let restored = try XCTUnwrap(try ctx.fetch(FetchDescriptor<Subject>()).first)
        XCTAssertEqual(restored.id, id, "the same row, so any selection still points at it")
        XCTAssertEqual(restored.name, "Chemistry")
        XCTAssertEqual(restored.dailyMinutes, 60)
        XCTAssertEqual(restored.periodsPerWeek, 5)
    }

    func testUndoingRestoresTopicsAssessmentsBlocksAndSessions() throws {
        let subject = try makeRichSubject()
        let snapshot = Undoable.snapshot(subject)

        undo.record(
            label: "Deleted",
            perform: { self.ctx.delete(subject); try? self.ctx.save() },
            revert: { Undoable.restore(snapshot, in: self.ctx) }
        )
        XCTAssertEqual(try count(Topic.self), 0)

        undo.undo()

        XCTAssertEqual(try count(Topic.self), 1, "topics came back")
        XCTAssertEqual(try count(Assessment.self), 1, "assessments came back")
        XCTAssertEqual(try count(PlanBlock.self), 1, "ticks came back")
        XCTAssertEqual(try count(StudySession.self), 1, "session history came back")
    }

    func testRestoredTickKeepsItsValueAndWeek() throws {
        let subject = try makeRichSubject()
        let week = Calendar.current.startOfDay(for: .now)
        let snapshot = Undoable.snapshot(subject)

        undo.record(
            label: "Deleted",
            perform: { self.ctx.delete(subject); try? self.ctx.save() },
            revert: { Undoable.restore(snapshot, in: self.ctx) }
        )
        undo.undo()

        let block = try XCTUnwrap(try ctx.fetch(FetchDescriptor<PlanBlock>()).first)
        XCTAssertTrue(block.isDone, "a restored tick is still ticked")
        XCTAssertEqual(block.targetMinutes, 60)
        XCTAssertEqual(try XCTUnwrap(block.topic).title, "Equilibria", "the tick reattached to its topic")
        XCTAssertEqual(Calendar.current.isDate(block.weekStart, inSameDayAs: week), true)
    }

    func testRestoredSessionKeepsMinutesAndNote() throws {
        let subject = try makeRichSubject()
        let snapshot = Undoable.snapshot(subject)

        undo.record(
            label: "Deleted",
            perform: { self.ctx.delete(subject); try? self.ctx.save() },
            revert: { Undoable.restore(snapshot, in: self.ctx) }
        )
        undo.undo()

        let session = try XCTUnwrap(try ctx.fetch(FetchDescriptor<StudySession>()).first)
        XCTAssertEqual(session.focusedMinutes, 50)
        XCTAssertEqual(session.awayMinutes, 3)
        XCTAssertEqual(session.note, "solid session")
        XCTAssertEqual(try XCTUnwrap(session.topic).title, "Equilibria")
    }

    func testRestoredSubjectIsUsableAgain() throws {
        // The real test: can you keep working, or is the restore a dead end?
        let subject = try makeRichSubject()
        let snapshot = Undoable.snapshot(subject)

        undo.record(
            label: "Deleted",
            perform: { self.ctx.delete(subject); try? self.ctx.save() },
            revert: { Undoable.restore(snapshot, in: self.ctx) }
        )
        undo.undo()

        let restored = try XCTUnwrap(try ctx.fetch(FetchDescriptor<Subject>()).first)
        let extra = Assessment(title: "Trial", date: Date())
        extra.subject = restored
        ctx.insert(extra)
        try ctx.save()

        XCTAssertEqual(try XCTUnwrap(try ctx.fetch(FetchDescriptor<Subject>()).first).assessments.count, 2)
    }

    func testSnapshotKeepsTopicIdentityForBlockReattachment() throws {
        let subject = try makeRichSubject()
        let topicID = try XCTUnwrap(subject.topics.first?.id)
        let snapshot = Undoable.snapshot(subject)
        XCTAssertEqual(snapshot.blocks.first?.topicID, topicID)
    }

    // MARK: Manager behaviour

    func testUndoingClearsThePendingAction() throws {
        let subject = try makeRichSubject()
        let snapshot = Undoable.snapshot(subject)
        undo.record(
            label: "Deleted",
            perform: { self.ctx.delete(subject); try? self.ctx.save() },
            revert: { Undoable.restore(snapshot, in: self.ctx) }
        )
        XCTAssertNotNil(undo.pending)
        undo.undo()
        XCTAssertNil(undo.pending, "there is nothing left to undo")
        XCTAssertEqual(undo.message, "Undone: Deleted")
    }

    func testANewActionReplacesThePreviousOffer() throws {
        undo.record(label: "Deleted First", perform: {}, revert: {})
        undo.record(label: "Deleted Second", perform: {}, revert: {})

        XCTAssertEqual(undo.pending?.label, "Deleted Second",
                       "only the most recent action is undoable, so there is no stale queue")

        // Undoing must run the newest reversal, not the first one recorded.
        var reverted = ""
        undo.undo()
        reverted = undo.message ?? ""
        XCTAssertEqual(reverted, "Undone: Deleted Second")
    }

    func testUndoWithNothingPendingDoesNothing() {
        undo.undo()
        XCTAssertNil(undo.message, "no banner appears from an empty undo")
    }

    func testClearPendingDropsTheOfferWithoutUndoing() throws {
        let subject = try makeRichSubject()
        let snapshot = Undoable.snapshot(subject)
        undo.record(
            label: "Deleted",
            perform: { self.ctx.delete(subject); try? self.ctx.save() },
            revert: { Undoable.restore(snapshot, in: self.ctx) }
        )
        undo.clearPending()

        XCTAssertNil(undo.pending)
        XCTAssertNil(undo.message)
        XCTAssertEqual(try count(Subject.self), 0, "the delete still stands")
    }

    func testRecordRunsTheDestructiveStepImmediately() throws {
        // A delete that has not visibly happened looks like a broken button.
        let subject = try makeRichSubject()
        let snapshot = Undoable.snapshot(subject)
        undo.record(
            label: "Deleted",
            perform: { self.ctx.delete(subject); try? self.ctx.save() },
            revert: { Undoable.restore(snapshot, in: self.ctx) }
        )
        XCTAssertEqual(try count(Subject.self), 0)
        XCTAssertEqual(undo.message, "Deleted")
    }
}