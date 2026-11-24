import FlashCardsCore
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

    /// 📅 Fixed checkpoints vs 🧠 FSRS.
    static let fixed = dynamic(light: 0x2F6FB5, dark: 0x6FA8E8)
    static let fsrs = dynamic(light: 0x7A4FB8, dark: 0xB08AE8)

    /// C program categories are shown in a code font.
    static func isCode(_ topic: String) -> Bool { topic.lowercased().contains("program") }

    static func questionFont(_ topic: String, size: CGFloat = 19) -> Font {
        isCode(topic) ? .system(size: size - 2, weight: .bold, design: .monospaced) : .system(size: size, weight: .bold)
    }

    static func answerFont(_ topic: String, size: CGFloat = 14) -> Font {
        isCode(topic) ? .system(size: size - 1, design: .monospaced) : .system(size: size)
    }

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

/// Which method schedules a card: 📅 fixed checkpoints or 🧠 FSRS.
/// 📅 Fixed checkpoint and 🧠 FSRS chips for a studied card. The method that sets the
/// card's next date is solid; the other is faded.
struct PhaseBadge: View {
    let review: CardReview?
    var compact = false

    var body: some View {
        if let review, let phase = Scheduler.phase(of: review) {
            let next = Scheduler.nextMethod(of: review)
            HStack(spacing: 4) {
                if let fixed = fixedText(phase) {
                    chip(fixed, Theme.fixed, active: next == .fixed)
                }
                chip(fsrsText(review, phase), Theme.fsrs, active: next == .fsrs || phase == .startsAtNextReview)
            }
            .help(helpText(review, phase))
        }
    }

    private func chip(_ text: String, _ color: Color, active: Bool) -> some View {
        Text(text)
            .font(.system(size: compact ? 10 : 11, weight: .bold))
            .foregroundStyle(color)
            .padding(.vertical, 3).padding(.horizontal, 8)
            .background(color.opacity(active ? 0.18 : 0.06), in: Capsule())
            .overlay(Capsule().stroke(color.opacity(active ? 0.5 : 0), lineWidth: 1))
            .opacity(active ? 1 : 0.6)
            .fixedSize()
    }

    private func fixedText(_ phase: Scheduler.Phase) -> String? {
        switch phase {
        case .startsAtNextReview: return compact ? "📅 starts today" : "📅 Fixed · starts today"
        case .checkpoint(let n, let day): return compact ? "📅 \(n)/4 · day \(day)" : "📅 Fixed \(n)/4 · day \(day)"
        case .fsrs: return nil
        }
    }

    private func fsrsText(_ r: CardReview, _ phase: Scheduler.Phase) -> String {
        if phase == .startsAtNextReview { return compact ? "🧠 starts today" : "🧠 FSRS · starts today" }
        let days = Int(r.stability.rounded())
        return compact ? "🧠 ~\(days)d" : "🧠 FSRS · memory ~\(days)d"
    }

    private func helpText(_ r: CardReview, _ phase: Scheduler.Phase) -> String {
        if phase == .startsAtNextReview { return "Revise today: its 1, 3, 7, 14-day checkpoints and FSRS both start then." }
        var parts: [String] = []
        if let cp = Scheduler.checkpointDue(of: r) { parts.append("📅 Next checkpoint: \(cp)") }
        if let f = Scheduler.fsrsDue(of: r) { parts.append("🧠 FSRS date: \(f)") }
        parts.append("Comes back on whichever is first.")
        return parts.joined(separator: "\n")
    }
}

extension Scheduler.Phase {
    var isFixed: Bool { if case .fsrs = self { return false } else { return true } }
}
