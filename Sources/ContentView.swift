import SwiftUI
import SwiftData

struct ContentView: View {
    @Query(sort: \Subject.position) private var subjects: [Subject]
    @State private var selectedSubjectID: Subject.ID?
    @State private var showingNewSubject = false

    private var selectedSubject: Subject? {
        subjects.first { $0.id == selectedSubjectID }
    }

    var body: some View {
        NavigationSplitView {
            List(selection: $selectedSubjectID) {
                ForEach(subjects) { subject in
                    NavigationLink(value: subject.id) {
                        SubjectRow(subject: subject)
                    }
                }
            }
            .navigationTitle("Shiken")
            .overlay {
                if subjects.isEmpty {
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
            if let subject = selectedSubject {
                PlannerView(subject: subject)
            } else {
                HomeView()
            }
        }
        .sheet(isPresented: $showingNewSubject) {
            SubjectEditorSheet { newID in
                selectedSubjectID = newID
            }
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