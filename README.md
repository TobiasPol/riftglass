# Riftglass

A native macOS companion app for League of Legends: builds and rune import in champ select, ranks and
a Tab overlay in game. Written in Swift 6 with SwiftUI and AppKit. No Electron, no injection, no memory
reading. It lives in your menu bar and uses close to 0 % CPU while League is closed.

> **Riftglass isn't endorsed by Riot Games and doesn't reflect the views or opinions of Riot Games or
> anyone officially involved in producing or managing Riot Games properties. Riot Games, and all
> associated properties are trademarks or registered trademarks of Riot Games, Inc.**

## Features

**Champ select**: a panel docks next to the League client as soon as you hover a champion:
- An **OP.GG build** for your champion and role: runes, summoner spells, starter/core/boots, next items,
  skill order, win rate and sample size.
- **Riot's own recommendations** from the client, which also work offline.
- **Game mode detection** (Ranked, Flex, ARAM, ARAM: Mayhem, Arena, URF, …): builds and item sets match
  the mode; in ARAM: Mayhem the champion's most picked augments.
- **Automatic import after lock-in**: the item set by default, runes and spells if you opt in.
- A **matchup briefing**: your likely lane opponent with your head-to-head win rate, lane advantage and
  a tip; both teams' physical/magic damage split and frontline; during your pick turn, counter options
  against your lane opponent (with win rate and sample size).
- One click imports runes, spells and an item set. Riftglass only replaces **its own** rune page
  ("Riftglass: …") and item sets. Your other pages and sets (OP.GG, U.GG, Blitz, …) are never touched.

**In game** (hold <kbd>Tab</kbd>):
- Solo-queue rank, KDA and CS for all ten players.
- Your CS/min compared with a guide value for your role, and progress on your planned build.
- At game start, a short banner with every player's rank.
- A **skill-point hint** above the ability bar whenever you can level an ability, following OP.GG's
  most common skill order.
- **ARAM: Mayhem**: whenever an augment choice is open (game start, then levels 7, 11 and 15 while dead
  or in the fountain), your champion's strong augments per rarity appear left of the selection cards.
  <kbd>⌥A</kbd> hides the list until the next choice or shows it any time.
- Optional, off by default: an item-gold estimate per lane, calculated from visible items only.

**After the game**, the menu bar shows a short summary of your last game.

## Install

1. Download the latest `Riftglass-x.y.z.dmg` from [Releases](https://github.com/TobiasPol/riftglass/releases).
   It is signed with a Developer ID and notarized by Apple.
2. Drag Riftglass to Applications and start it. A ◆ appears in the menu bar.
3. For the Tab overlay and <kbd>⌥A</kbd>, grant **Input Monitoring** when asked, then restart Riftglass.
   Riftglass only *listens* for these keys and never changes or sends input.

Riftglass is in **English and German** and follows your macOS language; champion, item and augment
names use the same language. To pick one for Riftglass only: System Settings → General → Language &
Region → Applications.

Updates arrive automatically through Sparkle (signed with EdDSA).

Requirements: macOS 14 or later, Apple Silicon.

## Data sources and privacy

| Data | Source | Leaves your Mac? |
|---|---|---|
| Champ select, rune pages, item sets | League client API (LCU, `127.0.0.1`) | no |
| In-game stats | Live Client Data API (`127.0.0.1:2999`) | no |
| Builds, win rates | [OP.GG](https://op.gg) public MCP API | champion + role only |
| Matchups, counters, lane shares | OP.GG public MCP API | your champion, the enemy champion and the role |
| Ranks | OP.GG public MCP API | Riot IDs of the players in your game (can be turned off) |
| Icons, item data | Riot Data Dragon CDN | no personal data |

There is no telemetry, no account and no backend. Details: [PRIVACY.md](PRIVACY.md).
Build and rank data © OP.GG. Riftglass is not affiliated with OP.GG.

## What Riftglass will never do

No enemy ultimate or summoner spell timers, no memory reading, no injection, no input automation,
nothing the player cannot see in game. See [docs/COMPLIANCE.md](docs/COMPLIANCE.md).

## Build from source

```bash
brew install xcodegen swiftlint swiftformat pre-commit jq
scripts/bootstrap.sh                          # .env, pre-commit, Xcode project
scripts/test.sh                               # unit tests of all packages
scripts/build.sh CODE_SIGNING_ALLOWED=NO      # unsigned debug build
```

Signed builds use the team in `src/mac/project.yml`; change `DEVELOPMENT_TEAM` to your own.
Releases: [docs/RELEASING.md](docs/RELEASING.md). Architecture: [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md).
Verified facts about the macOS client (ports, certificates, WAMP quirks): [docs/SPIKE.md](docs/SPIKE.md).

## Contributing

Issues and pull requests are welcome. See [CONTRIBUTING.md](CONTRIBUTING.md).

## License

[MIT](LICENSE) © 2026 Tobias Polley
