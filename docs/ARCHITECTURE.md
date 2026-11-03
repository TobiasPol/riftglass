# Architektur

Stand: v0.2 (Phasen 1–4 + Spielmodi/Skill-Overlay, PLAN §11; ein eigenes Backend gibt es nicht). Ausführlicher Plan: `PLAN.md`; verifizierte Fakten über den Client: `SPIKE.md`.

## Datenfluss

```
NSWorkspace.runningApplications (KVO)
        │  LeagueProcesses (clientUxPID, gamePID)
        ▼
   AppModel ──────────────► GameflowStateMachine ──► AppMode (dormant/client/champSelect/inGame/postGame)
        │ clientUxPID                ▲                        │
        ▼                            │ phase                  ▼ champSelect
   LCUConnection                     │               ChampSelectCoordinator
   ├─ CredentialResolver (KERN_PROCARGS2 → Lockfile-Fallback)       ├─ BuildProvider (StatsKit)
   ├─ LCUClient (REST, actor)  ◄──────────────── Aktionen ──────────┤─ DataDragon / IconCache (DataKit)
   └─ LCUEventStream (WAMP, actor)                                  └─ ChampSelectPanel + ClientDockController
        └─ [5,"OnJsonApiEvent"] → URI-Filter → phase / gameflow session / champ-select session
             gameflow session → GameQueue (GameMode.classify) → AppSettings.lastQueue
                                                   │ inGame (Spielprozess läuft, LCU meist beendet)
                                                   ▼
                                          InGameCoordinator
                                          ├─ LiveClient (2999, 1 Hz, nur Änderungen)
                                          ├─ RankLookup → OPGGRankProvider (Riot-IDs aus playerlist)
                                          ├─ HotkeyMonitor (Tab, listen-only) → OverlayPanel (Shielding+1)
                                          ├─ SkillOrderAdvisor (abilities + Skill-Order) → Skillpunkt-Overlay
                                          └─ GameSummary → Menüleiste
```

Build-Quellen im Champ Select (`BuildLoader`): `OPGGBuildProvider` (OP.GG MCP, Klassen-Notation →
`OPGGNotation`, 6-h-Disk-Cache) + `recommended-pages` der LCU (Riot), Duplikate nach Runen entfernt.
Welche Statistik (`BuildQueue`: ranked/flex/aram) und welche Importe gelten, entscheidet der erkannte
`GameMode`; nach dem Lock-in importiert `ChampSelectCoordinator+AutoImport` das Item-Set (Map des Modus).
In ARAM: Mayhem zusätzlich `OPGGAugmentProvider` (beliebteste Augments).

## Module

| Modul | Verantwortung | Nebenläufigkeit |
|---|---|---|
| `LeagueKit` | Prozess-Erkennung, Credentials, TLS (`LocalTrustEvaluator`), REST, WAMP, `GameflowStateMachine`, `RunePagePlanner`, `ItemSetMerger`, `ChampSelectActions` | `ClientWatcher` `@MainActor`; `LCUClient`/`LCUEventStream` sind Actors; Logik ist pur |
| `DataKit` | Data Dragon (per Patch auf Platte gecacht), Icon-Cache (`NSCache` + Disk) | `DataDragon` Actor, `IconCache` `@MainActor` |
| `LeagueKit` (Live) | `LiveClient`, `LiveGameSnapshot`, `InGameAnalysis` (CS/min, Build-Fortschritt, Item-Gold) | `LiveClient` Actor, Analyse pur |
| `StatsKit` | `BuildProvider`, `OPGGClient` (MCP/JSON-RPC), `OPGGNotation`, `OPGGBuildProvider`, `OPGGRankProvider`, `ResponseCache` | Structs + Actor (Cache) |
| `OverlayKit` | `ChampSelectPanel`, `ClientDockController` (2 Hz, nur Champ Select), `OverlayPanel` (Shielding+1, klick-durchlässig), `HotkeyMonitor`, `DockGeometry` | `@MainActor` |
| `App` | `AppModel`, `LCUConnection`, `ChampSelectCoordinator`, `InGameCoordinator`, `AppSettings`, Onboarding, Sparkle-`Updater` | `@MainActor` |

## Entscheidungen

- **Keine Timer, wenn League zu ist.** Einzige aktive Komponente ist KVO. Der Docking-Timer läuft nur
  im Champ Select; WebSocket-Reconnects nur, solange `LeagueClientUx` läuft.
- **TLS:** `SecPolicyCreateBasicX509` + gebündelte `riotgames.pem` als einziger Anker + eigene
  Host-/Port-Prüfung (`127.0.0.1`, erwarteter Port). Die SSL-Policy scheitert an der 100-Jahre-Laufzeit
  des LCU-Zertifikats.
- **WAMP:** spezifische Topics liefern auf macOS nichts → Sammel-Topic, Byte-Vorfilter auf die
  benötigten URIs, erst dann JSON-Dekodierung. Nach jedem (Re-)Subscribe wird der Zustand per REST
  nachgeladen (`LCUStreamMessage.subscribed`), damit verpasste Events keine Rolle spielen.
- **Nur eigene Daten verändern:** Runenseiten mit Präfix „Riftglass“ (nie `isDeletable == false` oder
  temporär), Item-Sets per deterministischer `uid` pro Champion. Fremde Item-Sets werden als
  `JSONValue` unverändert zurückgeschrieben, weil `PUT` die ganze Liste ersetzt.
- **Spiel-Erkennung über den Prozess**, nicht über die LCU – der Client darf sich im Spiel schließen.
- **Spielmodus aus der Queue**, nicht aus dem Live Client: die LCU kennt Queue-ID und Namen (Ranked vs.
  Flex, Mayhem vs. ARAM). Im Spiel gilt die gemerkte Lobby-Queue, wenn die Map übereinstimmt.
- **Overlays ohne Observation messen:** `OverlayPanel.update(rootView:)` tauscht den Inhalt synchron,
  damit `present` die neue Größe misst (Skill-Overlay).
- **Fixtures** liegen am Repo-Root und werden über `#filePath` gefunden (SwiftPM-Ressourcen dürfen
  nicht außerhalb des Packages liegen).
