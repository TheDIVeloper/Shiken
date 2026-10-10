import XCTest
@testable import ShikenMac

final class DayTaskEngineTests: XCTestCase {
    private var calendar: Calendar {
        var c = Calendar.current
        c.timeZone = .gmt
        return c
    }

    private func day(_ offset: Int) -> Date {
        calendar.date(byAdding: .day, value: offset, to: Date())!
    }

    private func makeSubject(
        id: UUID = UUID(),
        name: String = "Physics",
        dailyMinutes: Int = 60,
        dayModeRaw: String = "tasks",
        topics: [TopicPlan] = [],
        assessments: [AssessmentRef] = []
    ) -> SubjectPlanInput {
        SubjectPlanInput(
            id: id,
            name: name,
            accentHex: "4A90E2",
            dailyMinutes: dailyMinutes,
            dayModeRaw: dayModeRaw,
            topics: topics,
            assessments: assessments
        )
    }

    func testTasksDerivedFromTopicsWithPlannedMinutesHint() {
        let t1 = TopicPlan(topicID: UUID(), title: "Mechanics", weight: 2)
        let t2 = TopicPlan(topicID: UUID(), title: "Waves", weight: 1)
        let assessment = AssessmentRef(title: "Exam", date: day(20))
        let subject = makeSubject(topics: [t1, t2], assessments: [assessment])

        let tasks = DayTaskEngine.tasksForDay(
            subject: subject,
            driver: assessment,
            date: day(0),
            persisted: [],
            calendar: calendar
        )

        XCTAssertEqual(tasks.count, 2)
        XCTAssertEqual(tasks[0].title, "Mechanics")
        XCTAssertEqual(tasks[0].plannedMinutesHint, 40)
        XCTAssertFalse(tasks[0].isDone)
        XCTAssertEqual(tasks[1].title, "Waves")
        XCTAssertEqual(tasks[1].plannedMinutesHint, 20)
        XCTAssertFalse(tasks[1].isDone)
    }

    func testAdHocTasksAppendedInPositionOrder() {
        let t1 = TopicPlan(topicID: UUID(), title: "Mechanics", weight: 1)
        let assessment = AssessmentRef(title: "Exam", date: day(20))
        let subjectID = UUID()
        let subject = makeSubject(id: subjectID, topics: [t1], assessments: [assessment])

        let today = DayTaskEngine.normalizeDate(day(0), calendar: calendar)
        let adHoc1 = DayTaskRecord(
            subjectID: subjectID,
            date: today,
            title: "Past paper question 4",
            isDone: false,
            isAdHoc: true,
            position: 2
        )
        let adHoc2 = DayTaskRecord(
            subjectID: subjectID,
            date: today,
            title: "Formulas review",
            isDone: true,
            isAdHoc: true,
            position: 1
        )

        let tasks = DayTaskEngine.tasksForDay(
            subject: subject,
            driver: assessment,
            date: today,
            persisted: [adHoc1, adHoc2],
            calendar: calendar
        )

        XCTAssertEqual(tasks.count, 3)
        XCTAssertEqual(tasks[0].title, "Mechanics")
        XCTAssertFalse(tasks[0].isAdHoc)
        XCTAssertEqual(tasks[1].title, "Formulas review")
        XCTAssertTrue(tasks[1].isAdHoc)
        XCTAssertTrue(tasks[1].isDone)
        XCTAssertEqual(tasks[2].title, "Past paper question 4")
        XCTAssertTrue(tasks[2].isAdHoc)
        XCTAssertFalse(tasks[2].isDone)
    }

    func testTicksMatchedByTopicIDAndDate() {
        let topicID = UUID()
        let t1 = TopicPlan(topicID: topicID, title: "Equilibria", weight: 1)
        let assessment = AssessmentRef(title: "SAC", date: day(10))
        let subjectID = UUID()
        let subject = makeSubject(id: subjectID, topics: [t1], assessments: [assessment])

        let today = DayTaskEngine.normalizeDate(day(0), calendar: calendar)
        let record = DayTaskRecord(
            subjectID: subjectID,
            topicID: topicID,
            date: today,
            title: "Equilibria",
            isDone: true,
            isAdHoc: false
        )

        let tasks = DayTaskEngine.tasksForDay(
            subject: subject,
            driver: assessment,
            date: today,
            persisted: [record],
            calendar: calendar
        )

        XCTAssertEqual(tasks.count, 1)
        XCTAssertTrue(tasks[0].isDone)
        XCTAssertEqual(tasks[0].taskRecordID, record.id)
    }

    func testSyntheticTopicIsRecognised() {
        let subjectID = UUID()
        let assessment = AssessmentRef(title: "Exam", date: day(10))
        let subject = makeSubject(id: subjectID, name: "Italian", topics: [], assessments: [assessment])

        let tasks = DayTaskEngine.tasksForDay(
            subject: subject,
            driver: assessment,
            date: day(0),
            persisted: [],
            calendar: calendar
        )

        XCTAssertEqual(tasks.count, 1)
        XCTAssertTrue(tasks[0].isSynthetic)
        let summary = DayTaskEngine.summary(tasks: tasks)
        XCTAssertEqual(summary.totalTasks, 0, "synthetic topics do not create tickable tasks")
    }

    func testSummaryEvaluatesCompletionCorrectly() {
        let subjectID = UUID()
        let date = day(0)
        let task1 = DerivedDayTask(
            id: UUID(), taskRecordID: nil, subjectID: subjectID, subjectName: "Maths",
            subjectAccentHex: "123456", topicID: UUID(), title: "Calculus",
            plannedMinutesHint: 30, isAdHoc: false, isSynthetic: false, isDone: true, date: date
        )
        let task2 = DerivedDayTask(
            id: UUID(), taskRecordID: nil, subjectID: subjectID, subjectName: "Maths",
            subjectAccentHex: "123456", topicID: UUID(), title: "Vectors",
            plannedMinutesHint: 30, isAdHoc: false, isSynthetic: false, isDone: false, date: date
        )

        let partial = DayTaskEngine.summary(tasks: [task1, task2])
        XCTAssertEqual(partial.totalTasks, 2)
        XCTAssertEqual(partial.completedTasks, 1)
        XCTAssertEqual(partial.remainingTasks, 1)
        XCTAssertEqual(partial.percent, 50)
        XCTAssertFalse(partial.isComplete)

        let completeTask2 = DerivedDayTask(
            id: task2.id, taskRecordID: nil, subjectID: subjectID, subjectName: "Maths",
            subjectAccentHex: "123456", topicID: UUID(), title: "Vectors",
            plannedMinutesHint: 30, isAdHoc: false, isSynthetic: false, isDone: true, date: date
        )
        let allDone = DayTaskEngine.summary(tasks: [task1, completeTask2])
        XCTAssertEqual(allDone.completedTasks, 2)
        XCTAssertEqual(allDone.remainingTasks, 0)
        XCTAssertEqual(allDone.percent, 100)
        XCTAssertTrue(allDone.isComplete)
    }

    func testWindowSummaryAggregatesOverMultipleDays() {
        let topicID = UUID()
        let t1 = TopicPlan(topicID: topicID, title: "English Essay", weight: 1)
        let assessment = AssessmentRef(title: "Trial", date: day(14))
        let subjectID = UUID()
        let subject = makeSubject(id: subjectID, topics: [t1], assessments: [assessment])

        let day0 = DayTaskEngine.normalizeDate(day(0), calendar: calendar)
        let day1 = DayTaskEngine.normalizeDate(day(-1), calendar: calendar)
        let record0 = DayTaskRecord(subjectID: subjectID, topicID: topicID, date: day0, title: "English Essay", isDone: true)
        let record1 = DayTaskRecord(subjectID: subjectID, topicID: topicID, date: day1, title: "English Essay", isDone: true)

        let summary = DayTaskEngine.windowSummary(
            subject: subject,
            driver: assessment,
            persisted: [record0, record1],
            from: day(0),
            days: 7,
            calendar: calendar
        )

        XCTAssertEqual(summary.totalTasks, 7)
        XCTAssertEqual(summary.completedTasks, 2)
        XCTAssertEqual(summary.remainingTasks, 5)
    }
}
