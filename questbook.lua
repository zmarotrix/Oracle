-- Oracle.QuestBook: Oracle's quest engine (docs/oracle-redesign.md 4.3). No UI: facts about the quests
-- the player looks at, for the Ready check (an instance's Quests view) and the Zones space's quest
-- book. Facts, never orders (suite decision 9): it says where each quest and chain stands and where
-- its next step is; it never picks quests for the player. Player-facing words belong to the views:
-- everything here is codes, ids and numbers.
--
--   QB.State(id)        -> st = { s, why, ... }  where you stand with a quest:
--       s = "done" | "log" | "ready" | "locked" | "nfy" (not for you)
--       locked, why = "step"    (st.step: the first earlier step not done, st.left: how many are left;
--                                st.level too when you're also under its level)
--                     "level"   (st.level) · "skill" (st.skill = {skillId, value}, st.have)
--                     "rep"     (st.rep = {factionId, value}, st.have) · "event" (seasonal)
--                     "blocked" (st.other: not while that quest is in your log) · "spell"
--       nfy,    why = "faction" | "race" | "class" (st.side: the side that can take it, if one)
--                     "exclusive" (st.other: you took its alternative) · "skipped" (a breadcrumb
--                     whose quest you've already taken) · "ended" · "outleveled" · "rephigh"
--                     · "spell" · "hidden" · "unknown"
--   QB.ForMe(id)        -> whether your side, race and class can ever take it
--   QB.Side(id)         -> "Alliance" | "Horde" | nil (both)
--   QB.ChainTo(id)      -> { ids }: the steps that lead to a quest, first first, the quest itself last.
--                          "any" prerequisites follow the branch you took (done, then in your log,
--                          then the first you can take). DungeonJournal's leadIn where it has one.
--   QB.NextStep(steps)  -> id, st: the first step that isn't done (nil when all are)
--   QB.Giver(id)        -> { kind = "npcs"|"objects"|"items", id, name, area, x, y } or nil:
--                          who starts it and where (an item: where what drops it stands)
--   QB.AreaName(area)   -> the zone's name
--   QB.ZoneQuests(area) -> { ids }: the quests the quest log files under that zone
--   QB.Chains(ids, mode)-> { chains = { chain }, singles = { single } } for any set of quests
--   QB.Zone(area, mode) -> the same for a zone's quests. mode "mine" (default: only quests your
--                          side, race and class can take) or "all"
--       chain  = { key, title, titleId, level, shape = "rail"|"tree", quests = { ids in order },
--                  rails = { { steps = { ids }, from = { rail indexes it continues from } } },
--                  crumbs = { [id] = true } (optional breadcrumb steps),
--                  before = { ids outside the set its first steps need }, after = { ids that follow
--                  outside the set },
--                  state = "done"|"part"|"new"|"locked"|"nfy", done, total,
--                  next = { ids: the steps you can act on now, else the first locked one },
--                  giver = QB.Giver(next[1]) }
--       single = { id, level, state = st, before, after, giver }
--     A network of linked quests (prerequisites, next-in-chain, breadcrumbs) is one chain, split at
--     its hubs into rails: a quest that opens two lines starts a branch, a quest two lines lead to
--     starts a rail of its own. Redundant links (a -> c when a -> b -> c) are dropped first.
--   QB.ChainOf(id, mode)-> the chain (or single) holding a quest, in its zone's quest book
--   QB.Ready(key)       -> the Ready check for an instance:
--       { pick = { { area, name, inside, entries, givers = { { giver, entries } } } } (by zone of the
--         next step's giver), part, log, later, done, nfy = { entry },
--         counts = { pick, part, log, later, done, nfy, total, places } }
--       entry = { id, state = st, steps (QB.ChainTo), next, nextState, giver (of next), started,
--                 folded = { listed quests that are earlier steps of this one } }
--     A listed quest that is an earlier step of another listed quest folds into that one's entry.
--   QB.Invalidate(all)  -> forgets player state (all: the chain structure too). Done for you on
--                          NORGANNON_QUEST_*, quest log, level, skill and reputation messages; sends
--                          ORACLE_QUESTBOOK_CHANGED (next frame). QB.revision counts the changes.
--
-- Cached: structure per zone and mode for the session; states, paths and views until the next
-- change. Logic carried over from Oracle 0.12's quests.lua (side, path, lead-in) and Clairvoyance's
-- availability rules.

local Core = NorgannonCore
local DB = NorgannonDB
local O = Oracle
if not O or O.disabled then return end

local QB = { revision = 0 }
O.QuestBook = QB

local P = Core.Player

-- race masks per side: the classic races, then draenei, worgen, pandaren / goblins, blood elves,
-- pandaren; WoW Forever's two own races (95, 96) above 2^32
local ALLIANCE_RACES = { 1, 4, 8, 64, 1024, 2097152, 16777216, 4294967296 }
local HORDE_RACES = { 2, 16, 32, 128, 256, 512, 33554432, 8589934592 }
local REPEATABLE = 1

local function quest(id) return id and DB:Get("quests", id) end
local function hidden(id) return Core.DB:IsQuestHidden(id) end
local function hasFlag(mask, flag) return DB.HasFlag(mask, flag) end

-------------------------------------------------------------------------------------------
-- Caches
-------------------------------------------------------------------------------------------

local stateMemo, pathMemo, viewMemo, readyMemo = {}, {}, {}, {}
local structMemo, sideMemo, giverMemo = {}, {}, {}
local masks                             -- { race, class }, read once per invalidation

function QB.Invalidate(all)
  stateMemo, pathMemo, viewMemo, readyMemo, masks = {}, {}, {}, {}, nil
  if all then structMemo, sideMemo = {}, {} end
  QB.revision = QB.revision + 1
end

local function playerMasks()
  if masks then return masks[1], masks[2] end
  local enums = DB.enums or {}
  local _, _, raceId = UnitRace("player")
  masks = { enums.raceMaskById and enums.raceMaskById[raceId] or false,
    enums.classKeys and enums.classKeys[P.class or ""] or false }
  return masks[1], masks[2]
end

local function mySide()
  local f = P.faction or UnitFactionGroup("player")
  return (f == "Alliance" or f == "Horde") and f or nil
end

-------------------------------------------------------------------------------------------
-- Sides (0.12's Quests.Side / SideOf)
-------------------------------------------------------------------------------------------

local function anyRace(mask, list)
  for _, bit in ipairs(list) do
    if mask % (2 * bit) >= bit then return true end
  end
  return false
end

-- the side a race mask allows: a side, false when both, nil when it says nothing
local function sideOfMask(q)
  local races = q and q.races
  if not races or races == 0 then return nil end
  local a, h = anyRace(races, ALLIANCE_RACES), anyRace(races, HORDE_RACES)
  if a and h then return false end
  return a and "Alliance" or h and "Horde" or nil
end

local function sideOfGivers(who)
  local side
  for _, kind in ipairs({ "npcs", "objects" }) do
    for _, id in ipairs(who and who[kind] or {}) do
      local record = DB:Get(kind, id)
      local r = record and record.reaction
      if r == "AH" then return false end
      local this = r == "A" and "Alliance" or r == "H" and "Horde" or nil
      if this and side and this ~= side then return false end
      side = this or side
    end
  end
  return side
end

local function prereqIds(q)
  local out = {}
  local pre = q and q.prerequisites
  if not pre then return out end
  for _, p in ipairs(pre.all or {}) do out[#out + 1] = math.abs(p) end
  for _, p in ipairs(pre.any or {}) do out[#out + 1] = math.abs(p) end
  return out
end

---The side a quest belongs to: its race mask; without one, who gives it, who takes it back, then
---the quests before it (when they agree). nil: both sides can take it.
function QB.Side(id)
  local known = sideMemo[id]
  if known ~= nil then return known or nil end
  sideMemo[id] = false                  -- chains can loop in the data
  local q = quest(id)
  if not q then return nil end
  local side = sideOfMask(q)
  if side == nil then side = sideOfGivers(q.starters) end
  if side == nil then side = sideOfGivers(q.finishers) end
  if side == nil then
    for _, p in ipairs(prereqIds(q)) do
      local this = QB.Side(p)
      if not this or (side and this ~= side) then side = nil break end
      side = this
    end
  end
  sideMemo[id] = side or false
  return side or nil
end

-- why your side, race or class can never take it, or nil
local function identityBar(id, q)
  if not q then return "unknown" end
  if hidden(id) then return "hidden" end
  local race, class = playerMasks()
  local me = mySide()
  local side = QB.Side(id)
  if side and me and side ~= me then return "faction", side end
  if race and q.races and q.races ~= 0 and not hasFlag(q.races, race) then return "race", side end
  if class and q.classes and q.classes ~= 0 and not hasFlag(q.classes, class) then return "class", side end
end

---Whether your side, race and class can ever take a quest.
function QB.ForMe(id) return identityBar(id, quest(id)) == nil end
local forMe = QB.ForMe

-------------------------------------------------------------------------------------------
-- The way to a quest (0.12's Quests.Path, with the quest itself last)
-------------------------------------------------------------------------------------------

-- the prerequisites to follow back: all of "all", and of "any" the one you did, else the one in
-- your log, else the first you can take
local function choiceOf(q)
  local pre = q and q.prerequisites
  if not pre then return {} end
  local out = {}
  for _, p in ipairs(pre.all or {}) do out[#out + 1] = math.abs(p) end
  local any = pre.any
  if any and #any > 0 then
    local pick
    for _, p in ipairs(any) do if P:IsCompleted(math.abs(p)) then pick = p break end end
    if not pick then for _, p in ipairs(any) do if P:HasQuest(math.abs(p)) then pick = p break end end end
    if not pick then for _, p in ipairs(any) do if forMe(math.abs(p)) then pick = p break end end end
    out[#out + 1] = math.abs(pick or any[1])
  end
  return out
end

---The steps that lead to a quest, first first, ending with the quest. Only steps you can take.
function QB.ChainTo(id)
  local memo = pathMemo[id]
  if memo then return memo end
  local out, seen = {}, { [id] = true }
  local function walk(p, depth)
    if seen[p] or depth > 30 or #out >= 40 then return end
    seen[p] = true
    if not forMe(p) then return end
    local q = quest(p)
    for _, pre in ipairs(q.leadIn or {}) do walk(pre, depth + 1) end
    for _, pre in ipairs(choiceOf(q)) do walk(pre, depth + 1) end
    out[#out + 1] = p
  end
  local q = quest(id)
  for _, p in ipairs(q and q.leadIn or {}) do walk(p, 1) end
  for _, p in ipairs(choiceOf(q)) do walk(p, 1) end
  out[#out + 1] = id
  pathMemo[id] = out
  return out
end

-------------------------------------------------------------------------------------------
-- State
-------------------------------------------------------------------------------------------

local function spellKnown(spell)
  for _, api in ipairs({ "IsSpellKnown", "IsPlayerSpell" }) do
    local fn = rawget(_G, api)
    if fn then
      local ok, known = pcall(fn, spell)
      if ok then return known and true or false end
    end
  end
end

-- a prerequisite is met when done; a negative id (Questie's convention) when in the log or done
local function met(p)
  if p < 0 then return P:HasQuest(-p) or P:IsCompleted(-p) end
  return P:IsCompleted(p)
end

-- the first prerequisite that isn't met, or nil
local function missingPrereq(q)
  local pre = q.prerequisites
  if not pre then return nil end
  for _, p in ipairs(pre.all or {}) do
    if not met(p) then return math.abs(p) end
  end
  local any = pre.any
  if any and #any > 0 then
    for _, p in ipairs(any) do if met(p) then return nil end end
    return math.abs(any[1])
  end
end

local function compute(id)
  local q = quest(id)
  if not q then return { s = "nfy", why = "unknown" } end
  if P:IsCompleted(id) then return { s = "done" } end
  if P:HasQuest(id) then return { s = "log" } end
  local bar, side = identityBar(id, q)
  if bar then return { s = "nfy", why = bar, side = side } end
  for _, other in ipairs(q.exclusiveTo or {}) do
    if other ~= id and (P:IsCompleted(other) or P:HasQuest(other)) then return { s = "nfy", why = "exclusive", other = other } end
  end
  local target = q.breadcrumbFor
  if target and (P:IsCompleted(target) or P:HasQuest(target)) then return { s = "nfy", why = "skipped", other = target } end
  if q.availableUntilCompleted and P:IsCompleted(q.availableUntilCompleted) then
    return { s = "nfy", why = "ended", other = q.availableUntilCompleted }
  end
  local level = P.level or UnitLevel("player") or 1
  if q.maxLevel and q.maxLevel > 0 and level > q.maxLevel then return { s = "nfy", why = "outleveled", level = q.maxLevel } end
  local maxRep = q.requiredMaxRep
  if maxRep and maxRep[1] then
    local rep = P:GetReputation(maxRep[1])
    if rep and rep >= (maxRep[2] or 0) then return { s = "nfy", why = "rephigh", rep = maxRep, have = rep } end
  end
  local spell = q.requiredSpell
  local known = spell and spell ~= 0 and spellKnown(math.abs(spell))
  if spell and spell < 0 and known then return { s = "nfy", why = "spell", spell = -spell } end

  local tooLow = q.minLevel and q.minLevel > level and q.minLevel or nil
  -- an earlier step: the prerequisites gate; the path says where to go first
  local missing = missingPrereq(q)
  local w = q.availableStartingWith
  if not missing and w and not (P:HasQuest(w) or P:IsCompleted(w)) then missing = w end
  if missing then
    local step, left = nil, 0
    for _, s in ipairs(QB.ChainTo(id)) do
      if s ~= id and not P:IsCompleted(s) then
        left = left + 1
        step = step or s
      end
    end
    return { s = "locked", why = "step", step = step or missing, left = math.max(left, 1), level = tooLow }
  end
  if q.disabledByQuest and P:HasQuest(q.disabledByQuest) then return { s = "locked", why = "blocked", other = q.disabledByQuest } end
  if tooLow then return { s = "locked", why = "level", level = tooLow } end
  local skill = q.requiredSkill
  if skill and skill[1] then
    local rank = P:GetSkill(skill[1])
    if not rank or rank < (skill[2] or 1) then return { s = "locked", why = "skill", skill = skill, have = rank } end
  end
  local minRep = q.requiredMinRep
  if minRep and minRep[1] then
    local rep = P:GetReputation(minRep[1])
    if not rep or rep < (minRep[2] or 0) then return { s = "locked", why = "rep", rep = minRep, have = rep } end
  end
  if spell and spell > 0 and known == false then return { s = "locked", why = "spell", spell = spell } end
  if q.event then return { s = "locked", why = "event" } end
  return { s = "ready" }
end

---Where you stand with a quest (see the top of the file).
function QB.State(id)
  local st = stateMemo[id]
  if not st then
    st = compute(id)
    stateMemo[id] = st
  end
  return st
end
local state = QB.State

-- done, or a breadcrumb you went past: nothing left to do on that step
local function settled(st) return st.s == "done" or (st.s == "nfy" and st.why == "skipped") end

---The first step that isn't done, and its state; nil when every step is.
function QB.NextStep(steps)
  for _, s in ipairs(steps or {}) do
    local st = state(s)
    if not settled(st) then return s, st end
  end
end

-------------------------------------------------------------------------------------------
-- Where things are
-------------------------------------------------------------------------------------------

function QB.AreaName(area)
  if not area then return nil end
  if C_Map and C_Map.GetAreaInfo then
    local ok, name = pcall(C_Map.GetAreaInfo, area)
    if ok and type(name) == "string" and name ~= "" then return name end
  end
  local z = DB.zones and DB.zones[area]
  return z and z.name
end

-- where a creature or object stands: the preferred area if it's there, else where it stands most
local function placeOf(kind, id, prefer)
  local record = DB:Get(kind, id)
  local spawns = record and record.spawns
  if not spawns then return nil end
  local function first(points)
    for _, p in ipairs(points) do
      if p[1] and p[1] >= 0 then return p end
    end
  end
  if prefer and spawns[prefer] then
    local p = first(spawns[prefer])
    return prefer, p and p[1], p and p[2]
  end
  local best, bestN
  for area, points in pairs(spawns) do
    local n = #points
    if not best or n > bestN or (n == bestN and area < best) then best, bestN = area, n end
  end
  if not best then return nil end
  local p = first(spawns[best])
  return best, p and p[1], p and p[2]
end

---Who starts a quest and where: { kind, id, name, area, x, y } or nil. For an item, the area is
---where the creature most likely to drop it stands.
function QB.Giver(id)
  local memo = giverMemo[id]
  if memo ~= nil then return memo or nil end
  local q = quest(id)
  local s = q and q.starters or {}
  local g
  local prefer = q and q.zoneOrSort and q.zoneOrSort > 0 and q.zoneOrSort or nil
  for _, kind in ipairs({ "npcs", "objects" }) do
    local who = s[kind] and s[kind][1]
    if who and not g then
      g = { kind = kind, id = who, name = Core.DB:Name(kind, who) }
      g.area, g.x, g.y = placeOf(kind, who, prefer)
    end
  end
  local item = not g and s.items and s.items[1]
  if item then
    g = { kind = "items", id = item, name = Core.DB:Name("items", item) }
    local record = DB:Get("items", item)
    local best, chance
    for npc, c in pairs(record and record.drops and record.drops.npcs or {}) do
      c = tonumber(c) or 0
      if not best or c > chance or (c == chance and npc < best) then best, chance = npc, c end
    end
    if best then g.area = placeOf("npcs", best, prefer) g.dropper = best end
  end
  giverMemo[id] = g or false
  return g
end

-------------------------------------------------------------------------------------------
-- Chains: networks of linked quests, split at their hubs into rails
-------------------------------------------------------------------------------------------

local function levelOf(id)
  local q = quest(id)
  return q and q.level and q.level > 0 and q.level or 0
end

local function byLevel(a, b)
  local la, lb = levelOf(a), levelOf(b)
  if la ~= lb then return la < lb end
  return a < b
end

---The quests the quest log files under a zone (zoneOrSort), not hidden.
function QB.ZoneQuests(area)
  local out = {}
  for _, id in ipairs(Core.DB:Zone(area).quests) do
    local q = quest(id)
    if q and q.zoneOrSort == area and not hidden(id) then out[#out + 1] = id end
  end
  table.sort(out)
  return out
end

-- the links among a set: succ[a][b] = true when a comes before b; crumbs[id] when id is an
-- optional breadcrumb
local function links(set)
  local succ, pred, crumbs = {}, {}, {}
  for id in pairs(set) do succ[id], pred[id] = {}, {} end
  local function link(a, b)
    if a == b or not (set[a] and set[b]) then return end
    succ[a][b] = true
    pred[b][a] = true
  end
  for id in pairs(set) do
    local q = quest(id)
    for _, p in ipairs(prereqIds(q)) do link(p, id) end
    local lead, last = q.leadIn, nil
    for _, p in ipairs(lead or {}) do
      if set[p] then
        if last then link(last, p) end
        last = p
      end
    end
    if last then link(last, id) end
    if q.nextQuestInChain then link(id, q.nextQuestInChain) end
    if q.breadcrumbFor then link(id, q.breadcrumbFor) crumbs[id] = set[q.breadcrumbFor] or nil end
    for _, b in ipairs(q.breadcrumbs or {}) do
      link(b, id)
      if set[b] then crumbs[b] = true end
    end
  end
  return succ, pred, crumbs
end

local function count(t) local n = 0 for _ in pairs(t) do n = n + 1 end return n end

-- drop a -> c when c can be reached from a another way
local function reduce(members, succ, pred)
  local function reaches(from, to, skipA, skipC)
    local seen, stack = { [from] = true }, { from }
    while #stack > 0 do
      local x = table.remove(stack)
      for y in pairs(succ[x]) do
        if not (x == skipA and y == skipC) then
          if y == to then return true end
          if not seen[y] then seen[y] = true stack[#stack + 1] = y end
        end
      end
    end
    return false
  end
  for _, a in ipairs(members) do
    local targets = {}
    for c in pairs(succ[a]) do targets[#targets + 1] = c end
    if #targets > 1 then
      table.sort(targets)
      for _, c in ipairs(targets) do
        if reaches(a, c, a, c) then succ[a][c] = nil pred[c][a] = nil end
      end
    end
  end
end

-- one network as rails: { quests, rails = { { steps, from } }, depth }
local function railsOf(members, succ, pred)
  local depth, busy = {}, {}
  local function depthOf(x)
    if depth[x] then return depth[x] end
    if busy[x] then return 0 end          -- a loop in the data
    busy[x] = true
    local d = 0
    for p in pairs(pred[x]) do d = math.max(d, depthOf(p) + 1) end
    busy[x] = nil
    depth[x] = d
    return d
  end
  for _, x in ipairs(members) do depthOf(x) end
  table.sort(members, function(a, b)
    if depth[a] ~= depth[b] then return depth[a] < depth[b] end
    return byLevel(a, b)
  end)
  local function only(t) local k = next(t) return next(t, k) == nil and k or nil end
  local railOf, rails = {}, {}
  local function startsRail(x)
    local p = only(pred[x])
    return not p or only(succ[p]) == nil
  end
  local function grow(start)
    local steps, x = {}, start
    while x and not railOf[x] do
      steps[#steps + 1] = x
      railOf[x] = #rails + 1
      local nx = only(succ[x])
      x = nx and only(pred[nx]) and nx or nil
    end
    rails[#rails + 1] = { steps = steps }
  end
  for _, x in ipairs(members) do if not railOf[x] and startsRail(x) then grow(x) end end
  for _, x in ipairs(members) do if not railOf[x] then grow(x) end end   -- loops
  for _, rail in ipairs(rails) do
    local from, seen = {}, {}
    for p in pairs(pred[rail.steps[1]]) do
      local r = railOf[p]
      if r and not seen[r] then seen[r] = true from[#from + 1] = r end
    end
    table.sort(from)
    rail.from = from
  end
  local quests = {}
  for _, rail in ipairs(rails) do for _, x in ipairs(rail.steps) do quests[#quests + 1] = x end end
  return quests, rails, depth
end

-- the quests outside the set that a network hangs on, and those that follow it
local function outside(quests, set, mode)
  local before, after, seenB, seenA = {}, {}, {}, {}
  local function keep(id) return not hidden(id) and quest(id) and (mode == "all" or forMe(id)) end
  for _, id in ipairs(quests) do
    local q = quest(id)
    for _, p in ipairs(prereqIds(q)) do
      if not set[p] and not seenB[p] and keep(p) then seenB[p] = true before[#before + 1] = p end
    end
    local unlocks, nextId = Core.DB:Unlocks(id)
    if nextId and not set[nextId] and not seenA[nextId] and keep(nextId) then seenA[nextId] = true after[#after + 1] = nextId end
    for _, u in ipairs(unlocks) do
      if not set[u] and not seenA[u] and keep(u) then seenA[u] = true after[#after + 1] = u end
    end
  end
  table.sort(before, byLevel)
  table.sort(after, byLevel)
  return before, after
end

-- the player-free shape of a set of quests
local function structure(ids, mode)
  local set, list = {}, {}
  for _, id in ipairs(ids) do
    if not set[id] and quest(id) and not hidden(id) and (mode == "all" or forMe(id)) then
      set[id] = true
      list[#list + 1] = id
    end
  end
  local succ, pred, crumbs = links(set)
  -- networks: union-find over the links
  local root = {}
  for _, id in ipairs(list) do root[id] = id end
  local function find(x)
    while root[x] ~= x do root[x] = root[root[x]] x = root[x] end
    return x
  end
  for _, a in ipairs(list) do
    for b in pairs(succ[a]) do root[find(b)] = find(a) end
  end
  local groups, order = {}, {}
  for _, id in ipairs(list) do
    local r = find(id)
    if not groups[r] then groups[r] = {} order[#order + 1] = r end
    table.insert(groups[r], id)
  end
  local chains, singles = {}, {}
  for _, r in ipairs(order) do
    local members = groups[r]
    if #members == 1 then
      local id = members[1]
      local before, after = outside(members, set, mode)
      singles[#singles + 1] = { id = id, level = levelOf(id), before = before, after = after }
    else
      reduce(members, succ, pred)
      local quests, rails, depth = railsOf(members, succ, pred)
      -- the title: the last step of the longest line (decision 5.4: until better names come)
      local titleId
      for _, x in ipairs(quests) do
        if not titleId or depth[x] > depth[titleId] or (depth[x] == depth[titleId] and next(succ[titleId]) and not next(succ[x])) then
          titleId = x
        end
      end
      local chainCrumbs = {}
      for _, x in ipairs(quests) do if crumbs[x] then chainCrumbs[x] = true end end
      local level
      for _, x in ipairs(rails[1].steps) do
        local l = levelOf(x)
        if l > 0 and (not level or l < level) then level = l end
      end
      local before, after = outside(quests, set, mode)
      chains[#chains + 1] = {
        key = quests[1], titleId = titleId, title = Core.DB:Name("quests", titleId), level = level or 0,
        shape = #rails == 1 and "rail" or "tree", quests = quests, rails = rails, crumbs = chainCrumbs,
        before = before, after = after,
      }
    end
  end
  table.sort(chains, function(a, b)
    if a.level ~= b.level then return a.level < b.level end
    return (a.title or "") < (b.title or "")
  end)
  table.sort(singles, function(a, b) return byLevel(a.id, b.id) end)
  return { chains = chains, singles = singles }
end

-- the player's place in a chain
local function fillChain(c)
  local done, total, started, ready = 0, 0, false, false
  local open, firstLocked = {}, nil
  for _, x in ipairs(c.quests) do
    local st = state(x)
    if st.s == "nfy" then
      -- not yours (or a breadcrumb you went past): not counted
    else
      total = total + 1
      if st.s == "done" then done, started = done + 1, true
      elseif st.s == "log" then started = true open[#open + 1] = x
      elseif st.s == "ready" then ready = true open[#open + 1] = x
      elseif not firstLocked then firstLocked = x end
    end
  end
  c.done, c.total = done, total
  if total == 0 then c.state = "nfy"
  elseif done == total then c.state = "done"
  elseif started then c.state = "part"
  elseif ready then c.state = "new"
  else c.state = "locked" end
  if #open == 0 and firstLocked and c.state ~= "done" then open[1] = firstLocked end
  c.next = open
  c.giver = open[1] and QB.Giver(open[1]) or nil
  return c
end

local function view(key, ids, mode)
  mode = mode == "all" and "all" or "mine"
  local skey = key and (key .. ":" .. mode)
  local cached = skey and viewMemo[skey]
  if cached then return cached end
  local shape = skey and structMemo[skey]
  if not shape then
    shape = structure(ids or {}, mode)
    if skey then structMemo[skey] = shape end
  end
  local out = { chains = {}, singles = {}, mode = mode }
  for i, c in ipairs(shape.chains) do
    local v = {}
    for k, val in pairs(c) do v[k] = val end
    out.chains[i] = fillChain(v)
  end
  for i, s in ipairs(shape.singles) do
    out.singles[i] = { id = s.id, level = s.level, before = s.before, after = s.after,
      state = state(s.id), giver = QB.Giver(s.id) }
  end
  if skey then viewMemo[skey] = out end
  return out
end

---Chains and single quests among any set of quests (not cached).
function QB.Chains(ids, mode) return view(nil, ids, mode) end

---A zone's quest book: its chains and single quests, with where you stand.
function QB.Zone(area, mode)
  local key = "zone" .. tostring(area)
  local m = mode == "all" and "all" or "mine"
  if structMemo[key .. ":" .. m] then return view(key, nil, m) end
  return view(key, QB.ZoneQuests(area), m)
end

---The chain (or single entry) holding a quest, in its zone's quest book; nil when its zone has none.
function QB.ChainOf(id, mode)
  local q = quest(id)
  local area = q and q.zoneOrSort
  if not area or area <= 0 then return nil end
  local book = QB.Zone(area, mode)
  for _, c in ipairs(book.chains) do
    for _, x in ipairs(c.quests) do if x == id then return c end end
  end
  for _, s in ipairs(book.singles) do if s.id == id then return s end end
end

-------------------------------------------------------------------------------------------
-- The Ready check
-------------------------------------------------------------------------------------------

---An instance's quests sorted into what you do about them (see the top of the file).
function QB.Ready(key)
  local cached = readyMemo[key]
  if cached then return cached end
  local inst = Core.DB:Instance(key)
  local listed, isListed = {}, {}
  for _, id in ipairs(inst and inst.quests or {}) do
    if not isListed[id] and quest(id) and not hidden(id) then
      isListed[id] = true
      listed[#listed + 1] = id
    end
  end
  -- a listed quest that's an earlier step of another listed quest (one you can take) folds into it
  local foldedInto = {}
  for _, id in ipairs(listed) do
    if state(id).s ~= "nfy" then
      local steps = QB.ChainTo(id)
      for i = 1, #steps - 1 do
        local s = steps[i]
        if isListed[s] and s ~= id and not foldedInto[s] then foldedInto[s] = id end
      end
    end
  end
  -- a quest folded into one that's itself folded: up to the outermost
  local function outer(id)
    local seen = {}
    while foldedInto[id] and not seen[id] do seen[id] = true id = foldedInto[id] end
    return id
  end
  local out = { pick = {}, part = {}, log = {}, later = {}, done = {}, nfy = {} }
  local entries = {}
  for _, id in ipairs(listed) do
    if not foldedInto[id] then
      local st = state(id)
      local e = { id = id, state = st, folded = {} }
      entries[id] = e
      if st.s == "nfy" then
        out.nfy[#out.nfy + 1] = e
      else
        e.steps = QB.ChainTo(id)
        for _, s in ipairs(e.steps) do
          local ss = state(s)
          if ss.s == "done" or ss.s == "log" then e.started = true break end
        end
        if st.s == "done" then out.done[#out.done + 1] = e
        elseif st.s == "log" then out.log[#out.log + 1] = e
        else
          local nx, ns = QB.NextStep(e.steps)
          e.next, e.nextState = nx, ns
          e.giver = nx and QB.Giver(nx) or nil
          if ns and ns.s == "log" then out.part[#out.part + 1] = e
          elseif ns and ns.s == "ready" then
            local list = e.started and out.part or out.pick
            list[#list + 1] = e
          else out.later[#out.later + 1] = e end
        end
        e.giver = e.giver or QB.Giver(id)
      end
    end
  end
  for _, id in ipairs(listed) do
    if foldedInto[id] then
      local e = entries[outer(id)]
      if e then e.folded[#e.folded + 1] = id end
    end
  end
  for _, list in pairs(out) do
    table.sort(list, function(a, b) return byLevel(a.id, b.id) end)
  end

  -- Pick up: by the zone of the next step's giver, then by giver
  local groups, byArea = {}, {}
  for _, e in ipairs(out.pick) do
    local g = e.giver
    local area = g and g.area
    local inside = area ~= nil and inst ~= nil and area == inst.area
    local gkey = area or (g and g.kind == "items" and "item") or "unknown"
    local group = byArea[gkey]
    if not group then
      group = { area = area, name = area and QB.AreaName(area) or nil, inside = inside, entries = {}, givers = {}, byGiver = {} }
      byArea[gkey] = group
      groups[#groups + 1] = group
    end
    group.entries[#group.entries + 1] = e
    local who = g and (g.kind .. ":" .. g.id) or "?"
    local sub = group.byGiver[who]
    if not sub then
      sub = { giver = g, entries = {} }
      group.byGiver[who] = sub
      group.givers[#group.givers + 1] = sub
    end
    sub.entries[#sub.entries + 1] = e
  end
  for _, group in ipairs(groups) do group.byGiver = nil end
  -- zones by name, then inside the instance, then started from items or unknown
  local function rank(g) return g.inside and 2 or g.area and 1 or 3 end
  table.sort(groups, function(a, b)
    if rank(a) ~= rank(b) then return rank(a) < rank(b) end
    return (a.name or "") < (b.name or "")
  end)
  out.pickEntries, out.pick = out.pick, groups
  out.counts = {
    pick = #out.pickEntries, part = #out.part, log = #out.log, later = #out.later, done = #out.done, nfy = #out.nfy,
    total = #out.pickEntries + #out.part + #out.log + #out.later + #out.done, places = #groups,
  }
  readyMemo[key] = out
  return out
end

-------------------------------------------------------------------------------------------
-- Keeping up with the player
-------------------------------------------------------------------------------------------

local pending
local function changed(all)
  QB.Invalidate(all)
  if pending then return end
  pending = true
  local function announce()
    pending = nil
    Core:Send("ORACLE_QUESTBOOK_CHANGED", QB.revision)
  end
  if Core.NextFrame then Core:NextFrame(announce, "oracle.questbook") else announce() end
end

for _, msg in ipairs({ "NORGANNON_QUEST_ACCEPTED", "NORGANNON_QUEST_TURNED_IN", "NORGANNON_QUEST_REMOVED",
  "NORGANNON_LEVEL_CHANGED", "NORGANNON_SKILLS_CHANGED", "NORGANNON_REPUTATION_CHANGED" }) do
  Core:Listen(msg, "oracle.questbook", function() changed(false) end)
end
-- the quest log: only quests joining or leaving it change a state (every kill is a progress change)
Core:Listen("NORGANNON_QUESTLOG_UPDATED", "oracle.questbook", function(_, changes)
  if type(changes) ~= "table" or #(changes.accepted or {}) > 0 or #(changes.removed or {}) > 0 then changed(false) end
end)
-- who the player is (side, race, class) shapes the chains too
Core:Listen("NORGANNON_PLAYER_READY", "oracle.questbook", function() changed(true) end)
