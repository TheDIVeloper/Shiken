import SwiftUI

struct SettingsView: View {
    @AppStorage("focusLength") private var focusLength: Int = 50
    @AppStorage("defaultDailyMinutes") private var defaultDailyMinutes: Int = 60
    @AppStorage("trackInterruptions") private var trackInterruptions = true

    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1.0"
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

                Stepper("Default daily target \(defaultDailyMinutes) min", value: $defaultDailyMinutes, in: 15...240, step: 15)
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
                LabeledContent("Version", value: version)
            } header: {
                Text("About")
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Settings")
    }
}