import SwiftUI
import MeditationCore

/// The journey: every practice kept on this Mac, as totals, a calendar of days, the trend over recent
/// weeks, and the hours of the week the practitioner tends to practice; with a backup to carry it all to
/// another Mac or the web. It lies below setup, a scroll away, and beside a finished practice's time.
struct JourneyView: View {
    @ObservedObject var model: SessionModel
    /// The width it's laid out in: the window's, up to 1480, below setup; the column beside the time on completion.
    let width: CGFloat
    /// The window's compact sizes.
    let compact: Bool
    @State private var month: CivilDate?
    @State private var selectedDay: Int?

    /// Wide: the calendar beside the trend and, under it, the hours of the week. Medium: the calendar
    /// beside the trend, the hours of the week below. Narrow: one column. The web version arranges
    /// itself at the same widths.
    enum Arrangement { case wide, medium, narrow }
    static func arrangement(for width: CGFloat) -> Arrangement {
        width >= 1150 ? .wide : (width >= 720 ? .medium : .narrow)
    }
    private var arrangement: Arrangement { Self.arrangement(for: width) }
    /// Smaller type and padding in a compact window, and in any arrangement but the widest.
    private var dense: Bool { compact || arrangement != .wide }
    private var cardPadding: CGFloat { dense ? 16 : 20 }
    private var gap: CGFloat { dense ? 14 : 16 }
    private var calendarWidth: CGFloat { arrangement == .wide ? 460 : 440 }

    var body: some View {
        let insights = model.insights
        VStack(alignment: .leading, spacing: dense ? 14 : 18) {
            titleRow(insights)
            if model.history.isEmpty {
                emptyCard
            } else {
                tiles(insights)
                switch arrangement {
                case .wide:
                    // The trend takes whatever height the calendar leaves it.
                    HStack(alignment: .top, spacing: gap) {
                        calendarCard(insights).frame(width: calendarWidth)
                        VStack(spacing: gap) {
                            trendCard(insights)
                            rhythmCard(insights, cardWidth: width - calendarWidth - gap)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .fixedSize(horizontal: false, vertical: true)
                case .medium:
                    HStack(alignment: .top, spacing: gap) {
                        calendarCard(insights).frame(width: calendarWidth)
                        trendCard(insights).frame(maxWidth: .infinity)
                    }
                    .fixedSize(horizontal: false, vertical: true)
                    rhythmCard(insights, cardWidth: width)
                case .narrow:
                    calendarCard(insights)
                    trendCard(insights)
                    rhythmCard(insights, cardWidth: width)
                }
            }
        }
        .frame(maxWidth: width, alignment: .topLeading)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Your journey")
        .accessibilityIdentifier("journey")
    }

    // MARK: Title and backup

    /// The title beside the backup buttons, or above them when the two don't fit side by side.
    private func titleRow(_ insights: PracticeInsights) -> some View {
        let intro = VStack(alignment: .leading, spacing: dense ? 7 : 10) {
            Eyebrow(text: "YOUR JOURNEY")
            Text("Turn by turn.")
                .font(.system(size: dense ? 28 : 35, weight: .regular, design: .serif))
                .foregroundColor(Palette.ivory)
            Text(subtitle(insights)).font(.system(size: 13)).foregroundColor(Palette.muted)
        }
        return ViewThatFits(in: .horizontal) {
            HStack(alignment: .bottom, spacing: 20) {
                intro.fixedSize()
                Spacer(minLength: 12)
                backup(alignment: .trailing)
            }
            VStack(alignment: .leading, spacing: 14) {
                intro
                backup(alignment: .leading)
            }
        }
    }

    private func backup(alignment: HorizontalAlignment) -> some View {
        VStack(alignment: alignment, spacing: 8) {
            HStack(spacing: 10) {
                Button(action: model.importHistory) {
                    Label("Import backup…", systemImage: "square.and.arrow.down")
                }
                .buttonStyle(QuietButtonStyle())
                .help("Add the practices in a backup from another Mac or the web. Nothing here is replaced.")
                .accessibilityIdentifier("import-backup")
                Button(action: model.exportHistory) {
                    Label("Export backup…", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(QuietButtonStyle())
                .disabled(model.history.isEmpty)
                .opacity(model.history.isEmpty ? 0.45 : 1)
                .help("Save every practice to a file you can import on another Mac or on the web")
                .accessibilityIdentifier("export-backup")
            }
            Text(model.backupMessage ?? "Kept on this Mac. A backup carries it to another Mac or the web.")
                .font(.system(size: 11)).foregroundColor(model.backupMessage == nil ? Palette.muted : Palette.gold)
                .multilineTextAlignment(alignment == .leading ? .leading : .trailing)
                .frame(maxWidth: 430, alignment: alignment == .leading ? .leading : .trailing)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("backup-message")
        }
    }

    private func subtitle(_ insights: PracticeInsights) -> String {
        guard let first = insights.firstDay else { return "Nothing kept yet." }
        return "\(HistoryText.count(insights.all.practices, "practice")) since \(HistoryText.date(first)) · \(HistoryText.minutes(insights.all.seconds)) in all"
    }

    private var emptyCard: some View {
        VStack(spacing: 14) {
            Image(systemName: "calendar.badge.clock")
                .font(.system(size: 34, weight: .ultraLight)).foregroundColor(Palette.gold)
            Text("Your journey begins with your first practice.")
                .font(.system(size: dense ? 22 : 26, weight: .regular, design: .serif)).foregroundColor(Palette.ivory)
                .multilineTextAlignment(.center)
            Text("Every practice of a minute or more is kept here, on this Mac: a calendar of your days, how your practice is growing, and the hours you tend to practice. Practiced on another Mac or on the web? Import its backup.")
                .font(.system(size: 13)).foregroundColor(Palette.muted).multilineTextAlignment(.center)
                .lineSpacing(3).frame(maxWidth: 520).fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, dense ? 40 : 70)
        .journeyCard(padding: 24)
    }

    // MARK: Totals

    @ViewBuilder
    private func tiles(_ insights: PracticeInsights) -> some View {
        let today = StatTile(title: "TODAY", value: HistoryText.minutes(insights.todayTotals.seconds),
                             detail: insights.todayDetail, direction: nil, compact: dense)
        let week = StatTile(title: "LAST 7 DAYS", value: HistoryText.minutes(insights.last7),
                            detail: insights.weekComparison.text, direction: insights.weekComparison.direction, compact: dense)
        let month = StatTile(title: "LAST 30 DAYS", value: HistoryText.minutes(insights.last30),
                             detail: insights.monthComparison.text, direction: insights.monthComparison.direction, compact: dense)
        let streak = StatTile(title: "STREAK", value: insights.streakValue, detail: insights.streakDetail,
                              direction: nil, compact: dense)
        let cycles = StatTile(title: "CYCLES IN ALL", value: "\(insights.all.cycles)", detail: insights.cyclesDetail,
                              direction: nil, compact: dense, valueColor: Palette.cycles)
            .help("108 cycles make a mala, as 108 beads make a string of prayer beads")
        // Five in a row, or three and two where five won't fit. Tiles in a row share its height.
        if width < 700 {
            VStack(spacing: 10) {
                HStack(spacing: 10) { today; week; month }.fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 10) { streak; cycles }.fixedSize(horizontal: false, vertical: true)
            }
        } else {
            HStack(spacing: dense ? 10 : 14) { today; week; month; streak; cycles }
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: Calendar

    private func calendarCard(_ insights: PracticeInsights) -> some View {
        let today = insights.today
        let shown = month ?? CivilDate(dayNumber: today)
        let first = CivilDate(year: shown.year, month: shown.month, day: 1)?.dayNumber ?? today
        let length = CivilDate.days(inMonth: shown.month, year: shown.year)
        let leading = (CivilDate.weekday(first) - insights.firstWeekday + 7) % 7
        // Always six weeks, so the card keeps its height from month to month.
        let cells: [Int?] = (0..<42).map { index in
            let offset = index - leading
            return (0..<length).contains(offset) ? first + offset : nil
        }
        let earliest = CivilDate(dayNumber: insights.firstDay ?? today)
        let current = CivilDate(dayNumber: today)
        let canGoBack = (shown.year, shown.month) > (earliest.year, earliest.month)
        let canGoForward = (shown.year, shown.month) < (current.year, current.month)
        let selected = selectedDay ?? today
        let cellHeight: CGFloat = dense ? 38 : 40

        return VStack(alignment: .leading, spacing: dense ? 10 : 12) {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 5) {
                    Eyebrow(text: "CALENDAR")
                    Text("\(HistoryText.months[shown.month - 1]) \(String(shown.year))")
                        .font(.system(size: dense ? 19 : 21, weight: .regular, design: .serif)).foregroundColor(Palette.ivory)
                        .accessibilityIdentifier("calendar-month")
                }
                Spacer()
                monthButton("chevron.left", "Previous month", enabled: canGoBack) { step(shown, by: -1) }
                monthButton("chevron.right", "Next month", enabled: canGoForward) { step(shown, by: 1) }
            }
            HStack(spacing: 5) {
                ForEach(insights.weekdayOrder, id: \.self) { weekday in
                    Text(HistoryText.weekdays[weekday].prefix(3).uppercased())
                        .font(.system(size: 9, weight: .medium)).tracking(1).foregroundColor(Palette.muted)
                        .frame(maxWidth: .infinity)
                }
            }
            .accessibilityHidden(true)
            VStack(spacing: 5) {
                ForEach(0..<6, id: \.self) { row in
                    HStack(spacing: 5) {
                        ForEach(0..<7, id: \.self) { column in
                            if let day = cells[row * 7 + column] {
                                dayCell(day, insights: insights, selected: day == selected, height: cellHeight)
                            } else {
                                Color.clear.frame(maxWidth: .infinity).frame(height: cellHeight)
                            }
                        }
                    }
                }
            }
            Rectangle().fill(Palette.gold.opacity(0.14)).frame(height: 0.7)
            dayDetail(selected, insights: insights)
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .journeyCard(padding: cardPadding)
    }

    /// The day's number, then its cycles (bottom left, in blue) and its time (bottom right).
    private func dayCell(_ day: Int, insights: PracticeInsights, selected: Bool, height: CGFloat) -> some View {
        let totals = insights.totals(on: day)
        let level = insights.level(forDay: day)
        let future = day > insights.today
        let dark = level >= 3
        return Button {
            selectedDay = day
        } label: {
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 7).fill(Journey.heatColor(level))
                Text("\(CivilDate(dayNumber: day).day)")
                    .font(.system(size: 11, weight: day == insights.today ? .semibold : .regular)).monospacedDigit()
                    .foregroundColor(dark ? Palette.background : Palette.ivory.opacity(future ? 0.3 : 0.85))
                    .padding(.leading, 6).padding(.top, 4)
                if totals.practices > 0 {
                    HStack(alignment: .lastTextBaseline, spacing: 2) {
                        CycleCount(cycles: totals.cycles, size: 9)
                            .foregroundColor(dark ? Palette.cyclesOnGold : Palette.cycles)
                            .fixedSize()
                        // The time has the rest of the cell, and shrinks a little before it would be cut.
                        Text(HistoryText.compact(totals.seconds))
                            .font(.system(size: 9, weight: .medium)).monospacedDigit()
                            .foregroundColor(dark ? Palette.background.opacity(0.85) : Palette.ivory.opacity(0.75))
                            .lineLimit(1).minimumScaleFactor(0.75)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                    }
                    .padding(.horizontal, 4).padding(.bottom, 4)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                }
            }
            .frame(maxWidth: .infinity).frame(height: height)
            .overlay(RoundedRectangle(cornerRadius: 7)
                .stroke(selected ? Palette.ivory : (day == insights.today ? Palette.gold : .clear), lineWidth: selected ? 1.5 : 1))
            .contentShape(RoundedRectangle(cornerRadius: 7))
        }
        .buttonStyle(.plain)
        .disabled(future)
        .help(totals.practices == 0 ? "" : Journey.dayLabel(day, totals))
        .accessibilityLabel(Journey.dayLabel(day, totals))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func dayDetail(_ day: Int, insights: PracticeInsights) -> some View {
        let totals = insights.totals(on: day)
        let records = model.history.records(on: day)
        return VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(HistoryText.dayTitle(day)).font(.system(size: 13, weight: .medium)).foregroundColor(Palette.ivory)
                if totals.practices > 0 {
                    HStack(alignment: .firstTextBaseline, spacing: 5) {
                        Text(HistoryText.minutes(totals.seconds)).foregroundColor(Palette.gold)
                        Text("·").foregroundColor(Palette.muted)
                        CycleCount(cycles: totals.cycles, size: 12, unit: true).foregroundColor(Palette.cycles)
                        Text("·").foregroundColor(Palette.muted)
                        Text(HistoryText.count(totals.practices, "practice")).foregroundColor(Palette.muted)
                    }
                    .font(.system(size: 12))
                }
            }
            if records.isEmpty {
                Text(day == insights.today ? "No practice yet today." : "No practice on this day.")
                    .font(.system(size: 12)).foregroundColor(Palette.muted)
            } else {
                ForEach(records.prefix(3), id: \.id) { record in
                    Text(Journey.line(record)).font(.system(size: 12)).monospacedDigit().foregroundColor(Palette.muted)
                }
                if records.count > 3 {
                    Text("and \(records.count - 3) more").font(.system(size: 12)).foregroundColor(Palette.muted)
                }
            }
        }
        .frame(maxWidth: .infinity, minHeight: 62, alignment: .topLeading)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("day-detail")
    }

    private func monthButton(_ symbol: String, _ label: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 11, weight: .semibold))
                .frame(width: 30, height: 30)
                .background(Palette.ivory.opacity(0.04), in: Circle())
                .overlay(Circle().stroke(Palette.ivory.opacity(0.14), lineWidth: 0.7))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .foregroundColor(enabled ? Palette.gold : Palette.muted.opacity(0.4))
        .disabled(!enabled)
        .help(label)
        .accessibilityLabel(label)
    }

    /// Another month: today stays selected in this one; in another, its last day with practice, or its first.
    private func step(_ shown: CivilDate, by months: Int) {
        let index = shown.year * 12 + shown.month - 1 + months
        guard let next = CivilDate(year: index / 12, month: index % 12 + 1, day: 1) else { return }
        month = next
        let today = CivilDate(dayNumber: model.insights.today)
        if today.year == next.year && today.month == next.month {
            selectedDay = nil
        } else {
            let first = next.dayNumber
            selectedDay = (0..<CivilDate.days(inMonth: next.month, year: next.year)).map { first + $0 }
                .last { model.insights.totals(on: $0).practices > 0 } ?? first
        }
    }

    // MARK: Trend

    private func trendCard(_ insights: PracticeInsights) -> some View {
        let most = max(insights.weekTotals.max() ?? 0, 1)
        return VStack(alignment: .leading, spacing: dense ? 10 : 12) {
            Eyebrow(text: "TREND · LAST 12 WEEKS")
            HStack(spacing: 10) {
                Image(systemName: Journey.trendSymbol(insights.trend))
                    .font(.system(size: 17, weight: .regular)).foregroundColor(Palette.gold)
                Text(insights.trendTitle)
                    .font(.system(size: dense ? 22 : 25, weight: .regular, design: .serif)).foregroundColor(Palette.ivory)
                    .accessibilityIdentifier("trend-title")
            }
            Text(insights.trendDetail).font(.system(size: 12)).foregroundColor(Palette.muted)
                .lineSpacing(2).fixedSize(horizontal: false, vertical: true)
            // When the card beside it is taller, the chart grows, up to a point, and sits at the foot of the card.
            Spacer(minLength: 0)
            VStack(spacing: 6) {
                GeometryReader { chart in
                    HStack(alignment: .bottom, spacing: dense ? 5 : 7) {
                        ForEach(insights.weekTotals.indices, id: \.self) { index in
                            let seconds = insights.weekTotals[index]
                            let current = index == insights.weekTotals.count - 1
                            RoundedRectangle(cornerRadius: 3)
                                .fill(seconds == 0 ? Palette.ivory.opacity(0.07)
                                      : (current ? Palette.gold.opacity(0.5) : Palette.gold.opacity(0.88)))
                                .frame(height: seconds == 0 ? 2 : max(4, chart.size.height * CGFloat(seconds) / CGFloat(most)))
                                .frame(maxWidth: .infinity)
                                .help("Week of \(HistoryText.shortDate(insights.weekStarts[index])): \(HistoryText.minutes(seconds))")
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                }
                .frame(minHeight: dense ? 92 : 88, maxHeight: 190)
                .overlay(alignment: .topTrailing) {
                    Text(HistoryText.compact(most > 1 ? most : 0))
                        .font(.system(size: 9, weight: .medium)).foregroundColor(Palette.muted)
                        .offset(y: -14)
                }
                HStack {
                    Text(HistoryText.shortDate(insights.weekStarts[0]))
                    Spacer()
                    Text(HistoryText.shortDate(insights.weekStarts[6]))
                    Spacer()
                    Text("This week")
                }
                .font(.system(size: 9, weight: .medium)).foregroundColor(Palette.muted)
            }
            .padding(.top, 14)
            .layoutPriority(1)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Weekly practice, oldest first: " + insights.weekTotals.indices.map {
                "week of \(HistoryText.shortDate(insights.weekStarts[$0])), \(HistoryText.minutes(insights.weekTotals[$0]))"
            }.joined(separator: "; "))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .journeyCard(padding: cardPadding)
    }

    // MARK: Rhythm

    /// The hours of the week beside their notes when the card is wide enough, above them when it isn't.
    private func rhythmCard(_ insights: PracticeInsights, cardWidth: CGFloat) -> some View {
        let beside = cardWidth - 2 * cardPadding >= 800
        return VStack(alignment: .leading, spacing: 12) {
            Eyebrow(text: "WHEN YOU PRACTICE · LAST 12 WEEKS")
            let layout = beside ? AnyLayout(HStackLayout(alignment: .top, spacing: 22)) : AnyLayout(VStackLayout(alignment: .leading, spacing: 14))
            layout {
                heatMap(insights).frame(maxWidth: beside ? 520 : .infinity)
                VStack(alignment: .leading, spacing: 9) {
                    ForEach(insights.rhythmNotes, id: \.self) { note in
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Circle().fill(Palette.gold.opacity(0.8)).frame(width: 4, height: 4).offset(y: -2)
                            Text(note).font(.system(size: 12)).foregroundColor(Palette.ivory.opacity(0.86))
                                .lineSpacing(2).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityIdentifier("rhythm-notes")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .journeyCard(padding: cardPadding)
    }

    private func heatMap(_ insights: PracticeInsights) -> some View {
        let cellHeight: CGFloat = dense ? 13 : 15
        return VStack(alignment: .leading, spacing: 3) {
            ForEach(insights.weekdayOrder, id: \.self) { weekday in
                HStack(spacing: 3) {
                    Text(HistoryText.weekdays[weekday].prefix(3))
                        .font(.system(size: 9, weight: .medium)).foregroundColor(Palette.muted)
                        .frame(width: 26, alignment: .leading)
                    ForEach(0..<24, id: \.self) { hour in
                        RoundedRectangle(cornerRadius: 2.5)
                            .fill(Journey.heatColor(insights.heatLevel(weekday: weekday, hour: hour)))
                            .frame(maxWidth: .infinity).frame(height: cellHeight)
                    }
                }
            }
            HStack(spacing: 3) {
                Color.clear.frame(width: 26, height: 1)
                ForEach(0..<8, id: \.self) { mark in
                    Text(HistoryText.hourMark(mark * 3))
                        .font(.system(size: 8.5, weight: .medium)).foregroundColor(Palette.muted)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.top, 2)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("The hours of the week you practice, over the last twelve weeks. " + insights.rhythmNotes.joined(separator: " "))
        .accessibilityIdentifier("heat-map")
    }
}

/// One of the totals across the top of the journey.
private struct StatTile: View {
    let title: String
    let value: String
    let detail: String
    let direction: PracticeInsights.Comparison.Direction?
    let compact: Bool
    var valueColor = Palette.ivory

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 6 : 8) {
            Text(title).font(.system(size: 9, weight: .medium)).tracking(1.4).foregroundColor(Palette.muted)
                .lineLimit(1)
            Text(value).font(.system(size: compact ? 20 : 24, weight: .light, design: .rounded)).monospacedDigit()
                .foregroundColor(valueColor).lineLimit(1).minimumScaleFactor(0.6)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                if let symbol = direction.flatMap(Journey.directionSymbol) {
                    Image(systemName: symbol).font(.system(size: 9, weight: .bold))
                }
                Text(detail).lineLimit(2).fixedSize(horizontal: false, vertical: true)
            }
            .font(.system(size: 11))
            .foregroundColor(direction == .up ? Palette.gold : Palette.muted)
        }
        .frame(maxWidth: .infinity, minHeight: compact ? 70 : 80, maxHeight: .infinity, alignment: .topLeading)
        .journeyCard(padding: compact ? 13 : 16)
        .accessibilityElement(children: .combine)
    }
}

/// "↻ 3": a turning arrow and the count of cycles, as the calendar's days, the day picked, and today show them.
struct CycleCount: View {
    let cycles: Int
    var size: CGFloat = 9
    /// "↻ 3 cycles" rather than "↻ 3".
    var unit = false

    var body: some View {
        HStack(spacing: size * 0.2) {
            Image(systemName: "arrow.clockwise").font(.system(size: size * 0.78, weight: .bold))
            Text(unit ? HistoryText.count(cycles, "cycle") : "\(cycles)")
                .font(.system(size: size, weight: unit ? .regular : .semibold)).monospacedDigit()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(HistoryText.count(cycles, "cycle"))
    }
}

enum Journey {
    /// From an empty day or hour to a full one: faint ivory, then four depths of gold.
    static func heatColor(_ level: Int) -> Color {
        switch level {
        case 0: return Palette.ivory.opacity(0.045)
        case 1: return Palette.gold.opacity(0.24)
        case 2: return Palette.gold.opacity(0.45)
        case 3: return Palette.gold.opacity(0.7)
        default: return Palette.gold.opacity(0.95)
        }
    }

    static func directionSymbol(_ direction: PracticeInsights.Comparison.Direction) -> String? {
        switch direction {
        case .up: return "arrow.up.right"
        case .down: return "arrow.down.right"
        case .same: return "equal"
        case .none: return nil
        }
    }

    static func trendSymbol(_ trend: PracticeInsights.Trend) -> String {
        switch trend {
        case .rising: return "arrow.up.right.circle"
        case .steady: return "arrow.right.circle"
        case .easing: return "arrow.down.right.circle"
        case .beginning: return "sparkles"
        case .resting: return "moon.zzz"
        }
    }

    /// "Saturday, 14 November: 1 hr 50 min, 5 cycles, 3 practices"
    static func dayLabel(_ day: Int, _ totals: PracticeInsights.Totals) -> String {
        guard totals.practices > 0 else { return "\(HistoryText.dayTitle(day)): no practice" }
        return "\(HistoryText.dayTitle(day)): \(HistoryText.minutes(totals.seconds)), \(HistoryText.count(totals.cycles, "cycle")), \(HistoryText.count(totals.practices, "practice"))"
    }

    /// "6:42 am · 15 min · 3 cycles · Mac"
    static func line(_ record: PracticeRecord) -> String {
        var parts = [HistoryText.time(hour: record.start.hour, minute: record.start.minute),
                     HistoryText.minutes(record.seconds),
                     record.completed ? HistoryText.count(record.cycles, "cycle") : "\(record.cycles) of \(record.planned) cycles"]
        if record.timing == .freestyle { parts.append("freestyle") }
        if let device = record.device { parts.append(device == "web" ? "Web" : (device == "mac" ? "Mac" : device)) }
        return parts.joined(separator: " · ")
    }
}

extension View {
    /// The panels' look: a soft gradient, a fine gold edge.
    func journeyCard(padding: CGFloat) -> some View {
        self.padding(padding)
            .background {
                RoundedRectangle(cornerRadius: 15)
                    .fill(LinearGradient(colors: [Palette.panel.opacity(0.85), Palette.panel.opacity(0.45)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                    .overlay(RoundedRectangle(cornerRadius: 15).stroke(Palette.gold.opacity(0.17), lineWidth: 0.7))
            }
    }
}
