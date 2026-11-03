# Riftglass

Native macOS companion app for League of Legends (working title): rune/spell/item-set import in
champ select, later loading-screen ranks and an in-game overlay. Swift 6, SwiftUI + AppKit, no
Electron, no injection.

> **Riftglass isn't endorsed by Riot Games and doesn't reflect the views or opinions of Riot Games or
> anyone officially involved in producing or managing Riot Games properties. Riot Games, and all
> associated properties are trademarks or registered trademarks of Riot Games, Inc.**

## Status

| Phase | Inhalt | Stand |
|---|---|---|
| 0 | Scaffolding, Verifikations-Spike (`docs/SPIKE.md`) | fertig (Port 2999 + Overlay-Level → Phase 2) |
| 1 | Client-Erkennung, LCU (REST + WAMP), Champ-Select-Panel, Import | fertig, Platzhalter-Builds |
| 2–4 | Overlay, Backend, Verteilung | geplant (`docs/PLAN.md`) |

## Voraussetzungen

- macOS 14+, Apple Silicon, Xcode 16+ (getestet mit Xcode 27.2)
- `brew install xcodegen swiftlint swiftformat pre-commit jq` (oder `scripts/bootstrap.sh`, fragt vorher)
- Ein „Apple Development“-Zertifikat. Team-ID steht in `src/mac/project.yml` (`DEVELOPMENT_TEAM`).

## Befehle

```bash
scripts/bootstrap.sh   # einmalig: Tools prüfen, .env anlegen, pre-commit, Xcode-Projekt erzeugen
scripts/test.sh        # swift test für alle vier Packages
scripts/lint.sh        # SwiftFormat + SwiftLint (strict); --fix formatiert
scripts/build.sh       # xcodegen + xcodebuild (signiert); CI: scripts/build.sh CODE_SIGNING_ALLOWED=NO
```

Die App liegt danach unter `build/DerivedData/Build/Products/Debug/Riftglass.app` und lebt nur in der
Menüleiste (◆).

## Struktur

```
src/mac/project.yml          XcodeGen-Spezifikation (Riftglass.xcodeproj wird generiert, nicht eingecheckt)
src/mac/App/                 Menüleisten-App, Champ-Select-UI, Verbindungs-Lebenszyklus
src/mac/Packages/LeagueKit   Prozess-Erkennung, Credentials, TLS, LCU-REST/WAMP, Spielphase, Import-Logik
src/mac/Packages/DataKit     Data Dragon + Icon-Cache
src/mac/Packages/StatsKit    BuildProvider (Phase 1: Platzhalter)
src/mac/Packages/OverlayKit  NSPanel, Docking an den Client
tests/fixtures/              anonymisierte Aufnahmen vom echten Client
scripts/spike/               Verifikations-Skripte (brauchen laufenden Client)
docs/                        PLAN, SPIKE, ARCHITECTURE, COMPLIANCE
```

## Umgebungsvariablen

Die macOS-App braucht keine. Für das Backend (Phase 3) siehe `.env.example`: `RIOT_API_KEY`,
`DATABASE_URL` – nur in `.env` bzw. Dokploy, nie im Repo.

## Regeln

Siehe `docs/COMPLIANCE.md`: keine Gegner-Timer, kein Speicherlesen, keine Injection, keine Automatisierung.
