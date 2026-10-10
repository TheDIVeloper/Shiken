import SwiftUI
import SwiftData

struct ReviewView: View {
    @Query(sort: \Subject.position) private var subjects: [Subject]
    @Query(sort: \StudySession.startedAt, order: .reverse) private var sessions: [StudySession]
    @Query private var dayTasks: [DayTask]
    @Query private var revisionErrors: [RevisionError]

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

    private var records: [SessionRecord] {
        sessions.map {
            SessionRecord(
                subjectID: $0.subject?.id,
                topicID: $0.topic?.id,
                focusedMinutes: $0.focusedMinutes,
                startedAt: $0.startedAt
            )
        }
    }

    private var reviews: [SubjectReview] {
        subjects.compactMap { subject in
            // A finished subject has nothing left to revise for, so there is no
            // plan to hold it to. Its sessions still appear in the log.
            guard let next = subject.nextAssessment else { return nil }
            let topics = PlannerEngine.effectiveTopics(
                subjectID: subject.id, subjectName: subject.name, topics: subject.topicPlans
            )
            let plan = PlannerEngine.schedule(topics: topics, driver: next.date, dailyMinutes: subject.dailyMinutes)
            let taskSummary = DayTaskEngine.windowSummary(
                subject: subject.planInput,
                driver: AssessmentRef(id: next.id, title: next.title, date: next.date),
                persisted: dayTaskRecords
            )
            return ReviewEngine.review(
                subjectID: subject.id,
                name: subject.name,
                accentHex: subject.accentHex,
                topics: topics,
                plan: plan,
                sessions: records,
                driver: next.date,
                isTaskMode: subject.dayMode == .tasks,
                taskSummary: taskSummary
            )
        }
    }

    private var letterMarkdown: String { ReviewEngine.markdown(for: reviews) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DesignSystem.spaceXL()) {
                header

                if reviews.isEmpty {
                    quietEmptyState(
                        "Nothing to review yet.",
                        "Give a subject an assessment and this compares your plan against what you actually logged."
                    )
                } else {
                    ForEach(reviews, id: \.subjectID) { review in
                        let errorCount = revisionErrors.filter { $0.subject?.id == review.subjectID && !$0.isResolved }.count
                        SubjectReviewCard(review: review, activeErrors: errorCount)
                    }
                }
            }
            .padding(DesignSystem.spaceXL())
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle("Review")
    }

    /// Empty states use the same type scale and muted tone as the rest of the
    /// app instead of a large system glyph and display text, so a blank screen
    /// still looks like Shiken.
    private func quietEmptyState(_ title: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: DesignSystem.spaceXS()) {
            Text(title)
                .font(.system(size: DesignSystem.typeTitle(), weight: .semibold))
            Text(detail)
                .font(.system(size: DesignSystem.typeBody()))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(DesignSystem.spaceL())
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.radiusCard(), style: .continuous)
                .fill(DesignSystem.panelFill())
        )
        .padding(.top, DesignSystem.spaceL())
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: DesignSystem.spaceXS()) {
                Text("This week")
                    .font(.system(size: DesignSystem.typeDisplay(), weight: .semibold))
                Text("Planned against what actually happened, last 7 days.")
                    .font(.system(size: DesignSystem.typeBody()))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            ShareLink(item: letterMarkdown) {
                Label("Export", systemImage: "square.and.arrow.up")
            }
            .disabled(reviews.isEmpty)
        }
    }
}

private struct SubjectReviewCard: View {
    let review: SubjectReview
    let activeErrors: Int

    private var accent: Color { DesignSystem.hexColor(review.accentHex) }

    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.spaceM()) {
            HStack(alignment: .firstTextBaseline, spacing: DesignSystem.spaceS()) {
                Circle().fill(accent).frame(width: 8, height: 8)
                Text(review.name)
                    .font(.system(size: DesignSystem.typeTitle(), weight: .semibold))
                Spacer()
                gapChip
            }

            if activeErrors > 0 {
                Label("\(activeErrors) active \(activeErrors == 1 ? "error" : "errors") in revision log", systemImage: "exclamationmark.bubble")
                    .font(.system(size: DesignSystem.typeCaption()))
                    .foregroundStyle(.secondary)
            }

            HStack(alignment: .firstTextBaseline, spacing: DesignSystem.spaceXL()) {
                if review.isTaskMode {
                    metric(value: "\(review.plannedTasks)", label: "tasks planned")
                    metric(value: "\(review.completedTasks)", label: "tasks done")
                } else {
                    metric(value: "\(review.plannedMinutes)", label: "planned")
                    metric(value: "\(review.actualMinutes)", label: "actual")
                }
                metric(value: "\(review.completionPercent)%", label: "of plan")
                Spacer()
            }

            ratioBar

            if !review.topics.isEmpty {
                VStack(spacing: 0) {
                    ForEach(review.topics, id: \.topicID) { topic in
                        TopicReviewRow(topic: topic, accent: accent)
                    }
                }
            }
        }
        .padding(DesignSystem.spaceL())
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.radiusCard(), style: .continuous)
                .fill(DesignSystem.panelFill())
        )
    }

    private var gapChip: some View {
        if review.isTaskMode {
            let left = review.plannedTasks - review.completedTasks
            let text = left <= 0 ? "all tasks done" : "\(left) tasks to go"
            let color: Color = left <= 0 ? accent : .red
            return Text(text)
                .font(.system(size: DesignSystem.typeCaption(), weight: .semibold))
                .foregroundStyle(color)
                .padding(.horizontal, DesignSystem.spaceS())
                .padding(.vertical, DesignSystem.spaceXS())
                .background(Capsule().fill(color.opacity(0.12)))
        }
        let gap = review.gapMinutes
        let text = gap == 0 ? "on plan" : (gap > 0 ? "+\(gap)m" : "\(gap)m")
        let color: Color = gap >= 0 ? accent : .red
        return Text(text)
            .font(.system(size: DesignSystem.typeCaption(), weight: .semibold))
            .foregroundStyle(color)
            .padding(.horizontal, DesignSystem.spaceS())
            .padding(.vertical, DesignSystem.spaceXS())
            .background(Capsule().fill(color.opacity(0.12)))
    }

    private var ratioBar: some View {
        let ratio: Double
        if review.isTaskMode {
            ratio = review.plannedTasks > 0
                ? min(1.5, Double(review.completedTasks) / Double(review.plannedTasks))
                : 0
        } else {
            ratio = review.plannedMinutes > 0
                ? min(1.5, Double(review.actualMinutes) / Double(review.plannedMinutes))
                : 0
        }
        return GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(DesignSystem.hairline())
                Capsule()
                    .fill(accent)
                    .frame(width: geo.size.width * min(1, ratio))
                Rectangle()
                    .fill(Color.primary.opacity(0.25))
                    .frame(width: 1)
                    .offset(x: geo.size.width)
            }
        }
        .frame(height: 6)
    }

    private func metric(value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: DesignSystem.spaceXS()) {
            Text(value)
                .font(.system(size: DesignSystem.typeTitle(), weight: .semibold))
                .monospacedDigit()
            Text(label)
                .font(.system(size: DesignSystem.typeCaption(), weight: .medium))
                .foregroundStyle(.secondary)
        }
    }
}

private struct TopicReviewRow: View {
    let topic: TopicReview
    let accent: Color

    var body: some View {
        HStack(spacing: DesignSystem.spaceM()) {
            Text(topic.title)
                .font(.system(size: DesignSystem.typeBody(), weight: .medium))
                .lineLimit(1)

            Spacer()

            Text("\(topic.actualMinutes)m / \(topic.plannedMinutes)m")
                .font(.system(size: DesignSystem.typeBody()))
                .monospacedDigit()
                .foregroundStyle(.secondary)

            Text(topic.gapMinutes == 0 ? "0m" : (topic.gapMinutes > 0 ? "+\(topic.gapMinutes)" : "\(topic.gapMinutes)"))
                .font(.system(size: DesignSystem.typeCaption(), weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(topic.gapMinutes >= 0 ? accent : .red)
                .frame(width: 44, alignment: .trailing)
        }
        .padding(.vertical, DesignSystem.spaceS())
        .overlay(alignment: .bottom) {
            Divider()
        }
    }
}