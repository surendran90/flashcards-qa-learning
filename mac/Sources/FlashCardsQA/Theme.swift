import AppKit
import SwiftUI

/// Colors from `src/App.js`, with dark-mode variants.
enum Theme {
    static let ink = dynamic(light: 0x20211F, dark: 0xECEBE6)
    static let muted = dynamic(light: 0x777970, dark: 0xA3A59C)
    static let border = dynamic(light: 0xE6E1D8, dark: 0x3A3B37)
    static let card = dynamic(light: 0xFFFFFF, dark: 0x262724)
    static let bg = dynamic(light: 0xF7F5F0, dark: 0x1A1B19)
    static let accent = dynamic(light: 0x4B9479, dark: 0x5DAA8D)
    static let accentSoft = dynamic(light: 0xE9F5EF, dark: 0x22362E)
    static let red = dynamic(light: 0xD95F59, dark: 0xE2746E)
    static let redSoft = dynamic(light: 0xFFF0EF, dark: 0x3A2524)
    static let subtle = dynamic(light: 0xF1EFE9, dark: 0x30312D)
    /// Primary dark button fill (stays dark-ish in both themes).
    static let inkButton = dynamic(light: 0x20211F, dark: 0x44463F)

    private static func dynamic(light: UInt32, dark: UInt32) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let hex = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
            return NSColor(
                srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
                green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255,
                alpha: 1)
        })
    }
}

struct FilledButtonStyle: ButtonStyle {
    var color: Color
    var foreground: Color = .white
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .bold))
            .foregroundStyle(foreground)
            .padding(.vertical, 10)
            .padding(.horizontal, 17)
            .background(color.opacity(configuration.isPressed ? 0.8 : 1), in: RoundedRectangle(cornerRadius: 10))
            .opacity(isEnabled ? 1 : 0.45)
            .contentShape(Rectangle())
    }
}

struct OutlineButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .bold))
            .foregroundStyle(Theme.ink)
            .padding(.vertical, 9)
            .padding(.horizontal, 15)
            .background(Theme.card.opacity(configuration.isPressed ? 0.7 : 1), in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.border))
            .opacity(isEnabled ? 1 : 0.55)
            .contentShape(Rectangle())
    }
}

struct LinkButtonStyle: ButtonStyle {
    var underline = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13))
            .underline(underline)
            .foregroundStyle(Theme.muted.opacity(configuration.isPressed ? 0.6 : 1))
            .contentShape(Rectangle())
    }
}

extension View {
    func panel(radius: CGFloat = 16) -> some View {
        background(Theme.card, in: RoundedRectangle(cornerRadius: radius))
            .overlay(RoundedRectangle(cornerRadius: radius).stroke(Theme.border))
    }
}
