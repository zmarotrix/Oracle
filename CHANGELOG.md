# Changelog

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
