# Riftglass – Implementierungsplan (v5)

> Arbeitstitel. Native macOS-Companion-App für League of Legends, so nah an Blitz.gg / OP.GG wie
> Riots Regeln und macOS es erlauben. Priorität: macOS-Integration und Performance.
> v2 enthält die Korrekturen aus einem unabhängigen Review (Abschnitt 8), v3 die Spike-Ergebnisse
> (Abschnitt 9), v4 den Verzicht auf ein eigenes Backend und Spike 2 im Spiel (Abschnitt 10),
> v5 Spielmodus-Erkennung, Auto-Import und Skill-Overlay samt Wettbewerbsvergleich (Abschnitt 11).

## 1. Ziele und Nicht-Ziele

**Ziele**
- Champ Select: Runen, Summoner Spells und Item-Sets per Klick importieren, Build-/Matchup-Infos.
  Builds als **mehrere Optionen** darstellen, nicht als eine Anweisung (Riot: keine Apps, die
  Spielerentscheidungen diktieren).
- Ladebildschirm: Rang, LP, Winrate aller 10 Spieler – lokal über die LCU, ohne Backend.
- Im Spiel (Tab halten): KDA, CS/min vs. Benchmark, Build-Fortschritt.
  Gold-Schätzung pro Lane nur aus sichtbaren Items, hinter einem Schalter und als **Policy-Risiko**
  markiert (vor einer öffentlichen Version mit Riot klären).
- Nach dem Spiel: kompakte Analyse.
- Spürbar leichter als Electron-Apps: ~0 % CPU wenn League zu ist, < 1 % CPU im Spiel.

**Nicht-Ziele (Riot-Regeln / Account-Sicherheit)**
- Keine Gegner-Ultimate-Timer (verboten seit 13.03.2025), keine Gegner-Spell-Timer (Grauzone → weglassen).
- Kein Lesen des Spielspeichers, keine Injection, keine Eingabe-Automatisierung.
- Keine spielsitzungsspezifischen Infos, die der Spieler im Spiel nicht sehen kann.
- Kein Scraping von Blitz / OP.GG / U.GG. Keine Werbung.

## 2. Tech-Stack

| Bereich | Wahl | Begründung |
|---|---|---|
| Sprache | Swift 6 (strict concurrency) | nativ, kein Browser-Runtime |
| UI | SwiftUI für Inhalte, AppKit für Fenster (`NSPanel`) | SwiftUI allein kann keine nicht-aktivierenden Panels |
| Mindestversion | macOS 14 (Observation `@Observable`) | |
| Architektur | arm64 zuerst, Universal optional | League auf Mac ist Apple-Silicon-nativ |
| Projekt | XcodeGen (`project.yml`) + lokale Swift Packages | diffbar, Packages via `swift test` testbar |
| Signierung | **ab Phase 0** mit „Apple Development“-Zertifikat | sonst verfällt die Eingabeüberwachung bei jedem Build |
| Abhängigkeiten App | keine in Phase 1–2 (URLSession-WebSocket statt Starscream) | weniger Angriffsfläche |
| Updates | Sparkle 2 (Phase 4) | Standard außerhalb des App Store |
| Build-Daten | OP.GG MCP (offiziell, ohne Key) + Riot-Empfehlungen per LCU | kein eigenes Backend, kein Riot-API-Key |
| Lint/Format | SwiftLint + SwiftFormat via pre-commit | |
| CI | GitHub Actions (`macos-15`): lint + test + unsigned build; Release lokal (Zertifikate) | |

Kein Mac App Store: die Sandbox erschwert Zugriff auf fremde Prozesse und League-Dateien.

## 3. Repo-Struktur

```
riftglass/
├── src/
│   ├── mac/
│   │   ├── project.yml               # XcodeGen
│   │   ├── App/                      # App-Target: MenuBarExtra, Settings, Onboarding
│   │   └── Packages/
│   │       ├── LeagueKit/            # Client-Erkennung, LCU, Live Client, Spielphase
│   │       ├── DataKit/              # Data Dragon, Icon-Cache
│   │       ├── StatsKit/             # BuildProvider (lokal → Backend)
│   │       └── OverlayKit/           # NSPanel, Docking, Hotkey
│   └── backend/                      # Phase 3
├── tests/fixtures/                   # aufgezeichnete LCU-/Live-Client-JSONs (anonymisiert)
├── docs/                             # ARCHITECTURE.md, PLAN.md, COMPLIANCE.md, SPIKE.md
├── scripts/                          # bootstrap.sh, lint.sh, spike/*.sh, release.sh
├── .claude/                          # commands/, skills/, settings.json
├── .env.example  .gitignore  .dockerignore  README.md  CLAUDE.md
```

Regeln: keine Datei > 300 Zeilen, keine Funktion > 50 Zeilen, keine Secrets im Repo.

## 4. Architektur

### 4.1 Steuerung über die Spielphase
`GameflowStateMachine` (LeagueKit) entscheidet, welche Subsysteme laufen:

| Phase (LCU `gameflow-phase`) | aktiv |
|---|---|
| League nicht gestartet | nur `ClientWatcher` (KVO, keine Timer) |
| `None`/`Lobby`/`Matchmaking`/`ReadyCheck` | LCU-WebSocket |
| `ChampSelect` | + Champ-Select-Fenster, Docking (2 Hz), Icon-Prefetch |
| `GameStart`/`InProgress`/`Reconnect` | + Live-Client-Polling (1 Hz), HotkeyMonitor, Overlay |
| `PreEndOfGame`/`WaitingForStats`/`EndOfGame` | Post-Game-Zusammenfassung |
| `TerminatedInError` | sauber zurücksetzen |

Unbekannte Phasen tolerant behandeln. **Spiel-Erkennung unabhängig von der LCU:** Der Client kann sich
während des Spiels schließen („Client während des Spiels schließen“). Daher Game-Prozess über
`ClientWatcher` erkennen und Port 2999 selbst prüfen; LCU-Verlust im Spiel ist kein Fehler.

### 4.2 LeagueKit
- **ClientWatcher**: KVO auf `NSWorkspace.shared.runningApplications` (die Launch-Notification wird
  für Hintergrund-/LSUIElement-Prozesse nicht gesendet). Bundle-IDs im Spike verifizieren.
- **Verbindungsdaten** (in dieser Reihenfolge):
  1. Prozess-Argumente von `LeagueClientUx` via `sysctl(KERN_PROCARGS2)` (NUL-getrennt; der
     Install-Pfad enthält Leerzeichen): `--app-port`, `--remoting-auth-token`, `--install-directory`.
     `--riotgamesapi-settings` enthält fremde Tokens → nie lesen, nie loggen.
  2. Fallback: `lockfile` im Install-Verzeichnis (`name:pid:port:password:protocol`, ohne Newline).
     Die Datei bleibt nach dem Beenden liegen → PID (`LeagueClient`) auf Lebendigkeit prüfen.
  Kein fest verdrahteter Pfad, kein Datei-Watcher.
- **TLS**: Riots `riotgames.pem` bündeln. Im `URLSessionDelegate` die Kette mit
  `SecPolicyCreateBasicX509()` + `SecTrustSetAnchorCertificates` + `SecTrustSetAnchorCertificatesOnly(true)`
  prüfen und **selbst** sicherstellen, dass Host `127.0.0.1` und Port stimmen. Nicht die SSL-Policy
  verwenden: das LCU-Leaf hat zwar SAN `127.0.0.1`, aber 100 Jahre Laufzeit (Spike). Kette mit
  `riotgames.pem` für den LCU-Port verifiziert; Port 2999 wird in Phase 2 geprüft.
- **LCUClient** (`actor`): REST mit Basic-Auth `riot:<token>`; WebSocket via `URLSessionWebSocketTask`
  mit Subprotocol `wamp`; nach der Begrüßung (Opcode 0) `[5, "OnJsonApiEvent"]` abonnieren – die
  spezifischen Topics liefern auf macOS nichts (Spike). Events kommen als Opcode 8 mit `uri`; vor dem
  Dekodieren per Byte-Suche auf die relevanten URIs filtern. Reconnect mit Backoff.
  Endpunkte (inoffiziell, im Spike gegen echten Client prüfen):
  - `GET /lol-summoner/v1/current-summoner`, `GET /lol-champ-select/v1/session`
  - Runen: `GET /lol-perks/v1/inventory` (Seitenlimit), `GET /lol-perks/v1/pages`,
    `DELETE /lol-perks/v1/pages/{id}` (**nie** ohne ID – löscht alle Seiten),
    `POST /lol-perks/v1/pages` mit `current: true` (nur die eigene „Riftglass“-Seite ersetzen; ist kein
    Platz frei und keine eigene Seite vorhanden → Fehlermeldung, nie eine fremde Seite löschen).
  - Spells: `PATCH /lol-champ-select/v1/session/my-selection` (`spell1Id`, `spell2Id`).
  - Item-Sets: `GET` → eigenes Set per `uid` mergen → `PUT /lol-item-sets/v1/item-sets/{summonerId}/sets`
    (PUT ersetzt die gesamte Liste!). Pfad im Spike bestätigt.
  - Ränge: `GET /lol-ranked/v1/ranked-stats/{puuid}`.
  Alle Modelle tolerant dekodieren (optionale Felder).
- **LiveClient** (`actor`): `https://127.0.0.1:2999/liveclientdata/…` – **nicht** `allgamedata`
  (Event-Liste wächst), sondern `activeplayer`, `playerlist`, `gamestats` getrennt, 1 Hz, nur im Spiel.
  `Task.sleep(for: .seconds(1), tolerance: .milliseconds(250))`; UI bekommt nur geänderte Snapshots.

### 4.3 DataKit
- Data Dragon: `versions.json`, `champion.json`, `item.json`, `runesReforged.json`, `summoner.json`
  pro Patch in `~/Library/Application Support/Riftglass/ddragon/<version>/` cachen.
- Icons: `NSCache` + Disk-Cache; im Champ Select / Ladebildschirm vorladen, im Spiel nichts nachladen.

### 4.4 StatsKit
- Protokoll `BuildProvider` → `builds(champion:role:patch:) async -> [BuildOption]`.
- `OPGGBuildProvider`: OP.GG MCP `lol_get_champion_analysis`, Parser für OP.GGs Klassen-Notation,
  Disk-Cache pro Champion/Rolle (6 h), Quellenangabe „Daten: OP.GG“ in der UI.
- `RiotRecommendationProvider` (App, braucht LCU): `recommended-pages` → Runen + Spells als weitere Optionen
  und Fallback, wenn OP.GG nicht erreichbar ist.
- `OPGGRankProvider`: `lol_get_summoner_profile` für die 10 Riot-IDs aus der Live Client API (abschaltbar).

### 4.5 OverlayKit
- **OverlayPanel** (`NSPanel`): `.nonactivatingPanel` bereits im `init(styleMask:)` setzen
  (`[.borderless, .nonactivatingPanel]`), danach `isFloatingPanel = true`, **dann** `level` setzen.
  `collectionBehavior [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]`
  (nie `.fullScreenPrimary`), `becomesKeyOnlyIfNeeded = true`, `hidesOnDeactivate = false`,
  `hasShadow = false`, `ignoresMouseEvents = true` im Spiel. Level: **`CGShieldingWindowLevel() + 1`**
  (Spike 2: das Spiel liegt auf `CGShieldingWindowLevel()`, `.screenSaver` ist darunter unsichtbar).
  Ausblenden per `orderOut`, nie per `alphaValue = 0`. Keine `Material`-Unschärfe im Spiel.
- **ChampSelectPanel**: klickbar, nicht aktivierend, `acceptsFirstMouse` → erster Klick wirkt sofort.
- **ClientDockController**: `CGWindowListCopyWindowInfo` (Bounds + PID funktionieren ohne
  Bildschirmaufnahme-Recht), nur während Champ Select, 2 Hz. Umrechnung CG → AppKit über die Höhe von
  `NSScreen.screens[0]`, nicht `NSScreen.main`. Fensterbesitzer ist `LeagueClientUx` (Spike);
  Fenstername ist ohne Bildschirmaufnahme-Recht leer → Auswahl über PID, Layer 0, größte Fläche.
- **HotkeyMonitor** (`@MainActor`): `CGEvent.tapCreate(.cgSessionEventTap, .tailAppendEventTap,
  .listenOnly, keyDown|keyUp)` am Main-RunLoop (Listen-only blockiert keine Eingaben → kein eigener
  Thread nötig). Kontext über `refcon`/`Unmanaged`. Nur Tab (Keycode 48), Key-Repeats ignorieren, nur
  wenn das League-Spiel vorne ist (Frontmost-App per Notification cachen). `tapDisabledByTimeout`/
  `ByUserInput` → wieder einschalten. Recht: Eingabeüberwachung (`CGPreflightListenEventAccess` /
  `CGRequestListenEventAccess`); nach Erteilen ist ein App-Neustart nötig → im Onboarding anbieten.

### 4.6 App
- `MenuBarExtra` (LSUIElement), `Settings`-Scene, Onboarding für Eingabeüberwachung.
- Logging nur via `os.Logger`, keine Log-Dateien im Home-Verzeichnis, keine Telemetrie.
- Riot-Pflichthinweis („isn't endorsed by Riot Games …“) **gut sichtbar**: Onboarding, Settings,
  About und README.
- Produkt im Riot Developer Portal registrieren (auch bei reiner LCU-Nutzung).

## 5. Phasen und Definition of Done

### Phase 0 – Fundament + Verifikations-Spike
1. Repo-Scaffolding (Abschnitt 3), XcodeGen-Projekt, leere Packages, SwiftLint/SwiftFormat,
   pre-commit, CI, README/CLAUDE.md/ARCHITECTURE.md/COMPLIANCE.md, Signierung mit Apple Development.
2. **Spike gegen den echten Client** (Skripte in `scripts/spike/`, Ergebnisse in `docs/SPIKE.md`):
   Bundle-IDs (`defaults read …/Info CFBundleIdentifier`), Prozess-Argumente, Lockfile-Pfad,
   Zertifikate (`openssl s_client` für LCU-Port und 2999, SAN, Aussteller), Item-Set-Pfad,
   Besitzer des Client-Fensters, Overlay-Level im Vollbild. Fixtures aufzeichnen.
**DoD:** `xcodegen generate && xcodebuild build` und `swift test` grün (lokal + CI); SPIKE.md beantwortet
alle offenen Punkte aus Abschnitt 7.

### Phase 1 – Client & Champ Select
ClientWatcher, Verbindungsdaten, TLS, LCUClient (REST + WS), GameflowStateMachine, DataKit,
Champ-Select-Panel (angedockt) mit Platzhalter-Builds; Aktionen: Runen importieren, Spells setzen,
Item-Set mergen. Tests: Argument-/Lockfile-Parsing, Dekodierung aufgezeichneter Sessions,
State-Machine-Übergänge, Runenseiten-Builder (nur eigene Seite wird ersetzt), Item-Set-Merge.
**DoD:** Panel erscheint ≤ 1 s nach Champ-Select-Start; Import klappt, fremde Runenseiten und Item-Sets
bleiben unangetastet; mit geschlossenem League ~0 % CPU und keine Timer-Wakeups.

### Phase 2 – Ladebildschirm & In-Game-Overlay
LiveClient, HotkeyMonitor, OverlayPanel; Ladebildschirm mit Rängen (LCU `ranked-stats`); Tab-Overlay mit
KDA, CS/min vs. Benchmark, Build-Fortschritt; Gold-Schätzung hinter Schalter.
**DoD:** Overlay erscheint randlos und im Vollbild; League behält nach 100× Tab den Fokus; funktioniert
auch, wenn der Client sich im Spiel schließt; Ø < 1 % CPU im Spiel (Instruments, 10-Min-Match).

### Phase 3 – Build-Quellen ohne Backend (ersetzt das eigene Backend)
OP.GG MCP (Builds, Stats, Ränge) + Riot-Empfehlungen per LCU, Disk-Cache, Quellenangabe, Fehler-Fallback.
Kein Server, kein Riot-API-Key. Vor dem öffentlichen Release OP.GG über die Nutzung informieren.
**DoD:** Champ Select zeigt OP.GG-Build mit Winrate und Riot-Empfehlungen; ohne Netz bleiben Riot-Empfehlungen.

### Phase 4 – Feinschliff & Verteilung
Developer-ID-Signatur + Notarisierung (lokales Release-Skript, `notarytool`-Keychain-Profil), DMG,
Sparkle 2 (EdDSA, Appcast im Repo), Onboarding, App-Icon, öffentliches GitHub-Repo (MIT).
**DoD:** DMG startet auf frischem Mac ohne Gatekeeper-Umgehung; Auto-Update funktioniert.

## 6. Performance-Budget

| Zustand | CPU | RAM | Messung |
|---|---|---|---|
| League geschlossen | ~0 %, keine Timer | < 60 MB | Aktivitätsanzeige |
| Champ Select | < 2 % | < 90 MB | Instruments Time Profiler |
| Im Spiel | Ø < 1 % | < 100 MB | Instruments, 10-Min-Match |

## 7. Risiken / offene Fragen (→ Spike)
- LCU-Endpunkte sind inoffiziell (Stand Spike: alle benötigten liefern 200).
- ~~Bundle-IDs, Lockfile-Pfad, Besitzer des Client-Fensters~~ → geklärt (SPIKE.md).
- ~~Zertifikatskette LCU~~ → geklärt; Port 2999 offen (Phase 2).
- Overlay-Level im League-Vollbild (offen, Phase 2).
- WAMP-Topic-Namen: spezifische Topics funktionieren nicht; Sammel-Topic könnte künftig gedrosselt werden.
- Embedded Vanguard (macOS) könnte lokale APIs künftig einschränken.
- Gold-Schätzung und Build-Empfehlungen: Riot-Freigabe für öffentliche Version unklar.
- Production-Key-Freigabe kann Monate dauern; Apple Developer Program nötig.
- Name: keine Riot-Marken im App-Namen.

## 8. Änderungen gegenüber v1 (aus dem Review)
TLS-Validierung ohne SSL-Hostname-Policy · Runen nur per ID löschen · Item-Sets mergen statt
überschreiben · KVO statt Launch-Notification · Prozess-Argumente statt fester Lockfile-Pfad ·
Ränge lokal über LCU (Backend nicht mehr nötig) · zusätzliche Gameflow-Phasen und LCU-unabhängige
Spielerkennung · Disclaimer gut sichtbar + Portal-Registrierung · Policy-Risiko Gold-Diff/Builds ·
Signierung ab Phase 0 · Hotkey-Tap am Main-RunLoop · NSPanel-Reihenfolge und Level-Fallback ·
Koordinaten über `screens[0]` · Live Client ohne `allgamedata` · WebSocket-Subprotocol `wamp` ·
Verifikations-Spike in Phase 0.

## 9. Änderungen aus dem Spike (v3)
WAMP-Sammel-Topic `OnJsonApiEvent` + URI-Filter statt spezifischer Topics · Abo erst nach Opcode 0 ·
Argumente NUL-getrennt parsen (Leerzeichen im Pfad) · `--riotgamesapi-settings` nie lesen/loggen ·
Lockfile-PID auf Lebendigkeit prüfen · kein Public-Key-Pinning nötig · Fensterbesitzer `LeagueClientUx`,
Auswahl ohne Fensternamen · voller Runenseiten-Speicher → Fehler statt fremde Seite ersetzen.

## 10. Änderungen v4 (Spike 2, Entscheidungen)
Kein eigenes Backend und kein Riot-API-Key (Side-Project, Production-Key unverhältnismäßig) → OP.GG MCP +
LCU-Empfehlungen · Kein Scraping/keine undokumentierten Endpunkte (League Akari/champ-r tun das) ·
LCU ist im Spiel beendet → Ränge über Live-Client-Riot-IDs + OP.GG · Overlay auf `CGShieldingWindowLevel()+1` ·
Gold-Schätzung hinter Schalter, Standard aus · Veröffentlichung als öffentliches GitHub-Repo, MIT.

## 11. v5 – Spielmodus-Erkennung, Auto-Import, Skill-Overlay (2026-11-03)

### 11.1 Was andere Tools bieten (Stand November 2026)
Quellen: Hersteller-Seiten (Marketing) und Vergleiche von Konkurrenten (Hexgate, Buildzcrank) – mit Vorsicht
lesen. `?` = in der Recherche nicht bestätigt. Blitz' Overlays laufen laut Reviews nur unter Windows.

| Feature | Blitz | OP.GG Desktop | Porofessor | Riftglass v0.2 |
|---|---|---|---|---|
| Runen/Items/Spells importieren | ✓ auto | ✓ auto (nicht in Mayhem) | ? | ✓ Klick; Item-Set auto nach Lock-in, Runen opt-in |
| Builds pro Modus (ARAM, URF, …) | ✓ | ? | ? | ✓ Ranked/Flex/ARAM/Mayhem; URF/OFA mit SR-Daten |
| Skill-Order-Overlay im Spiel | ✓ „Recommended Skill Order“ | ? | ? | ✓ Skillpunkt-Hinweis über der Fähigkeitsleiste |
| Mayhem-/Arena-Augment-Overlay | ✓ | ✓ Tier-Overlay | – (Okt. 2026) | Champ Select: beliebteste Mayhem-Augments; Overlay offen |
| Ladebildschirm-Scouting (Ränge) | ✓ | ? | ✓ (Kernfeature) | ✓ Banner + Tab-Overlay |
| Eigene Jungle-/Relikt-Timer | ✓ (ARAM-Health-Relikte) | ? | ? | offen (nur eigene/sichtbare Infos erlaubt) |
| Item-Gold-Differenz | ✓ | ? | ? | ✓ hinter Schalter (Policy-Risiko) |
| Post-Game-Analyse | ? | ✓ (Mayhem-Augment-Historie) | ? | einfache Zusammenfassung |
| Auto-Accept | ? | ? | ? | **nie** (COMPLIANCE.md) |

Augment-Overlays erkennen die Auswahlkarten per Bilderkennung (Hexgate: Windows-OCR; ARAMKit: Bildvergleich),
da weder LCU noch Live Client die angebotenen Augments liefern.

### 11.2 Spielmodus-Erkennung
- `GameMode.classify(queueId:gameMode:mapId:description:)` (LeagueKit, pur): Queue-ID aus Riots
  `queues.json` → `gameMode`-String (inkl. Codenamen `KIWI` = Mayhem, `CHERRY` = Arena) → Map → `.unknown`.
  League Classic (Patch 26.15, Queue-ID unbekannt) über den Queue-Namen.
- Quelle: `/lol-gameflow/v1/session` → `gameData.queue`: per REST nach jedem (Re-)Subscribe, danach als
  WAMP-Event (Moduswechsel in der offenen Lobby lösen kein Phasen-Event aus); Fallback `queueId` aus der
  Champ-Select-Session. Im Spiel ist die LCU
  zu → gemerkte Lobby-Queue, wenn die Map zu `gamestats.mapNumber` passt, sonst Live-Client-`gameMode`.
- Fähigkeiten pro Modus: Lanes, Runenseiten (nicht Arena/Swarm/Classic), Item-Set-Map (11/12 bzw. keine),
  Riot-Empfehlungs-Map, Augments.

### 11.3 Builds und Auto-Import
- OP.GG MCP `game_mode` ∈ `ranked`, `flex`, `aram` (Spike 3). Mayhem nutzt ARAM-Builds; URF/OFA/
  Ultimate Spellbook die SR-Ranked-Daten als Näherung; Arena/Brawl/Swarm/Nexus Blitz/Classic: keine Builds.
- Item-Sets pro Champion **und Map** (`uid`-Byte = Map-ID, SR bleibt `00` → kompatibel zu v0.1), damit ein
  ARAM-Set das SR-Set nicht ersetzt.
- Auto-Import nach dem Lock-in (nicht beim Hovern), einmal pro Spiel und Champion (ARAM-Reroll = neuer Pick):
  Item-Set standardmäßig an, Runen + Spells opt-in.
- ARAM: Mayhem: die meistgewählten Augments des Champions (OP.GG `lol_list_aram_augments`, nur Pickrate).

### 11.4 Skillpunkt-Overlay
- Live Client `activeplayer.abilities.{Q,W,E,R}.abilityLevel` + `level` → `SkillOrderAdvisor` (pur):
  erster noch nicht genommener Schritt der OP.GG-Skill-Order, der jetzt lernbar ist; nach Stufe 15 Priorität
  (R, dann früh maximierte Fähigkeit). Abweichungen des Spielers werden toleriert.
- Erscheint nur bei unverteiltem Skillpunkt und League im Vordergrund, über der Fähigkeitsleiste
  (`CGShieldingWindowLevel()+1`, klick-durchlässig), kein Hotkey/Eingabeüberwachung nötig.
- Skill-Order aus dem Champ Select (passender Champion + Queue), sonst einmalig von OP.GG nachgeladen.

### 11.5 Roadmap (nächste Schritte, priorisiert)
1. **Live-Verifikation** (`scripts/spike/16-queue.sh`): Queue-IDs/`gameMode` von Mayhem, Arena, Classic,
   Brawl; `recommended-pages` mit Map 12; Position des Skill-Overlays auf verschiedenen Auflösungen.
2. **Arena:** Builds/Augments – OP.GG MCP hat keinen Arena-Modus; Quelle klären (kein Scraping).
3. **Augment-Overlay im Spiel:** bräuchte Bildschirmaufnahme + OCR der Auswahlkarten (wie Blitz/Hexgate).
   Kein Speicherlesen, aber neues Recht + Policy-Frage → erst mit Riot klären (COMPLIANCE.md).
4. **Eigene Timer:** ARAM-Health-Relikte und eigene Jungle-Camps nur aus Live-Client-Events, die der Spieler
   sieht; nie Gegner-Spells/Ults.
5. **Post-Game:** Match-Verlauf über OP.GG `lol_list_summoner_matches`, Build-Treue, LP-Verlauf.
6. **Matchup-Hinweise im Champ Select:** OP.GG `lol_get_lane_matchup_guide` für den Lane-Gegner.
