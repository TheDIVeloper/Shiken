import SwiftUI
import SwiftData

struct SubjectRow: View {
    let subject: Subject

    var body: some View {
        HStack(spacing: DesignSystem.spaceM()) {
            Circle()
                .fill(DesignSystem.hexColor(subject.accentHex))
                .frame(width: 8, height: 8)

            VStack(alignment: .leading, spacing: 2) {
                Text(subject.name)
                    .font(.system(size: DesignSystem.typeBody(), weight: .medium))
                if let exam = subject.examDate {
                    Text(examCountdown(exam))
                        .font(.system(size: DesignSystem.typeCaption()))
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 2)
    }

    private func examCountdown(_ exam: Date) -> String {
        let days = Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: .now), to: Calendar.current.startOfDay(for: exam)).day ?? 0
        if days < 0 { return "exam passed" }
        if days == 0 { return "exam today" }
        if days == 1 { return "exam tomorrow" }
        return "\(days) days to exam"
    }
}

struct SubjectEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var ctx
    var onSave: (UUID) -> Void

    @State private var name: String = ""
    @State private var examDate: Date = Calendar.current.date(byAdding: .day, value: 60, to: .now) ?? .now
    @State private var dailyMinutes: Int = 60
    @State private var accentHex: String = DesignSystem.subjectAccent()

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    TextField("Subject name", text: $name)
                }
                Section("Exam") {
                    DatePicker("Exam date", selection: $examDate, displayedComponents: .date)
                    Stepper("Daily target \(dailyMinutes) min", value: $dailyMinutes, in: 15...240, step: 15)
                }
                Section("Accent") {
                    HStack(spacing: DesignSystem.spaceM()) {
                        ForEach(DesignSystem.accentPalette, id: \.self) { hex in
                            Button {
                                accentHex = hex
                            } label: {
                                ZStack {
                                    Circle()
                                        .fill(DesignSystem.hexColor(hex))
                                        .frame(width: 22, height: 22)
                                    if accentHex == hex {
                                        Image(systemName: "checkmark")
                                            .font(.system(size: 11, weight: .bold))
                                            .foregroundStyle(.white)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                        }
                        Spacer()
                    }
                }
            }
            .formStyle(.grouped)

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Add subject") { save() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding()
        }
        .frame(width: 400)
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        let position = (try? ctx.fetchCount(FetchDescriptor<Subject>())) ?? 0
        let subject = Subject(name: trimmed, examDate: examDate, accentHex: accentHex, position: position)
        subject.dailyMinutes = dailyMinutes
        ctx.insert(subject)
        try? ctx.save()
        onSave(subject.id)
        dismiss()
    }
}