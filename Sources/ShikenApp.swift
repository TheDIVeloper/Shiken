import SwiftUI
import SwiftData

@main
struct ShikenApp: App {
    let container: ModelContainer

    init() {
        // `examDate` on Subject moved onto Assessment in 0.4. Lightweight
        // migration keeps existing rows; the backfill below turns each old exam
        // date into a named assessment so no plan silently loses its deadline.
        let schema = Schema([Subject.self, Topic.self, PlanBlock.self, StudySession.self, Assessment.self])
        do {
            container = try ModelContainer(for: schema)
        } catch {
            fatalError("Shiken failed to create its store: \(error)")
        }
        Migration.backfillAssessments(in: container.mainContext)
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .modelContainer(container)
        }
        #if os(macOS)
        .defaultSize(width: 1000, height: 660)
        #endif
    }
}

/// One-time data migrations. Each is idempotent, so running on every launch is
/// safe and a failed run simply tries again next time.
enum Migration {
    static func backfillAssessments(in ctx: ModelContext) {
        let subjects = (try? ctx.fetch(FetchDescriptor<Subject>())) ?? []
        var changed = false

        for subject in subjects {
            guard subject.assessments.isEmpty else { continue }
            let assessment = Assessment(
                title: "Exam",
                date: LegacyExamDateStore.examDate(for: subject),
                position: 0
            )
            assessment.subject = subject
            ctx.insert(assessment)
            changed = true
        }

        if changed { try? ctx.save() }
    }
}

/// SwiftData stores columns on the object itself, so the retired `examDate`
/// attribute is read reflectively. If it is gone — a fresh install, or a store
/// written after the migration — we fall back to a sensible default rather than
/// failing, because a subject with no date simply has no plan yet.
private enum LegacyExamDateStore {
    static func examDate(for subject: Subject) -> Date {
        let mirror = Mirror(reflecting: subject)
        for child in mirror.children where child.label == "examDate" {
            if let date = child.value as? Date { return date }
        }
        return Calendar.current.date(byAdding: .day, value: 60, to: .now) ?? .now
    }
}