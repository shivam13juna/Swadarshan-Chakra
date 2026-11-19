import SwiftUI

/// The cycle of ages (the supplied yuga chakra) with a white hour hand, its base fixed at the
/// swastika's centre. DialCardView turns the hand between steps.
struct YugaDial: View {
    /// Where the hand points for each step, in degrees clockwise from twelve o'clock: the top, where the
    /// Confluence Age meets Sat Yuga (step 1); the middle of Sat Yuga's quarter (2); the middle of Dwapar
    /// Yuga's (3); the middle of the Confluence Age's wedge, 336° to 360° in the picture (4); and near
    /// that wedge's end (5), 4° short of the top: the age is ending, but not yet over.
    static let stepAngles: [Double] = [0, 45, 225, 348, 356]
    static let places = ["the top, where the Confluence Age meets Sat Yuga", "Sat Yuga", "Dwapar Yuga",
                         "the Confluence Age", "the end of the Confluence Age, just short of Sat Yuga"]

    // Measured on the supplied pictures, as shares of their width and height.
    /// The swastika's centre on the dial.
    private static let centre = CGPoint(x: 627.5 / 1254, y: 619.5 / 1254)
    /// The middle of the hand's rounded base, about which it turns.
    private static let base = UnitPoint(x: 0.5, y: 2098.0 / 2172)
    /// The hand's tip.
    private static let tip: CGFloat = 33.0 / 2172
    /// How far the tip reaches from the swastika's centre, as a share of the dial's width: about halfway
    /// to the rim.
    private static let reach: CGFloat = 0.26

    let face: NSImage
    let hand: NSImage
    /// Degrees clockwise from twelve o'clock.
    let angle: Double
    let side: CGFloat

    /// The hand's turn from one step to the next: clockwise, as a clock turns, once the card has faded
    /// in; a longer way takes a little longer, and the longest ends well before the card does.
    static func turn(from: Double, to: Double) -> Animation {
        .easeInOut(duration: 0.8 + (to - from) / 150).delay(0.4)
    }

    var body: some View {
        let height = Self.reach * side / (Self.base.y - Self.tip)
        let width = height * hand.size.width / hand.size.height
        ZStack(alignment: .topLeading) {
            Image(nsImage: face).resizable().interpolation(.high)
                .frame(width: side, height: side)
            Image(nsImage: hand).resizable().interpolation(.high)
                .frame(width: width, height: height)
                .rotationEffect(.degrees(angle), anchor: Self.base)
                // Even all round, so it stays the same as the hand turns; it keeps the hand clear on gold.
                .shadow(color: .black.opacity(0.55), radius: max(1, side * 0.004))
                .offset(x: Self.centre.x * side - Self.base.x * width, y: Self.centre.y * side - Self.base.y * height)
        }
        .frame(width: side, height: side, alignment: .topLeading)
        .allowsHitTesting(false)
    }
}
