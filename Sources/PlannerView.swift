import SwiftUI
import SwiftData

// PlanBlock keyed by (topic, calendar week) so reconciliation can preserve
// isDone while targetMinutes evolve, and so a tick survives the plan's driver
// moving from one assessment to the next.
private struct PlanKey: Hashable {
    let topicID: UUID
    let weekStart: Date
}

private struct WeekCell: Identifiable {
    let id: UUID
    let title: String
    let minutes: Int
    let done: Bool
}

private enum PlanScale: String, CaseIterable, Identifiable {
    case weekly, daily
    var id: String { rawValue }
    var label: String { rawValue.capitalized }
}

struct PlannerView: View {
    @Bindable var subject: Subject
    @Environment(\.modelContext) private var ctx
    @State private var planScale: PlanScale = .weekly

    private var sortedTopics: [Topic] {
        subject.topics.sorted { $0.position < $1.position }
    }

    private var totalPriority: Int {
        sortedTopics.map { max(1, $0.weight) }.reduce(0, +)
    }

    /// Real topics if there are any, otherwise a single stand-in row for the
    /// subject as a whole. Purely derived: nothing is written to SwiftData.
    private var inputs: [TopicPlan] {
        PlannerEngine.effectiveTopics(
            subjectID: subject.id,
            subjectName: subject.name,
            topics: sortedTopics.map { TopicPlan(topicID: $0.id, title: $0.title, weight: max(1, $0.weight)) }
        )
    }

    private var usesStandIn: Bool { inputs.contains(where: \.isSynthetic) }

    /// The assessment the plan is built around: the next one still ahead.
    private var driver: AssessmentRef? {
        subject.nextAssessment.map { AssessmentRef(id: $0.id, title: $0.title, date: $0.date) }
    }

    private var blocks: [ScheduledBlock] {
        guard let driver else { return [] }
        return PlannerEngine.schedule(topics: inputs, driver: driver.date, dailyMinutes: subject.dailyMinutes)
    }

    private func key(_ topicID: UUID, week: Int) -> PlanKey? {
        guard let driver else { return nil }
        return PlanKey(
            topicID: topicID,
            weekStart: PlannerEngine.weekStart(forWeekIndex: week, driver: driver.date)
        )
    }

    private var doneMap: [PlanKey: PlanBlock] {
        var map: [PlanKey: PlanBlock] = [:]
        for block in subject.topics.flatMap(\.planBlocks) {
            if let topicID = block.topic?.id {
                map[PlanKey(topicID: topicID, weekStart: block.weekStart)] = block
            }
        }
        return map
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DesignSystem.spaceXL()) {
                header
                topicsSection
                planSection
            }
            .padding(DesignSystem.spaceXL())
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle(subject.name)
        .onAppear { reconcile() }
        .onChange(of: subject.sortedAssessments.map { "\($0.persistentModelID)-\($0.date)-\($0.title)" }.joined()) { _, _ in reconcile() }
        .onChange(of: subject.dailyMinutes) { _, _ in reconcile() }
        .onChange(of: subject.topics.map { "\($0.persistentModelID)-\($0.weight)" }.joined()) { _, _ in reconcile() }
    }

    // MARK: Header
 
    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: DesignSystem.spaceXS()) {
                HStack(spacing: DesignSystem.spaceS()) {
                    Text(subject.name)
                        .font(.system(size: DesignSystem.typeDisplay(), weight: .semibold))
                    if subject.dayMode == .tasks {
                        Text("Task checklist")
                            .font(.system(size: DesignSystem.typeCaption()))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Color.secondary.opacity(0.12)))
                    }
                }
                if let driver {
                    Text(driverLine)
                        .font(.system(size: DesignSystem.typeBody()))
                        .foregroundStyle(.secondary)
                } else if subject.isFinished {
                    Text("All assessments done: \(subject.name) is finished.")
                        .font(.system(size: DesignSystem.typeBody()))
                        .foregroundStyle(.secondary)
                } else {
                    Text("Add an assessment to build the plan.")
                        .font(.system(size: DesignSystem.typeBody()))
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Stepper(
                subject.dayMode == .tasks ? "≈ \(subject.dailyMinutes) m/day guide" : "\(subject.dailyMinutes) min/day",
                value: $subject.dailyMinutes,
                in: 15...720,
                step: 15
            )
        }
    }

    private var driverLine: String {
        guard let driver else { return "" }
        let days = Calendar.current.dateComponents(
            [.day],
            from: Calendar.current.startOfDay(for: .now),
            to: Calendar.current.startOfDay(for: driver.date)
        ).day ?? 0
        var line: String
        if days == 0 {
            line = "\(driver.title) is today"
        } else if days == 1 {
            line = "\(driver.title) is tomorrow"
        } else {
            line = "\(driver.title) \(driver.date.formatted(date: .abbreviated, time: .omitted)) · \(days) days out"
        }
        let upcoming = subject.upcomingAssessments
        if !upcoming.isEmpty {
            let names = upcoming.prefix(2).map(\.title).joined(separator: ", ")
            line += "  ·  then \(names)\(upcoming.count > 2 ? " (+\(upcoming.count - 2) more)" : "")"
        }
        return line
    }

    // MARK: Topics

    private var topicsSection: some View {
        VStack(alignment: .leading, spacing: DesignSystem.spaceS()) {
            Label("Topics", systemImage: "list.bullet.rectangle")
                .font(.system(size: DesignSystem.typeCaption(), weight: .semibold))
                .foregroundStyle(.secondary)

            VStack(spacing: 0) {
                ForEach(sortedTopics) { topic in
                    TopicRow(topic: topic, totalPriority: totalPriority, weeklyMinutes: weeklyMinutes(topic), showsDaily: planScale == .daily, isLast: sortedTopics.last?.persistentModelID == topic.persistentModelID) {
                        delete(topic)
                    }
                }
            }
            .background(
                RoundedRectangle(cornerRadius: DesignSystem.radiusCard(), style: .continuous)
                    .fill(DesignSystem.panelFill())
            )

            if usesStandIn {
                Text("No topics yet, so \(subject.name) plans as one block. Add topics to split it up.")
                    .font(.system(size: DesignSystem.typeCaption()))
                    .foregroundStyle(.tertiary)
            }

            Button {
                addTopic()
            } label: {
                Label("Add topic", systemImage: "plus")
                    .font(.system(size: DesignSystem.typeBody(), weight: .medium))
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity, alignment: .leading)

            Text("Priorities are relative: dials are scaled to fill exactly \(subject.dailyMinutes)min/day · \(subject.dailyMinutes * 7)min/wk across all topics; the coloured % shows the effective split.")
                .font(.system(size: DesignSystem.typeCaption()))
                .foregroundStyle(.tertiary)
        }
    }

    private var planSection: some View {
        VStack(alignment: .leading, spacing: DesignSystem.spaceS()) {
            if driver == nil {
                planHeading
                Text(subject.isFinished
                     ? "\(subject.name) has no assessments left, so there's no plan to build."
                     : "Add an assessment to \(subject.name) to generate the week-by-week plan.")
                    .font(.system(size: DesignSystem.typeBody()))
                    .foregroundStyle(.secondary)
            } else {
                HStack {
                    planHeading
                    Spacer()
                    Picker("Scale", selection: $planScale) {
                        ForEach(PlanScale.allCases) { scale in
                            Text(scale.label).tag(scale)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 200)
                }
                if planScale == .daily {
                    dailyGrid
                } else {
                    planGrid
                }
            }
        }
    }

    private var planHeading: some View {
        Label("Plan", systemImage: "square.grid.2x2")
            .font(.system(size: DesignSystem.typeCaption(), weight: .semibold))
            .foregroundStyle(.secondary)
    }

    private var planGrid: some View {
        let weeks = (blocks.map(\.weekIndex).max() ?? 0) + 1 // 0 = exam week
        let columns = (0..<weeks).reversed().map { $0 } // farthest week first, exam last

        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: DesignSystem.spaceXS()) {
                stickyColumn(title: "Topic", foot: "Total")
                ForEach(Array(columns.enumerated()), id: \.element) { _, week in
                    weekColumn(week, weeks: weeks)
                }
            }
        }
        .padding(DesignSystem.spaceS())
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.radiusCard(), style: .continuous)
                .fill(DesignSystem.panelFill())
        )
    }

    /// Shared row/column metrics so the sticky column and every data column align exactly.
    private struct GridMetrics {
        let header: CGFloat
        let cell: CGFloat
        let footer: CGFloat
        let column: CGFloat
        static let weekly = GridMetrics(header: 32, cell: 40, footer: 32, column: 104)
        static let daily = GridMetrics(header: 44, cell: 40, footer: 44, column: 88)
    }

    private func stickyColumn(title: String, foot: String, metrics: GridMetrics = .weekly) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.system(size: DesignSystem.typeCaption(), weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(height: metrics.header, alignment: .leading)
                .padding(.leading, DesignSystem.spaceM())
            ForEach(Array(inputs.enumerated()), id: \.element.topicID) { _, plan in
                HStack(spacing: 4) {
                    Text(plan.title)
                        .font(.system(size: DesignSystem.typeBody(), weight: .medium))
                        .italic(plan.isSynthetic)
                        .lineLimit(1)
                }
                .frame(width: 150, height: metrics.cell, alignment: .leading)
                .padding(.leading, DesignSystem.spaceM())
                .padding(.trailing, DesignSystem.spaceM())
            }
            Text(foot)
                .font(.system(size: DesignSystem.typeCaption(), weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(height: metrics.footer, alignment: .leading)
                .padding(.leading, DesignSystem.spaceM())
        }
        .padding(.trailing, DesignSystem.spaceM())
    }

    private var dailyGrid: some View {
        let weeks = (blocks.map(\.weekIndex).max() ?? 0) + 1
        let currentWeek = weeks - 1 // the week we're in right now (0 = exam week)
        let days = currentWeekDays
        let weeklyMins = inputs.map { plannedMinutes(plan: $0, week: currentWeek) ?? 0 }
        let distribution = PlannerEngine.dailyBreakdown(weeklyMinutes: weeklyMins, days: days)

        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: DesignSystem.spaceXS()) {
                stickyColumn(title: "Topic", foot: "Total", metrics: .daily)

                ForEach(0..<days, id: \.self) { day in
                    dayColumn(day, distribution: distribution)
                }
            }
        }
        .padding(DesignSystem.spaceS())
        .background(
                RoundedRectangle(cornerRadius: DesignSystem.radiusCard(), style: .continuous)
                    .fill(DesignSystem.panelFill())
            )
    }

    private var currentWeekDays: Int {
        guard let driver else { return 1 }
        let days = Calendar.current.dateComponents(
            [.day],
            from: Calendar.current.startOfDay(for: .now),
            to: Calendar.current.startOfDay(for: driver.date)
        ).day ?? 0
        return max(1, min(7, days + 1))
    }

    private func dateFor(day: Int) -> Date {
        Calendar.current.date(byAdding: .day, value: day, to: Calendar.current.startOfDay(for: .now)) ?? .now
    }

    private func dayTaskRecordFor(topicID: UUID, day: Int) -> DayTask? {
        let date = dateFor(day: day)
        return subject.dayTasks.first {
            $0.topicID == topicID && Calendar.current.isDate($0.date, inSameDayAs: date)
        }
    }

    private func toggleDailyTopicTask(topicID: UUID, title: String, day: Int, hint: Int) {
        let date = dateFor(day: day)
        if let existing = dayTaskRecordFor(topicID: topicID, day: day) {
            existing.isDone.toggle()
        } else {
            let record = DayTask(
                date: date,
                title: title,
                isDone: true,
                topicID: topicID,
                plannedMinutesHint: hint,
                isAdHoc: false,
                position: 0,
                subject: subject
            )
            ctx.insert(record)
        }
        try? ctx.save()
    }

    private func dayColumn(_ day: Int, distribution: [[Int]]) -> some View {
        let isToday = day == 0
        let width = GridMetrics.daily.column
        let columnTotal = inputs.indices.reduce(0) { $0 + distribution[$1][day] }
        let isTaskMode = subject.dayMode == .tasks

        return VStack(alignment: .center, spacing: 0) {
            Text(dayLabel(day))
                .font(.system(size: DesignSystem.typeCaption(), weight: .semibold))
                .foregroundStyle(isToday ? DesignSystem.hexColor(subject.accentHex) : Color.secondary)
                .lineLimit(1)
                .frame(width: width, height: GridMetrics.daily.header, alignment: .center)

            ForEach(inputs.indices, id: \.self) { index in
                let plan = inputs[index]
                let minutes = distribution[index][day]
                if isTaskMode && !plan.isSynthetic {
                    let task = dayTaskRecordFor(topicID: plan.topicID, day: day)
                    let isDone = task?.isDone ?? false
                    Button {
                        toggleDailyTopicTask(topicID: plan.topicID, title: plan.title, day: day, hint: minutes)
                    } label: {
                        HStack(spacing: 3) {
                            Image(systemName: isDone ? "checkmark.circle.fill" : "circle")
                                .font(.system(size: DesignSystem.typeCaption()))
                                .foregroundStyle(isDone ? DesignSystem.hexColor(subject.accentHex) : Color.secondary)
                            Text("\(minutes)m")
                                .font(.system(size: DesignSystem.typeCaption(), design: .monospaced))
                                .foregroundStyle(isDone ? Color.secondary : Color.primary)
                                .strikethrough(isDone, color: .secondary)
                        }
                        .frame(width: width, height: GridMetrics.daily.cell, alignment: .center)
                        .background(
                            RoundedRectangle(cornerRadius: DesignSystem.radiusS(), style: .continuous)
                                .fill(isDone ? DesignSystem.hexColor(subject.accentHex).opacity(0.14) : Color.clear)
                        )
                    }
                    .buttonStyle(.plain)
                } else {
                    Text("\(minutes)")
                        .font(.system(size: DesignSystem.typeBody(), weight: .medium))
                        .frame(width: width, height: GridMetrics.daily.cell, alignment: .center)
                        .background(
                            RoundedRectangle(cornerRadius: DesignSystem.radiusS(), style: .continuous)
                                .fill(isToday ? DesignSystem.hexColor(subject.accentHex).opacity(0.1) : Color.clear)
                        )
                }
            }

            if isTaskMode {
                let completed = inputs.filter { !$0.isSynthetic && dayTaskRecordFor(topicID: $0.topicID, day: day)?.isDone == true }.count
                let total = inputs.filter { !$0.isSynthetic }.count
                Text(total > 0 && completed >= total ? "Done ✓" : "\(completed)/\(total)")
                    .font(.system(size: DesignSystem.typeCaption(), weight: .semibold))
                    .foregroundStyle(total > 0 && completed >= total ? Color.green : Color.secondary)
                    .frame(width: width, height: GridMetrics.daily.footer, alignment: .center)
            } else {
                Text("\(columnTotal)m")
                    .font(.system(size: DesignSystem.typeCaption(), weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: width, height: GridMetrics.daily.footer, alignment: .center)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.radiusS(), style: .continuous)
                .fill(isToday ? DesignSystem.hexColor(subject.accentHex).opacity(0.06) : Color.clear)
        )
    }

    private func dayLabel(_ day: Int) -> String {
        if day == 0 { return "Today" }
        if let date = Calendar.current.date(byAdding: .day, value: day, to: .now) {
            return date.formatted(.dateTime.weekday(.short).day())
        }
        return "Day \(day + 1)"
    }

    private func cellLabel(_ minutes: Int, isDone: Bool) -> some View {
        let empty = minutes == 0
        return Text("\(minutes)")
            .font(.system(size: DesignSystem.typeBody(), weight: .medium))
            .foregroundStyle(isDone || empty ? Color.secondary : Color.primary)
            .strikethrough(isDone, color: .secondary)
            .frame(width: GridMetrics.weekly.column, height: GridMetrics.weekly.cell, alignment: .center)
            .background(
                RoundedRectangle(cornerRadius: DesignSystem.radiusS(), style: .continuous)
                    .fill(isDone ? DesignSystem.hexColor(subject.accentHex).opacity(0.14) : Color.clear)
            )
            .contentShape(Rectangle())
    }

    private func weekColumn(_ week: Int, weeks: Int) -> some View {
        let width = GridMetrics.weekly.column

        return VStack(alignment: .center, spacing: 0) {
            Text(weekLabel(week, weeks: weeks))
                .font(.system(size: DesignSystem.typeCaption(), weight: .semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(width: width, height: GridMetrics.weekly.header, alignment: .center)

            ForEach(inputs) { plan in
                // Minutes come from the computed plan, so a stand-in topic row
                // still shows its share of the week. Only ticking needs a
                // persisted PlanBlock, which a stand-in never has.
                let minutes = plannedMinutes(plan: plan, week: week) ?? 0
                let block = key(plan.topicID, week: week).flatMap { doneMap[$0] }

                if let block, !plan.isSynthetic {
                    Button {
                        block.isDone.toggle()
                        try? ctx.save()
                    } label: {
                        cellLabel(minutes, isDone: block.isDone)
                    }
                    .buttonStyle(.plain)
                } else {
                    cellLabel(minutes, isDone: false)
                        .allowsHitTesting(false)
                        .help(plan.isSynthetic ? "No topics yet, so this is the subject as a whole" : "")
                }
            }

            Text(totalFor(week))
                .font(.system(size: DesignSystem.typeCaption(), weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: width, height: GridMetrics.weekly.footer, alignment: .center)
        }
    }

    private func weeklyMinutes(_ topic: Topic) -> Int? {
        plannedMinutes(topic: topic, week: blocks.map(\.weekIndex).max() ?? 0)
    }

    private func plannedMinutes(topic: Topic, week: Int) -> Int? {
        plannedMinutes(plan: TopicPlan(topicID: topic.id, title: topic.title, weight: topic.weight), week: week)
    }

    private func plannedMinutes(plan: TopicPlan, week: Int) -> Int? {
        blocks.first { $0.topicID == plan.topicID && $0.weekIndex == week }?.minutes
    }

    private func totalFor(_ week: Int) -> String {
        let sum = blocks.filter { $0.weekIndex == week }.map(\.minutes).reduce(0, +)
        return "\(sum)m"
    }

    private func weekLabel(_ week: Int, weeks: Int) -> String {
        if week == 0 { return driver?.title ?? "Assessment" }
        let remaining = weeks - 1 - week
        if remaining == 0 { return "This Week" }
        return "\(remaining)w"
    }

    // MARK: Mutations

    private func addTopic() {
        let topic = Topic(title: "New topic", position: subject.topics.count)
        topic.subject = subject
        ctx.insert(topic)
        try? ctx.save()
    }

    private func delete(_ topic: Topic) {
        ctx.delete(topic)
        try? ctx.save()
    }

    private func reconcile() {
        guard let driver else {
            // Nothing left to revise for (or nothing set up yet). Drop the blocks:
            // with no assessment there is no ladder to reconcile against, and a
            // stale tick against a week that no longer exists is worse than none.
            for block in subject.topics.flatMap(\.planBlocks) { ctx.delete(block) }
            try? ctx.save()
            return
        }
        guard !inputs.isEmpty else { return }

        var byKey: [PlanKey: PlanBlock] = [:]
        for block in subject.topics.flatMap(\.planBlocks) {
            if let topicID = block.topic?.id {
                byKey[PlanKey(topicID: topicID, weekStart: block.weekStart)] = block
            }
        }

        let realTopicIDs = Set(subject.topics.map(\.id))

        var wanted = Set<PlanKey>()
        for scheduled in PlannerEngine.schedule(topics: inputs, driver: driver.date, dailyMinutes: subject.dailyMinutes) {
            // A stand-in row is derived, not stored: there is no Topic to hang a
            // PlanBlock off, and inventing one would manufacture data on disk.
            guard realTopicIDs.contains(scheduled.topicID) else { continue }
            let key = PlanKey(topicID: scheduled.topicID, weekStart: scheduled.weekStart)
            wanted.insert(key)
            if let existing = byKey[key] {
                existing.targetMinutes = scheduled.minutes
                existing.weekIndex = scheduled.weekIndex
            } else if let topic = subject.topics.first(where: { $0.id == scheduled.topicID }) {
                ctx.insert(
                    PlanBlock(
                        weekIndex: scheduled.weekIndex,
                        weekStart: scheduled.weekStart,
                        targetMinutes: scheduled.minutes,
                        topic: topic
                    )
                )
            }
        }
        // Anything the ladder no longer covers. A block whose week has passed
        // stays, so ticks already earned are never thrown away mid-term.
        for (key, block) in byKey where !wanted.contains(key) {
            if block.weekStart >= currentWeekStart { ctx.delete(block) }
        }
        try? ctx.save()
    }

    private var currentWeekStart: Date {
        PlannerEngine.weekStart(containing: .now)
    }
}

private struct TopicRow: View {
    @Bindable var topic: Topic
    let totalPriority: Int
    let weeklyMinutes: Int?
    let showsDaily: Bool
    let isLast: Bool
    let onDelete: () -> Void

    private var priorityBinding: Binding<Double> {
        Binding(
            get: { Double(topic.weight) },
            set: { topic.weight = Int($0.rounded(.down)) }
        )
    }

    private var effectivePercent: Int {
        guard totalPriority > 0 else { return 0 }
        return Int((Double(max(1, topic.weight)) / Double(totalPriority) * 100).rounded())
    }

    var body: some View {
        HStack(spacing: DesignSystem.spaceM()) {
            TextField("Topic title", text: $topic.title)
                .textFieldStyle(.plain)
                .font(.system(size: DesignSystem.typeBody(), weight: .medium))

            Spacer()

            if let weeklyMinutes {
                Text(showsDaily ? "≈ \(max(1, weeklyMinutes / 7))m/day" : "≈ \(weeklyMinutes)m/wk")
                    .font(.system(size: DesignSystem.typeCaption()))
                    .foregroundStyle(.secondary)
            }

            Slider(value: priorityBinding, in: 1...100, step: 5)
                .frame(width: 120)
                .tint(DesignSystem.hexColor(topic.subject?.accentHex ?? "#A7B99C"))

            Text("\(effectivePercent)%")
                .font(.system(size: DesignSystem.typeCaption(), weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(DesignSystem.hexColor(topic.subject?.accentHex ?? "#A7B99C"))
                .frame(minWidth: 44, alignment: .trailing)

            Button(role: .destructive) {
                onDelete()
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: DesignSystem.typeBody()))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, DesignSystem.spaceM())
        .padding(.vertical, DesignSystem.spaceS())
        .overlay(alignment: .bottom) {
            if !isLast {
                Divider()
            }
        }
    }
}