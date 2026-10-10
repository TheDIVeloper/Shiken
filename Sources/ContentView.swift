import SwiftUI
import SwiftData

enum SidebarSelection: Hashable {
    case plan
    case focus
    case sessions
    case review
    case errorLog
    case settings
    case subject(UUID)
}

struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.modelContext) private var ctx
    @Query(sort: \Subject.position) private var subjects: [Subject]
    @AppStorage("trackInterruptions") private var trackInterruptions = true
    @AppStorage("totalDailyMinutes") private var totalDailyMinutes = Timetable.defaultTotalDailyMinutes
    @State private var selection: SidebarSelection?
    @State private var showingEditor = false
    @State private var editingSubject: Subject?
    @State private var deletingSubject: Subject?
    @State private var focusTimer = FocusTimer()
    @State private var undo = ActionUndo()

    /// Every other subject's timetable inputs, so a subject editor can compute
    /// its suggestion against the whole set.
    private var timetablePeers: [SubjectPlan] {
        subjects.map {
            SubjectPlan(id: $0.id, periodsPerWeek: $0.periodsPerWeek, isEnrichment: $0.isEnrichment)
        }
    }

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                Section("Study") {
                    Label("Plan", systemImage: "calendar")
                        .tag(SidebarSelection.plan)
                    Label("Focus", systemImage: "timer")
                        .tag(SidebarSelection.focus)
                    Label("Sessions", systemImage: "list.bullet.rectangle.portrait")
                        .tag(SidebarSelection.sessions)
                    Label("Review", systemImage: "chart.bar.xaxis")
                        .tag(SidebarSelection.review)
                    Label("Error Log", systemImage: "exclamationmark.bubble")
                        .tag(SidebarSelection.errorLog)
                }

                Section("Subjects") {
                    if subjects.isEmpty {
                        // A quiet in-section prompt, not a whole-window state: Plan,
                        // Focus, Sessions and Review still work without a subject.
                        emptySubjectsHint
                    } else {
                        ForEach(activeSubjects) { subject in
                            subjectRow(subject)
                        }
                        if !finishedSubjects.isEmpty {
                            Divider()
                            ForEach(finishedSubjects) { subject in
                                subjectRow(subject)
                            }
                        }
                    }
                }

                Section("Shiken") {
                    Label("Settings", systemImage: "gear")
                        .tag(SidebarSelection.settings)
                }
            }
            .navigationTitle("Shiken")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        editingSubject = nil
                        showingEditor = true
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
        .overlay(alignment: .bottom) { undoBanner }
        .sheet(isPresented: $showingEditor) {
            SubjectEditorSheet(
                subject: editingSubject,
                peers: timetablePeers,
                totalDailyMinutes: totalDailyMinutes
            ) { newID in
                selection = .subject(newID)
            }
        }
        .confirmationDialog(
            "Delete \"\(deletingSubject?.name ?? "")?\"",
            isPresented: Binding(
                get: { deletingSubject != nil },
                set: { if !$0 { deletingSubject = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) { deleteSubject() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Topics, plans, assessments, and sessions for this subject will be permanently removed.")
        }
        .onChange(of: scenePhase) { _, phase in
            if trackInterruptions {
                if phase == .active {
                    focusTimer.awayEnd()
                } else {
                    focusTimer.awayBegin()
                }
            } else {
                focusTimer.awayEnd()
            }
        }
    }

    /// Subjects with something still to revise for, in the user's order.
    private var activeSubjects: [Subject] {
        subjects.filter { !$0.isFinished }
    }

    /// Everything with all assessments behind it. Kept in the sidebar, below the
    /// active ones, so the history stays reachable without cluttering the plan.
    private var finishedSubjects: [Subject] {
        subjects.filter(\.isFinished)
    }

    /// One caption line in the Subjects section, styled like everything else in
    /// the app rather than as a modal empty state.
    private var emptySubjectsHint: some View {
        Text("No subjects. Add one with its first assessment.")
            .font(.system(size: DesignSystem.typeCaption()))
            .foregroundStyle(.tertiary)
            .padding(.vertical, 2)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func subjectRow(_ subject: Subject) -> some View {
        SubjectRow(subject: subject)
            .tag(SidebarSelection.subject(subject.id))
            .contextMenu {
                Button {
                    editingSubject = subject
                    showingEditor = true
                } label: {
                    Label("Edit…", systemImage: "pencil")
                }
                Button(role: .destructive) {
                    deletingSubject = subject
                } label: {
                    Label("Delete…", systemImage: "trash")
                }
            }
    }

    @ViewBuilder
    private var detail: some View {
        switch selection {
        case .plan:
            PlanOverviewView()
        case .focus:
            FocusView()
        case .sessions:
            SessionLogView()
        case .review:
            ReviewView()
        case .errorLog:
            ErrorLogView()
        case .settings:
            SettingsView()
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

    private func deleteSubject() {
        guard let subject = deletingSubject else { return }
        if case .subject(let id) = selection, id == subject.id {
            selection = nil
        }

        let snapshot = Undoable.snapshot(subject)
        let wasSelected = selection
        undo.record(
            label: "Deleted \(subject.name)",
            perform: {
                ctx.delete(subject)
                try? ctx.save()
            },
            revert: {
                Undoable.restore(snapshot, in: ctx)
                selection = wasSelected
            }
        )
        deletingSubject = nil
    }

    // MARK: Undo

    /// Reversible confirmation. The banner is the only place in the app that
    /// mentions a deletion afterwards, and it disappears on its own: an undo
    /// offer that needs managing is just another notification.
    @ViewBuilder
    private var undoBanner: some View {
        if let message = undo.message {
            HStack(spacing: DesignSystem.spaceM()) {
                Text(message)
                    .font(.system(size: DesignSystem.typeCaption()))
                    .foregroundStyle(.secondary)
                Spacer()
                if undo.pending != nil {
                    Button("Undo") { undo.undo() }
                        .font(.system(size: DesignSystem.typeCaption(), weight: .semibold))
                }
            }
            .padding(.horizontal, DesignSystem.spaceL())
            .padding(.vertical, DesignSystem.spaceM())
            .background(
                RoundedRectangle(cornerRadius: DesignSystem.radiusCard(), style: .continuous)
                    .fill(DesignSystem.panelFill())
            )
            .padding(DesignSystem.spaceL())
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