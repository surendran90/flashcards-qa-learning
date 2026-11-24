import FlashCardsCore
import SwiftUI

/// Timer chip shown on the card: "⏱ 5:00 ▶", a ring that fills, red overtime ("+1:20").
struct CardTimerView: View {
    @Environment(CardTimer.self) private var timer

    var body: some View {
        let color = timer.isOvertime ? Theme.red : (timer.isRunning ? Theme.accent : Theme.muted)
        HStack(spacing: 8) {
            ZStack {
                Circle().stroke(Theme.border, lineWidth: 3)
                Circle().trim(from: 0, to: timer.fraction)
                    .stroke(color, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
            .frame(width: 18, height: 18)
            Text(CardTiming.display(remaining: timer.remaining))
                .font(.system(size: 14, weight: .bold).monospacedDigit())
                .foregroundStyle(timer.isOvertime ? Theme.red : Theme.ink)
                .fixedSize()
            Button { timer.toggle() } label: {
                Image(systemName: timer.isRunning ? "pause.fill" : "play.fill")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 24, height: 24)
                    .background(timer.isRunning ? Theme.inkButton : Theme.accent, in: Circle())
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .help(timer.isRunning ? "Pause (⌥Space)" : "Start the \(timer.limitMinutes)-minute timer (⌥Space)")
            if timer.elapsed > 0 && !timer.isRunning {
                Button { timer.reset() } label: {
                    Image(systemName: "arrow.counterclockwise").font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Theme.muted)
                }
                .buttonStyle(.plain)
                .help("Reset this card's timer")
            }
        }
        .padding(.vertical, 5).padding(.horizontal, 10)
        .background(Theme.bg, in: Capsule())
        .overlay(Capsule().stroke(timer.isOvertime ? Theme.red.opacity(0.6) : Theme.border))
        .fixedSize()
    }
}

/// Suggests a break after 50 minutes of timed work.
struct BreakNudge: View {
    @Environment(CardTimer.self) private var timer

    var body: some View {
        if timer.showBreakNudge {
            HStack(spacing: 10) {
                Text("☕️")
                Text("50 minutes of focused work — take a 10-minute break. Stand up, drink water, look away from the screen.")
                    .font(.system(size: 13))
                Spacer()
                Button("OK") { timer.dismissBreakNudge() }.buttonStyle(OutlineButtonStyle())
            }
            .padding(.vertical, 10).padding(.horizontal, 14)
            .background(Theme.accentSoft, in: RoundedRectangle(cornerRadius: 10))
            .padding(.bottom, 14)
        }
    }
}
