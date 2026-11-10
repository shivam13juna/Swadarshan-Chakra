import SwiftUI
import MeditationCore

/// The short card that opens every cycle: "Cycle 1", then "Cycle 2", and so on. After three
/// seconds the cycle's first step starts by itself; Space starts it sooner, Esc pauses.
struct CycleIntroductionView: View {
    @ObservedObject var model: SessionModel
    let icon: NSImage
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

                VStack(spacing: compact ? 22 : 30) {
                    BrandMark(image: icon)
                        .frame(width: compact ? 92 : 120, height: compact ? 92 : 120)
                        // The chakra turns one fifth, one form, while the card is shown.
                        .rotationEffect(.degrees(turned ? 72 : 0))
                        .shadow(color: Palette.gold.opacity(0.22), radius: 36)
                    Text("Cycle \(model.engine.currentCycle)")
                        .font(.system(size: compact ? 46 : 60, weight: .regular, design: .serif))
                        .foregroundColor(Palette.ivory)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(model.cycleTitle)
                .accessibilityIdentifier("cycle-introduction")

                // Same corner placement as the step screens, so the cycle box stays put as the card fades.
                VStack(spacing: 0) {
                    HStack(alignment: .top) {
                        CycleCounter(engine: model.engine).fixedSize()
                        Spacer()
                        Button(action: model.hideWindow) {
                            Image(systemName: "xmark").font(.system(size: 13, weight: .medium))
                                .frame(width: 15, height: 17)
                        }
                        .buttonStyle(ArtworkButtonStyle())
                        .help("Close to menu bar (⌘W). Your practice will pause.")
                        .accessibilityLabel("Close to menu bar")
                    }
                    Spacer()
                }
                .padding(.horizontal, padding)
                .padding(.top, max(padding, topInset + 12))
                .padding(.bottom, padding)
            }
        }
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: SessionEngine.standardIntroduction)) { turned = true }
        }
    }
}
