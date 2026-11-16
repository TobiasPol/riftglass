# Compliance

Riftglass muss mit Riots Richtlinien für Drittanbieter-Apps und mit Vanguard vereinbar bleiben.
Diese Datei ist verbindlich; Features, die hier als verboten stehen, werden nicht gebaut.

## Erlaubte Datenquellen
- **LCU** (lokal, `https://127.0.0.1:<app-port>`), inoffiziell, nur mit dem Token aus den
  Prozess-Argumenten/Lockfile des eigenen Benutzers.
- **Live Client Data API** (`https://127.0.0.1:2999`), nur Daten, die der Spieler im Spiel sehen kann.
- **Data Dragon** (statische Spieldaten, öffentlich).
- **OP.GG MCP** (`mcp-api.op.gg`, offizielle öffentliche Schnittstelle von OP.GG): Builds, Winrates, Ränge.
  Quellenangabe in der UI. Keine undokumentierten Endpunkte. Kein Riot-API-Key.
- **OP.GG-Webseite, nur die Mayhem-Augment-Seite** (`op.gg/lol/modes/aram-mayhem/<championId>/augments`):
  einzige Ausnahme vom Scraping-Verbot, entschieden am 2026-11-15, weil das MCP-Tool
  `lol_list_aram_augments` nur die Tiers 3–5 liefert und damit die besten Augments des Champions fehlen
  (SPIKE.md). Öffentliche Seite, ehrlicher User-Agent `Riftglass`, kein Login, keine weiteren Seiten.
  Abruf-Budget (`OPGGAugmentProvider`, per Test abgesichert): höchstens ein von op.gg beantworteter Abruf
  pro Champion in 6 h – auch eine Fehlerantwort oder eine nicht mehr lesbare Seite zählt und wird so lange
  auf der Platte gemerkt; gleichzeitige Anfragen teilen sich einen Abruf; blieb die Antwort ganz aus (kein
  Netz), frühestens nach 60 s erneut. Entfällt, sobald das MCP-Tool alle Tiers liefert.
- **Keine Riot-Empfehlungen** aus dem Client (`recommended-pages`, `recommended-champion-positions`) –
  Builds, Rollen und Augments kommen ausschließlich von OP.GG.

## Verboten
- Gegner-Ultimate-Timer (von Riot seit 13.03.2025 verboten) und Gegner-Summoner-Spell-Timer.
- Lesen des Spielspeichers, Injection in Spiel oder Client, Hooking.
- Eingabe-Automatisierung jeder Art (auch keine automatischen Picks, Bans oder Accept-Klicks).
- Informationen, die der Spieler im Spiel nicht sehen kann (z. B. versteckte Gegnerdaten).
- Scraping von Blitz.gg, U.GG o. Ä. und von OP.GG über die oben genannte Augment-Seite hinaus. Werbung in der App.
- Apps, die Spielerentscheidungen diktieren: Builds immer als **mehrere Optionen**, nie als Anweisung.

## Policy-Risiken
- Item-Gold-Schätzung pro Lane: nur aus sichtbaren Items, hinter Schalter, **standardmäßig aus**.
- Auto-Import nach dem Lock-in: schreibt nur Riftglass-eigene Item-Sets/Runenseiten (wie der Klick-Import),
  nie Picks/Bans/Accept. Item-Set standardmäßig an; Runen + Spells **opt-in**, weil sie die aktive Seite
  und die Spell-Auswahl des Spielers ändern. Abschaltbar in den Einstellungen.
- Skillpunkt-Overlay: zeigt die nächste Fähigkeit einer Statistik-Skill-Order als Hinweis; drückt keine
  Taste und levelt nichts (keine Eingabe-Automatisierung). Nur eigene Daten aus dem Live Client.
- Mayhem-Augments (Champ Select + Overlay im Spiel): statische OP.GG-Tierliste des eigenen Champions, vor
  dem Spiel bekannt (Riot: Overlays mit „static data that is available prior to the game“ erlaubt). Pro
  Seltenheit mehrere Optionen mit OP.GGs Tier (S, 1–5) –
  **nie Siegquoten** („Products cannot display win rates for Augments“, developer.riotgames.com/docs/lol),
  nie eine einzelne Anweisung. Das Overlay erscheint anhand der eigenen Stufe und des eigenen Todes-Status
  (Live Client); die angebotenen Karten werden **nicht** gelesen. Bildschirmaufnahme/OCR der Auswahlkarten
  bleibt ausgeschlossen, bis Riot es bestätigt. Abschaltbar.
- Matchup-Briefing im Champ Select: nur Champions, die der Spieler sieht (gelockte Gegner – keine
  Gegner-Hovers, keine Namen oder Ränge der Gegner). Gegner-Lanes werden aus OP.GG-Lane-Anteilen geschätzt
  und als „vermutlich“ markiert. Team-Hinweise sind neutrale Beobachtungen („… ist eine Option“), abschaltbar.
- Pick- und Ban-Optionen (seit 0.7, abschaltbar): Riot erlaubt Werkzeuge, die „multiple choices“ zeigen,
  verbietet aber „Apps that dictate player decisions“ und verlangt, dass Produkte die Vielfalt der
  Entscheidungen erhöhen (developer.riotgames.com/docs/lol, Game Integrity). Deshalb immer **mehrere**
  Optionen (Bans 5, Picks 3–5), jede mit sichtbaren Gründen (Lane-Stärke, Matchup, Synergie, Team-Passung,
  Meisterschaft) und dem Hinweis „Optionen, keine Empfehlung“; nie gehovert, gebannt oder gelockt
  (keine Eingabe-Automatisierung). Eingaben nur, was der Spieler sieht: eigene und verbündete Picks/Hovers/
  Ban-Hovers, gelockte Gegner – keine Gegner-Hovers, keine gegnerischen Bans vor der Aufdeckung. Die
  Meisterschaft ist eigene Daten aus der LCU und verlässt den Mac nicht. Die eigene Ban-Absicht bleibt in der
  Liste; nur Bans der Mitspieler werden ausgeblendet.
- Ränge aller 10 Spieler (wie Porofessor/Blitz): nur Spieler des eigenen Spiels, abschaltbar.
- Nutzung der OP.GG-MCP-Schnittstelle in einer App: OP.GG vor dem Release informiert/anfragen. Dabei auch
  das Lesen der Augment-Seite ansprechen und den MCP-Fehler melden (`lol_list_aram_augments` ohne Tier 0–2).

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
