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
                listSubheader

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

    // MARK: Stats and Status Filtering

    private var statsSection: some View {
        HStack(spacing: DesignSystem.spaceM()) {
            filterCard(
                status: .all,
                title: "All",
                value: summary.total,
                highlightColor: Color.secondary,
                icon: "tray.full"
            )
            filterCard(
                status: .due,
                title: "Due today",
                value: summary.dueToday,
                highlightColor: summary.dueToday > 0 ? Color.orange : Color.secondary,
                icon: "clock.badge.exclamationmark"
            )
            filterCard(
                status: .active,
                title: "Active",
                value: summary.active,
                highlightColor: Color.primary,
                icon: "arrow.triangle.2.circlepath"
            )
            filterCard(
                status: .resolved,
                title: "Resolved",
                value: summary.resolved,
                highlightColor: Color.green,
                icon: "checkmark.circle"
            )
        }
    }

    private func filterCard(
        status: ErrorFilterStatus,
        title: String,
        value: Int,
        highlightColor: Color,
        icon: String
    ) -> some View {
        let isSelected = filterStatus == status
        return Button {
            filterStatus = status
        } label: {
            VStack(alignment: .leading, spacing: DesignSystem.spaceS()) {
                HStack {
                    Image(systemName: icon)
                        .font(.system(size: DesignSystem.typeBody()))
                        .foregroundStyle(isSelected ? Color.accentColor : highlightColor)
                    Spacer()
                    if isSelected {
                        Circle()
                            .fill(Color.accentColor)
                            .frame(width: 6, height: 6)
                    }
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(value)")
                        .font(.system(size: DesignSystem.typeDisplay(), weight: .semibold, design: .monospaced))
                        .foregroundStyle(isSelected ? Color.accentColor : highlightColor)
                    Text(title)
                        .font(.system(size: DesignSystem.typeCaption(), weight: isSelected ? .semibold : .regular))
                        .foregroundStyle(isSelected ? .primary : .secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(DesignSystem.spaceM())
            .background(
                RoundedRectangle(cornerRadius: DesignSystem.radiusCard(), style: .continuous)
                    .fill(isSelected ? Color.accentColor.opacity(0.08) : DesignSystem.panelFill())
            )
            .overlay(
                RoundedRectangle(cornerRadius: DesignSystem.radiusCard(), style: .continuous)
                    .stroke(isSelected ? Color.accentColor : Color.secondary.opacity(0.12), lineWidth: isSelected ? 1.5 : 1)
            )
        }
        .buttonStyle(.plain)
        .contentShape(RoundedRectangle(cornerRadius: DesignSystem.radiusCard(), style: .continuous))
    }

    // MARK: List Subheader and Filters

    private var listSubheader: some View {
        HStack(alignment: .center) {
            HStack(spacing: DesignSystem.spaceS()) {
                Text(filterHeading)
                    .font(.system(size: DesignSystem.typeTitle(), weight: .semibold))
                Text("\(filteredRecords.count)")
                    .font(.system(size: DesignSystem.typeCaption(), weight: .bold))
                    .foregroundStyle(Color.accentColor)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.accentColor.opacity(0.12)))
            }

            Spacer()

            HStack(spacing: DesignSystem.spaceS()) {
                subjectMenu
                categoryMenu

                if selectedSubjectID != nil || selectedCategory != nil {
                    Button {
                        selectedSubjectID = nil
                        selectedCategory = nil
                    } label: {
                        Text("Reset")
                            .font(.system(size: DesignSystem.typeCaption(), weight: .medium))
                            .foregroundStyle(Color.accentColor)
                    }
                    .buttonStyle(.plain)
                    .padding(.leading, 4)
                }
            }
        }
    }

    private var filterHeading: String {
        switch filterStatus {
        case .all: return "All errors"
        case .due: return "Due for review today"
        case .active: return "Active errors"
        case .resolved: return "Resolved errors"
        }
    }

    private var subjectMenu: some View {
        Menu {
            Button("All subjects") {
                selectedSubjectID = nil
            }
            Divider()
            ForEach(subjects) { subj in
                Button(subj.name) {
                    selectedSubjectID = subj.id
                }
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "book.closed")
                    .font(.system(size: DesignSystem.typeCaption()))
                    .foregroundStyle(selectedSubjectID != nil ? Color.accentColor : Color.secondary)
                Text(selectedSubjectName)
                    .font(.system(size: DesignSystem.typeCaption(), weight: .medium))
                    .foregroundStyle(selectedSubjectID != nil ? Color.accentColor : Color.primary)
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(selectedSubjectID != nil ? Color.accentColor.opacity(0.7) : Color.secondary.opacity(0.5))
            }
            .padding(.horizontal, DesignSystem.spaceM())
            .padding(.vertical, DesignSystem.spaceXS())
            .background(
                RoundedRectangle(cornerRadius: DesignSystem.radiusS(), style: .continuous)
                    .fill(selectedSubjectID != nil ? Color.accentColor.opacity(0.08) : DesignSystem.panelFill())
            )
            .overlay(
                RoundedRectangle(cornerRadius: DesignSystem.radiusS(), style: .continuous)
                    .stroke(selectedSubjectID != nil ? Color.accentColor.opacity(0.4) : Color.secondary.opacity(0.15), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private var categoryMenu: some View {
        Menu {
            Button("All categories") {
                selectedCategory = nil
            }
            Divider()
            ForEach(ErrorCategory.allCases, id: \.self) { cat in
                Button(cat.label) {
                    selectedCategory = cat
                }
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "tag")
                    .font(.system(size: DesignSystem.typeCaption()))
                    .foregroundStyle(selectedCategory != nil ? Color.accentColor : Color.secondary)
                Text(selectedCategory?.label ?? "All categories")
                    .font(.system(size: DesignSystem.typeCaption(), weight: .medium))
                    .foregroundStyle(selectedCategory != nil ? Color.accentColor : Color.primary)
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(selectedCategory != nil ? Color.accentColor.opacity(0.7) : Color.secondary.opacity(0.5))
            }
            .padding(.horizontal, DesignSystem.spaceM())
            .padding(.vertical, DesignSystem.spaceXS())
            .background(
                RoundedRectangle(cornerRadius: DesignSystem.radiusS(), style: .continuous)
                    .fill(selectedCategory != nil ? Color.accentColor.opacity(0.08) : DesignSystem.panelFill())
            )
            .overlay(
                RoundedRectangle(cornerRadius: DesignSystem.radiusS(), style: .continuous)
                    .stroke(selectedCategory != nil ? Color.accentColor.opacity(0.4) : Color.secondary.opacity(0.15), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
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
            ScrollView {
                VStack(alignment: .leading, spacing: DesignSystem.spaceL()) {
                    VStack(alignment: .leading, spacing: DesignSystem.spaceXS()) {
                        Text("Log Revision Error")
                            .font(.system(size: DesignSystem.typeTitle(), weight: .semibold))
                        Text("Record a mistake made while revising to revisit it at spaced intervals until resolved.")
                            .font(.system(size: DesignSystem.typeCaption()))
                            .foregroundStyle(.secondary)
                    }

                    VStack(alignment: .leading, spacing: DesignSystem.spaceXS()) {
                        Text("Subject and Topic")
                            .font(.system(size: DesignSystem.typeCaption(), weight: .semibold))
                            .foregroundStyle(.secondary)

                        HStack(spacing: DesignSystem.spaceM()) {
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
                            .frame(maxWidth: .infinity, alignment: .leading)

                            if let subject = currentSubject, !subject.topics.isEmpty {
                                Picker("Topic", selection: $selectedTopicID) {
                                    Text("Whole subject").tag(nil as UUID?)
                                    ForEach(subject.topics.sorted { $0.position < $1.position }) { topic in
                                        Text(topic.title).tag(topic.id as UUID?)
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }
                    .padding(DesignSystem.spaceM())
                    .background(
                        RoundedRectangle(cornerRadius: DesignSystem.radiusCard(), style: .continuous)
                            .fill(DesignSystem.panelFill())
                    )

                    VStack(alignment: .leading, spacing: DesignSystem.spaceS()) {
                        Text("Mistake Category")
                            .font(.system(size: DesignSystem.typeCaption(), weight: .semibold))
                            .foregroundStyle(.secondary)

                        LazyVGrid(columns: [
                            GridItem(.flexible(), spacing: DesignSystem.spaceS()),
                            GridItem(.flexible(), spacing: DesignSystem.spaceS())
                        ], spacing: DesignSystem.spaceS()) {
                            ForEach(ErrorCategory.allCases, id: \.self) { cat in
                                let isSelected = category == cat
                                Button {
                                    category = cat
                                } label: {
                                    HStack(spacing: 8) {
                                        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                                            .font(.system(size: DesignSystem.typeBody()))
                                            .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                                        Text(cat.label)
                                            .font(.system(size: DesignSystem.typeCaption(), weight: isSelected ? .semibold : .medium))
                                            .foregroundStyle(isSelected ? Color.primary : Color.secondary)
                                        Spacer(minLength: 0)
                                    }
                                    .padding(.horizontal, DesignSystem.spaceM())
                                    .padding(.vertical, DesignSystem.spaceS())
                                    .background(
                                        RoundedRectangle(cornerRadius: DesignSystem.radiusS(), style: .continuous)
                                            .fill(isSelected ? Color.accentColor.opacity(0.12) : DesignSystem.panelFill())
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: DesignSystem.radiusS(), style: .continuous)
                                            .stroke(isSelected ? Color.accentColor : Color.secondary.opacity(0.15), lineWidth: 1)
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: DesignSystem.spaceXS()) {
                        Text("What was the mistake?")
                            .font(.system(size: DesignSystem.typeCaption(), weight: .semibold))
                            .foregroundStyle(.secondary)

                        TextField(
                            "Describe what slipped and what the correct rule, formula, or strategy should be...",
                            text: $errorDescription,
                            axis: .vertical
                        )
                        .textFieldStyle(.plain)
                        .lineLimit(4...8)
                        .padding(DesignSystem.spaceM())
                        .background(
                            RoundedRectangle(cornerRadius: DesignSystem.radiusCard(), style: .continuous)
                                .fill(DesignSystem.panelFill())
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: DesignSystem.radiusCard(), style: .continuous)
                                .stroke(Color.secondary.opacity(0.18), lineWidth: 1)
                        )
                    }

                    HStack {
                        Text("Date occurred")
                            .font(.system(size: DesignSystem.typeCaption(), weight: .semibold))
                            .foregroundStyle(.secondary)
                        Spacer()
                        DatePicker("", selection: $date, displayedComponents: .date)
                            .labelsHidden()
                            .datePickerStyle(.compact)
                    }
                    .padding(DesignSystem.spaceM())
                    .background(
                        RoundedRectangle(cornerRadius: DesignSystem.radiusCard(), style: .continuous)
                            .fill(DesignSystem.panelFill())
                    )
                }
                .padding(DesignSystem.spaceXL())
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save error") {
                        save()
                    }
                    .disabled(errorDescription.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || currentSubject == nil)
                    .buttonStyle(.borderedProminent)
                }
            }
        }
        .frame(minWidth: 540, idealWidth: 580, minHeight: 520, idealHeight: 560)
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
