# Privacy

Riftglass has no account, no backend, no analytics and no telemetry. Logs go only to the macOS unified
log (`os.Logger`) and never contain client tokens.

## What stays on your Mac
- The League client's local API (LCU) on `127.0.0.1`: champ select, rune pages, item sets, region.
  The auth token is read from the client's process arguments and only kept in memory.
- The Live Client Data API on `127.0.0.1:2999` during a game.
- Settings in `UserDefaults`, caches in `~/Library/Caches/Riftglass` and
  `~/Library/Application Support/Riftglass`.

## What is sent over the network
| Recipient | When | Data |
|---|---|---|
| OP.GG (`mcp-api.op.gg`) | champ select | champion name and role |
| OP.GG (`op.gg`, public champion page) | ARAM: Mayhem champ select or game, at most one answered request per champion in 6 hours (without any answer, e.g. offline, retried after a minute at the earliest) | champion ID |
| OP.GG (`mcp-api.op.gg`) | champ select, if "Matchup-Briefing" is on | your champion, the enemy lane champion and the role (no names or IDs of players) |
| OP.GG (`mcp-api.op.gg`) | champ select, if "Pick & ban options" is on | the tier list (no parameters), champion names and roles of your team and of visible enemies (no names or IDs of players); your mastery is read from the local client and never sent |
| OP.GG (`mcp-api.op.gg`) | game start, if "Ränge über OP.GG laden" is on | Riot IDs (name#tag) of the players in your game, region |
| Riot Data Dragon (`ddragon.leagueoflegends.com`) | first champ select per patch | nothing personal (static files) |
| GitHub (`raw.githubusercontent.com`, releases) | update check | standard Sparkle request (app version, macOS version) |

You can turn off the rank lookup in Settings → "Im Spiel".
