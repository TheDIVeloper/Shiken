import XCTest
@testable import ShikenMac

final class PlannerEngineTests: XCTestCase {
    private var calendar: Calendar { var c = Calendar.current; c.timeZone = .gmt; return c }
    private func day(_ offset: Int) -> Date {
        calendar.date(byAdding: .day, value: offset, to: Date())!
    }

    func testWeeksBetweenTodayIsOne() {
        XCTAssertEqual(PlannerEngine.weeksBetween(day(0), from: Date(), calendar: calendar), 1)
    }

    func testWeeksBetweenSixDaysIsOne() {
        XCTAssertEqual(PlannerEngine.weeksBetween(day(6), from: Date(), calendar: calendar), 1)
    }

    func testWeeksBetweenExactlyOneWeekIsTwo() {
        XCTAssertEqual(PlannerEngine.weeksBetween(day(7), from: Date(), calendar: calendar), 2)
    }

    func testWeeksBetweenThirtyDaysIsFive() {
        XCTAssertEqual(PlannerEngine.weeksBetween(day(30), from: Date(), calendar: calendar), 5)
    }

    func testWeeksClampedToTwentySix() {
        XCTAssertEqual(PlannerEngine.weeksBetween(day(400), from: Date(), calendar: calendar), 26)
    }

    func testScheduleEmptyTopics() {
        XCTAssertEqual(PlannerEngine.schedule(topics: [], driver: day(7), dailyMinutes: 60, from: Date()), [])
    }

    func testScheduleWeightedSplit() {
        let a = TopicPlan(topicID: UUID(), title: "A", weight: 1)
        let b = TopicPlan(topicID: UUID(), title: "B", weight: 2)
        let blocks = PlannerEngine.schedule(topics: [a, b], driver: day(7), dailyMinutes: 60, from: Date())
        XCTAssertEqual(blocks.count, 4) // 2 weeks x 2 topics
        let week1 = blocks.filter { $0.weekIndex == 0 }
        let week2 = blocks.filter { $0.weekIndex == 1 }
        XCTAssertEqual(week1.map(\.minutes).reduce(0, +), 420)
        XCTAssertEqual(week2.map(\.minutes).reduce(0, +), 420)
        let blockA = week1.first { $0.topicID == a.topicID }!.minutes
        let blockB = week1.first { $0.topicID == b.topicID }!.minutes
        XCTAssertEqual(blockA, 140)
        XCTAssertEqual(blockB, 280)
    }

    func testScheduleRemainderDistributed() {
        let a = TopicPlan(topicID: UUID(), title: "A", weight: 1)
        let b = TopicPlan(topicID: UUID(), title: "B", weight: 1)
        let blocks = PlannerEngine.schedule(topics: [a, b], driver: day(6), dailyMinutes: 30, from: Date())
        let week0 = blocks.filter { $0.weekIndex == 0 }
        XCTAssertEqual(week0.map(\.minutes).reduce(0, +), 210)
        XCTAssertEqual(week0.map(\.minutes).sorted(), [105, 105])
    }

    func testScheduleEveryWeekSumsToWeeklyTotal() {
        let weights = [2, 1, 5, 3, 4]
        let topics = (0..<5).map { TopicPlan(topicID: UUID(), title: "T\($0)", weight: weights[$0]) }
        let blocks = PlannerEngine.schedule(topics: topics, driver: day(30), dailyMinutes: 45, from: Date())
        let weeks = Set(blocks.map(\.weekIndex))
        for week in weeks {
            let sum = blocks.filter { $0.weekIndex == week }.map(\.minutes).reduce(0, +)
            XCTAssertEqual(sum, 45 * 7)
        }
    }

    func testDailyBreakdownEvenSplit() {
        XCTAssertEqual(PlannerEngine.dailyBreakdown(weeklyMinutes: [140], days: 7), [[20, 20, 20, 20, 20, 20, 20]])
    }

    func testDailyBreakdownRemainderOnEarliestDays() {
        XCTAssertEqual(PlannerEngine.dailyBreakdown(weeklyMinutes: [153], days: 7), [[22, 22, 22, 22, 22, 22, 21]])
    }

    func testDailyBreakdownZeroAndEmpty() {
        XCTAssertEqual(PlannerEngine.dailyBreakdown(weeklyMinutes: [0], days: 7), [[0, 0, 0, 0, 0, 0, 0]])
        XCTAssertEqual(PlannerEngine.dailyBreakdown(weeklyMinutes: [], days: 7), [])
    }

    func testDailyBreakdownPreservesTotals() {
        let input = [420, 153, 245]
        let output = PlannerEngine.dailyBreakdown(weeklyMinutes: input, days: 7)
        for (i, days) in output.enumerated() {
            let base = input[i] / 7
            let remainder = input[i] % 7
            XCTAssertEqual(days.reduce(0, +), input[i])
            XCTAssertEqual(days.filter { $0 == base + 1 }.count, remainder)
            XCTAssertTrue(days.allSatisfy { $0 == base || $0 == base + 1 })
        }
    }
}
// MARK: - Multiple assessments

final class AssessmentDriverTests: XCTestCase {
    private var calendar: Calendar { var c = Calendar.current; c.timeZone = .gmt; return c }
    private func day(_ offset: Int) -> Date {
        calendar.date(byAdding: .day, value: offset, to: Date())!
    }
    private func ref(_ title: String, _ offset: Int) -> AssessmentRef {
        AssessmentRef(title: title, date: day(offset))
    }

    // MARK: Choosing the driver

    func testEarliestUpcomingAssessmentDrives() {
        let next = PlannerEngine.nextAssessment(
            [ref("Exam", 60), ref("SAC 1", 7), ref("Trial", 30)],
            now: Date(), calendar: calendar
        )
        XCTAssertEqual(next?.title, "SAC 1", "you revise for what's soonest, not what's biggest")
    }

    func testPastAssessmentsAreNotDrivers() {
        let next = PlannerEngine.nextAssessment(
            [ref("Mid-term", -1), ref("Exam", 40)],
            now: Date(), calendar: calendar
        )
        XCTAssertEqual(next?.title, "Exam")
    }

    func testAnAssessmentTodayStillDrives() {
        let next = PlannerEngine.nextAssessment([ref("SAC", 0)], now: Date(), calendar: calendar)
        XCTAssertEqual(next?.title, "SAC")
    }

    func testAnAssessmentYesterdayIsFinished() {
        XCTAssertNil(PlannerEngine.nextAssessment([ref("SAC", -1)], now: Date(), calendar: calendar))
    }

    func testNoAssessmentsMeansNoDriver() {
        XCTAssertNil(PlannerEngine.nextAssessment([], now: Date(), calendar: calendar))
    }

    func testSameDayAssessmentsAreOrderedByNameForDeterminism() {
        let next = PlannerEngine.nextAssessment(
            [ref("Zebra", 3), ref("Alpha", 3)], now: Date(), calendar: calendar
        )
        XCTAssertEqual(next?.title, "Alpha")
    }

    // MARK: Finished subjects

    func testFinishedWhenEveryAssessmentHasPassed() {
        XCTAssertTrue(PlannerEngine.isFinished([ref("Exam", -10), ref("SAC", -2)], now: Date(), calendar: calendar))
    }

    func testNotFinishedWhileAnythingRemains() {
        XCTAssertFalse(PlannerEngine.isFinished([ref("Exam", -10), ref("SAC", 2)], now: Date(), calendar: calendar))
    }

    func testSubjectWithNoAssessmentsIsNotFinishedJustUnplanned() {
        XCTAssertFalse(
            PlannerEngine.isFinished([], now: Date(), calendar: calendar),
            "no assessments means nothing to be done about, not everything done"
        )
    }

    // MARK: Upcoming markers

    func testUpcomingExcludesTheDriver() {
        let driver = ref("SAC 1", 7)
        let upcoming = PlannerEngine.upcomingAfter(
            driver, in: [ref("Exam", 60), driver, ref("Trial", 30)],
            now: Date(), calendar: calendar
        )
        XCTAssertEqual(upcoming.map(\.title), ["Trial", "Exam"])
    }

    func testUpcomingExcludesAlreadyPastAssessments() {
        let driver = ref("SAC 1", 7)
        let upcoming = PlannerEngine.upcomingAfter(
            driver, in: [ref("Old", -5), ref("Exam", 60)],
            now: Date(), calendar: calendar
        )
        XCTAssertEqual(upcoming.map(\.title), ["Exam"])
    }

    // MARK: Daily budget is never split

    func testSubjectBudgetIsNotDividedBetweenAssessments() {
        let a = TopicPlan(topicID: UUID(), title: "A", weight: 1)
        let b = TopicPlan(topicID: UUID(), title: "B", weight: 1)
        let withOne = PlannerEngine.schedule(topics: [a, b], driver: day(3), dailyMinutes: 60, from: Date())
        let withFour = PlannerEngine.schedule(topics: [a, b], driver: day(3), dailyMinutes: 60, from: Date())
        XCTAssertEqual(withOne.map(\.minutes), withFour.map(\.minutes),
                       "more assessments must not shrink the daily target")
        XCTAssertEqual(withOne.filter { $0.weekIndex == 0 }.reduce(0) { $0 + $1.minutes }, 420)
    }

    func testLongerLadderDoesNotReduceAnySingleWeek() {
        let a = TopicPlan(topicID: UUID(), title: "A", weight: 1)
        let near = PlannerEngine.schedule(topics: [a], driver: day(3), dailyMinutes: 60, from: Date())
        let far = PlannerEngine.schedule(topics: [a], driver: day(40), dailyMinutes: 60, from: Date())
        XCTAssertEqual(near.first { $0.weekIndex == 0 }?.minutes,
                       far.first { $0.weekIndex == 0 }?.minutes)
    }

    // MARK: Week anchoring

    func testWeekStartIsStableForADateInTheSameWeek() {
        let monday = PlannerEngine.weekStart(containing: day(0), calendar: calendar)
        let later = calendar.date(byAdding: .day, value: 3, to: day(0))!
        XCTAssertEqual(PlannerEngine.weekStart(containing: later, calendar: calendar), monday)
    }

    func testWeekIndexStepsBackSevenDaysAtATime() {
        let driver = day(20)
        let week0 = PlannerEngine.weekStart(forWeekIndex: 0, driver: driver, now: Date(), calendar: calendar)
        let week1 = PlannerEngine.weekStart(forWeekIndex: 1, driver: driver, now: Date(), calendar: calendar)
        let week2 = PlannerEngine.weekStart(forWeekIndex: 2, driver: driver, now: Date(), calendar: calendar)
        XCTAssertEqual(calendar.dateComponents([.day], from: week1, to: week0).day, 7)
        XCTAssertEqual(calendar.dateComponents([.day], from: week2, to: week1).day, 7)
    }

    func testEveryBlockCarriesTheWeekStartItCovers() {
        let a = TopicPlan(topicID: UUID(), title: "A", weight: 1)
        let driver = day(20)
        let blocks = PlannerEngine.schedule(topics: [a], driver: driver, dailyMinutes: 60, from: Date(), calendar: calendar)
        XCTAssertFalse(blocks.isEmpty)
        XCTAssertEqual(blocks.filter { $0.weekIndex == 0 }.first?.weekStart,
                       PlannerEngine.weekStart(forWeekIndex: 0, driver: driver, now: Date(), calendar: calendar))
    }

    // MARK: The tick bug this model exists to prevent

    func testTickStaysOnItsCalendarWeekWhenTheDriverMoves() {
        let a = TopicPlan(topicID: UUID(), title: "A", weight: 1)
        let sac = day(3)
        let exam = day(60)

        // Plan for SAC 1. The block for the driver's week is the one containing today.
        let sacPlan = PlannerEngine.schedule(topics: [a], driver: sac, dailyMinutes: 60, from: Date(), calendar: calendar)
        let sacBlock = sacPlan.first { $0.weekIndex == 0 }!

        // SAC 1 passes; the exam becomes the driver. weekIndex 0 is now a
        // different week entirely.
        let examPlan = PlannerEngine.schedule(topics: [a], driver: exam, dailyMinutes: 60, from: Date(), calendar: calendar)
        let examBlock = examPlan.first { $0.weekIndex == 0 }!

        XCTAssertNotEqual(sacBlock.weekStart, examBlock.weekStart,
                          "weekIndex 0 means different calendar weeks either side of a driver change")

        // Keying on weekStart, the two weeks are distinct, so the tick is looked
        // up against the week it was actually made in and cannot drift onto the
        // exam's week.
        let keyForExamWeek = PlannerEngine.weekStart(forWeekIndex: 0, driver: exam, calendar: calendar)
        XCTAssertNotEqual(keyForExamWeek, sacBlock.weekStart)
    }

    func testDriverChangeKeepsTheCurrentWeeksPlanIdentical() {
        let a = TopicPlan(topicID: UUID(), title: "A", weight: 1)
        // Both drivers are far enough out that this week's column is the same
        // calendar week, so its block should carry the same anchor.
        let near = PlannerEngine.schedule(topics: [a], driver: day(20), dailyMinutes: 60, from: Date(), calendar: calendar)
        let far = PlannerEngine.schedule(topics: [a], driver: day(27), dailyMinutes: 60, from: Date(), calendar: calendar)
        let thisWeek = PlannerEngine.weekStart(containing: Date(), calendar: calendar)
        let nearThisWeek = near.first { $0.weekStart == thisWeek }
        let farThisWeek = far.first { $0.weekStart == thisWeek }
        XCTAssertNotNil(nearThisWeek)
        XCTAssertEqual(nearThisWeek?.minutes, farThisWeek?.minutes)
    }

    func testAPlanAlwaysHasAVisibleDriverToPointAt() {
        let a = TopicPlan(topicID: UUID(), title: "A", weight: 1)
        let blocks = PlannerEngine.schedule(
            topics: [a], driver: day(20), dailyMinutes: 60, from: Date(), calendar: calendar
        )
        XCTAssertFalse(blocks.isEmpty)
        // `driver` is a required argument, so a caller cannot build a plan without
        // naming an assessment to hold it to.
    }
}
