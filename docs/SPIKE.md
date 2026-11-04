# Verifikations-Spike (Phase 0)

Durchgeführt am 2026-11-02/03 auf macOS 27.2 (Apple Silicon), Xcode 27.2, League-Client Region EUW,
Practice-Tool-Champ-Select (Queue 3140). Skripte: `scripts/spike/`. Rohausgaben landen in
`scripts/spike/out/` (gitignored); anonymisierte Fixtures in `tests/fixtures/lcu/`.

## Ergebnisse

| # | Frage (PLAN §7) | Ergebnis | Skript |
|---|---|---|---|
| 1 | Bundle-IDs | siehe unten – bestätigt | `01-bundle-ids.sh` |
| 2 | Prozess-Argumente | `--app-port`, `--remoting-auth-token`, `--install-directory` vorhanden | `02-process-args.sh` |
| 3 | Lockfile | `<install-directory>/lockfile`, gehört `LeagueClient`, bleibt nach Beenden liegen | `03-lockfile.sh` |
| 4 | Zertifikat LCU | Kette mit `riotgames.pem` gültig, SAN `localhost` + `127.0.0.1` | `04-tls.sh` |
| 5 | Zertifikat 2999 | **offen** – braucht laufendes Spiel | `04-tls.sh` |
| 6 | REST-Endpunkte | alle aus PLAN §4.2 liefern 200 | `05-endpoints.sh` |
| 7 | Item-Set-Pfad | `/lol-item-sets/v1/item-sets/{summonerId}/sets` funktioniert weiterhin | `05-endpoints.sh` |
| 8 | WebSocket | Subprotocol `wamp` ok; **spezifische Topics liefern nichts** | `06`, `09`–`11` |
| 9 | Besitzer Client-Fenster | `LeagueClientUx` | `07-window-owner.swift` |
| 10 | Overlay-Level im Vollbild | **offen** – braucht laufendes Spiel (Phase 2) | `08-overlay-level.swift` |

### 1. Bundle-IDs
| Bundle-ID | Executable | LSUIElement | Pfad |
|---|---|---|---|
| `com.riotgames.leagueoflegends` | Launcher | – | `/Applications/League of Legends.app` |
| `com.riotgames.LeagueofLegends.LeagueClient` | `LeagueClient` | **1** | `Contents/LoL/LeagueClient.app` |
| `com.riotgames.LeagueofLegends.LeagueClientUx` | `LeagueClientUx` | 0 | `Contents/LoL/League of Legends.app` |
| `com.riotgames.LeagueofLegends.GameClient` | `LeagueofLegends` | 0 | `Contents/LoL/Game/LeagueofLegends.app` |
| `com.riotgames.RiotGames.RiotClient` | Riot Client | – | `/Users/Shared/Riot Games/Riot Client.app` |

`LeagueClient` ist ein Hintergrundprozess (LSUIElement) → bestätigt die Entscheidung für KVO auf
`runningApplications` statt `didLaunchApplicationNotification`. Helper-Prozesse heißen
`LeagueClientUx Helper (…)`, `pgrep -x`/Bundle-ID-Vergleich muss exakt sein.

### 2. Prozess-Argumente (`LeagueClientUx`)
- `--app-port=<port>`, `--remoting-auth-token=<22 Zeichen>`, `--app-pid=<pid von LeagueClient>`,
  `--install-directory=/Applications/League of Legends.app/Contents/LoL` – **enthält Leerzeichen**.
  Parsen über `KERN_PROCARGS2` (NUL-getrennt), niemals per Leerzeichen splitten.
- **Sicherheit:** `--riotgamesapi-settings=<base64-JSON>` enthält weitere Tokens (Riot-Client-Port +
  Auth-Token, `rso_auth.authorization-key`). Riftglass liest dieses Argument nie, und jede Log-/
  Debug-Ausgabe von Argumenten muss es schwärzen (`scripts/spike/lib.sh: redact`).
- `--subject=` enthält die PUUID des Spielers.

### 3. Lockfile
- Pfad `<install-directory>/lockfile`, Format `LeagueClient:<pid>:<port>:<password>:https`,
  **ohne abschließenden Zeilenumbruch**. PID ist die von `LeagueClient`, nicht `LeagueClientUx`.
- Die Datei bleibt nach dem Beenden liegen (alte PID/Port) → Fallback muss die PID auf Lebendigkeit
  prüfen (`kill(pid, 0)`).
- Daneben existiert `/Users/Shared/Riot Games/Metadata/league_of_legends.live/…lockfile` (Riot Client,
  anderes Format) – nicht verwenden.

### 4. TLS (LCU-Port)
- Kette: Leaf `CN=rclient` (gültig 2026 → **2125**, `CA:FALSE`, SAN `DNS:localhost, IP:127.0.0.1`)
  + CA `LoL Game Engineering Certificate Authority` (2013 → 2043).
- Die CA ist identisch mit Riots öffentlicher `riotgames.pem`
  (SHA-256 `CA:8C:9D:32:5B:4C:DC:46:4C:6C:94:A5:85:C8:5E:91:EC:23:D4:0B:A5:BF:3A:E2:82:2B:95:1A:4A:50:4E:A3`,
  abgeglichen mit `static.developer.riotgames.com/docs/lol/riotgames.pem`).
- `openssl verify -CAfile riotgames.pem` → OK. Plan bleibt: `SecPolicyCreateBasicX509()` + Anker +
  eigene Host/Port-Prüfung. Die SSL-Policy wäre wegen der SAN jetzt zwar möglich, aber die
  Leaf-Laufzeit von 100 Jahren verletzt Apples TLS-Laufzeitregeln – der Unit-Test
  `TrustEvaluatorTests` hält das Verhalten mit der aufgezeichneten Kette fest.
- Public-Key-Pinning-Fallback ist **nicht nötig**.

### 6./7. REST
Alle `200` im Lobby-Zustand: `gameflow-phase`, `current-summoner`, `perks/inventory`, `perks/pages`,
`item-sets/{summonerId}/sets`, `ranked-stats/{puuid}`; im Champ Select zusätzlich `session` und
`session/my-selection`. `/lol-loadouts/v4/loadouts/scope/account` existiert ebenfalls, wird nicht gebraucht.
- `perks/inventory` lieferte `canAddCustomPage: false` bei 2/2 belegten Seiten (beide von Drittanbieter-
  Tools). Ohne eigene „Riftglass“-Seite und ohne freien Platz darf Riftglass **nichts** löschen →
  Fehlermeldung statt fremde Seite zu ersetzen.
- Item-Sets: 62 Sets anderer Tools (U.GG etc.) im Account → Merge per `uid` ist Pflicht.

### 8. WebSocket (WAMP 1.0)
- Upgrade nur über HTTP/1.1 (`curl` versucht sonst HTTP/2 → 404). `URLSessionWebSocketTask` ist ok.
- Begrüßung: `[0, "<session>", 1, "WAMP-1.0-RiotRemoting"]`. Abos erst **nach** dieser Nachricht senden.
- `[5, "OnJsonApiEvent_lol-gameflow_v1_gameflow-phase"]` und `[5, "OnJsonApiEvent_lol-champ-select_v1_session"]`
  lieferten in zwei Durchläufen (Lobby → Champ Select → Lobby) **kein einziges Event**. Das Sammel-Topic
  `[5, "OnJsonApiEvent"]` liefert alle Events als `[8, "OnJsonApiEvent", {data, eventType, uri}]`, u. a.
  `/lol-gameflow/v1/gameflow-phase` und `/lol-champ-select/v1/session`.
  → **Plan-Änderung:** Sammel-Topic abonnieren, URI clientseitig filtern; vor dem JSON-Dekodieren per
  Byte-Suche auf die zwei relevanten URIs vorfiltern (die meisten Events betreffen andere URIs, z. B.
  `skin-carousel-skins`, `lol-chat`, `lol-lobby-team-builder`).
- Event-Fixture `tests/fixtures/lcu/ws-champ-select-event.json`: Umschlag wie live beobachtet, Nutzlast
  aus der REST-Aufzeichnung der Session (die Nutzlasten selbst wurden nicht mitgeschnitten).

### 9. Client-Fenster
- Besitzer: `LeagueClientUx` (PID aus `--app-pid` ist **nicht** der Fensterbesitzer), Layer 0,
  1600×900 Punkte. `kCGWindowName` ist ohne Bildschirmaufnahme-Recht leer → Fenster über PID +
  Layer 0 + größte Fläche wählen, nicht über den Namen.

## Offen (→ Phase 2, braucht laufendes Spiel)
- Port 2999: Zertifikat/Kette (`scripts/spike/04-tls.sh` während eines Spiels).
- Overlay-Level im Vollbild (`swift scripts/spike/08-overlay-level.swift [screensaver|shielding]`).

## Phase-1-Live-Verifikation (2026-11-03, Practice Tool, signierter Debug-Build)

| DoD-Punkt | Ergebnis |
|---|---|
| Panel ≤ 1 s nach Champ-Select-Start | ✓ 7–24 ms zwischen `Mode → champSelect` und `Panel shown` (os_log) |
| Panel angedockt | ✓ rechts neben dem `LeagueClientUx`-Fenster, folgt Fensterbewegung |
| Runen bei vollem Speicher | ✓ Fehlermeldung „kein freier Platz“, keine fremde Seite gelöscht |
| Runen neu anlegen | ✓ `Riftglass: Garen` erstellt (nachdem der Nutzer selbst Platz geschaffen hatte) |
| Eigene Seite ersetzen | ✓ DELETE per ID + POST, neue ID, Keystone gewechselt (8010 → 8437) |
| Spells setzen | ✓ `spell1Id/spell2Id` = 4/14 laut `my-selection` |
| Item-Set mergen | ✓ ein Riftglass-Set pro Champion; 62 fremde Sets byte-identisch (SHA-256 vorher = nachher, `12-snapshot-owned-data.sh`) |
| League geschlossen: ~0 % CPU, keine Timer-Wakeups | ✓ 0,0–0,2 % CPU, 0 Idle-Wakeups, 19 MB (`top`, 30 s) |
| Hover statt Lock-in | ✓ `championPickIntent` wird erkannt (`championId` bleibt 0 bis Lock-in) |

Nicht live geprüft: Ranked-Queue mit zugewiesener Position (Rollenfilter nur per Unit-Test),
Client-Neustart auf neuem Port während die App läuft, mehrere Bildschirme.

## Spike 2 – im Spiel und Build-Quellen (2026-11-03)

Skripte: `13-liveclient.sh`, `14-game-session.sh`, `15-recommendations.sh`, `08-overlay-level.swift`.

| Frage | Ergebnis |
|---|---|
| Läuft die LCU im Spiel? | **Nein.** `LeagueClientUx` beendet sich beim Spielstart (macOS-Standard) → im Spiel nur Live Client API |
| Port 2999 – Zertifikat | gleiches Leaf `CN=rclient` (SAN `127.0.0.1`), Kette nur Leaf; `openssl verify -CAfile riotgames.pem` OK |
| Live Client Endpunkte | `activeplayer`, `playerlist`, `gamestats`, `activeplayername` → 200 (Fixtures `tests/fixtures/liveclient/`) |
| `playerlist` enthält | `riotIdGameName`, `riotIdTagLine`, `team`, `position`, `items`, `scores`, `summonerSpells`, `isBot` – **keine PUUID** |
| Fenster des Spiels | Besitzer `com.riotgames.LeagueofLegends.GameClient`, Ebene **2147483628 = `CGShieldingWindowLevel()`**, Vollbild 3440×1440 |
| Overlay-Ebene im Vollbild | `.screenSaver` **unsichtbar**, `CGShieldingWindowLevel() + 1` **sichtbar** (vom Nutzer bestätigt) |
| Riot-Empfehlungen (LCU) | `GET /lol-perks/v1/recommended-pages/champion/{id}/position/{POS}/map/11` → mehrere Seiten mit `perks`, Styles **und `summonerSpellIds`**, keine Items |
| Positionen pro Champion | `GET /lol-perks/v1/recommended-champion-positions` → `{championId: {recommendedPositions: [...]}}` |
| Region | `GET /riotclient/region-locale` → `{region: "EUW", …}` |

### OP.GG MCP (`https://mcp-api.op.gg/mcp`, offiziell von OP.GG, ohne Key)
- JSON-RPC 2.0 über HTTP POST; `tools/call` funktioniert auch **ohne** `initialize`/Session (zustandslos), ~1,5 s.
- `lol_get_champion_analysis` (`game_mode`, `champion`, `position` ∈ top/mid/jungle/adc/support,
  `desired_output_fields`): eine Runenseite, Starter/Core/Stiefel, 4.–6.-Item-Alternativen, Spells,
  Skill-Order, Win-/Pick-/Ban-Rate, Tier. Champion-Name tolerant (`MONKEYKING`, `WUKONG`, `LEE_SIN`).
- `lol_get_summoner_profile` (`game_name`, `tag_line`, `region`): Rang/LP/W-L pro Queue; unranked → `null`.
- **Antwortformat ist kein JSON**, sondern eine Klassen-Notation:
  `class Runes: id,primary_page_id,…` + `LolGetChampionAnalysis("AHRI",Data(…,Runes(8112,8100,[…]),…))`
  → eigener Parser (`OPGGNotation`). Unzureichende Daten kommen als normales Ergebnis mit Meldungsfeld.

## Spike 3 – Spielmodi und Build-Quellen (2026-11-03, ohne laufenden Client)

| Frage | Ergebnis |
|---|---|
| Queue-IDs | Riots `queues.json`: 420/440 Ranked, 400 Draft, 430 Blind, 480 Swiftplay, 490 Quickplay, 450 ARAM, **2400 ARAM: Mayhem**, 1700/1710 Arena, 900/1900 URF, 1020 OFA, 1400 Ultimate Spellbook, 1300 Nexus Blitz, 2300 Brawl, 1810–1840 Swarm |
| League Classic | seit Patch 26.15 (bis Jan. 2027), Draft/Co-op/Custom, **Queue-ID nicht in `queues.json`** → Erkennung über Queue-Namen, live prüfen |
| OP.GG `game_mode` | Schema: `ranked`, `flex`, `urf`, `aram`, `nexus_blitz`. `ranked`/`flex`/`aram` liefern Builds; **`urf`/`nexus_blitz` lehnen jede Position ab** („must be NONE“, `none`/`NONE` → „invalid“) → nicht nutzbar |
| OP.GG ARAM | `position` Pflicht, wird ignoriert (`mid`/`top`/`adc` identisch); Fixture `opgg/ahri-aram.json`. Starter/Spells kommen als Klasse `Boots(…)` – Zuordnung ist positionell, Parser unverändert |
| OP.GG Augments | `lol_list_aram_augments(champion_id)` → `Augment(id,name,tier,performance,popular)` (Schema 2026-11-04 dokumentiert `desc`, `performance` = „performance score … on the selected champion“). `popular` = Pick-Anteil; `tier` (3–5) ist nur ein Pick-Anteil-Bucket (3 ≈ ≥ 17 %, 5 ≤ 5 %) → ungenutzt. `performance` ≈ 60–140, Ausreißer nur bei ~0 % Picks; manche `name` = `null`. **Keine Siegquote** (Riot verbietet Augment-Winrates). IDs = CommunityDragon. Fixture `opgg/ahri-aram-augments.json` |
| Augment-Metadaten | CommunityDragon `…/global/<locale>/v1/cherry-augments.json` (Arena + Mayhem): `id`, `nameTRA` (lokalisiert, de_de ≠ OP.GG-Englisch), `rarity` `kSilver/kGold/kPrismatic/kEventChoice`, `augmentSmallIconPath` → kleingeschrieben unter `global/default/` (HTTP 200). Fixture `cdragon/cherry-augments-de.json` (gekürzt) |
| ARAM: Mayhem Regeln | Riot-Support: „Rune settings are disabled in Mayhem“, kein Exhaust; erstes Augment zu Spielbeginn (Stufe 3), weitere bei 7/11/15; Wahl nur tot/im Brunnen. Ein Angebot = 3 Augments einer Seltenheit, 1 Reroll. Weder LCU noch Live Client liefern angebotene oder gewählte Augments |
| OP.GG Skill-Order | `data.skills.order` = 15 Schritte (Stufe 1–15), `data.skill_masteries` = Max-Reihenfolge |
| Live Client Fähigkeiten | `activeplayer.abilities.{Q,W,E,R}.abilityLevel` (Fixture `liveclient/activeplayer.json`) |

### Live bestätigt (2026-11-03, Client EUW, `16-queue.sh`)
| Lobby | `gameData.queue` | Riftglass |
|---|---|---|
| ARAM: Mayhem | `id 2400`, `mapId 12`, `gameMode "KIWI"`, `type "KIWI"`, `description "ARAM: Mayhem"` | `aramMayhem`, 43 ms nach Verbindung |
| Arena (Moduswechsel in offener Lobby) | `id 1750` (**nicht in `queues.json`**), `mapId 30`, `gameMode "CHERRY"`, `description "Arena 3x6"` | `arena` – zuerst über `CHERRY`, jetzt auch per ID |

- `recommended-pages/champion/103/position/{NONE,MIDDLE}/map/12` → 200, 3 ARAM-Seiten mit Spells `[4, 32]`
  (Flash + Schneeball) – Position egal.
- `recommended-pages/…/map/30` (Arena) → 200 mit generischen SR-artigen Seiten (Electrocute, `[4, 14]`), obwohl
  Arena keine Runen nutzt → Riftglass fragt für Arena bewusst keine Empfehlungen ab.
- **Bug gefunden und behoben:** Das Abfragen der Session beim Phasen-Event „Lobby“ lieferte noch keine Queue
  (Session wird kurz nach dem Phasenwechsel befüllt), und ein Moduswechsel in der offenen Lobby löst gar
  kein Phasen-Event aus. → `/lol-gameflow/v1/session` ist jetzt im WAMP-URI-Filter; Queue-ID `-1` während
  des Aufbaus wird ignoriert.

### Practice Tool Ende-zu-Ende (2026-11-03, signierter Debug-Build, Bard Support)
| Schritt | Ergebnis |
|---|---|
| Queue | `3140`, `"Multiplayer Practice Tool Custom"` → `summonersRift` (über `gameMode`/Map, ID nicht in der Tabelle) |
| Panel | 94 ms nach `Mode → champSelect` angedockt, OP.GG-Build Bard Support |
| Auto-Import | nach dem Lock-in genau einmal `items=true runes=false`, nach dem manuellen Import (seriell) |
| Queue im Spiel | gemerkte Lobby-Queue übernommen (Map 11 = `mapNumber` 11); Live Client `gameMode "PRACTICETOOL"` |
| Skill-Overlay | Shielding+1, 293×44 pt, mittig, 288 pt über dem unteren Rand (20 % von 1440) auf 3440×1440; vom Nutzer gesehen; Stufe 1–3 = Q › W › E wie vorgeschlagen, ausgeblendet sobald kein Punkt offen |

### Offen (→ `scripts/spike/16-queue.sh` im Client bzw. Spiel)
- Skill-Overlay ab Stufe 6 (R) und mit mehreren offenen Punkten live; 16:9-Bildschirm.
- `gameData.queue` für Classic und Brawl (ID, `gameMode`, `mapId`, `description`).
- Live-Client-`gameMode` im Spiel für Mayhem (`KIWI`?) und Arena (`CHERRY`?) – in der Lobby bestätigt, im Spiel offen.
- Mayhem-Augment-Overlay live: erscheint es zu Spielbeginn und beim Tod nach Stufe 7/11/15, verdeckt es die
  Auswahlkarten nicht (oben, 28 pt), liefert `playerlist[].isDead` in Mayhem zuverlässig? `allgamedata`-Dump
  auf Augment-Felder prüfen.
- Skill-Overlay-Position (20 % Höhe über unterem Rand) auf 16:9 und 21:9.

## Spike 4 – Matchup-Briefing (2026-11-03, OP.GG MCP live, ohne Client)
- `lol_get_lane_matchup_guide(position, my_champion, opponent_champion, lang)` antwortet als **JSON-Text**
  (nicht Klassen-Notation), ~50 KB, ohne `desired_output_fields`. Genutzt: `data.opponent_champion_tip`
  (englisch, auch mit `lang: de_DE`), `lane_advantage_champion`, `lane_solo_kill_advantage_champion`
  (Champion-Name oder leer), `recommended_play_style` (`even`, …) und `data.counters[]`
  `{champion_id, play, win}` – darin das Duell (Ahri vs. Zed mid: 3966/8004). Fixture (gekürzt):
  `tests/fixtures/opgg/ahri-zed-mid-guide.json`.
- `lol_get_champion_analysis` + `data.weak_counters[].{champion_id,champion_name,my_win_rate,counter_win_rate,play}`:
  3 Counter je Champion/Lane, `counter_win_rate` = Siegquote des Counters. `data.counters_meta` steht in der
  Feldliste, wird aber als „unmatched“ abgelehnt → nicht anfragen. Fixture: `zed-mid-counters.json`.
- `lol_list_lane_meta_champions(position: "all")` + `data.positions.<lane>[].{champion,role_rate}`: alle
  Meta-Champions je Lane mit Anteil, **nur Anzeigenamen** („Kog'Maw“, „Nunu & Willump“, „Wukong“) → Abgleich
  über normalisierte Namen. ~6 KB. Fixture: `lane-meta.json`.
- Champ-Select-Fixture `champ-select-session-draft.json` ist **synthetisch** (Normal Draft, 3 Gegner
  gelockt), bis `17-draft.sh` eine echte Aufnahme liefert.

### Offen (→ `scripts/spike/17-draft.sh` in Normal Draft / Ranked)
- Liefert `theirTeam[].assignedPosition` in Draft etwas? Wann erscheint `championId` gegnerischer Picks
  (erst nach Lock-in)?
- `GET /lol-champ-select/v1/pickable-champion-ids`: Status und Inhalt (gebannte/vergebene Champions entfernt?).
