# Changelog

## 0.13.0 (2026-11-16): a new design

Oracle is redesigned around what you look things up for: loot, professions, quests for a dungeon and a zone's quests.
Still a beta, so expect changes.

- **A new window**: the search and the spaces along the top (Dungeons & Raids, Professions, Zones), a list of places on
  the left, the page in the middle, and the **Inspector** on the right, which shows whatever you click.
- **One search for everything**: instances, bosses, items, recipes, professions, quests and zones, five of each, the
  closest matches first. A boss or an item opens on its loot; a recipe in Professions; a quest in its dungeon.
- **Dungeons & Raids** lists dungeons by level band (yours first) or raids. An instance opens on its **Loot**: the
  bosses down the side, numbered as on the map, and every drop beside them with its chance, whether you can use it, and
  its item level. **For me** keeps only what your class can use; **Uncommon+** hides the commons.
- **Map** is now a view of its own (the game map or the schematic, with the editor); clicking a boss there shows it in
  the Inspector instead of leaving the map. **Quests** and **Info** are 0.12's for now (the Ready check comes next).
- The Inspector: an item's every source (the boss and chance, quests, creatures, vendors, recipes), whether you can use
  it, Link and Show on map; a quest's state, giver, chain and rewards, with Track; a boss's loot.
- The old design is archived: tag v0.12.1, branch archive/oracle-1.
- **Wants**: right-click any item in a loot list (or Want in the Inspector) to want it. The Wants tab lists them by where
  they drop; an instance says how many of your wants drop there, in its header and in the list. Saved per character.
- **Professions**, rebuilt the AtlasLoot way: your professions first, then every one; each opens on your rank. Views:
  **By rank**, **By type** (what it makes: weapons, armour by kind and slot, consumables, ...), **By specialization**
  (Armorsmith, Weaponsmith and its masters, Gnomish and Goblin Engineering, Dragonscale, Elemental and Tribal
  Leatherworking) and **Trainers**. Each recipe shows what it makes, its skill-up colours, where it's learned and ✓ when
  you know it; filters: Learnable now, Not known, Skill-ups now. The header says the next rank you can train and your
  specialization. A recipe opens in the Inspector: reagents and where they come from, where to learn it, what uses it.
  The search finds specializations, and recipes by their specialization's name ("armorsmith").
- **Zones**, rebuilt with the same views as an instance: **Quests** is the zone's quest book (each chain with where you
  stand and its next step and where it is, unfolding to its steps; then single quests), **Loot** what the zone gives
  (Everything, Quest rewards, Creature drops, Rares, Vendors; For me, Uncommon+, World drops), **Map** and **Info** as
  before.
- **The Ready check** is a dungeon's Quests view: how many quests are ready, what to pick up grouped by where you go
  (with the giver and coordinates; a quest behind a chain by its first step), chains partway with their next step, what's
  in your log, what isn't yet, and Track pickups (Clairvoyance). Quests that are steps of another fold into it.
- Right-click a quest anywhere to Track it.
- Quests for the other faction or another class are never hidden: they sit at the bottom, greyed, under **Not for you**
  (in Questlines, Before you go and a zone's quests). Arrows, stars and ticks are the game's own icons.
- A dungeon's Quests view opens on **Questlines**: every quest chain that touches the instance, followed back to where
  it starts and on past the run, across zones. Each step shows where you stand: done (ticked), the step you're on
  (highlighted), what's coming. Steps done inside the dungeon are marked **In the dungeon**, and so are quests that
  start or end inside; a line that goes in more than once (Blackrock Depths) shows every visit. A quest that starts from
  an item found inside, like A Crumpled Up Note, is a step of its line: it says the note drops inside once you're on that
  step. **Before you go** (the pickups by where you go) is the other way to read it.

## 0.12.1 (2026-11-16)

- "Show all on the map" is now **Track these quests**: with Clairvoyance, the instance's quests get their own
  section in its tracker as well as their givers on the map.

## 0.12.0 (2026-11-15)

- **Before you go**: the Quests tab opens with what to pick up for the instance, grouped by where (each zone, or
  inside the instance for quests that start there or from an item that drops there), with a summary: how many to
  pick up, how many need earlier quests, how many are above your level, in your log or done. Click a row to see its
  quest. Click the heading to fold the list down to its summary.
- A quest that needs earlier quests is listed by the first one you haven't done ("first for Leaders of the Fang"),
  with where it starts; quests that share that first step share a row.
- **Show all on the map** puts every pickup on your map through Clairvoyance: each quest's giver, or the giver of
  the first quest before it. They leave the map as you take them.
- Each quest card says where you stand: done, in your quest log, ready to pick up, from which level, or how many
  earlier quests it needs and where the first one starts. It also says when a quest can't be shared (each of you
  picks it up), the optional quests that lead to it, and the quest it leads on to after the run.
- Track in Clairvoyance on a quest that needs earlier quests shows where the first of them starts.
- Questlines follow DungeonJournal's research on which quests come first (NorgannonDB 1.5), not only the
  prerequisites in the game data.
- The list updates as you pick up and hand in quests, and when you level.

## 0.11.3 (2026-11-09)

- Asks for Norgannon Core 1.21 or newer, the first Core with everything it needs; the map features from Core 1.28 switch on by themselves when Core has them. An older Core now gets a clear "update Norgannon Core" message instead of errors.

## 0.11.2, 2026-11-09

- **Showing an instance's entrance no longer opens the world map for you.** Opening Blizzard's map from an add-on taints
  its quest pins for the session, so opening the map or quest log later fails ("tried to call the protected function
  Button:SetPassThroughButtons()"). The entrance pulses if the map is already open on its zone; otherwise Oracle
  tells you which zone to open, and it pulses when you open the map there.

## 0.11.1, 2026-11-07

- The quest card no longer shows a greyed-out "Archivum" button: Archivum, the database browser, is shelved.

## 0.11.0, 2026-11-07

- Built on NorgannonDB Core 1.20's `Core:NewAddon`: the same commands, window and settings. `/oracle help` lists the
  commands; `/oracle <name>` still opens an instance.
- The "Show the minimap button" setting is gone: NorgannonDB > Minimap pins any add-on.
- Settings asked for in combat open when the fight ends.
- **Questlines**: on the Quests tab, quests that follow from each other are grouped under a
  heading with their first and last quest, numbered on a rail, with the earlier quests they hang
  on named when those aren't filed under the instance.
- **Faction**: a quest only one side can take has a stripe and a pill in that side's colour (also
  worked out from who gives it, when its race mask doesn't say). A filter shows your side, the
  other or all; the tab counts what shows, and quests you can't take are dimmed.
- The Info tab's greyed "Plan a run" button is gone: the suite's planner is shelved.

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
