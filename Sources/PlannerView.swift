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

struct PlannerView: View {
    @Bindable var subject: Subject
    @Environment(\.modelContext) private var ctx

    private var sortedTopics: [Topic] {
        subject.topics.sorted { $0.position < $1.position }
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
        .onChange(of: subject.examDate) { reconcile() }
        .onChange(of: subject.dailyMinutes) { reconcile() }
        .onChange(of: subject.topics.map { "\($0.persistentModelID)-\($0.weight)" }.joined()) { reconcile() }
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
                    TopicRow(topic: topic, isLast: sortedTopics.last?.persistentModelID == topic.persistentModelID) {
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
        }
    }

    private var planSection: some View {
        Group {
            if subject.examDate == nil {
                emptyPlan
            } else if inputs.isEmpty {
                VStack(alignment: .leading, spacing: DesignSystem.spaceS()) {
                    Label("Plan", systemImage: "square.grid.2x2")
                        .font(.system(size: DesignSystem.typeCaption(), weight: .semibold))
                        .foregroundStyle(.secondary)
                    Text("Add a topic and the week plan builds itself.")
                        .font(.system(size: DesignSystem.typeBody()))
                        .foregroundStyle(.secondary)
                }
            } else {
                planGrid
            }
        }
    }

    private var emptyPlan: some View {
        VStack(alignment: .leading, spacing: DesignSystem.spaceS()) {
            Label("Plan", systemImage: "square.grid.2x2")
                .font(.system(size: DesignSystem.typeCaption(), weight: .semibold))
                .foregroundStyle(.secondary)
            Text("Set an exam date for \(subject.name) to generate the week-by-week plan.")
                .font(.system(size: DesignSystem.typeBody()))
                .foregroundStyle(.secondary)
        }
    }

    private var planGrid: some View {
        let weeks = (blocks.map(\.weekIndex).max() ?? 0) + 1 // 0 = exam week
        let columns = (0..<weeks).reversed().map { $0 } // farthest week first, exam last

        return VStack(alignment: .leading, spacing: DesignSystem.spaceS()) {
            Label("Plan", systemImage: "square.grid.2x2")
                .font(.system(size: DesignSystem.typeCaption(), weight: .semibold))
                .foregroundStyle(.secondary)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 0) {
                    // Sticky topic column
                    VStack(alignment: .leading, spacing: 0) {
                        Text("Topic")
                            .font(.system(size: DesignSystem.typeCaption(), weight: .semibold))
                            .foregroundStyle(.secondary)
                            .frame(height: 28, alignment: .leading)
                        ForEach(sortedTopics) { topic in
                            Text(topic.title)
                                .font(.system(size: DesignSystem.typeBody(), weight: .medium))
                                .lineLimit(1)
                                .frame(minWidth: 150, maxWidth: 150, minHeight: 32, alignment: .leading)
                                .padding(.leading, DesignSystem.spaceM())
                        }
                    }
                    .padding(.trailing, DesignSystem.spaceM())

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
    }

    private func weekColumn(_ week: Int, weeks: Int) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(weekLabel(week, weeks: weeks))
                .font(.system(size: DesignSystem.typeCaption(), weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(height: 28, alignment: .leading)

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
                            .frame(width: 64, height: 32, alignment: .center)
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
                .frame(height: 28, alignment: .leading)
        }
        .padding(.horizontal, DesignSystem.spaceXS())
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
        return remaining == 0 ? "1w" : "\(remaining)w"
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
    let isLast: Bool
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: DesignSystem.spaceM()) {
            TextField("Topic title", text: $topic.title)
                .textFieldStyle(.plain)
                .font(.system(size: DesignSystem.typeBody(), weight: .medium))

            Spacer()

            Stepper(value: $topic.weight, in: 1...5) {
                Text("w\(topic.weight)")
                    .font(.system(size: DesignSystem.typeCaption(), weight: .semibold))
            }
            .labelsHidden()
            .frame(width: 90)

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