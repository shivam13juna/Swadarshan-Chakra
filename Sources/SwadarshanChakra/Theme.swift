import SwiftUI

enum Palette {
    static let background = Color(red: 0.027, green: 0.041, blue: 0.082)
    static let panel = Color(red: 0.061, green: 0.077, blue: 0.122)
    static let gold = Color(red: 0.85, green: 0.72, blue: 0.46)
    static let ivory = Color(red: 0.96, green: 0.93, blue: 0.85)
    static let muted = Color(red: 0.66, green: 0.68, blue: 0.73)
    static let faint = Color(red: 0.43, green: 0.47, blue: 0.55)
    static let error = Color(red: 1, green: 0.69, blue: 0.57)

    static func hindi(_ size: CGFloat) -> Font {
        // macOS supplies the font and its Devanagari shaping; no third-party font is bundled.
        .custom("KohinoorDevanagari-Regular", size: size, relativeTo: .title)
    }
}

struct MeditationBackground: View {
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                LinearGradient(colors: [Color(red: 0.055, green: 0.068, blue: 0.13), Palette.background,
                                        Color(red: 0.022, green: 0.032, blue: 0.059)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                RadialGradient(colors: [Palette.gold.opacity(0.065), .clear],
                               center: UnitPoint(x: 0.4, y: 0.43), startRadius: 20,
                               endRadius: geometry.size.width * 0.57)
                ForEach(0..<24, id: \.self) { index in
                    Circle()
                        .fill(Palette.gold.opacity(index.isMultiple(of: 3) ? 0.3 : 0.13))
                        .frame(width: index.isMultiple(of: 4) ? 2 : 1, height: index.isMultiple(of: 4) ? 2 : 1)
                        .position(x: geometry.size.width * CGFloat((index * 37 + 11) % 101) / 101,
                                  y: geometry.size.height * CGFloat((index * 53 + 7) % 97) / 97)
                }
            }
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}

struct BrandMark: View {
    let image: NSImage

    var body: some View {
        Image(nsImage: image)
            .resizable().interpolation(.high).scaledToFit()
            .accessibilityHidden(true)
    }
}

struct GoldButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    @Environment(\.isFocused) private var focused

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .semibold))
            .foregroundColor(Palette.background)
            .padding(.horizontal, 18).padding(.vertical, 14)
            .background(LinearGradient(colors: [Color(red: 0.91, green: 0.80, blue: 0.58), Palette.gold],
                                       startPoint: .topLeading, endPoint: .bottomTrailing))
            .clipShape(RoundedRectangle(cornerRadius: 9))
            .overlay(RoundedRectangle(cornerRadius: 9).stroke(focused ? Palette.ivory : .clear, lineWidth: 2))
            .opacity(!enabled ? 0.35 : (configuration.isPressed ? 0.78 : 1))
            .contentShape(RoundedRectangle(cornerRadius: 9))
    }
}

struct QuietButtonStyle: ButtonStyle {
    @Environment(\.isFocused) private var focused
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .medium))
            .foregroundColor(Palette.ivory.opacity(configuration.isPressed ? 0.6 : 0.9))
            .padding(.horizontal, 15).padding(.vertical, 12)
            .background(Palette.ivory.opacity(configuration.isPressed ? 0.09 : 0.035))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8)
                .stroke(focused ? Palette.gold : Palette.ivory.opacity(0.13), lineWidth: 1))
    }
}

struct Eyebrow: View {
    let text: String
    var color = Palette.gold
    var body: some View {
        Text(text).font(.system(size: 10, weight: .medium)).tracking(2.3).foregroundColor(color)
    }
}

struct Shortcut: View {
    let key: String
    let action: String
    var color = Palette.muted
    var body: some View {
        HStack(spacing: 8) {
            Text(key).font(.system(size: 10, weight: .medium))
                .padding(.horizontal, 7).padding(.vertical, 3)
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(color.opacity(0.4), lineWidth: 0.7))
            Text(action).font(.system(size: 11))
        }.foregroundColor(color)
    }
}
