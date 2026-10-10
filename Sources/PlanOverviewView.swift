import SwiftUI
import SwiftData

/// The cross-subject answer to "what am I doing today?": the question no
/// single subject's plan can answer on its own. Per-subject plans stay
/// authoritative; this aggregates them without re-weighting anyone's budget.
struct PlanOverviewView: View {
    @Query(sort: \Subject.position) private var subjects: [Subject]
    @Query(sort: \StudySession.startedAt, order: .reverse) private var sessions: [StudySession]
    @Query private var blocks: [PlanBlock]
    @Query private var dayTasks: [DayTask]

    @Environment(\.modelContext) private var ctx

    private enum Scale: String, CaseIterable, Identifiable {
        case today, week
        var id: String { rawValue }
        var label: String { rawValue == "today" ? "Today" : "Week" }
    }

    @State private var scale: Scale = .today
    @State private var selectedDate: Date = .now
    @State private var backlog = BacklogModel()
    @State private var adHocDrafts: [UUID: String] = [:]

    private var inputs: [SubjectPlanInput] {
        subjects.map(\.planInput)
    }

    private var dayTaskRecords: [DayTaskRecord] {
        dayTasks.compactMap { task in
            guard let subjectID = task.subject?.id else { return nil }
            return DayTaskRecord(
                id: task.id,
                subjectID: subjectID,
                topicID: task.topicID,
                date: task.date,
                title: task.title,
                isDone: task.isDone,
                isAdHoc: task.isAdHoc,
                position: task.position
            )
        }
    }

    /// Plan blocks in the backlog's vocabulary.
    private var backlogBlocks: [BacklogEngine.BacklogBlock] {
        blocks.compactMap { block in
            guard let topic = block.topic, let subjectID = topic.subject?.id else { return nil }
            return BacklogEngine.BacklogBlock(
                subjectID: subjectID, topicID: topic.id,
                weekStart: block.weekStart, isDone: block.isDone
            )
        }
    }

    private func loadBacklog() {
        backlog.load(subjects: inputs, blocks: backlogBlocks)
    }

    private var overview: Overview {
        let anchor = scale == .today ? selectedDate : .now
        return OverviewEngine.overview(
            subjects: inputs,
            days: 7,
            from: anchor,
            isDone: doneLookup,
            actuals: actualRecords
        )
    }

    /// Sessions in the engine's own vocabulary.
    private var actualRecords: [OverviewEngine.ActualRecord] {
        sessions.map {
            OverviewEngine.ActualRecord(
                subjectID: $0.subject?.id,
                topicID: $0.topic?.id,
                focusedMinutes: $0.focusedMinutes,
                startedAt: $0.startedAt
            )
        }
    }

    /// Live from SwiftData: a tick in a subject's own plan shows here immediately.
    /// Matched on the calendar week rather than the ladder position, so it agrees
    /// with what the subject's own grid is showing.
    private func doneLookup(topicID: UUID, weekStart: Date) -> Bool? {
        for subject in subjects {
            for topic in subject.topics where topic.id == topicID {
                guard let block = topic.planBlocks.first(where: { sameWeek($0.weekStart, weekStart) })
                else { return nil }
                return block.isDone
            }
        }
        return nil
    }

    private func sameWeek(_ lhs: Date, _ rhs: Date) -> Bool {
        Calendar.current.isDate(lhs, equalTo: rhs, toGranularity: .weekOfYear)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DesignSystem.spaceXL()) {
                header

                if subjects.isEmpty {
                    emptyState
                } else if overview.days.allSatisfy({ $0.totalMinutes == 0 }) {
                    emptyState
                } else {
                    controlsBar

                    if scale == .today { todayList } else { weekGrid }
                }

                if !backlog.items.isEmpty { backlogSection }
            }
            .padding(DesignSystem.spaceXL())
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle("Plan")
        .onAppear(perform: loadBacklog)
        .onChange(of: blocks.count) { _, _ in loadBacklog() }
    }

    // MARK: Controls Bar

    private var controlsBar: some View {
        HStack(spacing: DesignSystem.spaceM()) {
            Picker("Scale", selection: $scale) {
                ForEach(Scale.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 180)

            if scale == .today {
                dateNavigator
            }

            Spacer()
        }
    }

    private var dateNavigator: some View {
        HStack(spacing: DesignSystem.spaceS()) {
            Button {
                selectedDate = Calendar.current.date(byAdding: .day, value: -1, to: selectedDate) ?? selectedDate
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: DesignSystem.typeCaption(), weight: .semibold))
            }
            .buttonStyle(.plain)

            Text(dateDisplayTitle(selectedDate))
                .font(.system(size: DesignSystem.typeCaption(), weight: .semibold))
                .foregroundStyle(Calendar.current.isDateInToday(selectedDate) ? Color.primary : Color.secondary)

            Button {
                selectedDate = Calendar.current.date(byAdding: .day, value: 1, to: selectedDate) ?? selectedDate
            } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: DesignSystem.typeCaption(), weight: .semibold))
            }
            .buttonStyle(.plain)

            if !Calendar.current.isDateInToday(selectedDate) {
                Button("Today") {
                    selectedDate = .now
                }
                .buttonStyle(.plain)
                .font(.system(size: DesignSystem.typeCaption(), weight: .medium))
                .foregroundStyle(Color.accentColor)
            }
        }
        .padding(.horizontal, DesignSystem.spaceS())
        .padding(.vertical, DesignSystem.spaceXS())
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.radiusS(), style: .continuous)
                .fill(DesignSystem.panelFill())
        )
    }

    private func dateDisplayTitle(_ date: Date) -> String {
        if Calendar.current.isDateInToday(date) { return "Today" }
        return date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
    }

    // MARK: Backlog

    /// A quiet offer, never a total. There is deliberately no "180 minutes
    /// behind" anywhere in this app: a debt figure is what makes people stop
    /// opening it. One topic, one tap, and dismissing costs nothing.
    private var backlogSection: some View {
        VStack(alignment: .leading, spacing: DesignSystem.spaceS()) {
            ForEach(backlog.items.prefix(3)) { item in
                HStack(spacing: DesignSystem.spaceM()) {
                    Circle()
                        .fill(DesignSystem.hexColor(item.subjectAccentHex))
                        .frame(width: 8, height: 8)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.title)
                            .font(.system(size: DesignSystem.typeBody(), weight: .medium))
                        Text("Picked up from \(item.missedOn.formatted(.dateTime.weekday(.abbreviated)))")
                            .font(.system(size: DesignSystem.typeCaption()))
                            .foregroundStyle(.secondary)
                    }

                    Spacer(minLength: 0)

                    Button {
                        backlog.complete(item, in: ctx)
                    } label: {
                        Text("Done")
                            .font(.system(size: DesignSystem.typeCaption(), weight: .medium))
                    }
                    .buttonStyle(.plain)

                    Button {
                        backlog.dismiss(item)
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: DesignSystem.typeCaption()))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.tertiary)
                    .help("Not today")
                }
                .padding(DesignSystem.spaceM())
                .background(
                    RoundedRectangle(cornerRadius: DesignSystem.radiusCard(), style: .continuous)
                        .fill(DesignSystem.panelFill())
                )
            }
        }
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: DesignSystem.spaceXS()) {
            Text("Plan")
                .font(.system(size: DesignSystem.typeDisplay(), weight: .semibold))
            Text(scale == .today ? todaySubtitle : "The next seven days, every subject at once.")
                .font(.system(size: DesignSystem.typeBody()))
                .foregroundStyle(.secondary)
            if !overview.excluded.isEmpty {
                Label(
                    "Not planned: no assessment dated: \(overview.excluded.joined(separator: ", "))",
                    systemImage: "exclamationmark.triangle"
                )
                .font(.system(size: DesignSystem.typeCaption()))
                .foregroundStyle(.secondary)
            }
            if !overview.finished.isEmpty {
                Label(
                    "Finished, history kept: \(overview.finished.joined(separator: ", "))",
                    systemImage: "checkmark.circle"
                )
                .font(.system(size: DesignSystem.typeCaption()))
                .foregroundStyle(.tertiary)
            }
        }
    }

    private var todaySubtitle: String {
        guard let day = overview.today else { return "Nothing scheduled for this date." }
        let isToday = Calendar.current.isDateInToday(selectedDate)
        let dayPrefix = isToday ? "Today" : selectedDate.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
        let total = day.totalMinutes
        let count = day.subjects.count
        let subjectNoun = count == 1 ? "subject" : "subjects"

        let taskSubjects = subjects.filter { $0.dayMode == .tasks }
        if !taskSubjects.isEmpty && taskSubjects.count == subjects.count {
            let allTasks = taskSubjects.flatMap { subj -> [DerivedDayTask] in
                guard let planned = day.subjects.first(where: { $0.subjectID == subj.id }) else { return [] }
                return DayTaskEngine.tasksForDay(
                    subject: subj.planInput,
                    driver: AssessmentRef(id: planned.driver.id, title: planned.driver.title, date: planned.driver.date),
                    date: selectedDate,
                    persisted: dayTaskRecords
                )
            }
            let summary = DayTaskEngine.summary(tasks: allTasks)
            if summary.isComplete {
                return "\(dayPrefix): all \(summary.totalTasks) tasks completed across \(count) \(subjectNoun)."
            }
            return "\(dayPrefix): \(summary.completedTasks) of \(summary.totalTasks) tasks done across \(count) \(subjectNoun) · \(summary.remainingTasks) to go."
        }

        guard total > 0 else { return "Nothing scheduled for \(dayPrefix.lowercased())." }
        if day.isMet {
            return "\(dayPrefix): target met, \(day.actualMinutes)m against \(total)m planned across \(count) \(subjectNoun)."
        }
        return "\(dayPrefix): \(day.actualMinutes)m of \(total)m across \(count) \(subjectNoun) · \(day.remainingMinutes)m to go."
    }

    /// Thin determinate bar. Only ever shown for a day in progress, so it
    /// reports movement toward a target rather than grading a missed one.
    private func progressBar(fraction: Int, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            GeometryReader { geo in
                let clamped = CGFloat(min(100, max(0, fraction))) / 100
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.secondary.opacity(0.18))
                    Capsule().fill(Color.green).frame(width: geo.size.width * clamped)
                }
            }
            .frame(height: 5)

            Text(detail)
                .font(.system(size: DesignSystem.typeCaption()))
                .foregroundStyle(.tertiary)
                .monospacedDigit()
        }
    }

    private var emptyState: some View {
        Text("Add a subject and give it an assessment to revise for: this fills in.")
            .font(.system(size: DesignSystem.typeBody()))
            .foregroundStyle(.secondary)
    }

    // MARK: Today List

    private var todayList: some View {
        VStack(alignment: .leading, spacing: DesignSystem.spaceS()) {
            if let day = overview.today {
                ForEach(day.subjects) { planned in
                    if let subject = subjects.first(where: { $0.id == planned.subjectID }) {
                        if subject.dayMode == .tasks {
                            taskSubjectCard(subject: subject, planned: planned, day: day)
                        } else {
                            timeSubjectCard(subject: subject, planned: planned, day: day)
                        }
                    }
                }
            }
        }
    }

    // MARK: Task Mode Subject Card

    private func taskSubjectCard(subject: Subject, planned: PlannedSubject, day: OverviewDay) -> some View {
        let accent = DesignSystem.hexColor(planned.accentHex)
        let tasks = DayTaskEngine.tasksForDay(
            subject: subject.planInput,
            driver: AssessmentRef(id: planned.driver.id, title: planned.driver.title, date: planned.driver.date),
            date: selectedDate,
            persisted: dayTaskRecords
        )
        let summary = DayTaskEngine.summary(tasks: tasks)

        return VStack(alignment: .leading, spacing: DesignSystem.spaceS()) {
            HStack {
                Circle().fill(accent).frame(width: 8, height: 8)
                Text(planned.name)
                    .font(.system(size: DesignSystem.typeBody(), weight: .semibold))

                Text("Task checklist")
                    .font(.system(size: DesignSystem.typeCaption()))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.secondary.opacity(0.12)))

                Spacer()

                if summary.isComplete {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        Text("All done (\(summary.totalTasks))")
                            .font(.system(size: DesignSystem.typeBody(), weight: .semibold))
                            .foregroundStyle(.green)
                    }
                } else {
                    Text("\(summary.completedTasks)/\(summary.totalTasks) tasks")
                        .font(.system(size: DesignSystem.typeBody(), weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(accent)
                }
            }

            if !summary.isComplete && summary.totalTasks > 0 {
                progressBar(
                    fraction: summary.completionPercent,
                    detail: "\(summary.completedTasks) of \(summary.totalTasks) tasks · \(summary.remainingTasks) to go"
                )
            }

            VStack(alignment: .leading, spacing: DesignSystem.spaceXS()) {
                ForEach(tasks) { task in
                    taskRow(task: task, subject: subject)
                }
            }

            adHocInputRow(for: subject)

            HStack(spacing: DesignSystem.spaceM()) {
                Text("\(planned.driver.title) \(planned.driver.date.formatted(date: .abbreviated, time: .omitted))")
                    .font(.system(size: DesignSystem.typeCaption()))
                    .foregroundStyle(.tertiary)
                if let next = planned.upcoming.first {
                    Text("then \(next.title) \(next.date.formatted(date: .abbreviated, time: .omitted))")
                        .font(.system(size: DesignSystem.typeCaption()))
                        .foregroundStyle(.tertiary)
                        .help("Planned after \(planned.driver.title): not shaping the plan yet")
                }
                if summary.isComplete {
                    Label("Completed for this day", systemImage: "checkmark.circle.fill")
                        .font(.system(size: DesignSystem.typeCaption()))
                        .foregroundStyle(.green)
                }
            }
        }
        .padding(DesignSystem.spaceM())
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.radiusCard(), style: .continuous)
                .fill(DesignSystem.panelFill())
        )
    }

    private func taskRow(task: DerivedDayTask, subject: Subject) -> some View {
        HStack(spacing: DesignSystem.spaceS()) {
            Button {
                toggleTask(task, subject: subject)
            } label: {
                Image(systemName: task.isDone ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: DesignSystem.typeBody()))
                    .foregroundStyle(task.isDone ? DesignSystem.hexColor(subject.accentHex) : Color.secondary)
            }
            .buttonStyle(.plain)

            Text(task.title)
                .font(.system(size: DesignSystem.typeBody()))
                .strikethrough(task.isDone, color: .secondary)
                .foregroundStyle(task.isDone ? .secondary : .primary)

            Spacer()

            if task.plannedMinutesHint > 0 {
                Text("≈ \(task.plannedMinutesHint)m guide")
                    .font(.system(size: DesignSystem.typeCaption(), design: .monospaced))
                    .foregroundStyle(.tertiary)
            }

            if task.isAdHoc {
                Text("Ad hoc")
                    .font(.system(size: DesignSystem.typeCaption()))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(Capsule().fill(Color.secondary.opacity(0.12)))

                Button {
                    deleteAdHoc(task)
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: DesignSystem.typeCaption()))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func adHocInputRow(for subject: Subject) -> some View {
        HStack(spacing: DesignSystem.spaceS()) {
            Image(systemName: "plus.circle")
                .font(.system(size: DesignSystem.typeCaption()))
                .foregroundStyle(.tertiary)

            TextField("Add ad hoc task for today...", text: Binding(
                get: { adHocDrafts[subject.id] ?? "" },
                set: { adHocDrafts[subject.id] = $0 }
            ))
            .textFieldStyle(.plain)
            .font(.system(size: DesignSystem.typeCaption()))
            .onSubmit {
                submitAdHoc(for: subject)
            }

            if let draft = adHocDrafts[subject.id], !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Button("Add") {
                    submitAdHoc(for: subject)
                }
                .buttonStyle(.plain)
                .font(.system(size: DesignSystem.typeCaption(), weight: .medium))
                .foregroundStyle(DesignSystem.hexColor(subject.accentHex))
            }
        }
        .padding(.vertical, 2)
    }

    private func submitAdHoc(for subject: Subject) {
        let text = (adHocDrafts[subject.id] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        let dayStart = DayTaskEngine.normalizeDate(selectedDate)
        let maxPos = dayTasks
            .filter { $0.subject?.id == subject.id && Calendar.current.isDate($0.date, inSameDayAs: dayStart) }
            .map(\.position)
            .max() ?? 0

        let adHoc = DayTask(
            date: dayStart,
            title: text,
            isDone: false,
            topicID: nil,
            plannedMinutesHint: 0,
            isAdHoc: true,
            position: maxPos + 1,
            subject: subject
        )
        ctx.insert(adHoc)
        try? ctx.save()
        adHocDrafts[subject.id] = ""
    }

    private func toggleTask(_ task: DerivedDayTask, subject: Subject) {
        let dayStart = DayTaskEngine.normalizeDate(selectedDate)
        if let recordID = task.taskRecordID,
           let existing = dayTasks.first(where: { $0.id == recordID }) {
            existing.isDone.toggle()
        } else {
            let record = DayTask(
                date: dayStart,
                title: task.title,
                isDone: true,
                topicID: task.topicID,
                plannedMinutesHint: task.plannedMinutesHint,
                isAdHoc: task.isAdHoc,
                position: 0,
                subject: subject
            )
            ctx.insert(record)
        }
        try? ctx.save()
    }

    private func deleteAdHoc(_ task: DerivedDayTask) {
        guard let recordID = task.taskRecordID,
              let existing = dayTasks.first(where: { $0.id == recordID }) else { return }
        ctx.delete(existing)
        try? ctx.save()
    }

    // MARK: Time Mode Subject Card

    private func timeSubjectCard(subject: Subject, planned: PlannedSubject, day: OverviewDay) -> some View {
        let accent = DesignSystem.hexColor(planned.accentHex)
        return VStack(alignment: .leading, spacing: DesignSystem.spaceS()) {
            HStack {
                Circle().fill(accent).frame(width: 8, height: 8)
                Text(planned.name)
                    .font(.system(size: DesignSystem.typeBody(), weight: .semibold))
                Spacer()
                Text("\(planned.totalMinutes)m")
                    .font(.system(size: DesignSystem.typeBody(), weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(accent)

                if planned.isMet {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .help("Target met")
                }
            }

            if day.dayIndex == 0 && !planned.isMet && planned.totalMinutes > 0 {
                progressBar(fraction: planned.completionPercent,
                            detail: "\(planned.actualMinutes)m of \(planned.totalMinutes)m · \(planned.remainingMinutes)m to go")
            }

            VStack(alignment: .leading, spacing: DesignSystem.spaceXS()) {
                ForEach(planned.entries) { entry in
                    HStack {
                        Text(entry.title)
                            .font(.system(size: DesignSystem.typeBody()))
                            .italic(entry.isSynthetic)
                            .foregroundStyle(entry.isSynthetic ? .secondary : .primary)
                        Spacer()
                        Text("\(entry.minutes)m")
                            .font(.system(size: DesignSystem.typeCaption(), design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                }
            }

            HStack(spacing: DesignSystem.spaceM()) {
                Text("\(planned.driver.title) \(planned.driver.date.formatted(date: .abbreviated, time: .omitted))")
                    .font(.system(size: DesignSystem.typeCaption()))
                    .foregroundStyle(.tertiary)
                if let next = planned.upcoming.first {
                    Text("then \(next.title) \(next.date.formatted(date: .abbreviated, time: .omitted))")
                        .font(.system(size: DesignSystem.typeCaption()))
                        .foregroundStyle(.tertiary)
                        .help("Planned after \(planned.driver.title): not shaping the plan yet")
                }
                if day.dayIndex == 0, planned.actualMinutes > 0, !planned.isMet {
                    Text("\(planned.actualMinutes)m logged today")
                        .font(.system(size: DesignSystem.typeCaption()))
                        .foregroundStyle(.tertiary)
                }
                if let done = planned.isDone {
                    Label(done ? "This week done" : "In progress",
                          systemImage: done ? "checkmark.circle.fill" : "circle.lefthalf.filled")
                        .font(.system(size: DesignSystem.typeCaption()))
                        .foregroundStyle(done ? .green : .secondary)
                }
            }
        }
        .padding(DesignSystem.spaceM())
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.radiusCard(), style: .continuous)
                .fill(DesignSystem.panelFill())
        )
    }

    // MARK: Week Grid

    private var weekGrid: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: DesignSystem.spaceXS()) {
                ForEach(overview.days) { day in
                    dayColumn(day)
                }
            }
        }
        .padding(DesignSystem.spaceS())
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.radiusCard(), style: .continuous)
                .fill(DesignSystem.panelFill())
        )
    }

    private func dayColumn(_ day: OverviewDay) -> some View {
        let isToday = Calendar.current.isDateInToday(day.date)
        let width: CGFloat = 132

        return VStack(alignment: .leading, spacing: DesignSystem.spaceS()) {
            VStack(alignment: .leading, spacing: 1) {
                Text(isToday ? "Today" : day.date.formatted(.dateTime.weekday(.abbreviated)))
                    .font(.system(size: DesignSystem.typeCaption(), weight: .semibold))
                    .foregroundStyle(isToday ? .primary : .secondary)
                Text(day.date.formatted(date: .numeric, time: .omitted))
                    .font(.system(size: DesignSystem.typeCaption()))
                    .foregroundStyle(.tertiary)
            }

            HStack(spacing: 4) {
                Text("\(day.totalMinutes)m")
                    .font(.system(size: DesignSystem.typeBody(), weight: .semibold))
                    .monospacedDigit()
                if day.isMet {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: DesignSystem.typeCaption()))
                        .foregroundStyle(.green)
                        .help("Target met")
                }
            }

            Divider()

            if day.subjects.isEmpty {
                Text("None")
                    .font(.system(size: DesignSystem.typeCaption()))
                    .foregroundStyle(.tertiary)
            } else {
                ForEach(day.subjects) { planned in
                    let subject = subjects.first(where: { $0.id == planned.subjectID })
                    let isTaskMode = subject?.dayMode == .tasks

                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 5) {
                            Circle()
                                .fill(DesignSystem.hexColor(planned.accentHex))
                                .frame(width: 6, height: 6)
                            Text(planned.name)
                                .font(.system(size: DesignSystem.typeCaption(), weight: .medium))
                                .lineLimit(1)
                        }

                        if isTaskMode, let subject {
                            let tasks = DayTaskEngine.tasksForDay(
                                subject: subject.planInput,
                                driver: AssessmentRef(id: planned.driver.id, title: planned.driver.title, date: planned.driver.date),
                                date: day.date,
                                persisted: dayTaskRecords
                            )
                            let sum = DayTaskEngine.summary(tasks: tasks)
                            Text("\(sum.completedTasks)/\(sum.totalTasks) tasks")
                                .font(.system(size: DesignSystem.typeCaption()))
                                .foregroundStyle(sum.isComplete ? .green : .secondary)
                                .padding(.leading, 11)
                        } else {
                            ForEach(planned.entries) { entry in
                                Text(entry.isSynthetic ? "\(entry.minutes)m" : "\(entry.minutes)m \(entry.title)")
                                    .font(.system(size: DesignSystem.typeCaption()))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .padding(.leading, 11)
                            }
                        }
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, DesignSystem.spaceS())
        .padding(.horizontal, DesignSystem.spaceS())
        .frame(width: width, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.radiusS(), style: .continuous)
                .fill(isToday ? Color.accentColor.opacity(0.08) : Color.clear)
        )
    }
}