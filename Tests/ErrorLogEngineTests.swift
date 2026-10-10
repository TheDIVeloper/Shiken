import XCTest
@testable import ShikenMac

final class ErrorLogEngineTests: XCTestCase {
    private var calendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        return cal
    }

    private func date(dayOffset: Int, from base: Date) -> Date {
        calendar.date(byAdding: .day, value: dayOffset, to: base)!
    }

    func testInitialNextReviewDateIsOneDayOut() {
        let now = Date(timeIntervalSince1970: 1700000000)
        let next = ErrorLogEngine.initialNextReviewDate(from: now, calendar: calendar)
        let expected = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now))!
        XCTAssertEqual(next, expected)
    }

    func testIsDueDetection() {
        let today = Date(timeIntervalSince1970: 1700000000)
        let past = date(dayOffset: -2, from: today)
        let future = date(dayOffset: 2, from: today)

        XCTAssertTrue(ErrorLogEngine.isDue(nextReviewDate: past, isResolved: false, on: today, calendar: calendar))
        XCTAssertTrue(ErrorLogEngine.isDue(nextReviewDate: today, isResolved: false, on: today, calendar: calendar))
        XCTAssertFalse(ErrorLogEngine.isDue(nextReviewDate: future, isResolved: false, on: today, calendar: calendar))

        // Resolved errors are never due
        XCTAssertFalse(ErrorLogEngine.isDue(nextReviewDate: past, isResolved: true, on: today, calendar: calendar))
    }

    func testSpacedReviewProgressionWhenPassing() {
        let base = Date(timeIntervalSince1970: 1700000000)
        let startOfDay = calendar.startOfDay(for: base)

        // Stage 0 -> Stage 1 (+3 days)
        let step1 = ErrorLogEngine.recordReview(currentStage: 0, passed: true, reviewedAt: base, calendar: calendar)
        XCTAssertEqual(step1.nextStage, 1)
        XCTAssertFalse(step1.isResolved)
        XCTAssertEqual(step1.nextReviewDate, calendar.date(byAdding: .day, value: 3, to: startOfDay))

        // Stage 1 -> Stage 2 (+7 days)
        let step2 = ErrorLogEngine.recordReview(currentStage: 1, passed: true, reviewedAt: base, calendar: calendar)
        XCTAssertEqual(step2.nextStage, 2)
        XCTAssertFalse(step2.isResolved)
        XCTAssertEqual(step2.nextReviewDate, calendar.date(byAdding: .day, value: 7, to: startOfDay))

        // Stage 2 -> Stage 3 (Resolved)
        let step3 = ErrorLogEngine.recordReview(currentStage: 2, passed: true, reviewedAt: base, calendar: calendar)
        XCTAssertEqual(step3.nextStage, 3)
        XCTAssertTrue(step3.isResolved)
    }

    func testSpacedReviewProgressionWhenRusty() {
        let base = Date(timeIntervalSince1970: 1700000000)
        let startOfDay = calendar.startOfDay(for: base)

        // Failing at stage 2 drops back to stage 0 (+1 day)
        let demoted = ErrorLogEngine.recordReview(currentStage: 2, passed: false, reviewedAt: base, calendar: calendar)
        XCTAssertEqual(demoted.nextStage, 0)
        XCTAssertFalse(demoted.isResolved)
        XCTAssertEqual(demoted.nextReviewDate, calendar.date(byAdding: .day, value: 1, to: startOfDay))
    }

    func testFilteringBySubjectCategoryAndStatus() {
        let today = Date(timeIntervalSince1970: 1700000000)
        let subjectA = UUID()
        let subjectB = UUID()
        let topic1 = UUID()

        let errors = [
            ErrorRecord(
                subjectID: subjectA,
                subjectName: "Maths",
                topicID: topic1,
                category: .carelessSlip,
                errorDescription: "Sign error on line 3",
                date: today,
                nextReviewDate: date(dayOffset: -1, from: today),
                isResolved: false
            ),
            ErrorRecord(
                subjectID: subjectA,
                subjectName: "Maths",
                topicID: nil,
                category: .contentGap,
                errorDescription: "Forgot chain rule",
                date: today,
                nextReviewDate: date(dayOffset: 3, from: today),
                isResolved: false
            ),
            ErrorRecord(
                subjectID: subjectB,
                subjectName: "Physics",
                topicID: nil,
                category: .misreading,
                errorDescription: "Missed unit prefix",
                date: today,
                nextReviewDate: today,
                isResolved: true
            )
        ]

        // Filter by subject
        let forA = ErrorLogEngine.filter(errors: errors, filter: ErrorFilter(subjectID: subjectA), on: today, calendar: calendar)
        XCTAssertEqual(forA.count, 2)

        // Filter by topic
        let forTopic = ErrorLogEngine.filter(errors: errors, filter: ErrorFilter(topicID: topic1), on: today, calendar: calendar)
        XCTAssertEqual(forTopic.count, 1)

        // Filter by category
        let slips = ErrorLogEngine.filter(errors: errors, filter: ErrorFilter(category: .carelessSlip), on: today, calendar: calendar)
        XCTAssertEqual(slips.count, 1)

        // Filter by status: due today
        let due = ErrorLogEngine.filter(errors: errors, filter: ErrorFilter(status: .due), on: today, calendar: calendar)
        XCTAssertEqual(due.count, 1)
        XCTAssertEqual(due.first?.errorDescription, "Sign error on line 3")

        // Filter by status: active
        let active = ErrorLogEngine.filter(errors: errors, filter: ErrorFilter(status: .active), on: today, calendar: calendar)
        XCTAssertEqual(active.count, 2)

        // Filter by status: resolved
        let resolved = ErrorLogEngine.filter(errors: errors, filter: ErrorFilter(status: .resolved), on: today, calendar: calendar)
        XCTAssertEqual(resolved.count, 1)
        XCTAssertEqual(resolved.first?.subjectName, "Physics")
    }

    func testSummaryStatistics() {
        let today = Date(timeIntervalSince1970: 1700000000)
        let subject = UUID()

        let errors = [
            ErrorRecord(
                subjectID: subject,
                subjectName: "Chemistry",
                category: .carelessSlip,
                errorDescription: "Calculation error",
                nextReviewDate: date(dayOffset: -1, from: today),
                isResolved: false
            ),
            ErrorRecord(
                subjectID: subject,
                subjectName: "Chemistry",
                category: .carelessSlip,
                errorDescription: "Forgotten subscript",
                nextReviewDate: date(dayOffset: 5, from: today),
                isResolved: false
            ),
            ErrorRecord(
                subjectID: subject,
                subjectName: "Chemistry",
                category: .methodStrategy,
                errorDescription: "Selected wrong formula",
                nextReviewDate: today,
                isResolved: true
            )
        ]

        let summary = ErrorLogEngine.summary(errors: errors, on: today, calendar: calendar)
        XCTAssertEqual(summary.total, 3)
        XCTAssertEqual(summary.active, 2)
        XCTAssertEqual(summary.dueToday, 1)
        XCTAssertEqual(summary.resolved, 1)
        XCTAssertEqual(summary.countsByCategory[.carelessSlip], 2)
        XCTAssertEqual(summary.countsByCategory[.methodStrategy], 1)
        XCTAssertEqual(summary.countsByCategory[.contentGap], 0)
    }

    func testStageLabels() {
        XCTAssertEqual(ErrorLogEngine.stageLabel(stage: 0, isResolved: false), "Initial (due in 1d)")
        XCTAssertEqual(ErrorLogEngine.stageLabel(stage: 1, isResolved: false), "Review 1 (due in 3d)")
        XCTAssertEqual(ErrorLogEngine.stageLabel(stage: 2, isResolved: false), "Review 2 (due in 7d)")
        XCTAssertEqual(ErrorLogEngine.stageLabel(stage: 2, isResolved: true), "Resolved")
    }
}
