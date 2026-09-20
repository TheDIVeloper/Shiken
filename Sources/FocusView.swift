import SwiftUI
import SwiftData

struct FocusView: View {
    @Environment(\.modelContext) private var ctx
    @Environment(FocusTimer.self) private var timer
    @Query(sort: \Subject.position) private var subjects: [Subject]
    @Query(sort: \StudySession.startedAt, order: .reverse) private var sessions: [StudySession]
    @AppStorage("focusLength") private var lengthMinutes: Int = 50
    @AppStorage("customFocusMinutes") private var customFocusMinutes: Int = 45
    @State private var selectedLength: Int = 50
    @State private var customMinutesText = "45"

    @State private var subjectID: UUID?
    @State private var topicID: UUID?

    init() {
        let storedLength = UserDefaults.standard.integer(forKey: "focusLength")
        _selectedLength = State(initialValue: [25, 50, 90].contains(storedLength) ? storedLength : -1)
        let storedCustom = UserDefaults.standard.integer(forKey: "customFocusMinutes")
        let safe = (1...240).contains(storedCustom) ? storedCustom : 45
        _customMinutesText = State(initialValue: String(safe))
    }

    private var subject: Subject? { subjects.first { $0.id == subjectID } }
    private var topic: Topic? { subject?.topics.first { $0.id == topicID } }

    private var preset: Int {
        [25, 50, 90].contains(lengthMinutes) ? lengthMinutes : -1
    }

    private var todayFocused: Int {
        sessions
            .filter { Calendar.current.isDateInToday($0.startedAt) }
            .map(\.focusedMinutes)
            .reduce(0, +)
    }

    private var todayAway: Int {
        sessions
            .filter { Calendar.current.isDateInToday($0.startedAt) }
            .map(\.awayMinutes)
            .reduce(0, +)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: DesignSystem.spaceXL()) {
                pickers
                dial
                controls
                summary
            }
            .padding(DesignSystem.spaceXL())
            .frame(maxWidth: .infinity)
        }
        .navigationTitle("Focus")
        .onAppear {
            timer.lengthMinutes = lengthMinutes
            if subjectID == nil { subjectID = subjects.first?.id }
        }
        .onChange(of: lengthMinutes) { _, newValue in
            if !timer.isActive { timer.lengthMinutes = newValue }
        }
        .onChange(of: selectedLength) { _, newValue in
            if newValue == -1 {
                lengthMinutes = customFocusMinutes
            } else {
                lengthMinutes = newValue
            }
        }
        .onChange(of: subjectID) { _, _ in topicID = nil }
        .onChange(of: timer.lastCompleted) { _, completed in
            if let completed {
                record(completed)
                timer.lastCompleted = nil
            }
        }
    }

    // MARK: Pickers

    private var pickers: some View {
        HStack(spacing: DesignSystem.spaceM()) {
            Picker("Subject", selection: $subjectID) {
                Text("General").tag(UUID?.none)
                ForEach(subjects) { candidate in
                    Text(candidate.name).tag(Optional(candidate.id))
                }
            }
            .disabled(timer.isActive)

            if let subject, !subject.topics.isEmpty {
                Picker("Topic", selection: $topicID) {
                    Text("All topics").tag(UUID?.none)
                    ForEach(subject.topics.sorted { $0.position < $1.position }) { candidate in
                        Text(candidate.title).tag(Optional(candidate.id))
                    }
                }
                .disabled(timer.isActive)
            }
        }
        .frame(maxWidth: 480)
    }

    // MARK: Dial

    private var dial: some View {
        let total = max(1, timer.lengthMinutes * 60)
        let progress = timer.isActive ? 1 - Double(timer.remainingSeconds) / Double(total) : 0

        return ZStack {
            Circle()
                .stroke(DesignSystem.hairline(), lineWidth: 10)

            Circle()
                .trim(from: 0, to: max(0, min(1, progress)))
                .stroke(
                    DesignSystem.hexColor(subject?.accentHex ?? DesignSystem.subjectAccent()),
                    style: StrokeStyle(lineWidth: 10, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))

            VStack(spacing: DesignSystem.spaceS()) {
                Text(timeString(timer.remainingSeconds))
                    .font(.system(size: DesignSystem.typeHero(), weight: .semibold))
                    .monospacedDigit()
                if timer.awaySeconds > 0 {
                    Text("\(timer.awaySeconds / 60)m away")
                        .font(.system(size: DesignSystem.typeCaption(), weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(width: 220, height: 220)
        .padding(.top, DesignSystem.spaceS())
    }

    // MARK: Controls

    private var controls: some View {
        VStack(spacing: DesignSystem.spaceM()) {
            Picker("Length", selection: $selectedLength) {
                Text("25m").tag(25)
                Text("50m").tag(50)
                Text("90m").tag(90)
                Text("Custom").tag(-1)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(maxWidth: 260)
            .disabled(timer.isActive)

            if selectedLength == -1 {
                HStack(spacing: DesignSystem.spaceS()) {
                    Text("Length")
                        .font(.system(size: DesignSystem.typeCaption(), weight: .medium))
                        .foregroundStyle(.secondary)
                    TextField("45", text: $customMinutesText)
                        .textFieldStyle(.roundedBorder)
                        .multilineTextAlignment(.center)
                        .frame(width: 70)
                        .disabled(timer.isActive)
                        .onSubmit { commitCustomMinutes() }
                        .onChange(of: customMinutesText) { _, _ in
                            commitCustomMinutes()
                        }
                    Text("minutes")
                        .font(.system(size: DesignSystem.typeCaption(), weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }

            HStack(spacing: DesignSystem.spaceM()) {
                switch timer.phase {
                case .idle:
                    Button {
                        timer.start()
                    } label: {
                        Label("Start focus", systemImage: "play.fill")
                            .frame(minWidth: 130)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)

                case .running:
                    Button {
                        timer.pause()
                    } label: {
                        Label("Pause", systemImage: "pause.fill")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)

                    Button(role: .destructive) {
                        stopAndRecord()
                    } label: {
                        Label("Stop", systemImage: "stop.fill")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)

                case .paused:
                    Button {
                        timer.resume()
                    } label: {
                        Label("Resume", systemImage: "play.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)

                    Button(role: .destructive) {
                        stopAndRecord()
                    } label: {
                        Label("Stop", systemImage: "stop.fill")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                }
            }
        }
    }

    private var summary: some View {
        HStack(spacing: DesignSystem.spaceXL()) {
            stat(value: "\(todayFocused)", label: "min today")
            stat(value: "\(todayAway)", label: "min away")
            stat(value: "\(sessions.filter { Calendar.current.isDateInToday($0.startedAt) }.count)", label: "sessions")
        }
        .padding(.top, DesignSystem.spaceS())
    }

    private func stat(value: String, label: String) -> some View {
        VStack(spacing: DesignSystem.spaceXS()) {
            Text(value)
                .font(.system(size: DesignSystem.typeDisplay(), weight: .semibold))
                .monospacedDigit()
            Text(label)
                .font(.system(size: DesignSystem.typeCaption(), weight: .medium))
                .foregroundStyle(.secondary)
        }
        .frame(minWidth: 80)
    }

    // MARK: Helpers

    private func timeString(_ seconds: Int) -> String {
        String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }

    private func commitCustomMinutes() {
        let raw = Int(customMinutesText.trimmingCharacters(in: .whitespaces)) ?? 0
        let clamped = min(240, max(1, raw))
        customMinutesText = String(clamped)
        customFocusMinutes = clamped
        lengthMinutes = clamped
    }

    private func stopAndRecord() {
        if let completed = timer.stop() {
            record(completed)
        }
    }

    private func record(_ completed: CompletedSession) {
        let focusedMinutes = Int((Double(completed.focusedSeconds) / 60).rounded())
        let awayMinutes = Int((Double(completed.awaySeconds) / 60).rounded())
        guard focusedMinutes > 0 || awayMinutes > 0 else { return }
        let session = StudySession(
            startedAt: completed.startedAt,
            focusedMinutes: focusedMinutes,
            awayMinutes: awayMinutes,
            subject: subject,
            topic: topic
        )
        ctx.insert(session)
        try? ctx.save()
    }
}