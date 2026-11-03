# Riftglass – Implementierungsplan (v3, nach Spike)

> Arbeitstitel. Native macOS-Companion-App für League of Legends, so nah an Blitz.gg / OP.GG wie
> Riots Regeln und macOS es erlauben. Priorität: macOS-Integration und Performance.
> v2 enthält die Korrekturen aus einem unabhängigen Review (Abschnitt 8), v3 die Spike-Ergebnisse
> (Abschnitt 9, Details in `docs/SPIKE.md`).

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
| Backend (Phase 3) | TypeScript (Node 22, strict), Hono, Postgres, Docker → Dokploy | Engpass ist Riots Rate-Limit |
| Lint/Format | SwiftLint + SwiftFormat via pre-commit; ESLint + Prettier + Husky im Backend | |
| CI | GitHub Actions (`macos-15`): build + test; Backend: lint + test + Docker build | |

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
- Phase 1: `BundledBuildProvider` (handgepflegtes Fixture für ~5 Champions, klar als Platzhalter).
- Phase 3: `RemoteBuildProvider` gegen das eigene Backend, mit ETag + Disk-Cache.

### 4.5 OverlayKit
- **OverlayPanel** (`NSPanel`): `.nonactivatingPanel` bereits im `init(styleMask:)` setzen
  (`[.borderless, .nonactivatingPanel]`), danach `isFloatingPanel = true`, **dann** `level` setzen.
  `collectionBehavior [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]`
  (nie `.fullScreenPrimary`), `becomesKeyOnlyIfNeeded = true`, `hidesOnDeactivate = false`,
  `hasShadow = false`, `ignoresMouseEvents = true` im Spiel. Level-Kandidaten im Spike testen:
  `.screenSaver`, notfalls `CGShieldingWindowLevel() + 1`.
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

### Phase 3 – Backend (Builds)
Hono-API + Postgres; Crawler: `league-v4` Apex-Listen → `match-v5` → Aggregation pro Patch/Champion/Rolle
(Runen, Items, Spells, Skill-Order, Winrate, Mindest-Stichprobe), Rate-Limiter nach
`X-App-Rate-Limit`/`X-Method-Rate-Limit`. Ausgabe als statisches JSON mit ETag. Docker multi-stage,
non-root, Healthcheck, Dokploy. `RIOT_API_KEY`/`DATABASE_URL` nur in `.env`/Dokploy.
Riot-Key: „Personal API Key“ für privaten Gebrauch; öffentliche Version braucht Production Key.
**DoD:** App nutzt `RemoteBuildProvider` mit Builds des aktuellen Patches.

### Phase 4 – Feinschliff & Verteilung
Developer-ID-Signatur + Notarisierung in CI, Sparkle 2 (EdDSA), Onboarding-Feinschliff,
Instruments-Profiling, Post-Game-Ansicht.
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
