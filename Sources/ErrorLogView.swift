import SwiftUI
import SwiftData

struct ErrorLogView: View {
    @Environment(\.modelContext) private var ctx
    @Query(sort: \RevisionError.createdAt, order: .reverse) private var errors: [RevisionError]
    @Query(sort: \Subject.position) private var subjects: [Subject]

    @State private var filterStatus: ErrorFilterStatus = .all
    @State private var selectedSubjectID: UUID? = nil
    @State private var selectedCategory: ErrorCategory? = nil
    @State private var showingAddSheet = false

    private var errorRecords: [ErrorRecord] {
        errors.compactMap { error in
            guard let subject = error.subject else { return nil }
            let topicTitle = error.topicID.flatMap { tid in
                subject.topics.first(where: { $0.id == tid })?.title
            }
            return ErrorRecord(
                id: error.id,
                subjectID: subject.id,
                subjectName: subject.name,
                subjectAccentHex: subject.accentHex,
                topicID: error.topicID,
                topicTitle: topicTitle,
                category: error.category,
                errorDescription: error.errorDescription,
                date: error.date,
                stage: error.stage,
                lastReviewedAt: error.lastReviewedAt,
                nextReviewDate: error.nextReviewDate,
                isResolved: error.isResolved
            )
        }
    }

    private var summary: ErrorSummary {
        ErrorLogEngine.summary(errors: errorRecords)
    }

    private var filteredRecords: [ErrorRecord] {
        ErrorLogEngine.filter(
            errors: errorRecords,
            filter: ErrorFilter(
                subjectID: selectedSubjectID,
                topicID: nil,
                category: selectedCategory,
                status: filterStatus
            )
        )
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DesignSystem.spaceXL()) {
                header
                statsSection
                filterBar

                if filteredRecords.isEmpty {
                    emptyState
                } else {
                    cardsList
                }
            }
            .padding(DesignSystem.spaceXL())
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle("Error Log")
        .sheet(isPresented: $showingAddSheet) {
            LogErrorSheet(subjects: subjects)
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: DesignSystem.spaceXS()) {
                Text("Error Log")
                    .font(.system(size: DesignSystem.typeDisplay(), weight: .semibold))
                Text("Track revision slips, content gaps, and strategies until they are resolved.")
                    .font(.system(size: DesignSystem.typeBody()))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                showingAddSheet = true
            } label: {
                Label("Log error", systemImage: "plus")
                    .font(.system(size: DesignSystem.typeBody(), weight: .medium))
            }
            .buttonStyle(.borderedProminent)
            .tint(Color.accentColor)
        }
    }

    // MARK: Stats

    private var statsSection: some View {
        HStack(spacing: DesignSystem.spaceM()) {
            statCard(
                title: "Due today",
                value: "\(summary.dueToday)",
                highlightColor: summary.dueToday > 0 ? Color.orange : Color.secondary
            )
            statCard(
                title: "Active",
                value: "\(summary.active)",
                highlightColor: Color.primary
            )
            statCard(
                title: "Resolved",
                value: "\(summary.resolved)",
                highlightColor: Color.green
            )
            statCard(
                title: "Total logged",
                value: "\(summary.total)",
                highlightColor: Color.secondary
            )
        }
    }

    private func statCard(title: String, value: String, highlightColor: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value)
                .font(.system(size: DesignSystem.typeDisplay(), weight: .semibold, design: .monospaced))
                .foregroundStyle(highlightColor)
            Text(title)
                .font(.system(size: DesignSystem.typeCaption()))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(DesignSystem.spaceM())
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.radiusCard(), style: .continuous)
                .fill(DesignSystem.panelFill())
        )
    }

    // MARK: Filters

    private var filterBar: some View {
        HStack(spacing: DesignSystem.spaceM()) {
            Picker("Status", selection: $filterStatus) {
                ForEach(ErrorFilterStatus.allCases) { status in
                    Text(status.label).tag(status)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(maxWidth: 320)

            Menu {
                Button("All subjects") {
                    selectedSubjectID = nil
                }
                ForEach(subjects) { subj in
                    Button(subj.name) {
                        selectedSubjectID = subj.id
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Text(selectedSubjectName)
                        .font(.system(size: DesignSystem.typeCaption()))
                    Image(systemName: "chevron.down")
                        .font(.system(size: 8))
                }
                .padding(.horizontal, DesignSystem.spaceS())
                .padding(.vertical, DesignSystem.spaceXS())
                .background(
                    RoundedRectangle(cornerRadius: DesignSystem.radiusS(), style: .continuous)
                        .fill(DesignSystem.panelFill())
                )
            }
            .buttonStyle(.plain)

            Menu {
                Button("All categories") {
                    selectedCategory = nil
                }
                ForEach(ErrorCategory.allCases, id: \.self) { cat in
                    Button(cat.label) {
                        selectedCategory = cat
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Text(selectedCategory?.label ?? "All categories")
                        .font(.system(size: DesignSystem.typeCaption()))
                    Image(systemName: "chevron.down")
                        .font(.system(size: 8))
                }
                .padding(.horizontal, DesignSystem.spaceS())
                .padding(.vertical, DesignSystem.spaceXS())
                .background(
                    RoundedRectangle(cornerRadius: DesignSystem.radiusS(), style: .continuous)
                        .fill(DesignSystem.panelFill())
                )
            }
            .buttonStyle(.plain)

            Spacer()
        }
    }

    private var selectedSubjectName: String {
        if let id = selectedSubjectID, let subj = subjects.first(where: { $0.id == id }) {
            return subj.name
        }
        return "All subjects"
    }

    // MARK: Empty State

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: DesignSystem.spaceXS()) {
            Text(errors.isEmpty ? "No errors logged yet." : "No errors matching this filter.")
                .font(.system(size: DesignSystem.typeTitle(), weight: .semibold))
            Text(errors.isEmpty
                ? "Record revision mistakes to revisit them at spaced intervals until they are resolved."
                : "Try adjusting the status, subject, or category filter to view other errors.")
                .font(.system(size: DesignSystem.typeBody()))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(DesignSystem.spaceL())
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.radiusCard(), style: .continuous)
                .fill(DesignSystem.panelFill())
        )
    }

    // MARK: Cards List

    private var cardsList: some View {
        VStack(spacing: DesignSystem.spaceS()) {
            ForEach(filteredRecords) { record in
                if let model = errors.first(where: { $0.id == record.id }) {
                    errorCard(record: record, model: model)
                }
            }
        }
    }

    private func errorCard(record: ErrorRecord, model: RevisionError) -> some View {
        let isDue = ErrorLogEngine.isDue(
            nextReviewDate: record.nextReviewDate,
            isResolved: record.isResolved
        )

        return VStack(alignment: .leading, spacing: DesignSystem.spaceS()) {
            HStack(spacing: DesignSystem.spaceS()) {
                Circle()
                    .fill(DesignSystem.hexColor(record.subjectAccentHex))
                    .frame(width: 8, height: 8)

                Text(record.subjectName)
                    .font(.system(size: DesignSystem.typeCaption(), weight: .semibold))

                if let topicTitle = record.topicTitle {
                    Text("· \(topicTitle)")
                        .font(.system(size: DesignSystem.typeCaption()))
                        .foregroundStyle(.secondary)
                }

                categoryPill(record.category)

                Spacer()

                stagePill(record: record, isDue: isDue)
            }

            Text(record.errorDescription)
                .font(.system(size: DesignSystem.typeBody()))
                .foregroundStyle(record.isResolved ? .secondary : .primary)
                .strikethrough(record.isResolved, color: .secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: DesignSystem.spaceM()) {
                Text("Logged \(record.date.formatted(date: .abbreviated, time: .omitted))")
                    .font(.system(size: DesignSystem.typeCaption()))
                    .foregroundStyle(.tertiary)

                if let reviewed = record.lastReviewedAt {
                    Text("Last reviewed \(reviewed.formatted(date: .abbreviated, time: .omitted))")
                        .font(.system(size: DesignSystem.typeCaption()))
                        .foregroundStyle(.tertiary)
                }

                Spacer()

                cardActionButtons(record: record, model: model)
            }
        }
        .padding(DesignSystem.spaceM())
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.radiusCard(), style: .continuous)
                .fill(DesignSystem.panelFill())
        )
    }

    private func categoryPill(_ category: ErrorCategory) -> some View {
        Text(category.label)
            .font(.system(size: DesignSystem.typeCaption(), weight: .medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(Color.secondary.opacity(0.12)))
    }

    private func stagePill(record: ErrorRecord, isDue: Bool) -> some View {
        if record.isResolved {
            return AnyView(
                Text("Resolved")
                    .font(.system(size: DesignSystem.typeCaption(), weight: .semibold))
                    .foregroundStyle(.green)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.green.opacity(0.12)))
            )
        }

        if isDue {
            return AnyView(
                Text("Due today")
                    .font(.system(size: DesignSystem.typeCaption(), weight: .semibold))
                    .foregroundStyle(.orange)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.orange.opacity(0.12)))
            )
        }

        let label = ErrorLogEngine.stageLabel(stage: record.stage, isResolved: false)
        return AnyView(
            Text(label)
                .font(.system(size: DesignSystem.typeCaption()))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
                .background(Capsule().fill(Color.secondary.opacity(0.08)))
        )
    }

    private func cardActionButtons(record: ErrorRecord, model: RevisionError) -> some View {
        HStack(spacing: DesignSystem.spaceS()) {
            if !record.isResolved {
                Button {
                    reviewPass(model: model, passed: false)
                } label: {
                    Text("Still rusty")
                        .font(.system(size: DesignSystem.typeCaption(), weight: .medium))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.orange)
                .help("Reset interval to 1 day for prompt retesting")

                Button {
                    reviewPass(model: model, passed: true)
                } label: {
                    Text("Solid")
                        .font(.system(size: DesignSystem.typeCaption(), weight: .medium))
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.accentColor)
                .help("Advance to next review stage")

                Button {
                    resolveDirectly(model: model)
                } label: {
                    Text("Resolve")
                        .font(.system(size: DesignSystem.typeCaption(), weight: .medium))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.green)
            } else {
                Button {
                    reopen(model: model)
                } label: {
                    Text("Reopen")
                        .font(.system(size: DesignSystem.typeCaption(), weight: .medium))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }

            Button {
                ctx.delete(model)
                try? ctx.save()
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: DesignSystem.typeCaption()))
                    .foregroundStyle(.tertiary)
            }
            .buttonStyle(.plain)
            .help("Delete error")
        }
    }

    // MARK: Review Actions

    private func reviewPass(model: RevisionError, passed: Bool) {
        let result = ErrorLogEngine.recordReview(
            currentStage: model.stage,
            passed: passed,
            reviewedAt: .now
        )
        model.stage = result.nextStage
        model.nextReviewDate = result.nextReviewDate
        model.isResolved = result.isResolved
        model.lastReviewedAt = .now
        try? ctx.save()
    }

    private func resolveDirectly(model: RevisionError) {
        model.isResolved = true
        model.lastReviewedAt = .now
        try? ctx.save()
    }

    private func reopen(model: RevisionError) {
        model.isResolved = false
        model.stage = 0
        model.nextReviewDate = .now
        try? ctx.save()
    }
}

// MARK: Log Error Sheet

struct LogErrorSheet: View {
    let subjects: [Subject]
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var ctx

    @State private var selectedSubjectID: UUID?
    @State private var selectedTopicID: UUID?
    @State private var category: ErrorCategory = .carelessSlip
    @State private var errorDescription: String = ""
    @State private var date: Date = .now

    private var currentSubject: Subject? {
        if let id = selectedSubjectID {
            return subjects.first(where: { $0.id == id })
        }
        return subjects.first
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Subject", selection: Binding(
                        get: { currentSubject?.id ?? UUID() },
                        set: {
                            selectedSubjectID = $0
                            selectedTopicID = nil
                        }
                    )) {
                        ForEach(subjects) { subj in
                            Text(subj.name).tag(subj.id)
                        }
                    }

                    if let subject = currentSubject, !subject.topics.isEmpty {
                        Picker("Topic (optional)", selection: $selectedTopicID) {
                            Text("Whole subject").tag(nil as UUID?)
                            ForEach(subject.topics.sorted { $0.position < $1.position }) { topic in
                                Text(topic.title).tag(topic.id as UUID?)
                            }
                        }
                    }

                    Picker("Category", selection: $category) {
                        ForEach(ErrorCategory.allCases, id: \.self) { cat in
                            Text(cat.label).tag(cat)
                        }
                    }

                    DatePicker("Date occurred", selection: $date, displayedComponents: .date)
                }

                Section("Description") {
                    TextField("What was the mistake?", text: $errorDescription, axis: .vertical)
                        .lineLimit(3...6)
                }
            }
            .navigationTitle("Log Revision Error")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        save()
                    }
                    .disabled(errorDescription.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || currentSubject == nil)
                }
            }
        }
        .frame(minWidth: 420, minHeight: 340)
    }

    private func save() {
        guard let subject = currentSubject else { return }
        let trimmed = errorDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let initialDue = ErrorLogEngine.initialNextReviewDate(from: date)
        let error = RevisionError(
            date: date,
            categoryRaw: category.rawValue,
            errorDescription: trimmed,
            stage: 0,
            lastReviewedAt: nil,
            nextReviewDate: initialDue,
            isResolved: false,
            topicID: selectedTopicID,
            subject: subject
        )
        ctx.insert(error)
        try? ctx.save()
        dismiss()
    }
}
