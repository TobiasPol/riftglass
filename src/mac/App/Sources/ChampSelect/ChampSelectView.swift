import DataKit
import StatsKit
import SwiftUI

/// Content of the docked champ-select panel.
struct ChampSelectView: View {
    let coordinator: ChampSelectCoordinator

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            Divider().overlay(Palette.hairline)
            content
            Spacer(minLength: 0)
            footer
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Palette.background, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Palette.hairline))
        .foregroundStyle(Palette.text)
        .environment(\.colorScheme, .dark)
    }

    private var header: some View {
        HStack(spacing: 10) {
            if let id = coordinator.championId, let data = coordinator.staticData, let champion = data.champion(id) {
                IconView(
                    url: coordinator.dataDragon.championIconURL(champion, version: data.version),
                    icons: coordinator.icons,
                    size: 36
                )
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(coordinator.championName ?? "Champ Select")
                    .font(.system(size: 15, weight: .semibold))
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(Palette.secondaryText)
            }
        }
    }

    private var subtitle: String {
        guard let role = coordinator.role else { return "Riftglass" }
        return "Riftglass · \(role.rawValue.capitalized)"
    }

    @ViewBuilder
    private var content: some View {
        if coordinator.championId == nil {
            placeholder("Wähle oder hovere einen Champion, um Build-Optionen zu sehen.")
        } else if coordinator.isLoadingBuilds {
            ProgressView().controlSize(.small).frame(maxWidth: .infinity)
        } else if coordinator.builds.isEmpty {
            placeholder("Keine Builds verfügbar – OP.GG ist nicht erreichbar und der Client liefert keine Empfehlung.")
        } else {
            ScrollView {
                VStack(spacing: 10) {
                    ForEach(coordinator.builds) { build in
                        BuildOptionCard(build: build, coordinator: coordinator)
                    }
                }
            }
            .scrollIndicators(.never)
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 6) {
            ActionStatusView(state: coordinator.actionState)
            Text(Disclaimer.short)
                .font(.system(size: 9))
                .foregroundStyle(Palette.tertiaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func placeholder(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12))
            .foregroundStyle(Palette.secondaryText)
            .fixedSize(horizontal: false, vertical: true)
    }
}

private struct ActionStatusView: View {
    let state: ChampSelectCoordinator.ActionState

    var body: some View {
        switch state {
        case .idle:
            EmptyView()
        case let .running(text):
            Label { Text(text) } icon: { ProgressView().controlSize(.mini) }
                .font(.system(size: 11))
        case let .done(text):
            Label(text, systemImage: "checkmark.circle.fill")
                .font(.system(size: 11)).foregroundStyle(.green)
        case let .failed(text):
            Label(text, systemImage: "exclamationmark.triangle.fill")
                .font(.system(size: 11)).foregroundStyle(.orange)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

enum Palette {
    static let background = Color(red: 0.07, green: 0.08, blue: 0.10).opacity(0.97)
    static let card = Color.white.opacity(0.05)
    static let hairline = Color.white.opacity(0.10)
    static let text = Color.white.opacity(0.92)
    static let secondaryText = Color.white.opacity(0.60)
    static let tertiaryText = Color.white.opacity(0.38)
    static let accent = Color(red: 0.36, green: 0.78, blue: 0.86)
    static let positive = Color(red: 0.42, green: 0.82, blue: 0.55)
    static let negative = Color(red: 0.95, green: 0.45, blue: 0.42)
}
