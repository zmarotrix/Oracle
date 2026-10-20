# Changelog

## 0.10.0, 2026-10-20

Requires NorgannonDB 1.4 and NorgannonDB Core 1.14.

- **Crafts** (the sidebar's fourth category, where PvP was greyed): every profession's recipes on
  a skill ladder, coloured for your skill, with each recipe's orange / yellow / green / grey ranges
  on a 1-300 strip and your skill marked down the strips. Filters: All, Learnable now, Skill-ups.
  The search finds recipes. A recipe's page: what it makes, its reagents and where each comes from
  (a crafted reagent opens its own recipe), where to learn it (trainers with their price, your
  faction's first; recipe items with who sells or drops them; quests), what it's used in, and
  "Show on map" through Clairvoyance.
- **Zones**: every zone on Kalimdor and the Eastern Kingdoms with its level range (from its quests).
  The game's own world map of the zone, with dungeon entrances (click: open in Oracle), flight
  masters, innkeepers and rares pinned; the legend hides a kind. The page lists the zone's
  dungeons, services, trainers, rares, herbs and ore, the recipes its creatures drop (click: the
  recipe in Crafts) and its quests by level.
- PvP left the sidebar; battlegrounds can come back as zones.
- **A zone's items**: the Items tab lists what you can get there: its quest rewards, what its
  creatures drop and what its vendors sell, best item level first, with the source on each row.
  Filter by source and by Gear / Recipes / Everything; world drops only when asked for. Click a
  row to see its source on your map (a reward: the quest's giver).
- The ladder's skill bands (Apprentice, Journeyman, Expert, Artisan) fold; each profession has its
  own search, which the sidebar's search box follows.
- WoW Forever's recipes: the healing potions are First Aid's, as in WoW Forever, and the skill-up
  colours follow WoW Forever's numbers.
- Enchanting materials say what disenchants into them (quality and item levels) and no longer offer
  "Show on map": a reagent offers it only when something drops or sells it.
- Recipes count as Other in the Loot tab's filter, not Gear.
- Fixed: clicking a dungeon in the sidebar opened the Zones view.
- **Real dungeon maps for every classic dungeon and raid**, drawn from the game's own indoor
  minimap tiles under the bosses. Wings get their own map; Zul'Farrak, Zul'Gurub and the Ruins of
  Ahn'Qiraj show the terrain they're built on. A "Game map / Schematic" switch picks the view;
  WoW Forever's own instances keep the schematic (or the "not mapped yet" panel).
- **Bosses where they stand**: on the game map each boss sits at its spawn point and the entrance
  where the portal leaves you; the bosses the schematic left out join, lettered. Bosses a script
  summons are listed as not on the map.
- **Floors**: instances whose rooms stack (Scholomance, Blackrock Depths, Dire Maul, ...) get floor
  tabs; clicking a boss on another floor turns to it, and the boss list names each boss's floor.
- Oracle ships only tile ids and positions (`data/maps.lua`); the game draws its own textures.
  Boss and entrance positions come from the cmangos classic-db (GPL-3.0), with thanks.
- **Map editor** (`/oracle edit`, or "Edit map" beside the map switch): drag a boss or the
  entrance, place the bosses the map doesn't (summoned ones such as Ragnaros), send a marker or a
  room to another floor (or a new one), and name floors. Changes save at once and show at once;
  `tools/oracle_maps/edits.py` locks them into the shipped map data.
- **Zoom and move around the map**: the mouse wheel zooms (up to 4x) toward the cursor, dragging
  moves the map, and a double-click shows all of it again. The game map's tiles zoom; the boss
  markers keep their size so they don't cover the rooms. Works in the schematic, the game map and
  the editor; each instance opens showing the whole map.

## 0.9.0 (release candidate), 2026-10-19

The first complete build of Phase A (Atlas parity). What's left before 1.0 is a pass through the
in-game checklist (`docs/oracle-checklist.md` in the suite workspace) and the layouts' review.

- **The window**, matching the suite's mockup: search over instances, bosses and loot; Dungeons
  and Raids; sort by level, name or continent; zoom from the corner; opacity; lock; key binding.
- **Every vanilla dungeon and raid**, with wings as their own entries, and WoW Forever's own
  instances (four with bosses, loot and quests; the rest as players map them).
- **Schematic maps** for all 33 classic instances and wings: numbered bosses in route order,
  the entrance, points of interest, dotted paths; hover linked with the boss list.
- **Bosses**: rank, level, drop count and best gear. **Loot**: each boss's own loot with drop
  chances, filters, the game's tooltips and links, and trash drops. **Quests**: giver and
  location, requirements, prerequisites, rewards, XP, "Track in Clairvoyance". **Info**: location,
  levels, group size, keys, attunements, your lockout, "Show entrance on map".
- **Opens on the instance you're in**, on the right wing; optionally as you enter.
- **Suite links**: "Open in Oracle" in Clairvoyance's quest menu; an Oracle line in boss and
  loot tooltips.
- **Data**: NorgannonDB 1.3 (instances, loot table chances), with WoW Forever's dungeon data
  from DungeonJournal by Exehn, used with permission.

Requires NorgannonDB 1.3 and NorgannonDB Core 1.12.
