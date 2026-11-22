import SwiftUI

struct InGameSettingsSection: View {
    let model: AppModel
    @Bindable var settings: AppSettings

    private var regionBinding: Binding<String> {
        Binding(
            get: { settings.manualRegion ?? "" },
            set: { settings.manualRegion = $0.isEmpty ? nil : $0 }
        )
    }

    var body: some View {
        Section("In game") {
            Toggle("Skill point hint (which ability to level next)", isOn: $settings.skillOverlayEnabled)
            HStack {
                Slider(value: $settings.skillOverlayOffset, in: 0.10 ... 0.40, step: 0.02) {
                    Text("Skill hint height")
                }
                Text("\(Int((settings.skillOverlayOffset * 100).rounded()))%")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .frame(width: 38, alignment: .trailing)
            }
            .onChange(of: settings.skillOverlayOffset) { _, _ in model.inGame.updatePreviewOffset() }
            Button("Preview overlays (5 s)") { model.inGame.previewOverlays() }
            Toggle("ARAM: Mayhem – augment list at every augment choice", isOn: $settings.augmentOverlayEnabled)
            Picker("Augment overlay shortcut", selection: $settings.augmentToggleKeyCode) {
                ForEach(ToggleShortcut.allCases) { shortcut in
                    Text(shortcut.label).tag(shortcut.rawValue)
                }
            }
            .onChange(of: settings.augmentToggleKeyCode) { _, _ in model.inGame.updateHotkeySettings() }
            Text("""
            Appears next to the selection cards at game start and after levels 7, 11 and 15, once you are \
            dead or in the fountain: your champion's strong augments per rarity (OP.GG). Riftglass does not \
            read the offered cards. \(settings.toggleShortcutLabel) hides the list until the next choice and \
            shows it again (needs Input Monitoring); holding Tab shows it any time.
            """)
            .font(.caption).foregroundStyle(.secondary)
            Toggle("Tab overlay (ranks, CS/min, build progress)", isOn: $settings.tabOverlayEnabled)
            Toggle("Show objective respawn timers (Dragon, Baron, Inhib)", isOn: $settings.objectiveTimersEnabled)
            InputMonitoringStep()
            Toggle("Load ranks from OP.GG", isOn: $settings.ranksEnabled)
            Picker("Region", selection: regionBinding) {
                Text("Automatic").tag("")
                ForEach(AppSettings.knownRegions, id: \.self) { region in
                    Text(region).tag(region)
                }
            }
            Text("Sends the Riot IDs of the players in your current game to OP.GG.")
                .font(.caption).foregroundStyle(.secondary)
            Toggle("Item gold estimate per lane (experimental)", isOn: $settings.goldEstimateEnabled)
            Text("Only from visible items. Whether Riot allows this is unclear – so it is off by default.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}

struct DiagnosticsSettingsSection: View {
    let model: AppModel
    let settings: AppSettings
    @State private var cacheSize = CacheManager.formattedSize(CacheManager.totalBytes())

    var body: some View {
        Section("Diagnostics & Cache") {
            LabeledContent(
                "League client",
                value: model.isLCUConnected ? String(localized: "Connected") : String(localized: "Not connected")
            )
            LabeledContent(
                "Active region",
                value: settings.effectiveRegion ?? String(localized: "Unknown (open client once)")
            )
            LabeledContent(
                "Data Dragon patch",
                value: model.champSelect.staticData?.version ?? String(localized: "Not loaded yet")
            )
            LabeledContent("Cached data") {
                HStack(spacing: 8) {
                    Text(cacheSize).monospacedDigit().foregroundStyle(.secondary)
                    Button("Clear caches") {
                        CacheManager.clearAll()
                        cacheSize = CacheManager.formattedSize(CacheManager.totalBytes())
                    }
                }
            }
        }
        .onAppear { cacheSize = CacheManager.formattedSize(CacheManager.totalBytes()) }
    }
}
