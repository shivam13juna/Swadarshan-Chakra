import SwiftUI
import MeditationCore

/// The journey: every practice kept on this Mac, as totals, a calendar of days, the trend over recent
/// weeks, and the hours of the week the practitioner tends to practice; with a backup to carry it all to
/// another Mac or the web. It follows practice in the same scroll, with its own section boundary.
struct JourneyView: View {
    @ObservedObject var model: SessionModel
    /// The available width inside the history section.
    let width: CGFloat
    /// The window's compact sizes.
    let compact: Bool
    var addedPractice: PracticeRecord? = nil
    @State private var month: CivilDate?
    @State private var selectedDay: Int?
    @State private var expandedPractice: String?
    @State private var visiblePractices = 5

    /// The calendar and sessions share a row from 760 points; patterns always follow below.
    enum Arrangement { case wide, medium, narrow }
    static func arrangement(for width: CGFloat) -> Arrangement {
        width >= 1150 ? .wide : (width >= 760 ? .medium : .narrow)
    }
    private var arrangement: Arrangement { Self.arrangement(for: width) }
    /// Smaller type and padding in a compact window, and in any arrangement but the widest.
    private var dense: Bool { compact || arrangement != .wide }
    private var cardPadding: CGFloat { dense ? 16 : 20 }
    private var gap: CGFloat { dense ? 14 : 16 }
    private var calendarWidth: CGFloat { arrangement == .wide ? 440 : 370 }

    var body: some View {
        let insights = model.insights
        VStack(alignment: .leading, spacing: dense ? 14 : 18) {
            titleRow(insights)
            if model.history.isEmpty {
                emptyCard
            } else {
                tiles(insights)
                if arrangement != .narrow {
                    HStack(alignment: .top, spacing: gap) {
                        calendarCard(insights).frame(width: calendarWidth)
                        sessionsCard.frame(maxWidth: .infinity)
                    }
                } else {
                    calendarCard(insights)
                    sessionsCard
                }
                HStack {
                    Text("YOUR PRACTICE PATTERNS").font(.system(size: 10, weight: .medium)).tracking(1.5)
                    Spacer()
                    Text("Current streak: \(insights.streakValue) · Best: \(HistoryText.count(insights.bestStreak, "day"))")
                        .font(.system(size: 12))
                }
                .foregroundColor(Palette.muted).padding(.top, 18)
                trendCard(insights)
                rhythmCard(insights, cardWidth: width)
            }
            Text("ON THIS MAC · ALWAYS OFFLINE")
                .font(.system(size: 9, weight: .medium)).tracking(1.6).foregroundColor(Palette.muted)
                .padding(.top, 12)
        }
        .frame(maxWidth: width, alignment: .topLeading)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Your practice history")
        .accessibilityIdentifier("journey")
        .onChange(of: addedPractice) { record in
            guard let record else { return }
            month = CivilDate(dayNumber: record.day)
            selectDay(record.day)
            let records = Array(model.history.records(on: record.day).reversed())
            visiblePractices = max(5, (records.firstIndex(where: { $0.id == record.id }) ?? 0) + 1)
            expandedPractice = record.id
        }
    }

    // MARK: Title and backup

    /// A clear section title and a compact backup menu, with lifetime totals beneath.
    private func titleRow(_ insights: PracticeInsights) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 20) {
                Text("Your practice history")
                    .font(.system(size: dense ? 28 : 35, weight: .regular, design: .serif))
                    .foregroundColor(Palette.ivory)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                backup
            }
            Text(subtitle(insights)).font(.system(size: 13)).foregroundColor(Palette.muted)
                .fixedSize(horizontal: false, vertical: true)
            if let message = model.backupMessage {
                Text(message).font(.system(size: 12)).foregroundColor(Palette.gold)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("backup-message")
            }
        }
    }

    private var backup: some View {
        Menu {
            Button(action: model.importHistory) {
                Label("Import backup…", systemImage: "square.and.arrow.down")
            }
            .help("Add the practices in a backup from another Mac or the web. Nothing here is replaced.")
            .accessibilityIdentifier("import-backup")
            Button(action: model.exportHistory) {
                Label("Export backup…", systemImage: "square.and.arrow.up")
            }
            .disabled(model.history.isEmpty)
            .help("Save every practice to a file you can import on another Mac or on the web")
            .accessibilityIdentifier("export-backup")
        } label: {
            Label("Backups", systemImage: "externaldrive")
        }
        .menuStyle(.borderlessButton).fixedSize()
        .foregroundColor(Palette.muted)
        .help("Import or export your practice history")
        .accessibilityIdentifier("history-backups")
    }

    private func subtitle(_ insights: PracticeInsights) -> String {
        guard let first = insights.firstDay else { return "Nothing kept yet." }
        return "\(HistoryText.count(insights.all.practices, "practice")) · \(HistoryText.minutes(insights.all.seconds)) · \(HistoryText.count(insights.all.cycles, "cycle")) since \(HistoryText.date(first))"
    }

    private var emptyCard: some View {
        VStack(spacing: 14) {
            Image(systemName: "calendar.badge.clock")
                .font(.system(size: 34, weight: .ultraLight)).foregroundColor(Palette.gold)
            Text("Your journey begins with your first practice.")
                .font(.system(size: dense ? 22 : 26, weight: .regular, design: .serif)).foregroundColor(Palette.ivory)
                .multilineTextAlignment(.center)
            Text("A minute of practice or a complete cycle is saved here. To bring practices from another device, choose Backups → Import backup.")
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
        let average = StatTile(title: "AVERAGE PER CYCLE", value: insights.averageCycleSeconds.map { TimeText.duration(Double($0)) } ?? "—",
                               detail: "Per cycle · last 7 days", direction: nil, compact: dense)
            .help("Total practice time divided by all \(insights.last7Cycles) completed cycles in the last 7 days, including today")
            .accessibilityIdentifier("average-cycle")
        // Four in a row, or two by two. Longer sessions contribute all their completed cycles.
        if width < 700 {
            VStack(spacing: 10) {
                HStack(spacing: 10) { today; week }.fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 10) { month; average }.fixedSize(horizontal: false, vertical: true)
            }
        } else {
            HStack(spacing: dense ? 10 : 14) { today; week; month; average }
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
                                dayCell(day, insights: insights, selected: day == selectedDay, height: cellHeight)
                            } else {
                                Color.clear.frame(maxWidth: .infinity).frame(height: cellHeight)
                            }
                        }
                    }
                }
            }
            Rectangle().fill(Palette.gold.opacity(0.14)).frame(height: 0.7)
            if let selectedDay {
                Text(Journey.dayLabel(selectedDay, insights.totals(on: selectedDay)))
                    .font(.system(size: 12)).foregroundColor(Palette.muted)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("Select a day to see its sessions.").font(.system(size: 12)).foregroundColor(Palette.muted)
            }
        }
        .journeyCard(padding: cardPadding)
    }

    /// The day's number, then its cycles (bottom left, in blue) and its time (bottom right).
    private func dayCell(_ day: Int, insights: PracticeInsights, selected: Bool, height: CGFloat) -> some View {
        let totals = insights.totals(on: day)
        let level = insights.level(forDay: day)
        let future = day > insights.today
        let dark = level >= 3
        return Button {
            selectDay(day)
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

    // MARK: Past sessions

    private var sessionsCard: some View {
        let records = Array((selectedDay.map { model.history.records(on: $0) } ?? model.history.records).reversed())
        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 5) {
                    Eyebrow(text: "PAST PRACTICES")
                    Text(selectedDay.map(HistoryText.dayTitle) ?? "Recent sessions")
                        .font(.system(size: dense ? 19 : 21, weight: .regular, design: .serif))
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                if selectedDay != nil {
                    Button("All dates") { month = nil; selectDay(nil) }
                        .buttonStyle(QuietButtonStyle()).accessibilityIdentifier("all-practice-dates")
                }
            }
            if records.isEmpty {
                Text(selectedDay == model.insights.today ? "No practice yet today." : "No practice on this day.")
                    .font(.system(size: 13)).foregroundColor(Palette.muted)
                    .frame(maxWidth: .infinity, minHeight: 130, alignment: .center)
            } else {
                VStack(spacing: 0) {
                    ForEach(records.prefix(visiblePractices), id: \.id) { record in
                        sessionRow(record)
                    }
                }
                if records.count > visiblePractices {
                    Button("Show more sessions (\(records.count - visiblePractices) remaining)") { visiblePractices += 5 }
                        .buttonStyle(QuietButtonStyle()).accessibilityIdentifier("more-practices")
                }
                Text("\(min(records.count, visiblePractices)) of \(HistoryText.count(records.count, "session")) · Most recent first")
                    .font(.system(size: 11)).foregroundColor(Palette.muted)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .journeyCard(padding: cardPadding)
        .accessibilityIdentifier("practice-sessions")
    }

    private func sessionRow(_ record: PracticeRecord) -> some View {
        let expanded = expandedPractice == record.id
        return VStack(alignment: .leading, spacing: 0) {
            Rectangle().fill(Palette.ivory.opacity(0.09)).frame(height: 0.7)
            Button {
                expandedPractice = expanded ? nil : record.id
            } label: {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("\(HistoryText.date(record.day)) · \(HistoryText.time(hour: record.start.hour, minute: record.start.minute))")
                            .font(.system(size: 13, weight: .medium)).foregroundColor(Palette.ivory)
                        Text("\(record.completed ? HistoryText.count(record.cycles, "cycle") : "\(record.cycles) of \(record.planned) cycles") · \(record.manual ? "Added manually" : record.timing.title)")
                            .font(.system(size: 12)).foregroundColor(Palette.muted)
                    }
                    .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    Text(HistoryText.minutes(record.seconds)).font(.system(size: 15, weight: .medium))
                        .monospacedDigit().foregroundColor(Palette.gold).fixedSize()
                    Image(systemName: expanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 10)).foregroundColor(Palette.muted)
                }
                .padding(.vertical, 14)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(HistoryText.date(record.day)), \(Journey.line(record))")
            .accessibilityValue(expanded ? "Expanded" : "Collapsed")
            .accessibilityHint(record.manual ? "Show average time per step" : "Show the time spent in each form")
            .accessibilityIdentifier("practice-\(record.id)")
            if expanded {
                VStack(alignment: .leading, spacing: 10) {
                    Text(record.completed ? "Completed" : "Ended early")
                        .font(.system(size: 12, weight: .medium)).foregroundColor(Palette.muted)
                    if let steps = record.steps {
                        Eyebrow(text: "TIME BY FORM · ALL CYCLES")
                        ForEach(Stage.all) { stage in
                            HStack(spacing: 12) {
                                Text(String(format: "%02d", stage.id)).font(.system(size: 10)).foregroundColor(Palette.gold)
                                Text(stage.title).font(Palette.hindi(14)).foregroundColor(Palette.ivory)
                                Spacer(minLength: 0)
                                Text(TimeText.elapsed(Double(steps[stage.id - 1])))
                                    .font(.system(size: 13)).monospacedDigit().foregroundColor(Palette.ivory)
                            }
                        }
                    } else if let average = record.averageSecondsPerStep {
                        HStack {
                            Text("Average per step").font(.system(size: 13))
                            Spacer()
                            Text(average < 1 ? "<1 sec" : TimeText.elapsed(average.rounded()))
                                .font(.system(size: 16, weight: .medium)).monospacedDigit().foregroundColor(Palette.gold)
                        }
                        Text("\(TimeText.elapsed(Double(record.seconds))) ÷ (\(record.cycles) × 5 steps). Individual form times weren’t recorded.")
                            .font(.system(size: 12)).foregroundColor(Palette.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        Text("Time by form wasn’t saved for this practice.").font(.system(size: 13)).foregroundColor(Palette.muted)
                    }
                    if let device = record.device {
                        Text("Practiced on \(device == "mac" ? "Mac" : (device == "web" ? "Web" : device))")
                            .font(.system(size: 11)).foregroundColor(Palette.muted)
                    }
                }
                .padding(14).frame(maxWidth: .infinity, alignment: .leading)
                .background(Palette.background.opacity(0.5), in: RoundedRectangle(cornerRadius: 9))
                .padding(.bottom, 14)
            }
        }
    }

    private func selectDay(_ day: Int?) {
        selectedDay = day
        visiblePractices = 5
        expandedPractice = nil
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

    /// In the current month show recent sessions; in another, pick its last day with practice, or its first.
    private func step(_ shown: CivilDate, by months: Int) {
        let index = shown.year * 12 + shown.month - 1 + months
        guard let next = CivilDate(year: index / 12, month: index % 12 + 1, day: 1) else { return }
        month = next
        let today = CivilDate(dayNumber: model.insights.today)
        if today.year == next.year && today.month == next.month {
            selectDay(nil)
        } else {
            let first = next.dayNumber
            selectDay((0..<CivilDate.days(inMonth: next.month, year: next.year)).map { first + $0 }
                .last { model.insights.totals(on: $0).practices > 0 } ?? first)
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
            .font(.system(size: 12))
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
        if record.manual { parts.append("added manually") }
        else if record.timing == .freestyle { parts.append("freestyle") }
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
