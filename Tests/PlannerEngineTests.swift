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
        XCTAssertEqual(PlannerEngine.schedule(topics: [], examDate: day(7), dailyMinutes: 60, from: Date()), [])
    }

    func testScheduleWeightedSplit() {
        let a = TopicPlan(topicID: UUID(), title: "A", weight: 1)
        let b = TopicPlan(topicID: UUID(), title: "B", weight: 2)
        let blocks = PlannerEngine.schedule(topics: [a, b], examDate: day(7), dailyMinutes: 60, from: Date())
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
        let blocks = PlannerEngine.schedule(topics: [a, b], examDate: day(6), dailyMinutes: 30, from: Date())
        let week0 = blocks.filter { $0.weekIndex == 0 }
        XCTAssertEqual(week0.map(\.minutes).reduce(0, +), 210)
        XCTAssertEqual(week0.map(\.minutes).sorted(), [105, 105])
    }

    func testScheduleEveryWeekSumsToWeeklyTotal() {
        let weights = [2, 1, 5, 3, 4]
        let topics = (0..<5).map { TopicPlan(topicID: UUID(), title: "T\($0)", weight: weights[$0]) }
        let blocks = PlannerEngine.schedule(topics: topics, examDate: day(30), dailyMinutes: 45, from: Date())
        let weeks = Set(blocks.map(\.weekIndex))
        for week in weeks {
            let sum = blocks.filter { $0.weekIndex == week }.map(\.minutes).reduce(0, +)
            XCTAssertEqual(sum, 45 * 7)
        }
    }
}