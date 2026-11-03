# Architektur

Stand: Phase 1. Ausführlicher Plan: `PLAN.md`; verifizierte Fakten über den Client: `SPIKE.md`.

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
        └─ [5,"OnJsonApiEvent"] → URI-Filter → phase / champ-select session
```

## Module

| Modul | Verantwortung | Nebenläufigkeit |
|---|---|---|
| `LeagueKit` | Prozess-Erkennung, Credentials, TLS (`LocalTrustEvaluator`), REST, WAMP, `GameflowStateMachine`, `RunePagePlanner`, `ItemSetMerger`, `ChampSelectActions` | `ClientWatcher` `@MainActor`; `LCUClient`/`LCUEventStream` sind Actors; Logik ist pur |
| `DataKit` | Data Dragon (per Patch auf Platte gecacht), Icon-Cache (`NSCache` + Disk) | `DataDragon` Actor, `IconCache` `@MainActor` |
| `StatsKit` | `BuildProvider`-Protokoll, `BundledBuildProvider` (Platzhalter) | wertbasiert |
| `OverlayKit` | `ChampSelectPanel` (nicht aktivierend), `ClientDockController` (2 Hz, nur im Champ Select), `DockGeometry` (pur) | `@MainActor` |
| `App` | `AppModel`, `LCUConnection`, `ChampSelectCoordinator`, SwiftUI-Views | `@MainActor` |

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
- **Fixtures** liegen am Repo-Root und werden über `#filePath` gefunden (SwiftPM-Ressourcen dürfen
  nicht außerhalb des Packages liegen).
