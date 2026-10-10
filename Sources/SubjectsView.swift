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
    @State private var periodsPerWeek: Int
    @State private var isEnrichment: Bool
    @State private var dailyMinutesIsDerived: Bool
    @State private var dayModeRaw: String
    /// Timetable inputs for the other subjects, so this subject's suggestion is
    /// computed against the whole set rather than in isolation.
    @State private var peerTimetable: [SubjectPlan]
    /// The user's whole daily study budget, shown in the captions so the
    /// suggestion explains itself.
    @State private var totalDailyMinutes: Int
    /// Draft rows, so a half-typed assessment is not written to the store until Save.
    @State private var drafts: [AssessmentDraft]
    @State private var deletingDraft: Int?
    @State private var droppedNotice: String?
    @State private var newRowFocus: UUID?

    init(
        subject: Subject? = nil,
        peers: [SubjectPlan] = [],
        totalDailyMinutes: Int = Timetable.defaultTotalDailyMinutes,
        onSave: @escaping (UUID) -> Void
    ) {
        self.subject = subject
        self.onSave = onSave

        // Every timetable row, including the one being edited, so the divisor
        // stays correct no matter which subject is open.
        var timetable = peers
        if let subject {
            timetable.append(SubjectPlan(
                id: subject.id,
                periodsPerWeek: subject.periodsPerWeek,
                isEnrichment: subject.isEnrichment
            ))
        }
        let derived = Timetable.derivation(
            subjects: timetable, totalDailyMinutes: totalDailyMinutes
        )

        _peerTimetable = State(initialValue: peers)
        _totalDailyMinutes = State(initialValue: totalDailyMinutes)

        if let subject {
            _name = State(initialValue: subject.name)
            _periodsPerWeek = State(initialValue: subject.periodsPerWeek)
            _isEnrichment = State(initialValue: subject.isEnrichment)
            _dailyMinutesIsDerived = State(initialValue: subject.dailyMinutesIsDerived)
            _dayModeRaw = State(initialValue: subject.dayModeRaw)
            // A derived subject follows the timetable until the user overrides it.
            _dailyMinutes = State(initialValue: subject.dailyMinutesIsDerived
                ? derived[subject.id] ?? subject.dailyMinutes
                : subject.dailyMinutes)
            _accentHex = State(initialValue: subject.accentHex)
            _drafts = State(initialValue: subject.sortedAssessments.map {
                AssessmentDraft(id: $0.id, title: $0.title, date: $0.date)
            })
        } else {
            _name = State(initialValue: "")
            _periodsPerWeek = State(initialValue: 5)
            _isEnrichment = State(initialValue: false)
            _dailyMinutesIsDerived = State(initialValue: true)
            _dayModeRaw = State(initialValue: "time")
            _dailyMinutes = State(initialValue: Timetable.defaultTotalDailyMinutes)
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
                    Picker("Daily mode", selection: $dayModeRaw) {
                        ForEach(DayMode.allCases, id: \.rawValue) { mode in
                            Text(mode.label).tag(mode.rawValue)
                        }
                    }
                    .pickerStyle(.segmented)

                    rowCaption(
                        dayModeRaw == "tasks"
                        ? "Task checklist: daily completion is measured by ticking off each topic's task for the day. Minutes are kept only as a guide."
                        : "Time budget: daily completion is measured by focused minutes logged against your daily target."
                    )

                    Stepper(dayModeRaw == "tasks" ? "Daily guide \(dailyMinutes) min" : "Daily target \(dailyMinutes) min", value: $dailyMinutes, in: 15...240, step: 15)
                        .onChange(of: dailyMinutes) { _, _ in
                            // Any deliberate move to the stepper means the user has
                            // decided; stop re-deriving over the top of them.
                            dailyMinutesIsDerived = false
                        }

                    Picker("Lessons a week", selection: $periodsPerWeek) {
                        ForEach([1, 2, 3, 4, 5, 6, 7], id: \.self) { count in
                            Text("\(count)").tag(count)
                        }
                    }

                    rowCaption(
                        isEnrichment
                        ? "Enrichment subjects get a flat \(Timetable.enrichmentFloor)m, and don't take a share of your assessed subjects' time."
                        : "Your \(totalDailyMinutes)m of daily study is shared out between your assessed subjects in proportion to how many lessons each has."
                    )

                    Toggle("Enrichment drop", isOn: $isEnrichment)

                    rowCaption(
                        isEnrichment
                        ? "On: this is an enrichment subject such as Art, Music, Health or PE. Still examined, but needing far less revision."
                        : "Off: this subject is examined and shares out your daily study time."
                    )
                } header: {
                    Text("Daily target")
                } footer: {
                    Text(derivationNote)
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
        // Changing contact time re-derives the suggestion, but only while that
        // suggestion is still in play. An explicit daily target is not ours to move.
        .onChange(of: periodsPerWeek) { _, _ in refreshDerivedMinutes() }
        .onChange(of: isEnrichment) { _, _ in refreshDerivedMinutes() }
    }

    /// A short grey line under a control explaining what that control actually
    /// does. Labels alone ("Lessons a week", "Enrichment drop") name a setting
    /// without explaining it, and a setting nobody understands is a setting
    /// nobody trusts.
    private func rowCaption(_ text: String) -> some View {
        Text(text)
            .font(.system(size: DesignSystem.typeCaption()))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
    }

    /// Says where the number came from, in plain terms, including the working.
    /// Showing the arithmetic is what stops this looking like a black box.
    private var derivationNote: String {
        if !dailyMinutesIsDerived {
            return "You've set this one yourself, so Shiken will keep it exactly as it is. It's the total for the subject each day, not a split between assessments."
        }
        if isEnrichment {
            return "Suggested at \(dailyMinutes)m: enrichment subjects get a flat \(Timetable.enrichmentFloor)m a day. Adjust it above and Shiken will stop changing it."
        }
        return "Suggested at \(dailyMinutes)m from \(periodsPerWeek) of your \(assessedPeriods) assessed lessons. Adjust it above and Shiken will stop changing it."
    }

    private var assessedPeriods: Int {
        var all = peerTimetable.filter { !$0.isEnrichment }
        all.append(SubjectPlan(id: subject?.id ?? UUID(), periodsPerWeek: periodsPerWeek, isEnrichment: isEnrichment))
        return all.filter { !$0.isEnrichment }.reduce(0) { $0 + $1.periodsPerWeek }
    }

    private func refreshDerivedMinutes() {
        guard dailyMinutesIsDerived, let id = subject?.id else { return }
        var all = peerTimetable
        all.append(SubjectPlan(id: id, periodsPerWeek: periodsPerWeek, isEnrichment: isEnrichment))
        if let suggested = Timetable.derivation(subjects: all)[id] {
            dailyMinutes = suggested
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
            subject.periodsPerWeek = periodsPerWeek
            subject.isEnrichment = isEnrichment
            subject.dailyMinutesIsDerived = dailyMinutesIsDerived
            subject.dayModeRaw = dayModeRaw
            target = subject
        } else {
            let position = (try? ctx.fetchCount(FetchDescriptor<Subject>())) ?? 0
            let created = Subject(name: trimmed, accentHex: accentHex, position: position)
            created.dailyMinutes = dailyMinutes
            created.periodsPerWeek = periodsPerWeek
            created.isEnrichment = isEnrichment
            created.dailyMinutesIsDerived = dailyMinutesIsDerived
            created.dayModeRaw = dayModeRaw
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