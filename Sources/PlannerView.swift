import SwiftUI
import SwiftData

// PlanBlock keyed by (topic, weekIndex) so reconciliation can preserve isDone
// while targetMinutes evolve with the plan.
private struct PlanKey: Hashable {
    let topicID: UUID
    let week: Int
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

    private var inputs: [TopicPlan] {
        sortedTopics.map { TopicPlan(topicID: $0.id, title: $0.title, weight: max(1, $0.weight)) }
    }

    private var blocks: [ScheduledBlock] {
        guard let examDate = subject.examDate else { return [] }
        return PlannerEngine.schedule(topics: inputs, examDate: examDate, dailyMinutes: subject.dailyMinutes)
    }

    private var doneMap: [PlanKey: PlanBlock] {
        var map: [PlanKey: PlanBlock] = [:]
        for block in subject.topics.flatMap(\.planBlocks) {
            if let topicID = block.topic?.id {
                map[PlanKey(topicID: topicID, week: block.weekIndex)] = block
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
        .onChange(of: subject.examDate) { _, _ in reconcile() }
        .onChange(of: subject.dailyMinutes) { _, _ in reconcile() }
        .onChange(of: subject.topics.map { "\($0.persistentModelID)-\($0.weight)" }.joined()) { _, _ in reconcile() }
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: DesignSystem.spaceXS()) {
                Text(subject.name)
                    .font(.system(size: DesignSystem.typeDisplay(), weight: .semibold))
                if let exam = subject.examDate {
                    Text(examLine(exam))
                        .font(.system(size: DesignSystem.typeBody()))
                        .foregroundStyle(.secondary)
                } else {
                    Text("Set an exam date to build the plan.")
                        .font(.system(size: DesignSystem.typeBody()))
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Stepper("\(subject.dailyMinutes) min/day", value: $subject.dailyMinutes, in: 15...240, step: 15)
        }
    }

    private func examLine(_ exam: Date) -> String {
        let days = Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: .now), to: Calendar.current.startOfDay(for: exam)).day ?? 0
        if days < 0 { return "exam passed — plan is holding for the week before it" }
        if days == 0 { return "exam is today" }
        return exam.formatted(date: .abbreviated, time: .omitted) + " · \(days) days out"
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

            Button {
                addTopic()
            } label: {
                Label("Add topic", systemImage: "plus")
                    .font(.system(size: DesignSystem.typeBody(), weight: .medium))
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity, alignment: .leading)

            Text("Priorities are relative — dials are scaled to fill exactly \(subject.dailyMinutes)min/day · \(subject.dailyMinutes * 7)min/wk across all topics; the coloured % shows the effective split.")
                .font(.system(size: DesignSystem.typeCaption()))
                .foregroundStyle(.tertiary)
        }
    }

    private var planSection: some View {
        VStack(alignment: .leading, spacing: DesignSystem.spaceS()) {
            if subject.examDate == nil {
                planHeading
                Text("Set an exam date for \(subject.name) to generate the week-by-week plan.")
                    .font(.system(size: DesignSystem.typeBody()))
                    .foregroundStyle(.secondary)
            } else if inputs.isEmpty {
                planHeading
                Text("Add a topic and the week plan builds itself.")
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
            ForEach(sortedTopics) { topic in
                Text(topic.title)
                    .font(.system(size: DesignSystem.typeBody(), weight: .medium))
                    .lineLimit(1)
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
        let weeklyMins = sortedTopics.map { plannedMinutes(topic: $0, week: currentWeek) ?? 0 }
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
        guard let exam = subject.examDate else { return 1 }
        let days = Calendar.current.dateComponents(
            [.day],
            from: Calendar.current.startOfDay(for: .now),
            to: Calendar.current.startOfDay(for: exam)
        ).day ?? 0
        return max(1, min(7, days + 1))
    }

    private func dayColumn(_ day: Int, distribution: [[Int]]) -> some View {
        let isToday = day == 0
        let width = GridMetrics.daily.column
        let columnTotal = sortedTopics.indices.reduce(0) { $0 + distribution[$1][day] }

        return VStack(alignment: .center, spacing: 0) {
            Text(dayLabel(day))
                .font(.system(size: DesignSystem.typeCaption(), weight: .semibold))
                .foregroundStyle(isToday ? DesignSystem.hexColor(subject.accentHex) : Color.secondary)
                .lineLimit(1)
                .frame(width: width, height: GridMetrics.daily.header, alignment: .center)

            ForEach(sortedTopics.indices, id: \.self) { index in
                Text("\(distribution[index][day])")
                    .font(.system(size: DesignSystem.typeBody(), weight: .medium))
                    .frame(width: width, height: GridMetrics.daily.cell, alignment: .center)
                    .background(
                        RoundedRectangle(cornerRadius: DesignSystem.radiusS(), style: .continuous)
                            .fill(isToday ? DesignSystem.hexColor(subject.accentHex).opacity(0.1) : Color.clear)
                    )
            }

            Text("\(columnTotal)m")
                .font(.system(size: DesignSystem.typeCaption(), weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: width, height: GridMetrics.daily.footer, alignment: .center)
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

    private func weekColumn(_ week: Int, weeks: Int) -> some View {
        let width = GridMetrics.weekly.column

        return VStack(alignment: .center, spacing: 0) {
            Text(weekLabel(week, weeks: weeks))
                .font(.system(size: DesignSystem.typeCaption(), weight: .semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(width: width, height: GridMetrics.weekly.header, alignment: .center)

            ForEach(sortedTopics) { topic in
                if let block = doneMap[PlanKey(topicID: topic.id, week: week)],
                   let minutes = plannedMinutes(topic: topic, week: week) {
                    Button {
                        block.isDone.toggle()
                        try? ctx.save()
                    } label: {
                        Text("\(minutes)")
                            .font(.system(size: DesignSystem.typeBody(), weight: .medium))
                            .foregroundStyle(block.isDone ? Color.secondary : Color.primary)
                            .strikethrough(block.isDone, color: .secondary)
                            .frame(width: width, height: GridMetrics.weekly.cell, alignment: .center)
                            .background(
                                RoundedRectangle(cornerRadius: DesignSystem.radiusS(), style: .continuous)
                                    .fill(block.isDone ? DesignSystem.hexColor(subject.accentHex).opacity(0.14) : Color.clear)
                            )
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
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
        let topicID = topic.id
        return blocks.first { $0.topicID == topicID && $0.weekIndex == week }?.minutes
    }

    private func totalFor(_ week: Int) -> String {
        let sum = blocks.filter { $0.weekIndex == week }.map(\.minutes).reduce(0, +)
        return "\(sum)m"
    }

    private func weekLabel(_ week: Int, weeks: Int) -> String {
        if week == 0 { return "Exam" }
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
        guard let examDate = subject.examDate else {
            for block in subject.topics.flatMap(\.planBlocks) { ctx.delete(block) }
            try? ctx.save()
            return
        }
        guard !inputs.isEmpty else { return }

        var byKey: [PlanKey: PlanBlock] = [:]
        for block in subject.topics.flatMap(\.planBlocks) {
            if let topicID = block.topic?.id {
                byKey[PlanKey(topicID: topicID, week: block.weekIndex)] = block
            }
        }

        var wanted = Set<PlanKey>()
        for scheduled in PlannerEngine.schedule(topics: inputs, examDate: examDate, dailyMinutes: subject.dailyMinutes) {
            let key = PlanKey(topicID: scheduled.topicID, week: scheduled.weekIndex)
            wanted.insert(key)
            if let existing = byKey[key] {
                existing.targetMinutes = scheduled.minutes
            } else if let topic = subject.topics.first(where: { $0.id == scheduled.topicID }) {
                ctx.insert(PlanBlock(weekIndex: scheduled.weekIndex, targetMinutes: scheduled.minutes, topic: topic))
            }
        }
        for (key, block) in byKey where !wanted.contains(key) {
            ctx.delete(block)
        }
        try? ctx.save()
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