import SwiftUI
import MeditationCore

struct MeditationView: View {
    @ObservedObject var model: SessionModel
    let artwork: ArtworkLibrary
    var topInset: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Group {
                if model.engine.phase == .ready || model.engine.phase == .complete {
                    // Leaves at once; the cycle card then fades in over the dark window.
                    overview.transition(.identity)
                } else if model.engine.isIntroducingCycle {
                    CycleIntroductionView(model: model, icon: artwork.brandIcon, topInset: topInset)
                        .transition(.opacity)
                } else if model.engine.isIntroducingStage {
                    DialCardView(model: model, engine: model.engine, artwork: artwork, topInset: topInset)
                        .transition(.opacity)
                } else {
                    FullScreenStageView(model: model, engine: model.engine, artwork: artwork, topInset: topInset)
                        .transition(.opacity)
                }
            }
            // Cross-fade between the cards and the pictures, and from the cycle card to the first step's card.
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.5), value: model.engine.isIntroducing)
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.5), value: model.engine.isIntroducingCycle)
            .disabled(model.engine.phase == .confirming)
            .allowsHitTesting(model.engine.phase != .confirming)
            .accessibilityHidden(model.engine.phase == .confirming)
            if model.engine.phase == .confirming { ConfirmationOverlay(model: model, icon: artwork.brandIcon) }
        }
        .preferredColorScheme(.dark)
        .foregroundColor(Palette.ivory)
        .ignoresSafeArea()
    }

    private static let journeyAnchor = "journey"

    private var overview: some View {
        GeometryReader { geometry in
            let compact = geometry.size.height < 760 || geometry.size.width < 1180
            let horizontalPadding: CGFloat = compact ? 26 : 46
            let width = geometry.size.width - 2 * horizontalPadding
            ZStack {
                MeditationBackground()
                VStack(spacing: compact ? 13 : 23) {
                    header(compact: compact)
                    if model.engine.phase == .ready {
                        setup(compact: compact, width: width)
                    } else {
                        // Wide enough on a large display for every column title to fit on one line.
                        completion(compact: compact, width: width,
                                   panelWidth: compact ? 372 : min(560, max(470, geometry.size.width * 0.36)))
                    }
                    HStack {
                        if model.engine.phase == .ready {
                            Shortcut(key: "Space", action: "Next step during practice")
                        } else {
                            Shortcut(key: "Return", action: "Practice again")
                        }
                        Spacer()
                        Toggle(isOn: $model.opensInFullScreen) {
                            Text("Open in full screen").font(.system(size: 11)).foregroundColor(Palette.muted)
                        }
                        .toggleStyle(.checkbox).controlSize(.small).tint(Palette.gold)
                        .help("Untick to open meditation in an ordinary window. The green window button or ⌃⌘F switches at any time.")
                        .accessibilityIdentifier("open-in-full-screen")
                        .padding(.trailing, 22)
                        Text("ON THIS MAC · ALWAYS OFFLINE")
                            .font(.system(size: 9, weight: .medium)).tracking(1.6).foregroundColor(Palette.muted)
                    }.frame(height: 25)
                }
                .padding(.horizontal, horizontalPadding)
                .padding(.top, max(compact ? 20 : 30, topInset + 10))
                .padding(.bottom, compact ? 20 : 29)
            }
        }
    }

    /// Setup fills the window: the five forms in their circle beside the practice panel. The journey
    /// lies below, a scroll away; the header's Today and the word under the circle lead down to it.
    private func setup(compact: Bool, width: CGFloat) -> some View {
        GeometryReader { scroll in
            ScrollViewReader { proxy in
                ScrollView(.vertical) {
                    VStack(spacing: 0) {
                        HStack(spacing: compact ? 22 : 40) {
                            OrbitView(model: model, artwork: artwork)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .overlay(alignment: .bottom) { journeyCue }
                            SetupPanel(model: model, compact: compact)
                                .frame(width: compact ? 286 : 326)
                        }
                        .frame(height: scroll.size.height)
                        // A page of its own once scrolled to, however little it holds.
                        JourneyView(model: model, width: min(width, 1480), compact: compact)
                            .frame(maxWidth: .infinity)
                            .padding(.bottom, 4)
                            .frame(minHeight: scroll.size.height, alignment: .top)
                            .id(Self.journeyAnchor)
                            .padding(.top, compact ? 26 : 34)
                    }
                }
                .scrollIndicators(.automatic)
                .onAppear { showJourneyIfAsked(proxy, animated: false) }
                .onChange(of: model.journeyRequested) { _ in showJourneyIfAsked(proxy, animated: true) }
            }
        }
    }

    /// Completion: in place of the circle, the journey, this practice in it; beside it, the practice's
    /// own time. The journey scrolls on its own; the time stays in view.
    private func completion(compact: Bool, width: CGFloat, panelWidth: CGFloat) -> some View {
        let spacing: CGFloat = compact ? 22 : 40
        // On the largest displays the two stay together, centred.
        let column = min(1480, max(320, width - panelWidth - spacing))
        return HStack(alignment: .top, spacing: spacing) {
            ScrollViewReader { proxy in
                ScrollView(.vertical) {
                    JourneyView(model: model, width: column, compact: compact)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                        .padding(.bottom, 4)
                        .id(Self.journeyAnchor)
                }
                .scrollIndicators(.automatic)
                .onChange(of: model.journeyRequested) { _ in showJourneyIfAsked(proxy, animated: true) }
            }
            .frame(width: column)
            TimeSummaryPanel(model: model, compact: compact)
                .frame(width: panelWidth)
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }

    /// "Your journey ⌄", in the open space at the foot of the circle: down to the journey.
    private var journeyCue: some View {
        Button(action: model.showJourney) {
            HStack(spacing: 6) {
                Text("YOUR JOURNEY").font(.system(size: 9, weight: .medium)).tracking(2)
                Image(systemName: "chevron.down").font(.system(size: 8, weight: .semibold))
            }
            .foregroundColor(Palette.muted)
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(Palette.background.opacity(0.9), in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help("Your journey is below: a calendar of your days, your trend, and the hours you practice (⌘J)")
        .accessibilityIdentifier("journey-cue")
    }

    private func showJourneyIfAsked(_ proxy: ScrollViewProxy, animated: Bool) {
        guard model.journeyRequested else { return }
        model.journeyRequested = false
        // After the screen has been laid out, so the journey is where the scroll finds it.
        DispatchQueue.main.async {
            withAnimation(animated && !reduceMotion ? .easeInOut(duration: 0.45) : nil) {
                proxy.scrollTo(Self.journeyAnchor, anchor: .top)
            }
        }
    }

    /// Today's practice so far, in the setup header: its time and its cycles. It leads down to the journey.
    private var todayButton: some View {
        let today = model.insights.todayTotals
        return Button(action: model.showJourney) {
            HStack(spacing: 9) {
                Text("TODAY").font(.system(size: 9, weight: .medium)).tracking(1.6).foregroundColor(Palette.muted)
                if today.practices > 0 {
                    HStack(spacing: 6) {
                        Text(HistoryText.minutes(today.seconds)).foregroundColor(Palette.ivory)
                        Text("·").foregroundColor(Palette.muted)
                        CycleCount(cycles: today.cycles, size: 13, unit: true).foregroundColor(Palette.cycles)
                    }
                    .monospacedDigit()
                } else {
                    Text("No practice yet").foregroundColor(Palette.muted)
                }
                Image(systemName: "chevron.down").font(.system(size: 9, weight: .semibold)).foregroundColor(Palette.gold)
            }
        }
        .buttonStyle(QuietButtonStyle())
        .help("Today's practice so far. Your journey is below: click, scroll down, or press ⌘J.")
        .accessibilityLabel(today.practices > 0
            ? "Today: \(HistoryText.minutes(today.seconds)), \(HistoryText.count(today.cycles, "cycle")) in \(HistoryText.count(today.practices, "practice")). Show your journey."
            : "Today: no practice yet. Show your journey.")
        .accessibilityIdentifier("today")
    }

    private func header(compact: Bool) -> some View {
        HStack(spacing: 15) {
            SpinningBrandMark(image: artwork.brandIcon, size: compact ? 40 : 48, active: model.windowVisible)
            VStack(alignment: .leading, spacing: 1) {
                Text("स्वदर्शन चक्र").font(Palette.hindi(compact ? 23 : 27)).foregroundColor(Palette.ivory)
                Text("SWADARSHAN CHAKRA").font(.system(size: 8, weight: .medium)).tracking(2.8).foregroundColor(Palette.muted)
            }
            Spacer()
            HStack(spacing: 8) {
                Circle().fill(Palette.gold.opacity(0.75)).frame(width: 4, height: 4)
                Eyebrow(text: statusLabel, color: Palette.muted)
            }.padding(.trailing, compact ? 8 : 18)
            if model.engine.phase == .ready { todayButton }
            Button(action: model.close) {
                Image(systemName: "xmark").font(.system(size: 12, weight: .light))
                    .frame(width: 14, height: 16)
            }
            .buttonStyle(QuietButtonStyle())
            .help("Close to the menu bar (⌘W)")
            .accessibilityLabel("Close to menu bar")
            .accessibilityIdentifier("close-meditation")
        }.frame(height: compact ? 43 : 51)
    }

    private var statusLabel: String {
        switch model.engine.phase {
        case .ready: return "READY WHEN YOU ARE"
        case .running: return "PRACTICE IN PROGRESS"
        case .paused, .confirming: return "A MOMENT OF PAUSE"
        case .complete: return "PRACTICE COMPLETE"
        }
    }
}

private struct ConfirmationOverlay: View {
    @ObservedObject var model: SessionModel
    let icon: NSImage
    @FocusState private var cancelFocused: Bool

    var body: some View {
        ZStack {
            Palette.background.opacity(0.84).ignoresSafeArea()
            VStack(spacing: 23) {
                BrandMark(image: icon).frame(width: 56, height: 56)
                VStack(spacing: 12) {
                    Text(title).font(.system(size: 30, weight: .regular, design: .serif))
                    Text(message).font(.system(size: 14)).foregroundColor(Palette.muted)
                        .multilineTextAlignment(.center).lineSpacing(4)
                }
                HStack(spacing: 12) {
                    Button("Keep practicing", action: model.cancelConfirmation)
                        .buttonStyle(QuietButtonStyle()).focused($cancelFocused)
                        .keyboardShortcut(.cancelAction)
                    Button(actionLabel, action: model.confirm)
                        .buttonStyle(GoldButtonStyle()).accessibilityIdentifier("confirm-action")
                        .keyboardShortcut(.return, modifiers: .command)
                }
                Text("Esc to keep practicing · ⌘Return to confirm")
                    .font(.system(size: 11)).foregroundColor(Palette.muted)
            }
            .padding(38).frame(width: 470)
            .background(Palette.panel, in: RoundedRectangle(cornerRadius: 19))
            .overlay(RoundedRectangle(cornerRadius: 19).stroke(Palette.gold.opacity(0.25), lineWidth: 0.8))
            .shadow(color: .black.opacity(0.3), radius: 50)
            .onAppear { cancelFocused = true }
        }
        .accessibilityAddTraits(.isModal)
    }

    private var title: String {
        switch model.engine.pendingConfirmation {
        case .restart: return "Begin this practice again?"
        case .quit: return "End your practice and quit?"
        default: return "End this practice?"
        }
    }
    private var message: String {
        model.engine.pendingConfirmation == .restart
        ? "Your current progress will be cleared. You’ll return to the first form of the first cycle."
        : "Your current progress will be cleared. You can begin a new practice whenever you’re ready."
    }
    private var actionLabel: String {
        switch model.engine.pendingConfirmation {
        case .restart: return "Restart practice"
        case .quit: return "End and quit"
        default: return "End practice"
        }
    }
}
