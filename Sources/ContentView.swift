import SwiftUI
import SwiftData

enum SidebarSelection: Hashable {
    case focus
    case sessions
    case subject(UUID)
}

struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Query(sort: \Subject.position) private var subjects: [Subject]
    @State private var selection: SidebarSelection?
    @State private var showingNewSubject = false
    @State private var focusTimer = FocusTimer()

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                Section("Study") {
                    Label("Focus", systemImage: "timer")
                        .tag(SidebarSelection.focus)
                    Label("Sessions", systemImage: "list.bullet.rectangle.portrait")
                        .tag(SidebarSelection.sessions)
                }

                Section("Subjects") {
                    ForEach(subjects) { subject in
                        SubjectRow(subject: subject)
                            .tag(SidebarSelection.subject(subject.id))
                    }
                }
            }
            .navigationTitle("Shiken")
            .overlay {
                if subjects.isEmpty && selection == nil {
                    ContentUnavailableView(
                        "No subjects yet",
                        systemImage: "book.closed",
                        description: Text("Add a subject and its exam date — the plan builds from there.")
                    )
                }
            }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showingNewSubject = true
                    } label: {
                        Label("Add subject", systemImage: "plus")
                    }
                    .help("Add a subject")
                }
            }
        } detail: {
            detail
        }
        .environment(focusTimer)
        .sheet(isPresented: $showingNewSubject) {
            SubjectEditorSheet { newID in
                selection = .subject(newID)
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                focusTimer.awayEnd()
            } else {
                focusTimer.awayBegin()
            }
        }
    }

    @ViewBuilder
    private var detail: some View {
        switch selection {
        case .focus:
            FocusView()
        case .sessions:
            SessionLogView()
        case .subject(let id):
            if let subject = subjects.first(where: { $0.id == id }) {
                PlannerView(subject: subject)
            } else {
                HomeView()
            }
        case nil:
            HomeView()
        }
    }
}

struct HomeView: View {
    var body: some View {
        VStack(spacing: DesignSystem.spaceL()) {
            Image(systemName: "square.grid.2x2.fill")
                .font(.system(size: DesignSystem.typeHero()))
                .foregroundStyle(.quaternary)

            Text("Shiken")
                .font(.system(size: DesignSystem.typeDisplay(), weight: .semibold))

            Text("Your revision plan, held to account.")
                .font(.system(size: DesignSystem.typeBody(), weight: .regular))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}