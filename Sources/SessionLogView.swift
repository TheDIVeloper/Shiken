import SwiftUI
import SwiftData

struct SessionLogView: View {
    @Environment(\.modelContext) private var ctx
    @Query(sort: \StudySession.startedAt, order: .reverse) private var sessions: [StudySession]

    var body: some View {
        Group {
            if sessions.isEmpty {
                // Not an overlay on the List: a floating panel gets clipped by the
                // list's own row backgrounds and edges, so the card looks cut off.
                ScrollView {
                    emptyState
                        .padding(DesignSystem.spaceXL())
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                List {
                    ForEach(sessions) { session in
                        SessionRow(session: session)
                    }
                    .onDelete(perform: delete)
                }
            }
        }
        .navigationTitle("Sessions")
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: DesignSystem.spaceXS()) {
            Text("No sessions yet")
                .font(.system(size: DesignSystem.typeTitle(), weight: .semibold))
            Text("Your focus sessions land here once you run the timer.")
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

    private func delete(at offsets: IndexSet) {
        for index in offsets {
            ctx.delete(sessions[index])
        }
        try? ctx.save()
    }
}

private struct SessionRow: View {
    let session: StudySession

    var body: some View {
        HStack(spacing: DesignSystem.spaceM()) {
            Circle()
                .fill(DesignSystem.hexColor(session.subject?.accentHex ?? "9A8C98"))
                .frame(width: 8, height: 8)

            VStack(alignment: .leading, spacing: 2) {
                Text(session.subject?.name ?? "General")
                    .font(.system(size: DesignSystem.typeBody(), weight: .medium))
                HStack(spacing: DesignSystem.spaceXS()) {
                    Text(session.startedAt.formatted(date: .abbreviated, time: .shortened))
                    if let topic = session.topic, !topic.title.isEmpty {
                        Text("· \(topic.title)")
                    }
                }
                .font(.system(size: DesignSystem.typeCaption()))
                .foregroundStyle(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text("\(session.focusedMinutes)m")
                    .font(.system(size: DesignSystem.typeBody(), weight: .semibold))
                    .monospacedDigit()
                if session.awayMinutes > 0 {
                    Text("\(session.awayMinutes)m away")
                        .font(.system(size: DesignSystem.typeCaption()))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 2)
    }
}