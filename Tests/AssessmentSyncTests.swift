import XCTest
import SwiftData
@testable import ShikenMac

/// The editor's save path runs against a real in-memory SwiftData store, because
/// "I added an assessment and it did not save" is exactly the kind of bug a
/// mocked-out test cannot catch.
final class AssessmentSyncTests: XCTestCase {
    private var container: ModelContainer!
    private var ctx: ModelContext!

    override func setUpWithError() throws {
        container = try ModelContainer(
            for: Schema([Subject.self, Topic.self, PlanBlock.self, StudySession.self, Assessment.self]),
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        ctx = ModelContext(container)
    }

    override func tearDownWithError() throws {
        ctx = nil
        container = nil
    }

    private func makeSubject(name: String = "Chemistry") throws -> Subject {
        let subject = Subject(name: name)
        ctx.insert(subject)
        try ctx.save()
        return subject
    }

    private func assessmentCount(_ subject: Subject) throws -> Int {
        // Filtered in Swift rather than with #Predicate: the predicate macro
        // cannot follow a relationship hop to Subject.id, and this is a test
        // helper where clarity beats pushdown.
        try ctx.fetch(FetchDescriptor<Assessment>()).filter { $0.subject?.id == subject.id }.count
    }

    // MARK: The bug: adding an assessment must persist

    func testAddingOneAssessmentPersistsIt() throws {
        let subject = try makeSubject()
        let result = AssessmentSync.apply(
            [AssessmentDraft(title: "Exam", date: Date(), isNew: true)],
            to: subject, in: ctx
        )
        try ctx.save()

        XCTAssertEqual(result.saved, 1)
        XCTAssertEqual(result.dropped, 0)
        XCTAssertEqual(try assessmentCount(subject), 1, "the assessment reached the store")
        XCTAssertEqual(subject.assessmentRefs.map(\.title), ["Exam"])
    }

    func testAddingSeveralAssessmentsPersistsAllOfThem() throws {
        let subject = try makeSubject()
        let now = Date()
        let result = AssessmentSync.apply(
            [
                AssessmentDraft(title: "SAC 1", date: now, isNew: true),
                AssessmentDraft(title: "Trial", date: now, isNew: true),
                AssessmentDraft(title: "Exam", date: now, isNew: true)
            ],
            to: subject, in: ctx
        )
        try ctx.save()

        XCTAssertEqual(result.saved, 3)
        XCTAssertEqual(try assessmentCount(subject), 3)
        XCTAssertEqual(subject.assessmentRefs.map(\.title), ["SAC 1", "Trial", "Exam"])
        XCTAssertEqual(subject.sortedAssessments.map(\.position), [0, 1, 2], "list order is preserved")
    }

    func testASavedAssessmentSurvivesAFreshFetch() throws {
        let subject = try makeSubject()
        AssessmentSync.apply(
            [AssessmentDraft(title: "SAC 1", date: Date(), isNew: true)],
            to: subject, in: ctx
        )
        try ctx.save()

        // A new context sees only what actually committed to disk, so this fails
        // if the insert was silently discarded or never flushed.
        let fresh = ModelContext(container)
        let descriptor = FetchDescriptor<Assessment>()
        let reread = try fresh.fetch(descriptor)
        XCTAssertEqual(reread.count, 1)
        XCTAssertEqual(reread.first?.title, "SAC 1")
    }

    // MARK: Editing

    func testEditingAnExistingAssessmentUpdatesRatherThanDuplicates() throws {
        let subject = try makeSubject()
        let original = Assessment(title: "Old name", date: Date())
        original.subject = subject
        ctx.insert(original)
        try ctx.save()

        let newDate = Calendar.current.date(byAdding: .day, value: 7, to: Date())!
        AssessmentSync.apply(
            [AssessmentDraft(id: original.id, title: "SAC 2", date: newDate)],
            to: subject, in: ctx
        )
        try ctx.save()

        XCTAssertEqual(try assessmentCount(subject), 1, "editing must not create a second row")
        XCTAssertEqual(subject.assessmentRefs.map(\.title), ["SAC 2"])
        XCTAssertEqual(try XCTUnwrap(subject.assessmentRefs.first?.date), newDate)
    }

    func testAPassedAssessmentTakesOverAsTheDriver() throws {
        let subject = try makeSubject()
        let past = Calendar.current.date(byAdding: .day, value: -1, to: Date())!
        let future = Calendar.current.date(byAdding: .day, value: 30, to: Date())!
        AssessmentSync.apply(
            [
                AssessmentDraft(title: "SAC 1", date: past, isNew: true),
                AssessmentDraft(title: "Exam", date: future, isNew: true)
            ],
            to: subject, in: ctx
        )
        try ctx.save()

        XCTAssertEqual(subject.nextAssessment?.title, "Exam")
        XCTAssertFalse(subject.isFinished)
        XCTAssertEqual(subject.upcomingAssessments.map(\.title), [])
    }

    func testReorderingIsReflectedInTheDriver() throws {
        let subject = try makeSubject()
        let soon = Calendar.current.date(byAdding: .day, value: 5, to: Date())!
        let later = Calendar.current.date(byAdding: .day, value: 40, to: Date())!
        let sac = Assessment(title: "SAC 1", date: later, position: 0)
        let exam = Assessment(title: "Exam", date: soon, position: 1)
        sac.subject = subject
        exam.subject = subject
        ctx.insert(sac)
        ctx.insert(exam)
        try ctx.save()

        XCTAssertEqual(subject.nextAssessment?.title, "Exam",
                       "the driver follows dates, not list order")
    }

    // MARK: Deleting

    func testARemovedDraftIsDeletedFromTheStore() throws {
        let subject = try makeSubject()
        let keep = Assessment(title: "Exam", date: Date())
        let drop = Assessment(title: "SAC 1", date: Date())
        keep.subject = subject
        drop.subject = subject
        ctx.insert(keep)
        ctx.insert(drop)
        try ctx.save()
        XCTAssertEqual(try assessmentCount(subject), 2)

        AssessmentSync.apply([AssessmentDraft(id: keep.id, title: "Exam", date: Date())], to: subject, in: ctx)
        try ctx.save()

        XCTAssertEqual(try assessmentCount(subject), 1)
        XCTAssertEqual(subject.assessmentRefs.map(\.title), ["Exam"])
    }

    func testRemovingEveryAssessmentLeavesTheSubjectWithNoPlanNotFinished() throws {
        let subject = try makeSubject()
        let only = Assessment(title: "Exam", date: Date())
        only.subject = subject
        ctx.insert(only)
        try ctx.save()

        let result = AssessmentSync.apply([], to: subject, in: ctx)
        try ctx.save()

        XCTAssertEqual(result.saved, 0)
        XCTAssertEqual(try assessmentCount(subject), 0)
        XCTAssertFalse(subject.isFinished, "no assessments is 'unplanned', not 'done'")
        XCTAssertNil(subject.nextAssessment)
    }

    // MARK: Blank names

    func testABlankNameIsDroppedAndReported() throws {
        let subject = try makeSubject()
        let result = AssessmentSync.apply(
            [
                AssessmentDraft(title: "   ", date: Date(), isNew: true),
                AssessmentDraft(title: "Exam", date: Date(), isNew: true)
            ],
            to: subject, in: ctx
        )
        try ctx.save()

        XCTAssertEqual(result.saved, 1)
        XCTAssertEqual(result.dropped, 1, "a nameless row is reported, not silently lost")
        XCTAssertEqual(subject.assessmentRefs.map(\.title), ["Exam"])
    }

    func testRowsWithOnlyWhitespaceCountAsBlank() throws {
        let subject = try makeSubject()
        let result = AssessmentSync.apply(
            [AssessmentDraft(title: "\n\t  ", date: Date(), isNew: true)],
            to: subject, in: ctx
        )
        try ctx.save()
        XCTAssertEqual(result.dropped, 1)
        XCTAssertEqual(try assessmentCount(subject), 0)
    }

    func testANameWithSurroundingSpaceIsTrimmedOnSave() throws {
        let subject = try makeSubject()
        AssessmentSync.apply(
            [AssessmentDraft(title: "  SAC 1  ", date: Date(), isNew: true)],
            to: subject, in: ctx
        )
        try ctx.save()
        XCTAssertEqual(subject.assessmentRefs.map(\.title), ["SAC 1"])
    }

    // MARK: Derived state

    func testMultipleAssessmentsExposeTheSoonestAsDriverAndTheRestAsUpcoming() throws {
        let subject = try makeSubject()
        let in7 = Calendar.current.date(byAdding: .day, value: 7, to: Date())!
        let in30 = Calendar.current.date(byAdding: .day, value: 30, to: Date())!
        let in60 = Calendar.current.date(byAdding: .day, value: 60, to: Date())!
        AssessmentSync.apply(
            [
                AssessmentDraft(title: "SAC 1", date: in7, isNew: true),
                AssessmentDraft(title: "Trial", date: in30, isNew: true),
                AssessmentDraft(title: "Exam", date: in60, isNew: true)
            ],
            to: subject, in: ctx
        )
        try ctx.save()

        XCTAssertEqual(subject.nextAssessment?.title, "SAC 1")
        XCTAssertEqual(subject.upcomingAssessments.map(\.title), ["Trial", "Exam"])
        XCTAssertEqual(subject.planInput.assessments.count, 3)
    }

    func testAddingAnAssessmentToAnExistingSubjectLeavesItsTopicsAlone() throws {
        let subject = try makeSubject()
        let topic = Topic(title: "Equilibria", weight: 20)
        topic.subject = subject
        ctx.insert(topic)
        try ctx.save()

        AssessmentSync.apply(
            [AssessmentDraft(title: "Exam", date: Date(), isNew: true)],
            to: subject, in: ctx
        )
        try ctx.save()

        XCTAssertEqual(subject.topics.map(\.title), ["Equilibria"], "topics are untouched")
        XCTAssertEqual(subject.topicPlans.count, 1)
    }
}