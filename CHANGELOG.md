# Changelog

## Unreleased
- ARAM: Mayhem in game: the champion's strong augments per rarity (Prismatic, Gold, Silver) appear at the
  top of the screen whenever an augment choice is likely open – at the start and after levels 7, 11 and 15,
  while dead or in the fountain. Icons and names match the client; grades S/A/B/C from OP.GG performance,
  plus pick share. Also in the Tab overlay. Toggle in settings. The offered cards are not read.
- Champ select (Mayhem): augment card ranked the same way, per rarity, instead of by popularity.
- Fix: no rune import in ARAM: Mayhem (runes are disabled in the mode).

## 0.3.0
- Champ select: matchup briefing with your likely lane opponent (inferred lanes are marked "vermutlich"),
  matchup tips and head-to-head win rate from OP.GG, counter picks during your own pick turn, and a
  team-comp summary (damage split, frontline). Only locked champions are used; toggle in settings.
- Fix: "Einstellungen …" in the menu bar opens the Settings window in front of other apps.

## 0.2.0
- Game mode detection from the client's queue (Ranked Solo/Flex, Normal, Swiftplay, ARAM,
  ARAM: Mayhem, Arena, URF, One for All, Ultimate Spellbook, Nexus Blitz, Brawl, Swarm, League Classic).
- Builds per mode: OP.GG Ranked, Flex and ARAM statistics; Mayhem shows the champion's most picked augments.
  Modes without data (Arena, League Classic, …) say so instead of importing wrong pages.
- Item sets are bound to the mode's map (ARAM sets no longer replace the Summoner's Rift set).
- Automatic import after lock-in: item set on by default, runes and spells opt-in.
- In game: skill-point hint above the ability bar showing which ability to level next.

## 0.1.0 – first public release
- Champ select panel docked to the client: OP.GG build with win rate, Riot recommendations,
  one-click import of runes, summoner spells and item sets (own pages and sets only).
- In game: Tab overlay with ranks (OP.GG), KDA, CS, CS/min vs. role guide value, build progress;
  rank banner at game start; optional item-gold estimate (off by default).
- Post-game summary in the menu bar.
- Onboarding with Input Monitoring setup, launch at login, Sparkle auto-updates.
