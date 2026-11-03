# Riftglass

## Overview
Native macOS companion app for League of Legends (Blitz.gg/OP.GG-like, within Riot's rules). Reads only
local Riot APIs (LCU, Live Client Data API on 2999). Plan: `docs/PLAN.md`; verified facts about the real
client: `docs/SPIKE.md` – trust SPIKE.md over community docs.

## Tech Stack
- Language: Swift 6 (language mode 6, strict concurrency), macOS 14+, arm64
- UI: SwiftUI for content, AppKit `NSPanel` for windows
- Project: XcodeGen (`src/mac/project.yml`) + four local Swift packages
- Tests: Swift Testing (`import Testing`), fixtures in `tests/fixtures`
- Build data: OP.GG public MCP API + Riot recommendations via LCU (no backend, no Riot API key)
- Updates: Sparkle 2 (EdDSA, appcast.xml in repo); distribution: notarized DMG via scripts/release.sh
- Database: none

## Commands
- `scripts/build.sh` — generate Xcode project + build app (signed; add `CODE_SIGNING_ALLOWED=NO` unsigned)
- `scripts/test.sh` — `swift test` for all packages
- `scripts/lint.sh` — SwiftFormat check + SwiftLint strict (`--fix` to format)
- `scripts/release.sh <version>` — Developer ID build, notarize, DMG, appcast (see docs/RELEASING.md)
- `scripts/spike/*.sh` — need a running League client; never print tokens

## Architecture
See `docs/ARCHITECTURE.md`. LeagueKit = client detection/LCU/state machine/import logic (pure, tested);
DataKit = Data Dragon + icons; StatsKit = build providers; OverlayKit = panels/docking; App = wiring + UI.

## Environment Variables
None. Release script uses `NOTARY_PROFILE` (default `riftglass`, a notarytool keychain profile).

## Rules
- Max 300 lines per file, 50 per function (SwiftLint enforces).
- Never log or persist LCU tokens; `--riotgamesapi-settings` contains foreign tokens – never read it.
- Import only touches Riftglass-owned data: rune pages named `Riftglass…`, item sets with uid prefix
  `52494654-474c-4153-53`. `DELETE /lol-perks/v1/pages` only with an ID.
- WAMP: subscribe to `OnJsonApiEvent` after the welcome frame; specific topics deliver nothing on macOS.
- The LCU is closed during games on macOS – in-game data only from the Live Client API (2999).
- In-game overlays must use `CGShieldingWindowLevel() + 1` (`.screenSaver` is below the game).
- OP.GG MCP answers in a class notation, not JSON – parse with `OPGGNotation`.
- Forbidden features (docs/COMPLIANCE.md): enemy ult/spell timers, memory reading, injection, input automation.
- Fixtures must be anonymized (`scripts/spike/lib.sh: anonymize`).
