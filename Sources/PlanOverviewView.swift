import SwiftUI
import SwiftData

/// The cross-subject answer to "what am I doing today?" — the question no
/// single subject's plan can answer on its own. Per-subject plans stay
/// authoritative; this aggregates them without re-weighting anyone's budget.
struct PlanOverviewView: View {
    @Query(sort: \Subject.position) private var subjects: [Subject]

    private enum Scale: String, CaseIterable, Identifiable {
        case today, week
        var id: String { rawValue }
        var label: String { rawValue == "today" ? "Today" : "Week" }
    }

    @State private var scale: Scale = .today

    private var inputs: [SubjectPlanInput] {
        subjects.map { subject in
            SubjectPlanInput(
                id: subject.id,
                name: subject.name,
                accentHex: subject.accentHex,
                examDate: subject.examDate,
                dailyMinutes: subject.dailyMinutes,
                topics: subject.topics
                    .sorted { $0.position < $1.position }
                    .map { TopicPlan(topicID: $0.id, title: $0.title, weight: max(1, $0.weight)) }
            )
        }
    }

    @Query(sort: \StudySession.startedAt, order: .reverse) private var sessions: [StudySession]

    private var overview: Overview {
        OverviewEngine.overview(subjects: inputs, days: 7, isDone: doneLookup, actuals: actualRecords)
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
    private func doneLookup(topicID: UUID, weekIndex: Int) -> Bool? {
        for subject in subjects {
            for topic in subject.topics where topic.id == topicID {
                guard let block = topic.planBlocks.first(where: { $0.weekIndex == weekIndex }) else { return nil }
                return block.isDone
            }
        }
        return nil
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
                    Picker("Scale", selection: $scale) {
                        ForEach(Scale.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 200)

                    if scale == .today { todayList } else { weekGrid }
                }
            }
            .padding(DesignSystem.spaceXL())
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle("Plan")
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
                    "Not planned — no exam date: \(overview.excluded.joined(separator: ", "))",
                    systemImage: "exclamationmark.triangle"
                )
                .font(.system(size: DesignSystem.typeCaption()))
                .foregroundStyle(.secondary)
            }
        }
    }

    private var todaySubtitle: String {
        guard let day = overview.today else { return "Nothing scheduled today." }
        let total = day.totalMinutes
        guard total > 0 else { return "Nothing scheduled today." }
        let count = day.subjects.count
        let subjectNoun = count == 1 ? "subject" : "subjects"
        if day.isMet {
            return "Target met — \(day.actualMinutes)m against \(total)m planned across \(count) \(subjectNoun)."
        }
        return "\(day.actualMinutes)m of \(total)m across \(count) \(subjectNoun) · \(day.remainingMinutes)m to go."
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
        Text("Add a subject with an exam date and this fills in.")
            .font(.system(size: DesignSystem.typeBody()))
            .foregroundStyle(.secondary)
    }

    // MARK: Today

    private var todayList: some View {
        VStack(alignment: .leading, spacing: DesignSystem.spaceS()) {
            if let day = overview.today {
                ForEach(day.subjects) { planned in
                    subjectCard(planned, day: day)
                }
            }
        }
    }

    private func subjectCard(_ planned: PlannedSubject, day: OverviewDay) -> some View {
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
                Text("exam \(planned.examDate.formatted(date: .abbreviated, time: .omitted))")
                    .font(.system(size: DesignSystem.typeCaption()))
                    .foregroundStyle(.tertiary)
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

    // MARK: Week

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
        let isToday = day.dayIndex == 0
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
                Text("—")
                    .font(.system(size: DesignSystem.typeCaption()))
                    .foregroundStyle(.tertiary)
            } else {
                ForEach(day.subjects) { planned in
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 5) {
                            Circle()
                                .fill(DesignSystem.hexColor(planned.accentHex))
                                .frame(width: 6, height: 6)
                            Text(planned.name)
                                .font(.system(size: DesignSystem.typeCaption(), weight: .medium))
                                .lineLimit(1)
                        }
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