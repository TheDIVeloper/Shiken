import SwiftUI
import SwiftData

struct SettingsView: View {
    @AppStorage("focusLength") private var focusLength: Int = 50
    @AppStorage("defaultDailyMinutes") private var defaultDailyMinutes: Int = 60
    @AppStorage("trackInterruptions") private var trackInterruptions = true

    @AppStorage("totalDailyMinutes") private var totalDailyMinutes: Int = Timetable.defaultTotalDailyMinutes
    @State private var reminders = ReminderScheduler()
    @State private var reminderDenied = false
    @Environment(\.modelContext) private var ctx
    @Query private var subjects: [Subject]

    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1.0"
    }

    /// Re-derives daily targets from the timetable, but only for subjects whose
    /// number is still a suggestion. A subject the user has set by hand is left
    /// alone, because their number was a decision, not a default.
    private func applyDerivedMinutes(to total: Int) {
        let derived = Timetable.derivation(
            subjects: subjects.map {
                SubjectPlan(id: $0.id, periodsPerWeek: $0.periodsPerWeek, isEnrichment: $0.isEnrichment)
            },
            totalDailyMinutes: total
        )
        for subject in subjects where subject.dailyMinutesIsDerived {
            if let minutes = derived[subject.id] {
                subject.dailyMinutes = minutes
            }
        }
        try? ctx.save()
    }

    private func setReminders(_ enabled: Bool) {
        reminders.isEnabled = enabled
        if enabled {
            Task {
                let granted = await reminders.requestAuthorization()
                await MainActor.run {
                    // Never claim permission we do not have: the toggle snaps back
                    // and explains why rather than silently doing nothing.
                    if granted {
                        reminderDenied = false
                        rescheduleReminder()
                    } else {
                        reminders.isEnabled = false
                        reminderDenied = true
                    }
                }
            }
        } else {
            reminders.cancelAll()
        }
    }

    private func rescheduleReminder() {
        let summary = ReminderScheduler.summary(from: OverviewEngine.overview(subjects: subjects.map(\.planInput)))
        reminders.schedule(for: summary)
    }

    var body: some View {
        Form {
            Section("Study defaults") {
                Picker("Default focus length", selection: $focusLength) {
                    Text("25m").tag(25)
                    Text("50m").tag(50)
                    Text("90m").tag(90)
                }
                .pickerStyle(.segmented)

                Stepper("Default daily target \(defaultDailyMinutes) min", value: $defaultDailyMinutes, in: 15...720, step: 15)
                .onChange(of: defaultDailyMinutes) { _, new in
                    applyDerivedMinutes(to: new)
                }

                Stepper("Total daily study \(totalDailyMinutes) min", value: $totalDailyMinutes, in: 60...720, step: 30)
                Text("How long you revise for in total on a normal day, added across every subject. Shiken splits this between your assessed subjects by how many lessons each has, so raising it raises everyone's suggestion.")
                    .font(.system(size: DesignSystem.typeCaption()))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Text("Any subject where you've set the daily target yourself is left alone.")
                    .font(.system(size: DesignSystem.typeCaption()))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Section {
                Toggle("Track away time", isOn: $trackInterruptions)
                Text("When off, time away from the app during a session isn't counted against you.")
                    .font(.system(size: DesignSystem.typeCaption()))
                    .foregroundStyle(.secondary)
            } header: {
                Text("Focus")
            }

            Section {
                Toggle("Daily reminder", isOn: Binding(
                    get: { reminders.isEnabled },
                    set: { new in setReminders(new) }
                ))
                .disabled(reminderDenied)

                if reminders.isEnabled && !reminderDenied {
                    DatePicker(
                        "Time",
                        selection: Binding(
                            get: { reminders.time },
                            set: { new in
                                reminders.time = new
                                rescheduleReminder()
                            }
                        ),
                        displayedComponents: .hourAndMinute
                    )
                }

                if reminderDenied {
                    Label("Shiken doesn't have permission to send notifications. Turn it on in System Settings › Notifications.", systemImage: "exclamationmark.triangle")
                        .font(.system(size: DesignSystem.typeCaption()))
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Reminders")
            } footer: {
                Text("Shiken will message you once a day at the time you pick, naming the biggest thing planned for that day. Nothing before you turn this on, and never a message about what you didn't finish.")
            }

            Section {
                LabeledContent("Version", value: version)
            } header: {
                Text("About")
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Settings")
        .task {
            reminderDenied = await reminders.authorizationStatus() == .denied
            rescheduleReminder()
        }
    }
}