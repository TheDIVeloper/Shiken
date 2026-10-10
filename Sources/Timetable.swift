import Foundation

/// Turns a school timetable into a suggested daily figure per subject.
///
/// This exists because `dailyMinutes` is the input the entire plan hangs off. A
/// wrong guess corrupts every topic split, every weekly total and every target
/// tick downstream, so it is worth getting right once instead of guessing forever.
///
/// Two rules drive it:
/// - Contact time is a decent proxy for revision need, so minutes are shared out
///   in proportion to periods.
/// - Enrichment drops get a floor rather than a share of zero. Art and Music are
///   still examined, and a subject planned at zero is a subject that stops.
///
/// The derivation only ever produces a *default*. Once the user touches the
/// daily stepper, `dailyMinutesIsDerived` goes false and their number sticks.
enum Timetable {
    /// Default daily study budget the derivation shares out. Chosen because a
    /// Year 12 with four assessed subjects plus enrichment needs roughly this.
    static let defaultTotalDailyMinutes = 240

    /// Minimum daily minutes for an enrichment drop.
    static let enrichmentFloor = 15

    /// Stepper granularity, so a derived figure lands on a round number.
    static let step = 15

    /// Suggested daily minutes for one subject.
    ///
    /// - Parameters:
    ///   - periodsPerWeek: lessons a week on the timetable.
    ///   - isEnrichment: whether this is an enrichment drop.
    ///   - totalDailyMinutes: the user's whole daily study budget.
    ///   - totalPeriods: periods across every non-enrichment subject.
    static func derivedDailyMinutes(
        periodsPerWeek: Int,
        isEnrichment: Bool,
        totalDailyMinutes: Int = defaultTotalDailyMinutes,
        totalPeriods: Int
    ) -> Int {
        if isEnrichment { return enrichmentFloor }
        guard totalPeriods > 0, totalDailyMinutes > 0 else { return enrichmentFloor }

        let share = Double(totalDailyMinutes) * Double(max(0, periodsPerWeek)) / Double(totalPeriods)
        return roundedToStep(share)
    }

    /// Snaps to the stepper's step, never to zero. A subject planned at 0 minutes
    /// is worse than useless: it looks planned while producing nothing.
    static func roundedToStep(_ minutes: Double) -> Int {
        guard minutes > 0 else { return step }
        let snapped = (minutes / Double(step)).rounded() * Double(step)
        return max(step, Int(snapped))
    }

    /// Derives every subject at once, so the editor can show the whole picture
    /// and the user can see how one subject's change moves the others.
    ///
    /// Enrichment subjects are excluded from the divisor: they have their own
    /// floor, and including them would quietly shrink the assessed subjects.
    static func derivation(
        subjects: [SubjectPlan],
        totalDailyMinutes: Int = defaultTotalDailyMinutes
    ) -> [UUID: Int] {
        let totalPeriods = subjects
            .filter { !$0.isEnrichment }
            .reduce(0) { $0 + max(0, $1.periodsPerWeek) }

        return Dictionary(uniqueKeysWithValues: subjects.map { subject in
            let minutes = derivedDailyMinutes(
                periodsPerWeek: subject.periodsPerWeek,
                isEnrichment: subject.isEnrichment,
                totalDailyMinutes: totalDailyMinutes,
                totalPeriods: totalPeriods
            )
            return (subject.id, minutes)
        })
    }
}

/// The little bit of a subject the derivation needs. Keeps `Timetable` free of
/// SwiftData so it stays a pure, cheaply testable function.
struct SubjectPlan: Equatable, Sendable {
    let id: UUID
    let periodsPerWeek: Int
    let isEnrichment: Bool
}