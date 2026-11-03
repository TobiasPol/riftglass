# Compliance

Riftglass muss mit Riots Richtlinien für Drittanbieter-Apps und mit Vanguard vereinbar bleiben.
Diese Datei ist verbindlich; Features, die hier als verboten stehen, werden nicht gebaut.

## Erlaubte Datenquellen
- **LCU** (lokal, `https://127.0.0.1:<app-port>`), inoffiziell, nur mit dem Token aus den
  Prozess-Argumenten/Lockfile des eigenen Benutzers.
- **Live Client Data API** (`https://127.0.0.1:2999`), nur Daten, die der Spieler im Spiel sehen kann.
- **Data Dragon** (statische Spieldaten, öffentlich).
- **Riot API** (Phase 3) nur über das eigene Backend mit eigenem Key.

## Verboten
- Gegner-Ultimate-Timer (von Riot seit 13.03.2025 verboten) und Gegner-Summoner-Spell-Timer.
- Lesen des Spielspeichers, Injection in Spiel oder Client, Hooking.
- Eingabe-Automatisierung jeder Art (auch keine automatischen Picks, Bans oder Accept-Klicks).
- Informationen, die der Spieler im Spiel nicht sehen kann (z. B. versteckte Gegnerdaten).
- Scraping von Blitz.gg, OP.GG, U.GG o. Ä. Werbung in der App.
- Apps, die Spielerentscheidungen diktieren: Builds immer als **mehrere Optionen**, nie als Anweisung.

## Policy-Risiken (vor öffentlicher Version mit Riot klären)
- Gold-Schätzung pro Lane (Phase 2, hinter Schalter, standardmäßig aus).
- Build-Empfehlungen aus eigenen Statistiken (Phase 3).

## Pflichten
- Riot-Hinweis gut sichtbar: Menüleisten-Popover, Champ-Select-Panel, Einstellungen, README.
  Volltext in `src/mac/App/Sources/SettingsView.swift` (`Disclaimer.full`).
- Produkt im Riot Developer Portal registrieren (auch bei reiner LCU-Nutzung).
- Keine Riot-Marken im App-Namen oder Icon.
- Keine Telemetrie; Logs nur über `os.Logger`, keine Tokens in Logs.

## Datenschutz / Sicherheit
- `--remoting-auth-token` wird nur im Speicher gehalten und nie geloggt (`LCUCredentials.description`
  ist geschwärzt). `--riotgamesapi-settings` (enthält weitere Tokens) wird nie gelesen.
- TLS nur gegen Riots „LoL Game Engineering Certificate Authority“ (`riotgames.pem`), nur `127.0.0.1`, nur der erwartete Port.
- Aufgezeichnete Fixtures werden vor dem Einchecken anonymisiert (PUUID, Namen, IDs).
- Import verändert ausschließlich Riftglass-eigene Runenseiten und Item-Sets.
