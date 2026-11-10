import SwiftUI
import MeditationCore

struct OrbitView: View {
    @ObservedObject var model: SessionModel
    let artwork: ArtworkLibrary
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let height = geometry.size.height
            let cardWidth = min(202, max(102, min(width * 0.225, height * 0.275)))
            let cardHeight = cardWidth * 0.565 + 61
            let radiusX = max(60, (width - cardWidth - 22) / (2 * sin(.pi * 2 / 5)))
            let radiusY = max(60, (height - cardHeight - 16) / (1 + cos(.pi / 5)))
            let centerY = (height + radiusY * (1 - cos(.pi / 5))) / 2
            // The lower cards sit to either side of the center. Use that open central space
            // for a larger focus image, especially for the differently shaped second picture.
            let extraFocusHeight: CGFloat = model.engine.phase == .ready ? 20 : (model.engine.phase == .complete ? 0 : 80)
            let focusHeight = max(126, radiusY * (1 + cos(.pi / 5)) - cardHeight - 30) + extraFocusHeight
            let focusWidth = min(width * 0.44, 420)

            ZStack {
                Ellipse().stroke(Palette.gold.opacity(0.18), lineWidth: 0.7)
                    .frame(width: radiusX * 2, height: radiusY * 2)
                    .position(x: width / 2, y: centerY)
                Ellipse().stroke(Palette.gold.opacity(0.055), style: StrokeStyle(lineWidth: 0.6, dash: [2, 7]))
                    .frame(width: radiusX * 2 + 22, height: radiusY * 2 + 22)
                    .position(x: width / 2, y: centerY)

                ForEach(0..<5, id: \.self) { index in
                    let angle = Double(index) * 2 * .pi / 5 - .pi / 2 + .pi / 5
                    Image(systemName: "chevron.right")
                        .font(.system(size: 8, weight: .light)).foregroundColor(Palette.gold.opacity(0.3))
                        .rotationEffect(.radians(atan2(radiusY * cos(angle), -radiusX * sin(angle))))
                        .position(x: width / 2 + cos(angle) * radiusX, y: centerY + sin(angle) * radiusY)
                        .accessibilityHidden(true)
                }

                ForEach(Stage.all) { stage in
                    let angle = Double(stage.id - 1) * 2 * .pi / 5 - .pi / 2
                    StageCard(stage: stage, image: artwork.image(for: stage), width: cardWidth,
                              active: model.engine.phase != .complete && model.engine.currentStage.id == stage.id,
                              preview: model.engine.phase == .ready)
                        .frame(width: cardWidth, height: cardHeight)
                        .position(x: width / 2 + cos(angle) * radiusX, y: centerY + sin(angle) * radiusY)
                }

                Group {
                    if model.engine.phase == .complete {
                        CompletionFocus(model: model, compact: focusHeight < 280)
                    } else {
                        ActiveFocus(stage: model.engine.currentStage, artwork: artwork,
                                    availableHeight: focusHeight, paused: model.engine.phase == .paused || model.engine.phase == .confirming)
                            .id(model.engine.currentStage.id)
                            .transition(.opacity)
                    }
                }
                .frame(width: focusWidth, height: focusHeight)
                .position(x: width / 2, y: height / 2 + extraFocusHeight / 2)
                .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: model.engine.currentStage.id)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Five spiritual forms, in clockwise order")
    }
}

private struct StageCard: View {
    let stage: Stage
    let image: NSImage
    let width: CGFloat
    let active: Bool
    let preview: Bool

    var body: some View {
        VStack(spacing: 7) {
            Image(nsImage: image)
                .resizable().interpolation(.high).scaledToFit()
                .frame(width: width - 8, height: width * 0.565)
                .background(Palette.background)
                .padding(4)
                .background(Palette.background)
                .clipShape(RoundedRectangle(cornerRadius: 7))
                .overlay(RoundedRectangle(cornerRadius: 7)
                    .stroke(active ? Palette.gold : Palette.ivory.opacity(0.19), lineWidth: active ? 1.5 : 0.7))
                .shadow(color: active ? Palette.gold.opacity(0.14) : .clear, radius: 14)
                .opacity(active || preview ? 1 : 0.82)

            VStack(spacing: 1) {
                HStack(spacing: 5) {
                    Text(String(format: "%02d", stage.id)).font(.system(size: 9, weight: .medium)).monospacedDigit()
                        .foregroundColor(active ? Palette.gold : Palette.muted)
                    Text(stage.title).font(Palette.hindi(width < 145 ? 14 : 17))
                        .foregroundColor(active ? Palette.ivory : Palette.ivory.opacity(0.85))
                        .lineLimit(1).minimumScaleFactor(0.8)
                }
                Text(stage.context.isEmpty ? " " : stage.context)
                    .font(Palette.hindi(width < 145 ? 11 : 13)).foregroundColor(Palette.muted)
                    .lineLimit(1)
            }.frame(height: 40)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Stage \(stage.id) of 5, \(stage.label)\(active ? ", current stage" : "")")
        .accessibilityIdentifier(stage.assetID)
    }
}

private struct ActiveFocus: View {
    let stage: Stage
    let artwork: ArtworkLibrary
    let availableHeight: CGFloat
    let paused: Bool

    var body: some View {
        let compact = availableHeight < 240
        let imageHeight = max(65, availableHeight - (compact ? 92 : 113))
        VStack(spacing: 0) {
            Eyebrow(text: "\(paused ? "PAUSED  ·  " : "")FORM \(String(format: "%02d", stage.id)) / 05")
                .padding(.bottom, compact ? 10 : 14)
            Image(nsImage: artwork.image(for: stage))
                .resizable().interpolation(.high).scaledToFit()
                .frame(maxWidth: .infinity).frame(height: imageHeight)
                .shadow(color: Palette.gold.opacity(0.09), radius: 25)
                .accessibilityLabel(stage.label)
                .accessibilityIdentifier("active-artwork")
            Text(stage.title)
                .font(Palette.hindi(compact ? 25 : 34)).foregroundColor(Palette.ivory)
                .lineLimit(1).minimumScaleFactor(0.75)
                .padding(.top, compact ? 13 : 18)
            Text(stage.context.isEmpty ? " " : stage.context)
                .font(Palette.hindi(compact ? 15 : 18)).foregroundColor(Palette.gold.opacity(0.9))
                .lineLimit(1)
        }
        .accessibilityElement(children: .combine)
    }
}

private struct CompletionFocus: View {
    @ObservedObject var model: SessionModel
    let compact: Bool

    var body: some View {
        VStack(spacing: compact ? 11 : 19) {
            Image(systemName: "checkmark.seal")
                .font(.system(size: compact ? 28 : 38, weight: .ultraLight)).foregroundColor(Palette.gold)
            VStack(spacing: 7) {
                Text("Meditation complete")
                    .font(.system(size: compact ? 25 : 32, weight: .regular, design: .serif))
                    .foregroundColor(Palette.ivory)
                Text("\(model.engine.completedCycles) \(model.engine.completedCycles == 1 ? "cycle" : "cycles") completed")
                    .font(.system(size: 13)).foregroundColor(Palette.muted)
            }
            HStack(spacing: 24) {
                summary("PRACTICED", TimeText.elapsed(model.engine.activeSeconds))
                Rectangle().fill(Palette.gold.opacity(0.25)).frame(width: 1, height: 32)
                summary("PLANNED", TimeText.elapsed(model.engine.configuration.plannedSeconds))
            }.padding(.vertical, compact ? 0 : 4)
            HStack(spacing: 10) {
                Button("Practice again", action: model.practiceAgain).buttonStyle(GoldButtonStyle())
                    .keyboardShortcut(.return, modifiers: [])
                    .accessibilityIdentifier("practice-again")
                Button("Close", action: model.hideWindow).buttonStyle(QuietButtonStyle())
            }
        }
    }

    private func summary(_ name: String, _ value: String) -> some View {
        VStack(spacing: 6) {
            Text(name).font(.system(size: 9, weight: .medium)).tracking(1.5).foregroundColor(Palette.muted)
            Text(value).font(.system(size: compact ? 20 : 24, weight: .light)).monospacedDigit().foregroundColor(Palette.ivory)
        }
    }
}
