import XCTest
@testable import ShikenMac

final class OverviewEngineTests: XCTestCase {
    private var calendar: Calendar { var c = Calendar.current; c.timeZone = .gmt; return c }
    private func day(_ offset: Int) -> Date {
        calendar.date(byAdding: .day, value: offset, to: Date())!
    }

    private func subject(
        _ name: String,
        examInDays: Int?,
        dailyMinutes: Int = 60,
        topics: [TopicPlan] = []
    ) -> SubjectPlanInput {
        SubjectPlanInput(
            id: UUID(),
            name: name,
            accentHex: "#A7B99C",
            examDate: examInDays.map { day($0) },
            dailyMinutes: dailyMinutes,
            topics: topics
        )
    }

    // MARK: - Default topic

    func testSubjectWithNoTopicsPlansAsItself() {
        let topics = PlannerEngine.effectiveTopics(
            subjectID: UUID(), subjectName: "Chemistry", topics: []
        )
        XCTAssertEqual(topics.count, 1)
        XCTAssertEqual(topics.first?.title, "Chemistry")
        XCTAssertEqual(topics.first?.weight, 1)
        XCTAssertEqual(topics.first?.isSynthetic, true)
    }

    func testRealTopicsAlwaysWinOverTheStandIn() {
        let real = [TopicPlan(topicID: UUID(), title: "Stoichiometry", weight: 3)]
        let topics = PlannerEngine.effectiveTopics(
            subjectID: UUID(), subjectName: "Chemistry", topics: real
        )
        XCTAssertEqual(topics, real)
        XCTAssertFalse(topics.contains { $0.isSynthetic })
    }

    func testStandInIdentityIsStableAcrossCalls() {
        let id = UUID()
        let first = PlannerEngine.effectiveTopics(subjectID: id, subjectName: "Physics", topics: [])
        let second = PlannerEngine.effectiveTopics(subjectID: id, subjectName: "Physics", topics: [])
        XCTAssertEqual(first.first?.topicID, id)
        XCTAssertEqual(first, second, "a re-render must not change the stand-in's identity")
    }

    func testTopiclessSubjectProducesARealPlanNotAnEmptyOne() {
        let blocks = PlannerEngine.schedule(
            topics: PlannerEngine.effectiveTopics(
                subjectID: UUID(), subjectName: "Chemistry", topics: []
            ),
            examDate: day(14), dailyMinutes: 60, from: Date(), calendar: calendar
        )
        XCTAssertFalse(blocks.isEmpty, "a subject with no topics must still get a week plan")
        // Each week must total the daily budget x 7, on its own.
        for week in Set(blocks.map(\.weekIndex)) {
            let sum = blocks.filter { $0.weekIndex == week }.reduce(0) { $0 + $1.minutes }
            XCTAssertEqual(sum, 60 * 7, "week \(week) must total the weekly budget")
        }
    }

    // MARK: - Cross-subject totals

    func testOverviewSpansAllSubjects() {
        let overview = OverviewEngine.overview(
            subjects: [
                subject("Chemistry", examInDays: 14, dailyMinutes: 60),
                subject("Physics", examInDays: 21, dailyMinutes: 30)
            ],
            from: Date(), calendar: calendar
        )
        XCTAssertEqual(overview.today?.subjects.count, 2)
        XCTAssertEqual(Set(overview.today?.subjects.map(\.subjectID) ?? []).count, 2)
    }

    func testSubjectWithoutExamDateIsExcludedNotSilentlyDropped() {
        let overview = OverviewEngine.overview(
            subjects: [
                subject("Chemistry", examInDays: 14),
                subject("English", examInDays: nil)
            ],
            from: Date(), calendar: calendar
        )
        XCTAssertEqual(overview.excluded, ["English"])
        XCTAssertEqual(overview.today?.subjects.count, 1, "a dateless subject must not contribute minutes")
    }

    func testDayTotalsEqualTheSumOfTheirSubjects() {
        let overview = OverviewEngine.overview(
            subjects: [
                subject("Chemistry", examInDays: 14, dailyMinutes: 60),
                subject("Physics", examInDays: 21, dailyMinutes: 45)
            ],
            from: Date(), calendar: calendar
        )
        for day in overview.days {
            XCTAssertEqual(
                day.totalMinutes, day.subjects.reduce(0) { $0 + $1.totalMinutes },
                "day \(day.dayIndex) total must equal the sum of its subjects"
            )
        }
    }

    func testNothingIsPlannedPastAnExamsArrival() {
        // Exam in 2 days means only today and tomorrow are revisable.
        let overview = OverviewEngine.overview(
            subjects: [subject("Chemistry", examInDays: 2, dailyMinutes: 60)],
            from: Date(), calendar: calendar
        )
        let contributing = overview.days.filter { $0.totalMinutes > 0 }
        XCTAssertEqual(contributing.count, 3, "today plus the exam day, not a full week")
    }

    func testOverviewTotalEqualsDailyBudgetWhileExamIsFarOff() {
        let overview = OverviewEngine.overview(
            subjects: [subject("Chemistry", examInDays: 30, dailyMinutes: 60)],
            from: Date(), calendar: calendar
        )
        XCTAssertEqual(
            overview.today?.totalMinutes, 60,
            "a subject's own daily budget must survive into the cross-subject view"
        )
    }

    func testSubjectBudgetsAreNotReweightedAgainstEachOther() {
        let overview = OverviewEngine.overview(
            subjects: [
                subject("Big", examInDays: 30, dailyMinutes: 120),
                subject("Small", examInDays: 30, dailyMinutes: 20)
            ],
            from: Date(), calendar: calendar
        )
        let byName = Dictionary(uniqueKeysWithValues: overview.today!.subjects.map { ($0.name, $0.totalMinutes) })
        XCTAssertEqual(byName["Big"], 120)
        XCTAssertEqual(byName["Small"], 20)
    }

    func testEntryMinutesReconcileWithTheSubjectsOwnPlan() {
        let input = subject("Chemistry", examInDays: 14, dailyMinutes: 60)
        let overview = OverviewEngine.overview(subjects: [input], from: Date(), calendar: calendar)
        let entryTotal = overview.today!.subjects[0].entries.reduce(0) { $0 + $1.minutes }
        XCTAssertEqual(entryTotal, overview.today!.subjects[0].totalMinutes)
    }

    func testTopiclessSubjectAppearsWithAStandInRowInTheOverview() {
        let overview = OverviewEngine.overview(
            subjects: [subject("Chemistry", examInDays: 14)],
            from: Date(), calendar: calendar
        )
        let entries = overview.today!.subjects[0].entries
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries.first?.title, "Chemistry")
        XCTAssertEqual(entries.first?.isSynthetic, true)
    }

    func testDaysAreClampedToAWeek() {
        let overview = OverviewEngine.overview(
            subjects: [subject("Chemistry", examInDays: 90)], days: 30, from: Date(), calendar: calendar
        )
        XCTAssertEqual(overview.days.count, 7)
    }

    func testEmptyInputProducesAnEmptyButValidOverview() {
        let overview = OverviewEngine.overview(subjects: [], from: Date(), calendar: calendar)
        XCTAssertEqual(overview.days.count, 7)
        XCTAssertEqual(overview.today?.totalMinutes, 0)
        XCTAssertTrue(overview.excluded.isEmpty)
    }

    func testDoneStateReflectsTicks() {
        let input = subject("Chemistry", examInDays: 14, topics: [
            TopicPlan(topicID: UUID(), title: "One", weight: 1),
            TopicPlan(topicID: UUID(), title: "Two", weight: 1)
        ])
        let topicIDs = input.topics.map(\.topicID)

        let none = OverviewEngine.overview(subjects: [input], from: Date(), calendar: calendar,
                                           isDone: { _, _ in nil })
        XCTAssertNil(none.today!.subjects[0].isDone, "untouched plan should have no done state")

        let all = OverviewEngine.overview(subjects: [input], from: Date(), calendar: calendar,
                                          isDone: { id, _ in topicIDs.contains(id) })
        XCTAssertEqual(all.today!.subjects[0].isDone, true)

        let some = OverviewEngine.overview(subjects: [input], from: Date(), calendar: calendar,
                                           isDone: { id, _ in id == topicIDs[0] })
        XCTAssertEqual(some.today!.subjects[0].isDone, false)
    }

    func testStandInIsNeverReportedDoneBecauseItCannotBeTicked() {
        let input = subject("Chemistry", examInDays: 14)
        let overview = OverviewEngine.overview(subjects: [input], from: Date(), calendar: calendar,
                                              isDone: { _, _ in true })
        XCTAssertNotEqual(overview.today!.subjects[0].isDone, true,
                          "a stand-in row has no checkbox, so claiming it is done would be a lie")
    }
}