import XCTest
@testable import ShikenMac

/// The wording rules are the feature. A reminder that says "you are behind"
/// becomes a nag, and a nag gets the app deleted.
final class ReminderSchedulerTests: XCTestCase {
    private let calendar = Calendar(identifier: .gregorian)

    override func setUp() {
        super.setUp()
        // The scheduler reads real UserDefaults, so a running app that has already
        // toggled reminders would otherwise leak state into this test and fail it.
        // Anything asserting "off by default" has to control its own starting point.
        UserDefaults.standard.removeObject(forKey: "remindersEnabled")
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: "remindersEnabled")
        super.tearDown()
    }

    private func make(
        name: String,
        minutes: Int,
        assessments: [AssessmentRef]? = nil,
        syntheticOnly: Bool = false
    ) -> PlannedSubject {
        let in30 = calendar.date(byAdding: .day, value: 30, to: .now)!
        return PlannedSubject(
            subjectID: UUID(),
            name: name,
            accentHex: "#9A8C98",
            driver: assessments?.first ?? AssessmentRef(title: "Exam", date: in30),
            upcoming: [],
            totalMinutes: minutes,
            entries: [PlannedEntry(
                topicID: UUID(),
                title: syntheticOnly ? name : "Topic",
                minutes: minutes,
                isSynthetic: syntheticOnly
            )],
            weekMinutes: minutes,
            isDone: nil,
            actualMinutes: 0
        )
    }

    private func overview(_ subjects: [PlannedSubject]) -> Overview {
        Overview(days: [OverviewDay(
            dayIndex: 0, date: .now, subjects: subjects,
            totalMinutes: subjects.reduce(0) { $0 + $1.totalMinutes }, actualMinutes: 0
        )], excluded: [], finished: [])
    }

    // MARK: Choosing one subject

    func testTheBusiestSubjectIsTheOneMentioned() throws {
        let summary = try XCTUnwrap(ReminderScheduler.summary(from: overview([
            make(name: "Physics", minutes: 90),
            make(name: "Chemistry", minutes: 60),
            make(name: "English", minutes: 45)
        ])))
        XCTAssertEqual(summary.subjectName, "Physics")
        XCTAssertEqual(summary.minutes, 90)
    }

    func testOnlyOneSubjectIsEverMentioned() throws {
        // Four badges is a nag. One is a fact.
        let summary = try XCTUnwrap(ReminderScheduler.summary(from: overview([
            make(name: "Physics", minutes: 90),
            make(name: "Chemistry", minutes: 60),
            make(name: "English", minutes: 45),
            make(name: "Biology", minutes: 30)
        ])))
        XCTAssertTrue(summary.subjectName.contains("Physics"))
        XCTAssertFalse(summary.subjectName.contains("Chemistry"))
        XCTAssertFalse(summary.subjectName.contains("English"))
    }

    func testASubjectPlannedOnlyAsAStandInIsSkipped() throws {
        // A topicless subject's italic row is not real work, so reminding about it
        // would point at something the user cannot act on.
        let summary = try XCTUnwrap(ReminderScheduler.summary(from: overview([
            make(name: "Chemistry", minutes: 60, syntheticOnly: true),
            make(name: "Physics", minutes: 30)
        ])))
        XCTAssertEqual(summary.subjectName, "Physics")
    }

    func testNothingPlannedMeansNoReminder() {
        XCTAssertNil(ReminderScheduler.summary(from: overview([])))
    }

    func testAZeroMinuteSubjectIsNotWorthAReminder() {
        XCTAssertNil(ReminderScheduler.summary(from: overview([make(name: "Art", minutes: 0)])))
    }

    func testAnEmptyWeekProducesNoReminder() {
        let empty = Overview(days: [], excluded: ["Art"], finished: [])
        XCTAssertNil(ReminderScheduler.summary(from: empty))
    }

    // MARK: Defaults

    func testRemindersAreOffUntilAskedFor() {
        let scheduler = ReminderScheduler()
        XCTAssertFalse(scheduler.isEnabled, "a reminder nobody opted into is an interruption")
    }

    func testTheDefaultReminderTimeIsLateAfternoon() {
        // After school, before evening. The one window where a study reminder is
        // plausible rather than irritating.
        let components = Calendar.current.dateComponents(
            [.hour, .minute], from: ReminderScheduler.defaultTime
        )
        XCTAssertEqual(components.hour, 17)
        XCTAssertEqual(components.minute, 0)
    }
}