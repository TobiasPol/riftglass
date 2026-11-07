import LeagueKit
import SwiftUI

/// Small pill above the ability bar: the ability to level now, plus the next steps of the order.
/// Solid background, no `Material` blur in game (GPU cost).
struct SkillOverlayView: View {
    let advice: SkillAdvice

    var body: some View {
        HStack(spacing: 10) {
            Text(advice.unspentPoints > 1 ? "\(advice.unspentPoints) skill points" : "Skill point")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Palette.secondaryText)
            KeyCap(slot: advice.next, prominent: true)
            if !advice.then.isEmpty {
                Text("then").font(.system(size: 10)).foregroundStyle(Palette.tertiaryText)
                ForEach(Array(advice.then.enumerated()), id: \.offset) { _, slot in
                    KeyCap(slot: slot, prominent: false)
                }
            }
            Text("OP.GG").font(.system(size: 9)).foregroundStyle(Palette.tertiaryText)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(Palette.background, in: Capsule())
        .overlay(Capsule().strokeBorder(Palette.hairline))
        .foregroundStyle(Palette.text)
        .environment(\.colorScheme, .dark)
    }
}

private struct KeyCap: View {
    let slot: SkillSlot
    let prominent: Bool

    var body: some View {
        Text(slot.rawValue)
            .font(.system(size: prominent ? 17 : 11, weight: .bold, design: .rounded))
            .frame(width: prominent ? 30 : 20, height: prominent ? 30 : 20)
            .background(
                prominent ? Palette.accent.opacity(0.9) : Color.white.opacity(0.08),
                in: RoundedRectangle(cornerRadius: 6, style: .continuous)
            )
            .foregroundStyle(prominent ? Color.black : Palette.secondaryText)
    }
}
