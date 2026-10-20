# Oracle

> [!WARNING]
> **Very much a work in progress.** This is an early build for WoW Forever (client 1.60.1), in
> active development and testing. Expect missing features, rough edges, bugs, and changes that
> break things between versions. Bug reports and feedback are welcome in
> [Issues](../../issues).

Every dungeon and raid in WoW Forever: a map, the bosses, their loot and the quests that send you
there; every zone; every profession's recipes. Part of the NorgannonDB suite, with Clairvoyance,
Foresight and Archivum.

**v0.10:**
- **Crafts**: every profession's recipes on a skill ladder: each recipe at the skill where it's
  learned, coloured for your skill, its orange / yellow / green / grey ranges on a 1-300 strip with
  your skill marked. Filter to what you can learn now or what still gives skill-ups; the sidebar's
  search finds recipes. A recipe shows what it makes, its reagents and where each comes from, and
  where to learn it: trainers (your faction's first, with the price), recipe items (who sells or
  drops them), quests; "Show on map" through Clairvoyance.
- **Zones**: every zone the game puts on Kalimdor or the Eastern Kingdoms, with its level range.
  The game's own world map of the zone with its dungeon entrances, flight masters, innkeepers and
  rares pinned (each kind can be hidden); the zone's dungeons, services, trainers, rares, herbs and
  ore, the recipes its creatures drop, and its quests by level.

**v0.9 (release candidate):**
- The window, as in the suite's mockup: search over instances, bosses and loot; Dungeons and
  Raids; sort by level, name or continent.
- Every vanilla dungeon and raid, with wings as their own entries (Scarlet Monastery, Dire Maul,
  Blackrock Spire, Stratholme), and WoW Forever's own instances as NorgannonDB learns them.
- Schematic maps for every classic instance and wing: numbered bosses in route order, the
  entrance and points of interest, connected by paths (Oracle's own drawings).
- The Bosses tab (numbered as on the map, with ranks, levels and their best gear) and the Loot
  tab (each boss's own loot with drop chances; filter by boss and kind; the game's tooltips,
  shift-click to link, ctrl-click to try on).
- The Quests tab: every quest that sends you there, with its giver, requirements, rewards and
  XP; "Track in Clairvoyance" puts the giver on your map.
- "Open in Oracle" from Clairvoyance's quest menu, and an Oracle line in boss and loot tooltips.
- The Info tab: location, level range, group size, keys and attunements, your lockout, and
  "Show entrance on map".
- Real maps of every classic dungeon and raid, drawn from the game's own minimap, with each boss
  at its spawn point and floor tabs where rooms stack; the hand-drawn schematic is a click away.
- A movable window you can zoom from its corner, with adjustable opacity and a lock.

- Opens on the instance you're in (on the right wing), optionally as you enter; settings under
  NorgannonDB in the game's Settings (`/oracle settings`); a key binding.

Next: WoW Forever's own recipes from the Collector, and the in-game checklist.

`/oracle` opens it; `/oracle deadmines` opens an instance by name. `/oracle edit` turns on the map editor
(drag bosses, place summoned ones, move rooms between floors, name floors).

Boss and entrance positions on the game maps come from the cmangos classic-db
(github.com/cmangos/classic-db, GPL-3.0), with thanks.

Requires NorgannonDB and NorgannonDB Core. Made by **Maro**. All rights reserved for now; see
`LICENSE`.
