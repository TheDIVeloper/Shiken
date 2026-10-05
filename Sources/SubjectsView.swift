import SwiftUI
import SwiftData

struct SubjectRow: View {
    let subject: Subject

    var body: some View {
        HStack(spacing: DesignSystem.spaceM()) {
            Circle()
                .fill(subject.isFinished ? Color.secondary.opacity(0.35) : DesignSystem.hexColor(subject.accentHex))
                .frame(width: 8, height: 8)

            VStack(alignment: .leading, spacing: 2) {
                Text(subject.name)
                    .font(.system(size: DesignSystem.typeBody(), weight: .medium))
                    .foregroundStyle(subject.isFinished ? .secondary : .primary)

                if subject.assessmentRefs.isEmpty {
                    Text("no assessments")
                        .font(.system(size: DesignSystem.typeCaption()))
                        .foregroundStyle(.tertiary)
                } else if let next = subject.nextAssessment {
                    Text("\(next.title) · \(countdown(next.date))")
                        .font(.system(size: DesignSystem.typeCaption()))
                        .foregroundStyle(subject.isFinished ? .tertiary : .secondary)
                } else {
                    // Finished subjects keep their place and their history. They
                    // leave the Plan view because there is nothing left to revise
                    // for, but nothing is deleted.
                    Label("done", systemImage: "checkmark")
                        .font(.system(size: DesignSystem.typeCaption()))
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 2)
    }

    private func countdown(_ date: Date) -> String {
        let cal = Calendar.current
        let days = cal.dateComponents([.day], from: cal.startOfDay(for: .now), to: cal.startOfDay(for: date)).day ?? 0
        if days == 0 { return "today" }
        if days == 1 { return "tomorrow" }
        return "\(days)d"
    }
}

struct SubjectEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var ctx
    var subject: Subject?
    var onSave: (UUID) -> Void

    @State private var name: String
    @State private var dailyMinutes: Int
    @State private var accentHex: String
    /// Draft rows, so a half-typed assessment is not written to the store until Save.
    @State private var drafts: [AssessmentDraft]
    @State private var deletingDraft: Int?
    @State private var droppedNotice: String?
    @State private var newRowFocus: UUID?

    init(subject: Subject? = nil, onSave: @escaping (UUID) -> Void) {
        self.subject = subject
        self.onSave = onSave
        if let subject {
            _name = State(initialValue: subject.name)
            _dailyMinutes = State(initialValue: subject.dailyMinutes)
            _accentHex = State(initialValue: subject.accentHex)
            _drafts = State(initialValue: subject.sortedAssessments.map {
                AssessmentDraft(id: $0.id, title: $0.title, date: $0.date)
            })
        } else {
            _name = State(initialValue: "")
            _dailyMinutes = State(initialValue: max(15, UserDefaults.standard.integer(forKey: "defaultDailyMinutes")))
            _accentHex = State(initialValue: DesignSystem.subjectAccent())
            _drafts = State(initialValue: [
                AssessmentDraft(
                    title: "Exam",
                    date: Calendar.current.date(byAdding: .day, value: 60, to: .now) ?? .now,
                    isNew: true
                )
            ])
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    TextField("Subject name", text: $name)
                }
                Section {
                    Stepper("Daily target \(dailyMinutes) min", value: $dailyMinutes, in: 15...240, step: 15)
                } footer: {
                    Text("One figure for the whole subject, kept across every assessment. Assessments are deadlines, not slices of your day.")
                }

                assessmentsSection

                Section("Accent") {
                    HStack(spacing: DesignSystem.spaceM()) {
                        ForEach(DesignSystem.accentPalette, id: \.self) { hex in
                            Button {
                                accentHex = hex
                            } label: {
                                ZStack {
                                    Circle()
                                        .fill(DesignSystem.hexColor(hex))
                                        .frame(width: 22, height: 22)
                                    if accentHex == hex {
                                        Image(systemName: "checkmark")
                                            .font(.system(size: 11, weight: .bold))
                                            .foregroundStyle(.white)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                        }
                        Spacer()
                    }
                }
            }
            .formStyle(.grouped)

            HStack(spacing: DesignSystem.spaceS()) {
                if let droppedNotice {
                    Text(droppedNotice)
                        .font(.system(size: DesignSystem.typeCaption()))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(subject == nil ? "Add subject" : "Save") { save() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding()
        }
        .frame(width: 460)
        .confirmationDialog(
            deletingDraft.map { drafts[$0].resolvedTitle } ?? "this assessment",
            isPresented: Binding(
                get: { deletingDraft != nil },
                set: { if !$0 { deletingDraft = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Remove", role: .destructive) {
                if let index = deletingDraft { drafts.remove(at: index) }
                deletingDraft = nil
            }
            Button("Cancel", role: .cancel) { deletingDraft = nil }
        } message: {
            Text("It will be removed from Shiken.")
        }
    }

    // MARK: Assessments

    private var assessmentsSection: some View {
        Section {
            // Labeled rows rather than bare controls: a bare TextField in a Form
            // gives no visible edge, so the only cue that you can type is the
            // caret — which is not discoverable.
            ForEach(drafts.indices, id: \.self) { index in
                VStack(alignment: .leading, spacing: DesignSystem.spaceXS()) {
                    TextField("Assessment name", text: $drafts[index].title)
                        .textFieldStyle(.roundedBorder)
                        .id(newRowFocus == drafts[index].id ? drafts[index].id : nil)

                    HStack(spacing: DesignSystem.spaceS()) {
                        DatePicker(
                            "Date",
                            selection: $drafts[index].date,
                            displayedComponents: .date
                        )
                        .labelsHidden()
                        .accessibilityLabel("Assessment date")

                        Text(drafts[index].date.formatted(date: .abbreviated, time: .omitted))
                            .font(.system(size: DesignSystem.typeCaption()))
                            .foregroundStyle(.secondary)

                        Spacer()

                        Button(role: .destructive) {
                            deletingDraft = index
                        } label: {
                            Label("Remove", systemImage: "trash")
                                .labelStyle(.iconOnly)
                                .font(.system(size: DesignSystem.typeBody()))
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.tertiary)
                        .help("Remove this assessment")
                    }
                }
                .padding(.vertical, DesignSystem.spaceXS())
            }

            Button {
                addDraft()
            } label: {
                Label("Add assessment", systemImage: "plus.circle")
                    .font(.system(size: DesignSystem.typeBody(), weight: .medium))
            }
            .buttonStyle(.plain)
            .padding(.vertical, DesignSystem.spaceXS())
        } header: {
            Text("Assessments")
        } footer: {
            Text("The next one still ahead drives the plan; it becomes the target once the one before it passes. Later ones are shown but do not change the plan yet.")
        }
    }

    private func addDraft() {
        // Default the date to after everything already in the list, so a new
        // assessment is never accidentally the next one due.
        let latest = drafts.map(\.date).max() ?? Date()
        let proposed = max(
            latest,
            Calendar.current.date(byAdding: .day, value: 30, to: .now) ?? .now
        )
        let draft = AssessmentDraft(title: "", date: proposed, isNew: true)
        drafts.append(draft)
        newRowFocus = draft.id
    }

    // MARK: Save

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }

        let target: Subject
        if let subject {
            subject.name = trimmed
            subject.dailyMinutes = dailyMinutes
            subject.accentHex = accentHex
            target = subject
        } else {
            let position = (try? ctx.fetchCount(FetchDescriptor<Subject>())) ?? 0
            let created = Subject(name: trimmed, accentHex: accentHex, position: position)
            created.dailyMinutes = dailyMinutes
            ctx.insert(created)
            target = created
        }

        let result = AssessmentSync.apply(drafts, to: target, in: ctx)
        try? ctx.save()

        // Confirm rather than trust: if nothing was stored the user must not be
        // left believing their assessments saved.
        if result.saved == 0 {
            droppedNotice = "No assessment had a name, so nothing was saved."
            return
        }

        onSave(target.id)
        dismiss()
    }
}