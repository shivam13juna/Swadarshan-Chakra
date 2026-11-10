import SwiftUI
import MeditationCore

struct SetupPanel: View {
    @ObservedObject var model: SessionModel
    let compact: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 18 : 24) {
            VStack(alignment: .leading, spacing: 12) {
                Eyebrow(text: "YOUR PRACTICE")
                Text("Your quiet moment.")
                    .font(.system(size: compact ? 28 : 35, weight: .regular, design: .serif))
                    .foregroundColor(Palette.ivory).fixedSize(horizontal: false, vertical: true)
                Text("Five forms. One complete cycle.")
                    .font(.system(size: 13)).foregroundColor(Palette.muted)
            }

            Rectangle().fill(Palette.gold.opacity(0.17)).frame(height: 1)

            VStack(spacing: compact ? 16 : 22) {
                NumberInput(title: "Cycles", hint: "1–108 rounds", value: $model.cyclesText,
                            range: SessionConfiguration.cycleRange, fallback: 1, valid: model.cyclesValid,
                            error: "Enter a whole number from 1 to 108.", identifier: "cycles-input")
                StepDurationInput(model: model)
            }

            HStack(alignment: .top, spacing: 0) {
                derivedValue("PER CYCLE", value: model.configuration.map { TimeText.duration($0.secondsPerCycle) } ?? "—")
                Spacer(minLength: 8)
                Rectangle().fill(Palette.ivory.opacity(0.12)).frame(width: 1, height: 38)
                Spacer(minLength: 18)
                derivedValue("PLANNED TIME", value: model.configuration.map { TimeText.duration($0.plannedSeconds) } ?? "—")
            }
            .padding(14)
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

                Text("Each step gets this full time. Space moves to the next step early.")
                    .font(.system(size: 11)).foregroundColor(Palette.muted)
                    .lineSpacing(3).fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(compact ? 22 : 28)
        .background {
            RoundedRectangle(cornerRadius: 17)
                .fill(LinearGradient(colors: [Palette.panel.opacity(0.85), Palette.panel.opacity(0.45)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                .overlay(RoundedRectangle(cornerRadius: 17).stroke(Palette.gold.opacity(0.17), lineWidth: 0.7))
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

private struct StepDurationInput: View {
    @ObservedObject var model: SessionModel
    @FocusState private var focused: Component?
    private enum Component { case minutes, seconds }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Time per step").font(.system(size: 13, weight: .medium)).foregroundColor(Palette.ivory)
                    Text("For each form").font(.system(size: 11)).foregroundColor(Palette.muted)
                }
                Spacer(minLength: 0)
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
            if !model.durationValid {
                Text(error).font(.system(size: 11)).foregroundColor(Palette.error)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("step-duration-error")
            }
        }
    }

    private func field(_ value: Binding<String>, unit: String, component: Component) -> some View {
        VStack(spacing: 1) {
            TextField(unit, text: value)
                .textFieldStyle(.plain).multilineTextAlignment(.center)
                .font(.system(size: 20, weight: .regular, design: .rounded)).monospacedDigit()
                .foregroundColor(Palette.ivory).frame(width: 37, height: 26)
                .focused($focused, equals: component)
                .accessibilityLabel(component == .minutes ? "Minutes per step" : "Additional seconds per step")
                .accessibilityIdentifier(component == .minutes ? "minutes-input" : "seconds-input")
            Text(unit).font(.system(size: 9)).foregroundColor(Palette.muted).accessibilityHidden(true)
        }
    }

    private var error: String {
        if !model.minutesValid { return "Enter whole minutes from 0 to 120." }
        if !model.secondsValid { return "Enter whole seconds from 0 to 59." }
        return "Choose 1 second to 120 minutes per step."
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
