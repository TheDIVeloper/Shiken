import SwiftUI
import SwiftData

@main
struct ShikenApp: App {
    let container: ModelContainer

    init() {
        let schema = Schema([Subject.self, Topic.self, PlanBlock.self, StudySession.self])
        do {
            container = try ModelContainer(for: schema)
        } catch {
            fatalError("Shiken failed to create its store: \(error)")
        }
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