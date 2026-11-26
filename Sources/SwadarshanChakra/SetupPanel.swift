import SwiftUI
import MeditationCore

extension TimingMode {
    var title: String {
        switch self {
        case .perStep: return "Time per step"
        case .total: return "Total time"
        case .freestyle: return "Freestyle"
        }
    }
}

/// Selects the whole value of the field that just gained focus, by a click or Tab, so typing replaces it.
/// A click puts the insertion point under the pointer while AppKit tracks the mouse, so the selection
/// waits for that to finish: a timer in the default run-loop mode doesn't fire during the tracking.
@MainActor private func selectWholeValueOfFocusedField() {
    RunLoop.main.add(Timer(timeInterval: 0, repeats: false) { _ in
        MainActor.assumeIsolated {
            guard let editor = NSApp.keyWindow?.firstResponder as? NSTextView, editor.isFieldEditor else { return }
            editor.selectAll(nil)
        }
    }, forMode: .default)
}

struct SetupPanel: View {
    @ObservedObject var model: SessionModel
    let compact: Bool

    var body: some View {
        // Keep both ways of recording practice visible, including in the smallest window, 1024 × 640.
        VStack(alignment: .leading, spacing: compact ? 8 : 18) {
            VStack(alignment: .leading, spacing: compact ? 6 : 10) {
                Eyebrow(text: "YOUR PRACTICE")
                Text("Your quiet moment.")
                    .font(.system(size: compact ? 26 : 35, weight: .regular, design: .serif))
                    .foregroundColor(Palette.ivory).fixedSize(horizontal: false, vertical: true)
                Text("Five forms. One complete cycle.")
                    .font(.system(size: 13)).foregroundColor(Palette.muted)
                Button { model.addingPractice = true } label: {
                    Text("Add spinned cycles manually")
                        .font(.system(size: compact ? 13 : 14, weight: .semibold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(GoldButtonStyle())
                .help("Record completed cycles and time practiced elsewhere")
                .accessibilityIdentifier("add-practice")
                .padding(.top, 4)
            }

            Rectangle().fill(Palette.gold.opacity(0.17)).frame(height: 1)

            VStack(spacing: compact ? 14 : 22) {
                NumberInput(title: "Cycles", hint: "1–108 rounds", value: $model.cyclesText,
                            range: SessionConfiguration.cycleRange, fallback: 1, valid: model.cyclesValid,
                            error: "Enter a whole number from 1 to 108.", identifier: "cycles-input")
                DurationInput(model: model)
            }

            summary
                .padding(compact ? 8 : 14)
                .background(Palette.background.opacity(0.65), in: RoundedRectangle(cornerRadius: 9))

            VStack(spacing: 12) {
                Button(action: model.begin) {
                    HStack(spacing: 10) {
                        Image(systemName: "play.fill").font(.system(size: 10))
                        Text("Begin meditation")
                        Spacer(minLength: 0)
                        Image(systemName: "return").font(.system(size: 12)).opacity(0.55)
                    }.frame(maxWidth: .infinity)
                }
                .buttonStyle(GoldButtonStyle())
                .keyboardShortcut(.return, modifiers: [])
                .disabled(model.configuration == nil)
                .accessibilityIdentifier("begin-meditation")

                Text(note)
                    .font(.system(size: 11)).foregroundColor(Palette.muted)
                    .lineSpacing(3).fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(compact ? 18 : 24)
        .background {
            RoundedRectangle(cornerRadius: 17)
                .fill(LinearGradient(colors: [Palette.panel.opacity(0.85), Palette.panel.opacity(0.45)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                .overlay(RoundedRectangle(cornerRadius: 17).stroke(Palette.gold.opacity(0.17), lineWidth: 0.7))
        }
    }

    private var note: String {
        switch model.timingMode {
        case .perStep: return "Each step gets this full time. Space moves to the next step early."
        case .total: return "This time is shared equally by every step. Space moves to the next step early."
        case .freestyle: return "No timer: stay with each step as long as you like. Space moves to the next step."
        }
    }

    /// The two amounts the practitioner did not enter, calculated from the one they did. Freestyle
    /// has no time to calculate, only steps.
    private var summary: some View {
        let configuration = model.configuration
        let values: [(String, String?)]
        switch model.timingMode {
        case .perStep:
            values = [("PER CYCLE", configuration.map { TimeText.duration($0.secondsPerCycle) }),
                      ("PLANNED TIME", configuration.map { TimeText.duration($0.plannedSeconds) })]
        case .total:
            values = [("PER STEP", configuration.map { TimeText.approximateDuration($0.secondsPerStage) }),
                      ("PER CYCLE", configuration.map { TimeText.approximateDuration($0.secondsPerCycle) })]
        case .freestyle:
            values = [("PER CYCLE", "\(Stage.all.count) steps"),
                      ("IN ALL", configuration.map { "\($0.stepCount) steps" })]
        }
        return HStack(alignment: .top, spacing: 0) {
            derivedValue(values[0].0, value: values[0].1 ?? "—")
            Spacer(minLength: 8)
            Rectangle().fill(Palette.ivory.opacity(0.12)).frame(width: 1, height: 38)
            Spacer(minLength: 18)
            derivedValue(values[1].0, value: values[1].1 ?? "—")
        }
    }

    private func derivedValue(_ title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title).font(.system(size: 9, weight: .medium)).tracking(1.4).foregroundColor(Palette.muted)
            Text(value).font(.system(size: 20, weight: .light, design: .rounded))
                .monospacedDigit().foregroundColor(Palette.ivory).lineLimit(2).minimumScaleFactor(0.65)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct DurationInput: View {
    @ObservedObject var model: SessionModel
    @FocusState private var focused: Component?
    private enum Component { case minutes, seconds }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 5) {
                    modeMenu
                    Text(hint).font(.system(size: 11)).foregroundColor(Palette.muted)
                }
                Spacer(minLength: 0)
                // Freestyle has no time to enter; the fields keep theirs for when a timer is chosen again.
                if model.timingMode != .freestyle {
                    HStack(spacing: 7) {
                        field($model.minutesText, unit: "min", component: .minutes)
                        Text(":").font(.system(size: 18, weight: .light)).foregroundColor(Palette.muted)
                            .padding(.bottom, 13).accessibilityHidden(true)
                        field($model.secondsText, unit: "sec", component: .seconds)
                    }
                    .padding(.horizontal, 9).padding(.vertical, 5)
                    .background(Palette.background.opacity(0.6), in: RoundedRectangle(cornerRadius: 7))
                    .overlay(RoundedRectangle(cornerRadius: 7)
                        .stroke(!model.durationValid ? Palette.error : (focused != nil ? Palette.gold : Palette.ivory.opacity(0.16)), lineWidth: 1))
                }
            }
            if let problem = model.durationProblem {
                Text(problem).font(.system(size: 11)).foregroundColor(Palette.error)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("step-duration-error")
            }
            if model.timingMode != .freestyle {
                Toggle(isOn: $model.showsCountdownBar) {
                    Text("Show countdown bar").font(.system(size: 11)).foregroundColor(Palette.muted)
                }
                .toggleStyle(.checkbox).controlSize(.small).tint(Palette.gold)
                .help("A thin bar along the bottom of each step shows how much of its time is left. Untick to hide it.")
                .accessibilityIdentifier("show-countdown-bar")
                .padding(.top, 2)
            }
        }
        .onChange(of: focused) { if $0 != nil { selectWholeValueOfFocusedField() } }
    }

    /// A drop-down in place of the field's title: time per step, a total for all cycles, or no timer.
    private var modeMenu: some View {
        Menu {
            Picker("Set time", selection: Binding(get: { model.timingMode }, set: { model.setTimingMode($0) })) {
                ForEach(TimingMode.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            .pickerStyle(.inline).labelsHidden()
        } label: {
            HStack(spacing: 5) {
                Text(model.timingMode.title).font(.system(size: 13, weight: .medium)).foregroundColor(Palette.ivory)
                Image(systemName: "chevron.down").font(.system(size: 9, weight: .semibold)).foregroundColor(Palette.gold)
            }
            .contentShape(Rectangle())
        }
        .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
        .help("Set the time for each step, a total shared by every step, or no timer (freestyle)")
        .accessibilityLabel("Set time: \(model.timingMode.title)")
        .accessibilityIdentifier("timing-mode")
    }

    private var hint: String {
        switch model.timingMode {
        case .perStep: return "For each form"
        case .freestyle: return "No timer, at your own pace"
        case .total:
            guard let cycles = model.cycles else { return "For all cycles" }
            return cycles == 1 ? "For 1 cycle" : "For all \(cycles) cycles"
        }
    }

    private func field(_ value: Binding<String>, unit: String, component: Component) -> some View {
        let perStep = model.timingMode == .perStep
        return VStack(spacing: 1) {
            TextField(unit, text: value)
                .textFieldStyle(.plain).multilineTextAlignment(.center)
                .font(.system(size: 20, weight: .regular, design: .rounded)).monospacedDigit()
                .foregroundColor(Palette.ivory).frame(width: 37, height: 26)
                .focused($focused, equals: component)
                .accessibilityLabel(component == .minutes
                    ? (perStep ? "Minutes per step" : "Total minutes")
                    : (perStep ? "Additional seconds per step" : "Additional total seconds"))
                .accessibilityIdentifier(component == .minutes ? "minutes-input" : "seconds-input")
            Text(unit).font(.system(size: 9)).foregroundColor(Palette.muted).accessibilityHidden(true)
        }
    }
}

private struct NumberInput: View {
    let title: String
    let hint: String
    @Binding var value: String
    let range: ClosedRange<Int>
    let fallback: Int
    let valid: Bool
    let error: String
    let identifier: String
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(title).font(.system(size: 13, weight: .medium)).foregroundColor(Palette.ivory)
                    Text(hint).font(.system(size: 11)).foregroundColor(Palette.muted)
                }
                Spacer(minLength: 0)
                HStack(spacing: 0) {
                    adjustmentButton("minus", by: -1)
                    TextField(title, text: $value)
                        .textFieldStyle(.plain).multilineTextAlignment(.center)
                        .font(.system(size: 18, weight: .regular, design: .rounded)).monospacedDigit()
                        .foregroundColor(Palette.ivory).frame(width: 37, height: 38)
                        .focused($focused).accessibilityLabel(title)
                        .accessibilityIdentifier(identifier)
                    adjustmentButton("plus", by: 1)
                }
                .background(Palette.background.opacity(0.6), in: RoundedRectangle(cornerRadius: 7))
                .overlay(RoundedRectangle(cornerRadius: 7)
                    .stroke(!valid ? Palette.error : (focused ? Palette.gold : Palette.ivory.opacity(0.16)), lineWidth: 1))
            }
            if !valid {
                Text(error).font(.system(size: 11)).foregroundColor(Palette.error)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("\(identifier)-error")
            }
        }
        .onChange(of: focused) { if $0 { selectWholeValueOfFocusedField() } }
    }

    private func adjustmentButton(_ symbol: String, by delta: Int) -> some View {
        Button {
            let current = SessionConfiguration.integer(value, in: range) ?? fallback
            value = String(min(range.upperBound, max(range.lowerBound, current + delta)))
        } label: {
            Image(systemName: symbol).font(.system(size: 9, weight: .medium))
                .foregroundColor(Palette.gold).frame(width: 25, height: 38).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(delta > 0 ? "Increase" : "Decrease") \(title.lowercased())")
    }
}
