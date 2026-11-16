import SwiftUI
import MeditationCore

/// How the practice's time was spent, beside the completion screen's circle: for each cycle, the time
/// practiced in each of its five steps, the average per step, and the cycle's total, then all cycles
/// together. Practiced time includes pauses spent with a step; the cards and time away never count.
struct TimeSummaryPanel: View {
    let engine: SessionEngine
    let compact: Bool

    private var rowHeight: CGFloat { compact ? 24 : 27 }

    var body: some View {
        let cycles = engine.stepSeconds
        VStack(alignment: .leading, spacing: compact ? 12 : 18) {
            VStack(alignment: .leading, spacing: compact ? 8 : 10) {
                Eyebrow(text: "YOUR TIME")
                Text("How you spent it.")
                    .font(.system(size: compact ? 26 : 32, weight: .regular, design: .serif))
                    .foregroundColor(Palette.ivory).fixedSize(horizontal: false, vertical: true)
                Text("The time practiced in each step, with each cycle's total and its average per step. Pauses with a step count; the cards and time away don't.")
                    .font(.system(size: compact ? 11 : 12)).foregroundColor(Palette.muted)
                    .lineSpacing(3).fixedSize(horizontal: false, vertical: true)
            }

            Rectangle().fill(Palette.gold.opacity(0.17)).frame(height: 1)

            VStack(spacing: 0) {
                header
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(cycles.indices, id: \.self) { index in
                            row(String(format: "%02d", index + 1), cycles[index], average: Double(Stage.all.count))
                                .accessibilityLabel(spoken("Cycle \(index + 1)", cycles[index], steps: Stage.all.count))
                        }
                    }
                }
                .frame(maxHeight: CGFloat(cycles.count) * rowHeight)
                if cycles.count > 1 {
                    let together = (0..<Stage.all.count).map { step in cycles.map { $0[step] }.reduce(0, +) }
                    Rectangle().fill(Palette.gold.opacity(0.22)).frame(height: 0.7).padding(.top, 4)
                    row("ALL", together, average: Double(Stage.all.count * cycles.count), emphasis: true)
                        .accessibilityLabel(spoken("All \(cycles.count) cycles", together, steps: Stage.all.count * cycles.count))
                }
            }
        }
        .padding(compact ? 22 : 28)
        .background {
            RoundedRectangle(cornerRadius: 17)
                .fill(LinearGradient(colors: [Palette.panel.opacity(0.85), Palette.panel.opacity(0.45)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                .overlay(RoundedRectangle(cornerRadius: 17).stroke(Palette.gold.opacity(0.17), lineWidth: 0.7))
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Your time")
        .accessibilityIdentifier("time-summary")
    }

    /// Cycle, the five steps, the average per step, and the cycle's total, in shares of the width. The
    /// wide panel gives the last two their titles on one line; the compact one sets them on two.
    private var shares: [CGFloat] {
        compact ? [0.1, 0.104, 0.104, 0.104, 0.104, 0.104, 0.19, 0.19]
                : [0.075, 0.093, 0.093, 0.093, 0.093, 0.093, 0.23, 0.23]
    }
    private var titles: [String] {
        ["CYCLE", "01", "02", "03", "04", "05"]
            + (compact ? ["AVERAGE\nPER STEP", "TOTAL\nTHIS CYCLE"] : ["AVERAGE PER STEP", "TOTAL THIS CYCLE"])
    }
    private static let columnHelp = ["The cycle"] + Stage.all.map { "Step \($0.id): \($0.label)" }
        + ["This cycle's average time per step", "The time practiced in this cycle, in all"]

    /// Every title sits on the row below it.
    private var header: some View {
        GeometryReader { geometry in
            HStack(alignment: .bottom, spacing: 0) {
                ForEach(titles.indices, id: \.self) { column in
                    Text(titles[column])
                        .font(.system(size: 9, weight: .medium)).tracking(column == 0 || column > 5 ? 0.6 : 1.1)
                        .lineSpacing(2)
                        .multilineTextAlignment(column == 0 ? .leading : .trailing)
                        .foregroundColor(column == 0 || column > 5 ? Palette.muted : Palette.gold.opacity(0.85))
                        .lineLimit(compact && column > 5 ? 2 : 1).minimumScaleFactor(0.7)
                        // A little room before each title, so neighbours never touch.
                        .frame(maxWidth: geometry.size.width * shares[column] - (column == 0 ? 0 : 6),
                               alignment: column == 0 ? .leading : .trailing)
                        .frame(width: geometry.size.width * shares[column], alignment: column == 0 ? .leading : .trailing)
                        .help(Self.columnHelp[column])
                }
            }
            .frame(maxHeight: .infinity, alignment: .bottom)
            .padding(.bottom, compact ? 5 : 6)
        }
        .frame(height: rowHeight + (compact ? 14 : 4))
        .accessibilityHidden(true)
    }

    private func row(_ name: String, _ seconds: [TimeInterval], average count: Double, emphasis: Bool = false) -> some View {
        let total = seconds.reduce(0, +)
        let values = seconds.map(Self.clock) + [Self.clock(total / count), Self.clock(total)]
        return GeometryReader { geometry in
            HStack(spacing: 0) {
                Text(name)
                    .font(.system(size: emphasis ? 9 : (compact ? 11 : 12), weight: .medium)).tracking(emphasis ? 0.6 : 0)
                    .monospacedDigit().foregroundColor(Palette.muted)
                    .frame(width: geometry.size.width * shares[0], alignment: .leading)
                // The steps, then the average per step in gold, then the cycle's total.
                ForEach(values.indices, id: \.self) { index in
                    Text(values[index])
                        .font(.system(size: compact ? 11 : 12, weight: index >= 5 || emphasis ? .medium : .regular))
                        .monospacedDigit()
                        .foregroundColor(index == 5 ? Palette.gold : Palette.ivory.opacity(index == 6 ? 1 : 0.86))
                        .lineLimit(1).minimumScaleFactor(0.75)
                        .frame(width: geometry.size.width * shares[index + 1], alignment: .trailing)
                }
            }
            .frame(maxHeight: .infinity)
        }
        .frame(height: rowHeight)
        .overlay(alignment: .bottom) {
            if !emphasis { Rectangle().fill(Palette.ivory.opacity(0.06)).frame(height: 0.5) }
        }
        .accessibilityElement(children: .ignore)
    }

    /// Like the practiced time, without the leading zero of the minutes ("1:05", "0:38"), so the
    /// numbers stay clear of each other in narrow columns.
    private static func clock(_ seconds: TimeInterval) -> String {
        let text = TimeText.elapsed(seconds)
        return text.count == 5 && text.hasPrefix("0") ? String(text.dropFirst()) : text
    }

    private func spoken(_ name: String, _ seconds: [TimeInterval], steps: Int) -> String {
        let total = seconds.reduce(0, +)
        let parts = seconds.indices.map { "step \($0 + 1), \(TimeText.duration(seconds[$0]))" }
        return "\(name): \(TimeText.duration(total)) in all, \(TimeText.duration(total / Double(steps))) per step on average. "
            + parts.joined(separator: "; ")
    }
}
