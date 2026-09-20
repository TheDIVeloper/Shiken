import Foundation

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
}