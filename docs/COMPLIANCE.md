# Compliance

Riftglass muss mit Riots Richtlinien für Drittanbieter-Apps und mit Vanguard vereinbar bleiben.
Diese Datei ist verbindlich; Features, die hier als verboten stehen, werden nicht gebaut.

## Erlaubte Datenquellen
- **LCU** (lokal, `https://127.0.0.1:<app-port>`), inoffiziell, nur mit dem Token aus den
  Prozess-Argumenten/Lockfile des eigenen Benutzers.
- **Live Client Data API** (`https://127.0.0.1:2999`), nur Daten, die der Spieler im Spiel sehen kann.
- **Data Dragon** (statische Spieldaten, öffentlich).
- **OP.GG MCP** (`mcp-api.op.gg`, offizielle öffentliche Schnittstelle von OP.GG): Builds, Winrates, Ränge.
  Quellenangabe in der UI. Kein Scraping, keine undokumentierten Endpunkte. Kein Riot-API-Key.

## Verboten
- Gegner-Ultimate-Timer (von Riot seit 13.03.2025 verboten) und Gegner-Summoner-Spell-Timer.
- Lesen des Spielspeichers, Injection in Spiel oder Client, Hooking.
- Eingabe-Automatisierung jeder Art (auch keine automatischen Picks, Bans oder Accept-Klicks).
- Informationen, die der Spieler im Spiel nicht sehen kann (z. B. versteckte Gegnerdaten).
- Scraping von Blitz.gg, OP.GG, U.GG o. Ä. Werbung in der App.
- Apps, die Spielerentscheidungen diktieren: Builds immer als **mehrere Optionen**, nie als Anweisung.

## Policy-Risiken
- Item-Gold-Schätzung pro Lane: nur aus sichtbaren Items, hinter Schalter, **standardmäßig aus**.
- Auto-Import nach dem Lock-in: schreibt nur Riftglass-eigene Item-Sets/Runenseiten (wie der Klick-Import),
  nie Picks/Bans/Accept. Item-Set standardmäßig an; Runen + Spells **opt-in**, weil sie die aktive Seite
  und die Spell-Auswahl des Spielers ändern. Abschaltbar in den Einstellungen.
- Skillpunkt-Overlay: zeigt die nächste Fähigkeit einer Statistik-Skill-Order als Hinweis; drückt keine
  Taste und levelt nichts (keine Eingabe-Automatisierung). Nur eigene Daten aus dem Live Client.
- Mayhem-Augments: nur Pick-Anteile im Champ Select. Ein Augment-Overlay im Spiel bräuchte Bildschirm-
  aufnahme/OCR der Auswahlkarten – vor einer Umsetzung mit Riot klären.
- Matchup-Briefing im Champ Select: nur Champions, die der Spieler sieht (gelockte Gegner – keine
  Gegner-Hovers, keine Namen oder Ränge der Gegner). Gegner-Lanes werden aus OP.GG-Lane-Anteilen geschätzt
  und als „vermutlich“ markiert. Counter-Picks nur während des eigenen Picks, als Liste mit Siegquote und
  Stichprobe („Optionen, keine Empfehlung“), nie automatisch gewählt. Team-Hinweise sind neutrale
  Beobachtungen („… ist eine Option“), abschaltbar.
- Ränge aller 10 Spieler (wie Porofessor/Blitz): nur Spieler des eigenen Spiels, abschaltbar.
- Nutzung der OP.GG-MCP-Schnittstelle in einer App: OP.GG vor dem Release informiert/anfragen.

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
