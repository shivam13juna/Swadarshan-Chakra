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
