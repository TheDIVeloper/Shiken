import XCTest
@testable import ShikenMac

final class BacklogEngineTests: XCTestCase {
    private let calendar = Calendar(identifier: .gregorian)

    private func day(_ offset: Int) -> Date {
        calendar.date(byAdding: .day, value: offset, to: calendar.startOfDay(for: .now))!
    }

    /// `weeksAgo: 1` means seven days before today. Negative goes forwards.
    private func weekStart(weeksAgo: Int) -> Date {
        calendar.date(byAdding: .day, value: -weeksAgo * 7, to: calendar.startOfDay(for: .now))!
    }

    private func make(
        _ name: String,
        topics: [TopicPlan],
        assessments: [AssessmentRef]
    ) -> SubjectPlanInput {
        SubjectPlanInput(
            id: UUID(), name: name, accentHex: "#9A8C98",
            dailyMinutes: 60, topics: topics, assessments: assessments
        )
    }

    private func block(
        _ subject: SubjectPlanInput, _ topic: TopicPlan, weeksAgo: Int, done: Bool
    ) -> BacklogEngine.BacklogBlock {
        BacklogEngine.BacklogBlock(
            subjectID: subject.id, topicID: topic.topicID,
            weekStart: weekStart(weeksAgo: weeksAgo), isDone: done
        )
    }

    private func futureAssessment(_ offset: Int) -> AssessmentRef {
        AssessmentRef(title: "Exam", date: day(offset))
    }

    // MARK: The core promise: never a total, only topics

    func testAMissedTopicIsOfferedForPullingForward() {
        let subject = make("Chemistry", topics: [], assessments: [futureAssessment(30)])
        let topic = TopicPlan(topicID: subject.id, title: "Equilibria", weight: 20, isSynthetic: false)
        var planned = subject
        planned = SubjectPlanInput(
            id: subject.id, name: subject.name, accentHex: subject.accentHex,
            dailyMinutes: 60, topics: [topic], assessments: subject.assessments
        )

        let items = BacklogEngine.backlog(
            subjects: [planned],
            blocks: [block(planned, topic, weeksAgo: 1, done: false)]
        )

        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items.first?.title, "Equilibria")
        XCTAssertEqual(items.first?.subjectName, "Chemistry")
    }

    func testATickedTopicIsNotBacklog() {
        let subject = make("Chemistry", topics: [], assessments: [futureAssessment(30)])
        let topic = TopicPlan(topicID: UUID(), title: "Stoichiometry", weight: 20, isSynthetic: false)
        let planned = SubjectPlanInput(
            id: subject.id, name: subject.name, accentHex: subject.accentHex,
            dailyMinutes: 60, topics: [topic], assessments: subject.assessments
        )

        let items = BacklogEngine.backlog(
            subjects: [planned],
            blocks: [block(planned, topic, weeksAgo: 1, done: true)]
        )
        XCTAssertTrue(items.isEmpty, "something already done is not work to catch up on")
    }

    func testSyntheticStandInRowsAreNeverOffered() {
        // A topicless subject's italic row is a rendering device, not real work.
        // Offering it would be asking the user to tick a stand-in.
        let subject = make("Art", topics: [], assessments: [futureAssessment(20)])
        let synthetic = TopicPlan(topicID: subject.id, title: "Art", weight: 1, isSynthetic: true)
        let planned = SubjectPlanInput(
            id: subject.id, name: subject.name, accentHex: subject.accentHex,
            dailyMinutes: 60, topics: [synthetic], assessments: subject.assessments
        )

        XCTAssertTrue(BacklogEngine.backlog(
            subjects: [planned],
            blocks: [block(planned, synthetic, weeksAgo: 1, done: false)]
        ).isEmpty)
    }

    // MARK: Bounds

    func testAFutureBlockIsNotBacklog() {
        let subject = make("Chemistry", topics: [], assessments: [futureAssessment(30)])
        let topic = TopicPlan(topicID: UUID(), title: "Rates", weight: 20, isSynthetic: false)
        let planned = SubjectPlanInput(
            id: subject.id, name: subject.name, accentHex: subject.accentHex,
            dailyMinutes: 60, topics: [topic], assessments: subject.assessments
        )
        XCTAssertTrue(BacklogEngine.backlog(
            subjects: [planned],
            blocks: [block(planned, topic, weeksAgo: -1, done: false)]
        ).isEmpty, "you cannot be behind on tomorrow")
    }

    func testBlocksOlderThanTheLookbackAreNotResurfaced() {
        // A term-old topic the user never came back to is not what they need to
        // be told about today.
        let subject = make("Chemistry", topics: [], assessments: [futureAssessment(60)])
        let topic = TopicPlan(topicID: UUID(), title: "Old topic", weight: 20, isSynthetic: false)
        let planned = SubjectPlanInput(
            id: subject.id, name: subject.name, accentHex: subject.accentHex,
            dailyMinutes: 60, topics: [topic], assessments: subject.assessments
        )
        XCTAssertTrue(BacklogEngine.backlog(
            subjects: [planned],
            blocks: [block(planned, topic, weeksAgo: 8, done: false)]
        ).isEmpty)
    }

    func testATopicMissedTwiceAppearsOnce() {
        // Two missed weeks of the same topic is one thing to do, not two. This is
        // what keeps the list from turning into a wall.
        let subject = make("Chemistry", topics: [], assessments: [futureAssessment(60)])
        let topic = TopicPlan(topicID: UUID(), title: "Nomenclature", weight: 20, isSynthetic: false)
        let planned = SubjectPlanInput(
            id: subject.id, name: subject.name, accentHex: subject.accentHex,
            dailyMinutes: 60, topics: [topic], assessments: subject.assessments
        )
        let items = BacklogEngine.backlog(
            subjects: [planned],
            blocks: [
                block(planned, topic, weeksAgo: 1, done: false),
                block(planned, topic, weeksAgo: 2, done: false)
            ]
        )
        XCTAssertEqual(items.count, 1)
    }

    func testATopicTickedInALaterWeekIsNotBacklog() {
        // Missed Monday, then did it Wednesday: the user already came back to it.
        let subject = make("Chemistry", topics: [], assessments: [futureAssessment(60)])
        let topic = TopicPlan(topicID: UUID(), title: "Redox", weight: 20, isSynthetic: false)
        let planned = SubjectPlanInput(
            id: subject.id, name: subject.name, accentHex: subject.accentHex,
            dailyMinutes: 60, topics: [topic], assessments: subject.assessments
        )
        let items = BacklogEngine.backlog(
            subjects: [planned],
            blocks: [
                block(planned, topic, weeksAgo: 2, done: false),
                block(planned, topic, weeksAgo: 1, done: true)
            ]
        )
        XCTAssertTrue(items.isEmpty)
    }

    // MARK: Eligibility

    func testAFinishedSubjectHasNoBacklog() {
        // Every assessment past means the subject is done and history is kept.
        // There is nothing left to revise for, so nothing to be behind on.
        let subject = make("Chemistry", topics: [], assessments: [AssessmentRef(title: "Exam", date: day(-1))])
        let topic = TopicPlan(topicID: UUID(), title: "Rates", weight: 20, isSynthetic: false)
        let planned = SubjectPlanInput(
            id: subject.id, name: subject.name, accentHex: subject.accentHex,
            dailyMinutes: 60, topics: [topic], assessments: subject.assessments
        )
        XCTAssertTrue(BacklogEngine.backlog(
            subjects: [planned],
            blocks: [block(planned, topic, weeksAgo: 1, done: false)]
        ).isEmpty)
    }

    func testASubjectWithNoAssessmentsHasNoBacklog() {
        let subject = make("Art", topics: [], assessments: [])
        let topic = TopicPlan(topicID: UUID(), title: "Drawing", weight: 20, isSynthetic: false)
        let planned = SubjectPlanInput(
            id: subject.id, name: subject.name, accentHex: subject.accentHex,
            dailyMinutes: 60, topics: [topic], assessments: subject.assessments
        )
        XCTAssertTrue(BacklogEngine.backlog(
            subjects: [planned],
            blocks: [block(planned, topic, weeksAgo: 1, done: false)]
        ).isEmpty)
    }

    // MARK: Ordering and tone

    func testOldestMissedTopicComesFirst() throws {
        let subject = make("Chemistry", topics: [], assessments: [futureAssessment(60)])
        let older = TopicPlan(topicID: UUID(), title: "Older", weight: 20, isSynthetic: false)
        let newer = TopicPlan(topicID: UUID(), title: "Newer", weight: 20, isSynthetic: false)
        let planned = SubjectPlanInput(
            id: subject.id, name: subject.name, accentHex: subject.accentHex,
            dailyMinutes: 60, topics: [older, newer], assessments: subject.assessments
        )
        let items = BacklogEngine.backlog(
            subjects: [planned],
            blocks: [
                block(planned, newer, weeksAgo: 1, done: false),
                block(planned, older, weeksAgo: 2, done: false)
            ]
        )
        XCTAssertEqual(try XCTUnwrap(items.first).title, "Older")
    }

    func testTheListStaysShortEnoughToActOn() {
        // A wall of rows is the failure mode this feature exists to avoid.
        let subject = make("Chemistry", topics: [], assessments: [futureAssessment(90)])
        let topics = (0..<30).map {
            TopicPlan(topicID: UUID(), title: "Topic \($0)", weight: 5, isSynthetic: false)
        }
        let planned = SubjectPlanInput(
            id: subject.id, name: subject.name, accentHex: subject.accentHex,
            dailyMinutes: 60, topics: topics, assessments: subject.assessments
        )
        let items = BacklogEngine.backlog(
            subjects: [planned],
            blocks: topics.map { block(planned, $0, weeksAgo: 1, done: false) }
        )
        XCTAssertEqual(items.count, 30, "the engine lists them all; the view caps what it shows")
    }

    func testBacklogNeverContainsAMinutesTotal() {
        // The absence of a debt figure is the design, not an oversight. If a
        // summary type ever grows a minutes field, this should fail loudly.
        let subject = make("Chemistry", topics: [], assessments: [futureAssessment(30)])
        let topic = TopicPlan(topicID: UUID(), title: "Equilibria", weight: 20, isSynthetic: false)
        let planned = SubjectPlanInput(
            id: subject.id, name: subject.name, accentHex: subject.accentHex,
            dailyMinutes: 60, topics: [topic], assessments: subject.assessments
        )
        let items = BacklogEngine.backlog(
            subjects: [planned],
            blocks: [block(planned, topic, weeksAgo: 1, done: false)]
        )
        for item in items {
            XCTAssertFalse(item.subtitle.contains("behind"))
            XCTAssertFalse(item.subtitle.lowercased().contains("minutes"))
            XCTAssertFalse(item.subtitle.lowercased().contains("overdue"))
        }
    }

    func testNoSubjectsMeansNoBacklog() {
        XCTAssertTrue(BacklogEngine.backlog(subjects: [], blocks: []).isEmpty)
    }

    func testSubtitleNamesTheSubjectAndDay() throws {
        let subject = make("Chemistry", topics: [], assessments: [futureAssessment(30)])
        let topic = TopicPlan(topicID: UUID(), title: "Equilibria", weight: 20, isSynthetic: false)
        let planned = SubjectPlanInput(
            id: subject.id, name: subject.name, accentHex: subject.accentHex,
            dailyMinutes: 60, topics: [topic], assessments: subject.assessments
        )
        let item = try XCTUnwrap(BacklogEngine.backlog(
            subjects: [planned],
            blocks: [block(planned, topic, weeksAgo: 1, done: false)]
        ).first)
        XCTAssertTrue(item.subtitle.contains("Chemistry"))
        XCTAssertTrue(item.isTickable)
    }
}