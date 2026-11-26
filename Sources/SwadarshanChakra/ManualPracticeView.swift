import SwiftUI
import MeditationCore

/// Records a completed practice elsewhere. Only total time is entered; per-form times stay unknown.
struct ManualPracticeView: View {
    @ObservedObject var model: SessionModel
    var onSave: (PracticeRecord) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var start: Date
    @State private var cyclesText = "1"
    @State private var minutesText = ""
    @State private var secondsText = "0"
    @State private var saveError: String?

    init(model: SessionModel, onSave: @escaping (PracticeRecord) -> Void) {
        self.model = model
        self.onSave = onSave
        _start = State(initialValue: model.currentDate)
    }

    private var cycles: Int? { SessionConfiguration.integer(cyclesText, in: SessionConfiguration.cycleRange) }
    private var minutes: Int? { SessionConfiguration.integer(minutesText, in: 0...1440) }
    private var seconds: Int? { SessionConfiguration.integer(secondsText, in: 0...59) }
    private var total: Int? {
        guard let minutes, let seconds, (1...86_400).contains(minutes * 60 + seconds) else { return nil }
        return minutes * 60 + seconds
    }
    private var valid: Bool { cycles != nil && total != nil && start <= model.currentDate }
    private var validation: String? {
        if cycles == nil { return "Enter 1–108 whole cycles." }
        if seconds == nil { return "Enter whole seconds from 0 to 59." }
        if !minutesText.isEmpty && total == nil { return "Enter a total time from 1 second to 24 hours." }
        return nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Add practice").font(.system(size: 30, weight: .regular, design: .serif))
                Text("Keep a record of the chakra you spun elsewhere.")
                    .font(.system(size: 13)).foregroundColor(Palette.muted)
            }
            VStack(alignment: .leading, spacing: 8) {
                Text("When did you start?").font(.system(size: 13, weight: .medium))
                DatePicker("When did you start?", selection: $start,
                           in: Date(timeIntervalSince1970: 0)...model.currentDate,
                           displayedComponents: [.date, .hourAndMinute])
                    .labelsHidden().datePickerStyle(.field)
                    .accessibilityIdentifier("manual-start")
            }
            HStack(alignment: .bottom, spacing: 20) {
                numberField("Completed cycles", value: $cyclesText, identifier: "manual-cycles")
                Text("1 cycle = 5 steps").font(.system(size: 12)).foregroundColor(Palette.muted)
                    .padding(.bottom, 13)
            }
            VStack(alignment: .leading, spacing: 10) {
                Text("Total practice time").font(.system(size: 13, weight: .medium))
                HStack(spacing: 16) {
                    numberField("Minutes", value: $minutesText, identifier: "manual-minutes")
                    numberField("Seconds", value: $secondsText, identifier: "manual-seconds")
                }
            }
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Average per step").font(.system(size: 13, weight: .medium))
                    Spacer()
                    Text(averageText).font(.system(size: 22, weight: .regular, design: .serif))
                        .monospacedDigit().foregroundColor(Palette.gold)
                        .accessibilityIdentifier("manual-average")
                }
                Text("Total time ÷ (cycles × 5). Individual form times aren’t recorded.")
                    .font(.system(size: 12)).foregroundColor(Palette.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(16).background(Palette.gold.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
            if let error = saveError ?? validation {
                Text(error).font(.system(size: 12)).foregroundColor(Palette.error)
                    .fixedSize(horizontal: false, vertical: true).accessibilityIdentifier("manual-error")
            }
            HStack(spacing: 12) {
                Spacer()
                Button("Cancel") { dismiss() }.buttonStyle(QuietButtonStyle()).keyboardShortcut(.cancelAction)
                Button("Save practice", action: save).buttonStyle(GoldButtonStyle())
                    .keyboardShortcut(.defaultAction).disabled(!valid)
                    .accessibilityIdentifier("save-manual-practice")
            }
        }
        .padding(28).frame(width: 520)
        .foregroundColor(Palette.ivory).background(Palette.panel).preferredColorScheme(.dark)
    }

    private var averageText: String {
        guard let cycles, let total else { return "—" }
        let average = Double(total) / Double(cycles * Stage.all.count)
        return average < 1 ? "<1 sec" : TimeText.elapsed(average.rounded())
    }

    private func numberField(_ title: String, value: Binding<String>, identifier: String) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title).font(.system(size: 12)).foregroundColor(Palette.muted)
            TextField(title, text: value).textFieldStyle(.roundedBorder)
                .font(.system(size: 18)).monospacedDigit()
                .accessibilityLabel(title).accessibilityIdentifier(identifier)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    private func save() {
        guard valid, let cycles, let total else { return }
        do {
            let record = try model.addPractice(start: start, cycles: cycles, seconds: total)
            onSave(record)
            dismiss()
        } catch { saveError = error.localizedDescription }
    }
}
