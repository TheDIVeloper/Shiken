import XCTest
@testable import ShikenMac

final class ReviewEngineTests: XCTestCase {
    private var calendar: Calendar { var c = Calendar.current; c.timeZone = .gmt; return c }
    private func day(_ offset: Int, from now: Date) -> Date {
        calendar.date(byAdding: .day, value: offset, to: now)!
    }

    func testCurrentWeekIndexExamSoonIsZero() {
        let now = Date()
        XCTAssertEqual(ReviewEngine.currentWeekIndex(examDate: day(6, from: now), now: now, calendar: calendar), 0)
    }

    func testCurrentWeekIndexTwoWeeksOut() {
        let now = Date()
        XCTAssertEqual(ReviewEngine.currentWeekIndex(examDate: day(13, from: now), now: now, calendar: calendar), 1)
    }

    func testSessionsInWindowFiltersBySubjectAndDate() {
        let now = Date()
        let subject = UUID()
        let other = UUID()
        let sessions = [
            SessionRecord(subjectID: subject, topicID: nil, focusedMinutes: 30, startedAt: day(-1, from: now)),
            SessionRecord(subjectID: subject, topicID: nil, focusedMinutes: 30, startedAt: day(-10, from: now)),
            SessionRecord(subjectID: other, topicID: nil, focusedMinutes: 30, startedAt: day(-1, from: now))
        ]
        let inWindow = ReviewEngine.sessionsInWindow(sessions, subjectID: subject, now: now, calendar: calendar)
        XCTAssertEqual(inWindow.count, 1)
        XCTAssertEqual(inWindow.first?.focusedMinutes, 30)
    }

    func testReviewAggregatesPlannedAndActual() {
        let now = Date()
        let exam = day(10, from: now) // weeksBetween = 2 -> current week index 1
        let a = UUID(), b = UUID()
        let subject = UUID()
        let topics = [
            TopicPlan(topicID: a, title: "Mechanisms", weight: 1),
            TopicPlan(topicID: b, title: "Thermo", weight: 1)
        ]
        let plan = [
            ScheduledBlock(weekIndex: 1, topicID: a, minutes: 140),
            ScheduledBlock(weekIndex: 1, topicID: b, minutes: 140),
            ScheduledBlock(weekIndex: 0, topicID: a, minutes: 140)
        ]
        let sessions = [
            SessionRecord(subjectID: subject, topicID: a, focusedMinutes: 90, startedAt: day(-1, from: now)),
            SessionRecord(subjectID: subject, topicID: b, focusedMinutes: 120, startedAt: day(-2, from: now)),
            SessionRecord(subjectID: subject, topicID: a, focusedMinutes: 60, startedAt: day(-9, from: now))
        ]
        let review = ReviewEngine.review(
            subjectID: subject, name: "Chemistry", accentHex: "9A8C98",
            topics: topics, plan: plan, sessions: sessions, examDate: exam, now: now, calendar: calendar
        )
        XCTAssertEqual(review.plannedMinutes, 280)
        XCTAssertEqual(review.actualMinutes, 210) // 90 + 120; the 9-day-old one is outside the window
        XCTAssertEqual(review.gapMinutes, -70)
        XCTAssertEqual(review.completionPercent, 75)
        XCTAssertEqual(review.topics.first { $0.topicID == a }?.actualMinutes, 90)
    }

    func testVerdictBands() {
        XCTAssertEqual(ReviewEngine.verdict(planned: 0, actual: 100), "No targets planned for this week.")
        XCTAssertTrue(ReviewEngine.verdict(planned: 100, actual: 110).contains("Plan met"))
        XCTAssertTrue(ReviewEngine.verdict(planned: 100, actual: 85).contains("Close"))
        XCTAssertTrue(ReviewEngine.verdict(planned: 100, actual: 60).contains("drift"))
        XCTAssertTrue(ReviewEngine.verdict(planned: 100, actual: 20).contains("Well behind"))
    }

    func testLetterAndMarkdownContainNumbers() {
        let subject = UUID()
        let topic = UUID()
        let review = SubjectReview(
            subjectID: subject, name: "Physics", accentHex: "5B7B8C",
            plannedMinutes: 200, actualMinutes: 150,
            topics: [TopicReview(topicID: topic, title: "Waves", plannedMinutes: 200, actualMinutes: 150)]
        )
        let letter = ReviewEngine.letter(for: review)
        XCTAssertTrue(letter.contains("Physics"))
        XCTAssertTrue(letter.contains("150m"))
        XCTAssertTrue(letter.contains("Waves"))

        let markdown = ReviewEngine.markdown(for: [review])
        XCTAssertTrue(markdown.hasPrefix("# Shiken — weekly review"))
        XCTAssertTrue(markdown.contains("Physics"))
    }
}