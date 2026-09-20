import SwiftUI
import SwiftData

struct SessionLogView: View {
    @Environment(\.modelContext) private var ctx
    @Query(sort: \StudySession.startedAt, order: .reverse) private var sessions: [StudySession]

    var body: some View {
        List {
            ForEach(sessions) { session in
                SessionRow(session: session)
            }
            .onDelete(perform: delete)
        }
        .overlay {
            if sessions.isEmpty {
                ContentUnavailableView(
                    "No sessions yet",
                    systemImage: "timer",
                    description: Text("Your focus sessions land here once you run the timer.")
                )
            }
        }
        .navigationTitle("Sessions")
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