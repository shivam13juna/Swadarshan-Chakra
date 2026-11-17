import SwiftUI
import MeditationCore

/// The short card just before each step: the cycle of ages, its hand turning clockwise from where the
/// step just finished stands to where the next one does. Before a cycle's first step, after the cycle
/// card, the hand simply stands at the top, where that step is. After three seconds the step starts by
/// itself; Space starts it sooner, Esc pauses. Like the cycle card, it is not practice time.
struct DialCardView: View {
    @ObservedObject var model: SessionModel
    /// Drawn from this value rather than `model.engine`, like FullScreenStageView, so the card keeps
    /// its step as it fades out.
    let engine: SessionEngine
    let artwork: ArtworkLibrary
    let topInset: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var turned = false

    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            let compact = size.width < 1100 || size.height < 720
            let padding: CGFloat = compact ? 24 : 38
            ZStack {
                MeditationBackground()

                YugaDial(face: artwork.dialFace, hand: artwork.dialHand, angle: turned ? to : from,
                         side: min(780, max(330, min(size.width, size.height) * 0.72)))
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Step \(engine.stageIndex + 1) of 5. On the cycle of ages, the hand \(from == to ? "points" : "turns") to \(YugaDial.places[engine.stageIndex]).")
                    .accessibilityIdentifier("dial-card")

                // Same corner placement as the step screens, so the cycle box stays put as the card fades.
                VStack(spacing: 0) {
                    HStack(alignment: .top) {
                        CycleCounter(engine: engine).fixedSize()
                        Spacer()
                        Button(action: model.close) {
                            Image(systemName: "xmark").font(.system(size: 13, weight: .medium))
                                .frame(width: 15, height: 17)
                        }
                        .buttonStyle(ArtworkButtonStyle())
                        .help("End this practice and close to the menu bar (⌘W)")
                        .accessibilityLabel("End practice and close")
                    }
                    Spacer()
                }
                .padding(.horizontal, padding)
                .padding(.top, max(padding, topInset + 12))
                .padding(.bottom, padding)
            }
        }
        .onAppear {
            guard !reduceMotion, from != to else { turned = true; return }
            withAnimation(YugaDial.turn(from: from, to: to)) { turned = true }
        }
    }

    /// Where the step just finished stands, and where the next one does; before a cycle's first step,
    /// both are the top.
    private var from: Double { YugaDial.stepAngles[max(0, engine.stageIndex - 1)] }
    private var to: Double { YugaDial.stepAngles[engine.stageIndex] }
}
