import SwiftUI
import MeditationCore

struct MeditationView: View {
    @ObservedObject var model: SessionModel
    let artwork: ArtworkLibrary
    var topInset: CGFloat = 0

    var body: some View {
        ZStack {
            Group {
                if model.engine.phase == .ready || model.engine.phase == .complete {
                    overview
                } else {
                    FullScreenStageView(model: model, artwork: artwork, topInset: topInset)
                }
            }
            .disabled(model.engine.phase == .confirming)
            .allowsHitTesting(model.engine.phase != .confirming)
            .accessibilityHidden(model.engine.phase == .confirming)
            if model.engine.phase == .confirming { ConfirmationOverlay(model: model, icon: artwork.brandIcon) }
        }
        .preferredColorScheme(.dark)
        .foregroundColor(Palette.ivory)
        .ignoresSafeArea()
    }

    private var overview: some View {
        GeometryReader { geometry in
            let compact = geometry.size.height < 760 || geometry.size.width < 1180
            let horizontalPadding: CGFloat = compact ? 26 : 46
            ZStack {
                MeditationBackground()
                VStack(spacing: compact ? 13 : 23) {
                    header(compact: compact)
                    if model.engine.phase == .ready {
                        HStack(spacing: compact ? 22 : 40) {
                            OrbitView(model: model, artwork: artwork).frame(maxWidth: .infinity, maxHeight: .infinity)
                            SetupPanel(model: model, compact: compact)
                                .frame(width: compact ? 286 : 326)
                        }.frame(maxHeight: .infinity)
                    } else {
                        OrbitView(model: model, artwork: artwork).frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                    HStack {
                        if model.engine.phase == .ready {
                            Shortcut(key: "Space", action: "Next step during practice")
                        } else {
                            Shortcut(key: "Return", action: "Practice again")
                        }
                        Spacer()
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

    private func header(compact: Bool) -> some View {
        HStack(spacing: 15) {
            BrandMark(image: artwork.brandIcon).frame(width: compact ? 40 : 48, height: compact ? 40 : 48)
            VStack(alignment: .leading, spacing: 1) {
                Text("स्वदर्शन चक्र").font(Palette.hindi(compact ? 23 : 27)).foregroundColor(Palette.ivory)
                Text("SWADARSHAN CHAKRA").font(.system(size: 8, weight: .medium)).tracking(2.8).foregroundColor(Palette.muted)
            }
            Spacer()
            HStack(spacing: 8) {
                Circle().fill(Palette.gold.opacity(0.75)).frame(width: 4, height: 4)
                Eyebrow(text: statusLabel, color: Palette.muted)
            }.padding(.trailing, compact ? 8 : 18)
            Button(action: model.hideWindow) {
                Image(systemName: "xmark").font(.system(size: 12, weight: .light))
                    .frame(width: 14, height: 16)
            }
            .buttonStyle(QuietButtonStyle())
            .help("Close to menu bar (⌘W). Your practice will pause.")
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
