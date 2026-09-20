import Foundation
import SwiftUI

// DesignSystem — shared token set (macOS + iOS). Function-call style to match Sumi Hub.
enum DesignSystem {
    // MARK: Spacing
    static func spaceXS() -> CGFloat { 4 }
    static func spaceS() -> CGFloat { 8 }
    static func spaceM() -> CGFloat { 12 }
    static func spaceL() -> CGFloat { 16 }
    static func spaceXL() -> CGFloat { 24 }
    static func spaceXXL() -> CGFloat { 32 }

    // MARK: Radii
    static func radiusS() -> CGFloat { 6 }
    static func radiusCard() -> CGFloat { 10 }

    // MARK: Type
    static func typeCaption() -> CGFloat { 11 }
    static func typeBody() -> CGFloat { 14 }
    static func typeTitle() -> CGFloat { 18 }
    static func typeDisplay() -> CGFloat { 26 }
    static func typeHero() -> CGFloat { 44 }

    // MARK: Surfaces
    static func hairline() -> Color { Color.primary.opacity(0.08) }
    static func panelFill() -> Color { Color.primary.opacity(0.04) }

    // MARK: Accent palette (muted zen tones; hex strings stored on Subject)
    static let accentPalette: [String] = [
        "9A8C98", "B8745B", "5B7B8C", "7B8C5B", "8C6B98", "C08D5A"
    ]

    static func hexColor(_ hex: String) -> Color {
        var value: UInt64 = 0
        let cleaned = hex.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "#", with: "")
        guard Scanner(string: cleaned).scanHexInt64(&value), cleaned.count == 6 else {
            return .secondary
        }
        let red = Double((value >> 16) & 0xFF) / 255.0
        let green = Double((value >> 8) & 0xFF) / 255.0
        let blue = Double(value & 0xFF) / 255.0
        return Color(red: red, green: green, blue: blue)
    }

    static func subjectAccent() -> String { accentPalette[0] }
}