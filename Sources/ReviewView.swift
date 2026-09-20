import SwiftUI
import SwiftData

struct ReviewView: View {
    @Query(sort: \Subject.position) private var subjects: [Subject]
    @Query(sort: \StudySession.startedAt, order: .reverse) private var sessions: [StudySession]

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
            guard let exam = subject.examDate else { return nil }
            let topics = subject.topics
                .sorted { $0.position < $1.position }
                .map { TopicPlan(topicID: $0.id, title: $0.title, weight: max(1, $0.weight)) }
            let plan = PlannerEngine.schedule(topics: topics, examDate: exam, dailyMinutes: subject.dailyMinutes)
            return ReviewEngine.review(
                subjectID: subject.id,
                name: subject.name,
                accentHex: subject.accentHex,
                topics: topics,
                plan: plan,
                sessions: records,
                examDate: exam
            )
        }
    }

    private var letterMarkdown: String { ReviewEngine.markdown(for: reviews) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DesignSystem.spaceXL()) {
                header

                if reviews.isEmpty {
                    ContentUnavailableView(
                        "Nothing to review",
                        systemImage: "chart.bar.xaxis",
                        description: Text("Add a subject with an exam date to see planned vs actual.")
                    )
                    .frame(maxWidth: .infinity)
                    .padding(.top, DesignSystem.spaceXXL())
                } else {
                    ForEach(reviews, id: \.subjectID) { review in
                        SubjectReviewCard(review: review)
                    }
                }
            }
            .padding(DesignSystem.spaceXL())
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle("Review")
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

            HStack(alignment: .firstTextBaseline, spacing: DesignSystem.spaceXL()) {
                metric(value: "\(review.plannedMinutes)", label: "planned")
                metric(value: "\(review.actualMinutes)", label: "actual")
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
        let ratio = review.plannedMinutes > 0
            ? min(1.5, Double(review.actualMinutes) / Double(review.plannedMinutes))
            : 0
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

            Text(topic.gapMinutes == 0 ? "—" : (topic.gapMinutes > 0 ? "+\(topic.gapMinutes)" : "\(topic.gapMinutes)"))
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