import SwiftUI
import MeditationCore

/// The artwork occupies the complete window. Only small controls sit over its edges.
struct FullScreenStageView: View {
    @ObservedObject var model: SessionModel
    /// Drawn from this value rather than `model.engine`: SwiftUI may still re-evaluate a view while it
    /// fades out, and the last step must not switch to the next cycle's first picture as it leaves.
    let engine: SessionEngine
    let artwork: ArtworkLibrary
    let topInset: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            let compact = size.width < 1100 || size.height < 720
            let padding: CGFloat = compact ? 24 : 38
            ZStack {
                Image(nsImage: artwork.image(for: engine.currentStage))
                    .resizable().interpolation(.high)
                    .scaledToFill()
                    .frame(width: size.width, height: size.height, alignment: .center)
                    .clipped()
                    .id(engine.currentStage.id)
                    .transition(.opacity)
                    .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: engine.currentStage.id)
                    .accessibilityLabel(engine.currentStage.label)
                    .accessibilityIdentifier("active-artwork")

                // Local edge shading keeps controls legible on all five pictures without
                // dimming the main subject or adding bars outside the picture.
                VStack(spacing: 0) {
                    LinearGradient(colors: [.black.opacity(0.28), .clear], startPoint: .top, endPoint: .bottom)
                        .frame(height: min(size.height * 0.22, 170))
                    Spacer(minLength: 0)
                    LinearGradient(colors: [.clear, .black.opacity(0.72)], startPoint: .top, endPoint: .bottom)
                        .frame(height: min(size.height * 0.40, 290))
                }.allowsHitTesting(false).accessibilityHidden(true)

                VStack(spacing: 0) {
                    topControls
                    Spacer(minLength: 16)
                    if size.width < 760 {
                        VStack(alignment: .leading, spacing: 20) {
                            stageInformation(compact: true)
                            playbackControls
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        HStack(alignment: .bottom, spacing: 25) {
                            stageInformation(compact: compact)
                            Spacer(minLength: 0)
                            playbackControls
                        }
                    }
                }
                .padding(.horizontal, padding)
                .padding(.top, max(padding, topInset + 12))
                .padding(.bottom, padding)

                // How much of this step's time is left, along the bottom edge.
                StepMeter(engine: engine, moving: model.windowVisible)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            }
            .frame(width: size.width, height: size.height)
            .clipped()
        }
    }

    private var topControls: some View {
        HStack(alignment: .top) {
            // Both boxes share the wider one's width, so the pair reads as one aligned stack.
            VStack(alignment: .leading, spacing: 8) {
                CycleCounter(engine: engine)
                CounterCapsule {
                    HStack(spacing: 13) {
                        Text("STEP \(String(format: "%02d", engine.stageIndex + 1)) / 05")
                        if engine.phase != .running {
                            Label("Paused", systemImage: "pause.fill").font(.system(size: 11, weight: .medium))
                        }
                    }
                }
                .accessibilityLabel("Step \(engine.stageIndex + 1) of 5\(engine.phase == .running ? "" : ", paused")")
            }
            .fixedSize(horizontal: true, vertical: false)
            Spacer()
            Button(action: model.hideWindow) {
                Image(systemName: "xmark").font(.system(size: 13, weight: .medium))
                    .frame(width: 15, height: 17)
            }
            .buttonStyle(ArtworkButtonStyle())
            .help("Close to menu bar (⌘W). Your practice will pause.")
            .accessibilityLabel("Close to menu bar")
            .accessibilityIdentifier("close-meditation")
        }
    }

    private func stageInformation(compact: Bool) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(engine.currentStage.title)
                .font(Palette.hindi(compact ? 29 : 38))
                .foregroundColor(.white)
                .lineLimit(1).minimumScaleFactor(0.75)
                .shadow(color: .black.opacity(0.25), radius: 6, y: 2)
            if !engine.currentStage.context.isEmpty {
                Text(engine.currentStage.context)
                    .font(Palette.hindi(compact ? 16 : 19)).foregroundColor(.white.opacity(0.88))
            }
            HStack(spacing: 12) {
                Text(TimeText.countdown(engine.remainingSeconds))
                    .font(.system(size: 20, weight: .regular, design: .rounded)).monospacedDigit()
                    .accessibilityLabel("\(TimeText.countdown(engine.remainingSeconds)) remaining")
                    .accessibilityIdentifier("remaining-time")
                Rectangle().fill(.white.opacity(0.35)).frame(width: 1, height: 14).accessibilityHidden(true)
                Text("\(engine.completedCycles) / \(engine.configuration.cycles) cycles completed")
                    .font(.system(size: 12)).monospacedDigit()
            }
            .foregroundColor(.white.opacity(0.9)).padding(.top, 5)
        }
    }

    private var playbackControls: some View {
        VStack(alignment: .trailing, spacing: 11) {
            if engine.phase == .running {
                HStack(spacing: 9) {
                    Button { model.pause() } label: { Label("Pause", systemImage: "pause") }
                        .buttonStyle(ArtworkButtonStyle()).accessibilityIdentifier("pause-meditation")
                    Button { model.nextStage() } label: { Label("Next step", systemImage: "arrow.right") }
                        .buttonStyle(ArtworkButtonStyle()).accessibilityIdentifier("next-stage")
                }
                // Same order as the buttons above: Pause, then Next step.
                HStack(spacing: 17) {
                    Shortcut(key: "Esc", action: "Pause", color: .white.opacity(0.85))
                    Shortcut(key: "Space", action: "Next step", color: .white.opacity(0.85))
                }
            } else {
                HStack(spacing: 9) {
                    Button(action: model.resume) { Label("Resume", systemImage: "play.fill") }
                        .buttonStyle(ArtworkButtonStyle(prominent: true))
                        .keyboardShortcut(.return, modifiers: [])
                        .accessibilityIdentifier("resume-meditation")
                    Button("Restart") { model.request(.restart) }
                        .buttonStyle(ArtworkButtonStyle()).keyboardShortcut("r", modifiers: .command)
                        .help("Restart practice (⌘R)")
                    Button("End") { model.request(.end) }
                        .buttonStyle(ArtworkButtonStyle()).keyboardShortcut("e", modifiers: .command)
                        .help("End practice (⌘E)")
                }
                Text(model.pauseReason).font(.system(size: 11)).foregroundColor(.white.opacity(0.85))
            }
        }
    }
}

/// A small top-left capsule. Inside a fixed-size stack, capsules share the widest one's width.
struct CounterCapsule<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        content
            .font(.system(size: 10, weight: .medium)).tracking(1.6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .foregroundColor(.white.opacity(0.92))
            .padding(.horizontal, 14).padding(.vertical, 10)
            .background(.black.opacity(0.26), in: Capsule())
            .accessibilityElement(children: .ignore)
    }
}

/// "CYCLE 02 / 03", in the same place on the cycle card and on every step.
struct CycleCounter: View {
    let engine: SessionEngine

    var body: some View {
        CounterCapsule {
            Text("CYCLE \(String(format: "%02d", engine.currentCycle)) / \(String(format: "%02d", engine.configuration.cycles))")
        }
        .accessibilityLabel("Cycle \(engine.currentCycle) of \(engine.configuration.cycles)")
        .accessibilityIdentifier("cycle-counter")
    }
}

/// A thin white bar along the bottom edge: the time left in this step, out of its full time. It is
/// full as a step begins, empties as the countdown runs, and holds still while paused.
struct StepMeter: View {
    let engine: SessionEngine
    /// Whether the window can be seen. The bar glides only then; otherwise it is drawn still.
    let moving: Bool

    var body: some View {
        StepMeterBar(fraction: 1 - engine.progress, remaining: engine.remainingSeconds,
                     step: engine.transitionCount, gliding: moving && engine.phase == .running)
            .frame(height: 4)
            .allowsHitTesting(false)
            // The countdown beside the title already says how long is left.
            .accessibilityHidden(true)
    }
}

private struct StepMeterBar: NSViewRepresentable {
    let fraction: Double
    let remaining: TimeInterval
    let step: Int
    let gliding: Bool

    func makeNSView(context: Context) -> StepMeterView { StepMeterView() }
    func updateNSView(_ view: StepMeterView, context: Context) {
        view.show(fraction: fraction, remaining: remaining, step: step, gliding: gliding)
    }
}

/// Core Animation runs the countdown in the window server, as it turns the header chakra: the bar
/// glides between the timer's ticks while the app does no work per frame.
final class StepMeterView: NSView {
    private static let trackColor = NSColor(white: 1, alpha: 0.2)
    private static let fillColor = NSColor(white: 1, alpha: 0.9)
    private let trackLayer = CALayer()
    private let fillLayer = CALayer()
    private var fraction = 1.0
    private var step: Int?
    private var gliding = false

    init() {
        super.init(frame: .zero)
        wantsLayer = true
        trackLayer.backgroundColor = Self.trackColor.cgColor
        fillLayer.backgroundColor = Self.fillColor.cgColor
        fillLayer.anchorPoint = CGPoint(x: 0, y: 0.5)   // It shortens toward the left edge.
        for sublayer in [trackLayer, fillLayer] {
            sublayer.isHidden = true
            layer?.addSublayer(sublayer)
        }
    }

    required init?(coder: NSCoder) { nil }

    /// What the bar shows at this moment, as a share of the step's time, for the live timer check.
    var shownFraction: Double {
        guard gliding else { return fraction }
        return (fillLayer.presentation() ?? fillLayer).value(forKeyPath: "transform.scale.x") as? Double ?? 0
    }

    // Decorative: clicks reach whatever is behind it.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        trackLayer.frame = bounds
        fillLayer.bounds = CGRect(origin: .zero, size: bounds.size)
        fillLayer.position = CGPoint(x: bounds.minX, y: bounds.midY)
        CATransaction.commit()
    }

    func show(fraction: Double, remaining: TimeInterval, step: Int, gliding: Bool) {
        // A new step, or this one resumed, glides again from where it stands; ticks in between change nothing.
        let restart = gliding && (!self.gliding || step != self.step)
        let redraw = gliding != self.gliding || (!gliding && fraction != self.fraction)
        self.fraction = fraction
        self.step = step
        self.gliding = gliding
        guard restart || redraw else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        trackLayer.isHidden = !gliding
        fillLayer.isHidden = !gliding
        if restart {
            fillLayer.transform = CATransform3DMakeScale(0, 1, 1)   // Where the glide ends.
            let countdown = CABasicAnimation(keyPath: "transform.scale.x")
            countdown.fromValue = fraction
            countdown.toValue = 0
            countdown.duration = max(remaining, 0.01)
            fillLayer.add(countdown, forKey: "countdown")
        } else if !gliding {
            fillLayer.removeAnimation(forKey: "countdown")
        }
        CATransaction.commit()
        if redraw { needsDisplay = true }
    }

    // Still, the bar is drawn like any view, so offscreen renders (the README screenshots) include it.
    override func draw(_ dirtyRect: NSRect) {
        guard !gliding else { return }
        Self.trackColor.setFill()
        bounds.fill(using: .sourceOver)
        Self.fillColor.setFill()
        NSRect(x: bounds.minX, y: bounds.minY, width: bounds.width * fraction, height: bounds.height)
            .fill(using: .sourceOver)
    }
}

struct ArtworkButtonStyle: ButtonStyle {
    var prominent = false
    @Environment(\.isFocused) private var focused

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .medium))
            .foregroundColor(prominent ? Palette.background : .white)
            .padding(.horizontal, 15).padding(.vertical, 12)
            .background(prominent ? .white.opacity(0.94) : .black.opacity(0.32), in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8)
                .stroke(.white.opacity(focused ? 1 : 0.25), lineWidth: focused ? 2 : 0.7))
            .opacity(configuration.isPressed ? 0.65 : 1)
    }
}
