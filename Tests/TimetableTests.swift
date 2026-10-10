import XCTest
@testable import ShikenMac

final class TimetableTests: XCTestCase {
    // MARK: Proportional sharing

    func testDailyMinutesShareOutByPeriods() {
        // 20 periods a week across two subjects, 240 minutes to share.
        XCTAssertEqual(
            Timetable.derivedDailyMinutes(
                periodsPerWeek: 10, isEnrichment: false, totalDailyMinutes: 240, totalPeriods: 20
            ),
            120,
            "half the contact time gets half the minutes"
        )
        XCTAssertEqual(
            Timetable.derivedDailyMinutes(
                periodsPerWeek: 5, isEnrichment: false, totalDailyMinutes: 240, totalPeriods: 20
            ),
            60
        )
    }

    func testMorePeriodsNeverMeansFewerMinutes() {
        let single = Timetable.derivedDailyMinutes(
            periodsPerWeek: 1, isEnrichment: false, totalDailyMinutes: 240, totalPeriods: 20
        )
        let double = Timetable.derivedDailyMinutes(
            periodsPerWeek: 2, isEnrichment: false, totalDailyMinutes: 240, totalPeriods: 20
        )
        XCTAssertGreaterThan(double, single)
    }

    func testDerivedMinutesLandOnTheStepperStep() {
        let minutes = Timetable.derivedDailyMinutes(
            periodsPerWeek: 3, isEnrichment: false, totalDailyMinutes: 240, totalPeriods: 19
        )
        XCTAssertEqual(minutes % Timetable.step, 0, "a derived figure must fit the stepper")
        XCTAssertGreaterThan(minutes, 0)
    }

    func testASubjectIsNeverDerivedToZero() {
        // One subject with a single period against a large total would round to
        // nothing, which is worse than useless: it looks planned and produces
        // nothing.
        let minutes = Timetable.derivedDailyMinutes(
            periodsPerWeek: 1, isEnrichment: false, totalDailyMinutes: 60, totalPeriods: 200
        )
        XCTAssertEqual(minutes, Timetable.step)
    }

    func testNoPeriodsFallsBackToTheFloorRatherThanCrashing() {
        XCTAssertEqual(
            Timetable.derivedDailyMinutes(
                periodsPerWeek: 5, isEnrichment: false, totalDailyMinutes: 240, totalPeriods: 0
            ),
            Timetable.enrichmentFloor
        )
    }

    // MARK: Enrichment

    func testEnrichmentGetsAFloorNotAZero() {
        // Art and Music are still examined. A subject planned at zero is a
        // subject that quietly stops.
        XCTAssertEqual(
            Timetable.derivedDailyMinutes(
                periodsPerWeek: 1, isEnrichment: true, totalDailyMinutes: 240, totalPeriods: 20
            ),
            Timetable.enrichmentFloor
        )
    }

    func testEnrichmentIsExcludedFromTheDivisor() {
        // Two assessed subjects share 240m between them: 120 each. Enrichment
        // sits outside that pool and must not shrink them.
        let subjects = [
            SubjectPlan(id: UUID(), periodsPerWeek: 5, isEnrichment: false),
            SubjectPlan(id: UUID(), periodsPerWeek: 5, isEnrichment: false),
            SubjectPlan(id: UUID(), periodsPerWeek: 1, isEnrichment: true)
        ]
        let derived = Timetable.derivation(subjects: subjects, totalDailyMinutes: 240)

        let assessed = subjects.filter { !$0.isEnrichment }.map { derived[$0.id] }
        XCTAssertEqual(assessed, [120, 120])
        XCTAssertEqual(derived[subjects[2].id], Timetable.enrichmentFloor)
    }

    // MARK: Whole-set derivation

    func testRaisingTheTotalRaisesEveryDerivedSubject() {
        let subjects = [
            SubjectPlan(id: UUID(), periodsPerWeek: 4, isEnrichment: false),
            SubjectPlan(id: UUID(), periodsPerWeek: 4, isEnrichment: false)
        ]
        let low = Timetable.derivation(subjects: subjects, totalDailyMinutes: 120)
        let high = Timetable.derivation(subjects: subjects, totalDailyMinutes: 300)
        for subject in subjects {
            XCTAssertGreaterThan(high[subject.id] ?? 0, low[subject.id] ?? 0)
        }
    }

    func testEmptySubjectSetProducesNoSuggestions() {
        XCTAssertTrue(Timetable.derivation(subjects: []).isEmpty)
    }

    func testDerivationCoversEverySubjectExactlyOnce() {
        let subjects = (0..<6).map { _ in
            SubjectPlan(id: UUID(), periodsPerWeek: 4, isEnrichment: false)
        }
        XCTAssertEqual(Timetable.derivation(subjects: subjects).count, subjects.count)
    }

    func testDuplicateSubjectIDsDoNotCrashDerivation() {
        let sharedID = UUID()
        let subjects = [
            SubjectPlan(id: sharedID, periodsPerWeek: 4, isEnrichment: false),
            SubjectPlan(id: sharedID, periodsPerWeek: 4, isEnrichment: false),
            SubjectPlan(id: UUID(), periodsPerWeek: 4, isEnrichment: false)
        ]
        let derived = Timetable.derivation(subjects: subjects)
        XCTAssertEqual(derived.count, 2)
        XCTAssertNotNil(derived[sharedID])
    }
}