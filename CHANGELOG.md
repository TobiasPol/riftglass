# Changelog

## Unreleased
- **Pick and ban options in champ select.** While your ban is open, five ban options: strong champions the
  enemy is likely to pick (OP.GG win, pick and ban rate), champions in your lane weighted higher, and the
  champions that beat your declared pick. Until you lock in, pick options for your lane, each with the
  reasons behind it: lane strength, head-to-head against your (likely) lane opponent, duo synergy with your
  teammates, what your team lacks (magic or physical damage, frontline) and your own champion mastery –
  champions you have barely played rank lower, because players below ~12k mastery win ~44 % instead of
  ~51 %. Matchup and synergy are measured against both champions' usual win rates, so a strong champion
  is not mistaken for a counter. After the lock-in: your champion's duo win rate with each ally.
  Options only – Riftglass never hovers, bans or locks anything. Can be turned off in the settings.
- The counter list during your pick is now part of the pick options.

## 0.6.0
- **ARAM: Mayhem augments were wrong and nearly the same for every champion – fixed.** OP.GG's API only
  hands out the three weakest tiers of its augment list, and Riftglass ranked that remainder by a
  "performance" score that favours the same generic augments everywhere (Hand of Baron, Stats!, Omni
  Soul). The list now comes from OP.GG's champion page with all tiers and shows OP.GG's own tier (S, 1–5)
  per rarity: Garen gets Spin To Win, Kog'Maw his on-hit augments. The pick share is gone – that number
  never was one.
- **Builds come from OP.GG only.** Riot's recommendations from the client are no longer shown or used as a
  fallback; without an assigned lane (blind pick, custom) OP.GG's most played lane for the champion decides.
- Swapping lanes in champ select now loads the build, matchup and counters for the new lane.
- Build progress in the Tab overlay counts core items and boots plus one of the "Then" options. Starter
  items and all three alternatives used to count, so a finished build read 5/8 with a sold Doran's item as
  "next". A build left over from another champion is no longer shown.
- The skill-point hint recovers when OP.GG is briefly unreachable at game start (it used to stay off for
  the whole game) and uses the champion's usual lane when the game reports none.
- An error text from OP.GG is no longer cached for six hours as if it were data.
- No lane guess for an enemy who is never played in the remaining lane; lane shares refresh every 6 hours.
- The win rate on the build card is labelled as what it is: the core item path's.

## 0.5.1
- Riftglass no longer registers as a game. macOS showed a rocket in the menu bar in place of the
  Riftglass ◇ icon; the app category is now Utilities.

## 0.5.0
- Riftglass is now in **English and German** and follows your macOS language (per app: System Settings →
  General → Language & Region → Applications). Champion, item, rune and augment names follow it too.
- ARAM: Mayhem: the augment list now sits **left of the selection cards** as one narrow column instead of
  covering the middle card at the top. **⌥A** hides it until the next choice or shows it any time; there is
  also a switch in the menu bar.
- ARAM: Mayhem: a choice is no longer lost when you reach a new level just before leaving the fountain –
  each choice must have been open for 5 seconds to count as made.
- ARAM: Mayhem: the skill-point hint steps aside while the augment list is shown (it covered the card
  description), and the rank banner sits right of the cards.
- Rank banner waits for the game to start (a long loading screen used to let it expire unseen).
- Fewer requests: ranks that can't be found are given up after three tries instead of every 30 seconds.

## 0.4.0
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
