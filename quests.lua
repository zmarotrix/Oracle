-- The Quests tab (mockup renderQuests): one card per quest that sends you to the instance, by
-- level: the level and name in your difficulty colour, "From <giver> · zone (x, y) · requires
-- level N" (or where to pick it up), "After: <prerequisites>", the rewards in two columns, then
-- "Track in Clairvoyance" (shows the giver on your map), and the XP.
--
-- Quests that follow from each other are one questline: a heading that names where it starts and
-- ends (and the earlier quests it hangs on, when those don't belong to this instance), then its
-- cards in order, numbered on a rail. Faction: a quest only one side can take has a stripe and a
-- pill in that side's colour, and the bar on top shows your side, the other or all
-- (OracleDB.questSide); a side's quests are dimmed when you can't take them.

local Core = NorgannonCore
local DB = NorgannonDB
local O = Oracle
if O.disabled then return end
local UI = Core.UI
local C = UI.C

local Quests = {}
O.Quests = Quests

-- race masks: the classic races, then draenei, worgen, pandaren / goblins, blood elves, pandaren
local ALLIANCE = 1 + 4 + 8 + 64 + 1024 + 2097152 + 16777216
local HORDE = 2 + 16 + 32 + 128 + 256 + 512 + 33554432
local SIDE_COLOR = { Alliance = UI.Hex("5b9bff"), Horde = UI.Hex("ff5b4f") }
local LINE_COLOR = UI.Hex("b48cff")
local CARD_PAD = 12
local RAIL = 26                -- how far a questline's cards sit in, for the rail

-- bitwise AND of two masks, in plain Lua (no client library needed)
local function band(a, b)
  a = a % 4294967296
  local r, p = 0, 1
  while a > 0 and b > 0 do
    if a % 2 == 1 and b % 2 == 1 then r = r + p end
    a, b, p = math.floor(a / 2), math.floor(b / 2), p * 2
  end
  return r
end

---"Alliance" or "Horde" when the quest's race mask allows only one side; false when it names
---both; nil when it says nothing about the sides.
function Quests.Side(q)
  local races = q and q.races
  if not races or races == 0 then return nil end
  local a, h = band(races, ALLIANCE) ~= 0, band(races, HORDE) ~= 0
  if a and h then return false end
  return a and "Alliance" or h and "Horde" or nil
end

-- the side that all these creatures or objects serve: a side, false when they're mixed or serve
-- both, nil when none of them says
local function sideOfGivers(givers)
  local side
  for _, g in ipairs(givers) do
    local record = DB:Get(g[1], g[2])
    local r = record and record.reaction
    if r == "AH" then return false end
    local this = r == "A" and "Alliance" or r == "H" and "Horde" or nil
    if this and side and this ~= side then return false end
    side = this or side
  end
  return side
end

local function givers(who)
  local out = {}
  for _, id in ipairs(who and who.npcs or {}) do out[#out + 1] = { "npcs", id } end
  for _, id in ipairs(who and who.objects or {}) do out[#out + 1] = { "objects", id } end
  return out
end

local function prerequisitesOf(q)
  local out = {}
  local pre = q and q.prerequisites or {}
  for _, id in ipairs(pre.all or {}) do out[#out + 1] = id end
  for _, id in ipairs(pre.any or {}) do out[#out + 1] = id end
  return out
end

local sideMemo = {}

---The side a quest belongs to: its race mask; without one, who gives it, who takes it back, then
---the quests before it (when they agree). nil: both sides can take it.
function Quests.SideOf(id)
  local known = sideMemo[id]
  if known ~= nil then return known or nil end
  sideMemo[id] = false                  -- chains can loop in the data
  local q = DB:Get("quests", id)
  if not q then return nil end
  local side = Quests.Side(q)
  if side == nil then side = sideOfGivers(givers(q.starters)) end
  if side == nil then side = sideOfGivers(givers(q.finishers)) end
  if side == nil then
    for _, p in ipairs(prerequisitesOf(q)) do
      local this = Quests.SideOf(p)
      if not this or (side and this ~= side) then side = nil break end
      side = this
    end
  end
  sideMemo[id] = side or false
  return side or nil
end

local function mySide()
  local f = Core.Player.faction or UnitFactionGroup("player")
  return (f == "Alliance" or f == "Horde") and f or nil
end

-- where a creature or object stands: "Westfall (56.3, 47.6)"
local function whereIs(kind, id)
  local record = DB:Get(kind, id)
  for area, points in pairs(record and record.spawns or {}) do
    local p = points[1]
    if p and p[1] and p[1] >= 0 then
      return string.format("%s (%.1f, %.1f)", O.Model.AreaName(area) or "?", p[1], p[2]), area, p
    end
  end
end

---A quest's card text: { id, name, level, color, from, after, rewards, choice, xp, side, starter }.
function Quests.Card(id)
  local q = DB:Get("quests", id)
  if not q then return nil end
  local level = q.level and q.level > 0 and q.level or nil
  local card = {
    id = id, name = Core.DB:Name("quests", id) or q.name or ("Quest " .. id), level = level,
    color = level and UI.Difficulty(level, Core.Player.level or UnitLevel("player") or 1) or C.text,
    side = Quests.SideOf(id), rewards = q.rewards and q.rewards.items or {}, choice = q.rewards and q.rewards.choice,
    xp = q.rewards and q.rewards.xp,
  }
  local s = q.starters or {}
  local parts = {}
  if s.npcs and s.npcs[1] then
    card.starter = { kind = "npc", id = s.npcs[1] }
    parts[#parts + 1] = "From |cffffffff" .. (Core.DB:Name("npcs", s.npcs[1]) or "?") .. "|r"
    local where = whereIs("npcs", s.npcs[1])
    if where then parts[#parts + 1] = where end
  elseif s.objects and s.objects[1] then
    card.starter = { kind = "object", id = s.objects[1] }
    parts[#parts + 1] = "From |cffffffff" .. (Core.DB:Name("objects", s.objects[1]) or "?") .. "|r"
    local where = whereIs("objects", s.objects[1])
    if where then parts[#parts + 1] = where end
  elseif s.items and s.items[1] then
    card.starter = { kind = "item", id = s.items[1] }
    parts[#parts + 1] = "Starts from |cffffffff" .. (Core.DB:Name("items", s.items[1]) or "an item") .. "|r"
  elseif q.startNote then
    parts[#parts + 1] = "From " .. q.startNote
  else
    parts[#parts + 1] = "Starts from an item or object"
  end
  if q.minLevel and q.minLevel > 1 then parts[#parts + 1] = "requires level " .. q.minLevel end
  card.from = table.concat(parts, " · ")
  card.after = Quests.AfterText(q)
  card.status = Quests.Status(id)
  local notes = {}
  local crumbs = {}
  for _, b in ipairs(q.breadcrumbs or {}) do
    if Quests.ForMe(b) then crumbs[#crumbs + 1] = Core.DB:Name("quests", b) or ("Quest " .. b) end
  end
  if #crumbs > 0 then notes[#notes + 1] = "Optional lead-in: " .. table.concat(crumbs, " or ") end
  if q.shareable == false then notes[#notes + 1] = "Can't be shared: each of you picks it up" end
  card.notes = notes
  return card
end

---"After: A, B or C" for a quest's prerequisites, leaving out the ones in skip (a set of ids).
function Quests.AfterText(q, skip)
  local pre = q.prerequisites or {}
  local function name(p) return Core.DB:Name("quests", p) or ("Quest " .. p) end
  local names, any = {}, {}
  for _, p in ipairs(pre.all or {}) do if not (skip and skip[p]) then names[#names + 1] = name(p) end end
  for _, p in ipairs(pre.any or {}) do if not (skip and skip[p]) then any[#any + 1] = name(p) end end
  if #any > 0 then names[#names + 1] = table.concat(any, " or ") end
  return #names > 0 and ("After: " .. table.concat(names, ", ")) or nil
end

---The instance's quests as cards, by level then name.
function Quests.Cards(key)
  local inst = Core.DB:Instance(key)
  local out, here = {}, {}
  for _, id in ipairs(inst and inst.quests or {}) do here[id] = true end
  for _, id in ipairs(inst and inst.quests or {}) do
    local card = Quests.Card(id)
    if card and not Core.DB:IsQuestHidden(id) then
      -- the follow-up you take after the run, when it isn't one of this instance's quests
      local nextId = DB:Get("quests", id).nextQuestInChain
      if nextId and not here[nextId] and DB:Get("quests", nextId) and not Core.DB:IsQuestHidden(nextId) then
        table.insert(card.notes, "Leads on to: " .. (Core.DB:Name("quests", nextId) or ("Quest " .. nextId)))
      end
      out[#out + 1] = card
    end
  end
  table.sort(out, function(a, b)
    if (a.level or 0) ~= (b.level or 0) then return (a.level or 0) < (b.level or 0) end
    return a.name < b.name
  end)
  return out
end

---The cards a side view keeps (mode "mine", "other" or "all"), and how many it leaves out.
function Quests.Filter(cards, mode)
  local me = mySide()
  if mode == "all" or not me then return cards, 0 end
  local want = mode == "other" and (me == "Alliance" and "Horde" or "Alliance") or me
  local out = {}
  for _, card in ipairs(cards) do
    if not card.side or card.side == want then out[#out + 1] = card end
  end
  return out, #cards - #out
end

local peek                      -- an instance opened on a quest the side view would hide: show all

local function sideMode(key)
  if peek == key then return "all" end
  return O.db.questSide or "mine"
end

---How many quests the Quests tab shows for an instance (its count on the tab).
function Quests.Visible(key)
  return #(Quests.Filter(Quests.Cards(key), sideMode(key)))
end

---Groups cards into what the tab shows, by level: { card } for a quest on its own, and for a
---questline { line = true, cards, steps, lead, leadFirst }. Its cards are in order, each with its
---card.step; lead counts the earlier quests the line hangs on that aren't among the cards, back to
---leadFirst. Links: prerequisites, nextQuestInChain and breadcrumbs.
function Quests.Lines(cards)
  local byId, before, root = {}, {}, {}
  for _, card in ipairs(cards) do byId[card.id] = card before[card.id] = {} root[card.id] = card.id end
  local function find(id)
    while root[id] ~= id do id = root[id] end
    return id
  end
  local function link(first, next)
    if first == next or not (byId[first] and byId[next]) then return end
    before[next][first] = true
    root[find(next)] = find(first)
  end
  local outside = {}
  for _, card in ipairs(cards) do
    local q = DB:Get("quests", card.id)
    local pre = prerequisitesOf(q)
    for _, p in ipairs(q.leadIn or {}) do pre[#pre + 1] = p end     -- DungeonJournal's lead-in
    for _, p in ipairs(pre) do
      link(p, card.id)
      if not byId[p] then outside[card.id] = outside[card.id] or {} table.insert(outside[card.id], p) end
    end
    if q.nextQuestInChain then link(card.id, q.nextQuestInChain) end
    if q.breadcrumbFor then link(card.id, q.breadcrumbFor) end
  end

  local stepMemo = {}
  local function stepOf(id)
    if stepMemo[id] then return stepMemo[id] end
    stepMemo[id] = 1                    -- chains can loop in the data
    local step = 1
    for p in pairs(before[id]) do step = math.max(step, stepOf(p) + 1) end
    stepMemo[id] = step
    return step
  end

  -- the earlier quests a line hangs on, walking back from those outside the instance's list
  local function leadIn(members)
    local seen, count, first, firstDepth = {}, 0, nil, -1
    local function walk(id, depth)
      if seen[id] or byId[id] or count >= 40 then return end
      seen[id] = true
      local q = DB:Get("quests", id)
      if not q or Core.DB:IsQuestHidden(id) then return end
      count = count + 1
      if depth > firstDepth then first, firstDepth = id, depth end
      for _, p in ipairs(prerequisitesOf(q)) do walk(p, depth + 1) end
      for _, p in ipairs(q.leadIn or {}) do walk(p, depth + 1) end
    end
    for _, card in ipairs(members) do
      for _, p in ipairs(outside[card.id] or {}) do walk(p, 0) end
    end
    return count, first
  end

  local groups, order = {}, {}
  for _, card in ipairs(cards) do
    local r = find(card.id)
    if not groups[r] then groups[r] = {} order[#order + 1] = groups[r] end
    table.insert(groups[r], card)
  end
  local entries = {}
  for _, members in ipairs(order) do
    if #members == 1 then
      entries[#entries + 1] = { card = members[1] }
    else
      local steps, inLine = 0, {}
      for _, card in ipairs(members) do
        card.step = stepOf(card.id)
        steps = math.max(steps, card.step)
        inLine[card.id] = true
      end
      table.sort(members, function(a, b)
        if a.step ~= b.step then return a.step < b.step end
        if (a.level or 0) ~= (b.level or 0) then return (a.level or 0) < (b.level or 0) end
        return a.name < b.name
      end)
      for i, card in ipairs(members) do
        card.steps, card.lastInLine = steps, i == #members
        card.after = Quests.AfterText(DB:Get("quests", card.id), inLine)   -- the rail says the rest
      end
      local lead, leadFirst = leadIn(members)
      entries[#entries + 1] = { line = true, cards = members, steps = steps, lead = lead, leadFirst = leadFirst }
    end
  end
  local function head(e) return e.card or e.cards[1] end
  table.sort(entries, function(a, b)
    local x, y = head(a), head(b)
    if (x.level or 0) ~= (y.level or 0) then return (x.level or 0) < (y.level or 0) end
    return x.name < y.name
  end)
  return entries
end

-------------------------------------------------------------------------------------------
-- Where you stand with a quest: done, in your log, ready, too low, or what comes first
-------------------------------------------------------------------------------------------

local function playerMasks()
  local enums = DB.enums or {}
  local _, _, raceId = UnitRace("player")
  return enums.raceMaskById and enums.raceMaskById[raceId], enums.classKeys and enums.classKeys[Core.Player.class or ""]
end

---Whether you can ever take a quest, as far as the data says: your side, race and class.
function Quests.ForMe(id)
  local q = DB:Get("quests", id)
  if not q or Core.DB:IsQuestHidden(id) then return false end
  local race, class = playerMasks()
  if race and q.races and q.races ~= 0 and not DB.HasFlag(q.races, race) then return false end
  if class and q.classes and q.classes ~= 0 and not DB.HasFlag(q.classes, class) then return false end
  local side, me = Quests.SideOf(id), mySide()
  return not (side and me and side ~= me)
end
local forMe = Quests.ForMe

-- the prerequisites to follow back: all of "all", and of "any" the one you did, else the first you can take
local function choiceOf(q)
  local pre = q and q.prerequisites
  if not pre then return {} end
  local out = {}
  for _, p in ipairs(pre.all or {}) do out[#out + 1] = p end
  if pre.any and #pre.any > 0 then
    local pick
    for _, p in ipairs(pre.any) do if Core.Player:IsCompleted(p) then pick = p break end end
    if not pick then for _, p in ipairs(pre.any) do if forMe(p) then pick = p break end end end
    out[#out + 1] = pick or pre.any[1]
  end
  return out
end

---The quests you do before this one, in order: DungeonJournal's lead-in where the data has one,
---and the prerequisites walked back. Only steps you can take; never the quest itself.
function Quests.Path(id)
  local out, seen = {}, { [id] = true }
  local function walk(p, depth)
    if seen[p] or depth > 30 or #out >= 40 then return end
    seen[p] = true
    if not forMe(p) then return end
    local q = DB:Get("quests", p)
    for _, pre in ipairs(q.leadIn or {}) do walk(pre, depth + 1) end
    for _, pre in ipairs(choiceOf(q)) do walk(pre, depth + 1) end
    out[#out + 1] = p
  end
  local q = DB:Get("quests", id)
  for _, p in ipairs(q and q.leadIn or {}) do walk(p, 1) end
  for _, p in ipairs(choiceOf(q)) do walk(p, 1) end
  return out
end

---Where you stand: { code = "done" | "inlog" | "ready" | "level" | "chain" | "notforyou",
---level (for "level"), next, left, total, nextInLog (for "chain": the first step not done,
---how many are left of how many) }.
function Quests.Status(id)
  local P = Core.Player
  if P:IsCompleted(id) then return { code = "done" } end
  if P:HasQuest(id) then return { code = "inlog" } end
  if not forMe(id) then return { code = "notforyou" } end
  local path = Quests.Path(id)
  local first, left = nil, 0
  for _, p in ipairs(path) do
    if not P:IsCompleted(p) then
      left = left + 1
      first = first or p
    end
  end
  if first then
    return { code = "chain", next = first, left = left, total = #path, nextInLog = P:HasQuest(first) }
  end
  local q = DB:Get("quests", id)
  local level = P.level or UnitLevel("player") or 1
  if q and q.minLevel and q.minLevel > level then return { code = "level", level = q.minLevel } end
  return { code = "ready" }
end

-- a quest's giver: { kind = "npc" | "object" | "item", id } or nil
local function starterOf(id)
  local s = (DB:Get("quests", id) or {}).starters or {}
  if s.npcs and s.npcs[1] then return { kind = "npc", id = s.npcs[1] } end
  if s.objects and s.objects[1] then return { kind = "object", id = s.objects[1] } end
  if s.items and s.items[1] then return { kind = "item", id = s.items[1] } end
end

local function questName(id) return Core.DB:Name("quests", id) or ("Quest " .. id) end

local function starterText(id)
  local st = starterOf(id)
  if not st then return nil end
  local plural = st.kind .. "s"
  local name = Core.DB:Name(plural, st.id) or "?"
  if st.kind == "item" then return "starts from " .. name end
  local where = whereIs(plural, st.id)
  return "from " .. name .. (where and (" · " .. where) or "")
end

---A status as one line of card text, coloured, or nil.
function Quests.StatusText(st)
  local code = st and st.code
  if code == "done" then return UI.Code(C.good) .. "Done|r" end
  if code == "inlog" then return UI.Code(C.info) .. "In your quest log|r" end
  if code == "ready" then return UI.Code(C.good) .. "Ready to pick up|r" end
  if code == "level" then return UI.Code(C.warn) .. "From level " .. st.level .. "|r" end
  if code == "chain" then
    local head = st.left == 1 and "Needs 1 earlier quest" or ("Needs " .. st.left .. " earlier quests")
    local step = questName(st.next)
    if st.nextInLog then return UI.Code(C.warn) .. head .. "|r · in your log: " .. step end
    local from = starterText(st.next)
    return UI.Code(C.warn) .. head .. "|r · first: |cffffffff" .. step .. "|r" .. (from and (", " .. from) or "")
  end
end

---Shows a quest's giver on the map through Clairvoyance; when earlier quests come first, the
---giver of the first one you haven't done. Returns what happened ("tracked", "trackedfirst",
---"inlog", "nostarter", "noclairvoyance") and the quest whose giver it is.
function Quests.Track(card)
  if Core.Player:HasQuest(card.id) then return "inlog" end
  local target, starter, result = card.id, card.starter, "tracked"
  local st = Quests.Status(card.id)
  if st.code == "chain" and not st.nextInLog then
    target, starter, result = st.next, starterOf(st.next), "trackedfirst"
  end
  if not starter then return "nostarter" end
  for _, action in ipairs(Core:ActionsFor(starter.kind, starter.id)) do
    if action.id == "clairvoyance.track" then
      action.run(starter.kind, starter.id)
      return result, target
    end
  end
  return "noclairvoyance"
end

-------------------------------------------------------------------------------------------
-- Before you go: what to pick up for an instance, grouped by where
-------------------------------------------------------------------------------------------

-- where you pick a quest up: the zone (or "inside" the instance), for grouping
local function placeOf(id, inst)
  local st = starterOf(id)
  if not st then
    local q = DB:Get("quests", id)
    return q and q.startNote and "Elsewhere" or "Unknown", 9
  end
  if st.kind == "item" then
    local item = DB:Get("items", st.id)
    for npc in pairs(item and item.drops and item.drops.npcs or {}) do
      local record = DB:Get("npcs", npc)
      if record and record.spawns and inst and inst.area and record.spawns[inst.area] then return "inside", 8 end
    end
    return "From an item", 7
  end
  local _, area = whereIs(st.kind .. "s", st.id)
  if not area then return "Unknown", 9 end
  if inst and area == inst.area then return "inside", 8 end
  return O.Model.AreaName(area) or "?", 1
end

---An instance's pickups: { groups = { {place, rows = { {quest, target, status, alsoFor = {ids}} }} },
---counts = { pickup, inlog, done, chain, level } }. A row's target is the quest you pick up
---now: the quest itself, or the first step before it. Quests sharing that first step are one row.
---cards: the cards the side view shows.
function Quests.Plan(key, cards)
  local inst = Core.DB:Instance(key)
  local counts = { pickup = 0, inlog = 0, done = 0, chain = 0, level = 0 }
  local byTarget, groups, byPlace = {}, {}, {}
  for _, card in ipairs(cards) do
    local st = Quests.Status(card.id)
    local code = st.code
    if code == "done" then counts.done = counts.done + 1
    elseif code == "inlog" then counts.inlog = counts.inlog + 1
    elseif code ~= "notforyou" and not (code == "chain" and st.nextInLog) then
      if code == "chain" then counts.chain = counts.chain + 1
      elseif code == "level" then counts.level = counts.level + 1
      else counts.pickup = counts.pickup + 1 end
      local target = code == "chain" and st.next or card.id
      local row = byTarget[target]
      if row then
        table.insert(row.alsoFor, card.id)
      else
        row = { quest = card.id, target = target, status = st, alsoFor = {} }
        byTarget[target] = row
        local place, rank = placeOf(target, inst)
        local group = byPlace[place]
        if not group then
          group = { place = place, rank = rank, rows = {} }
          byPlace[place] = group
          groups[#groups + 1] = group
        end
        table.insert(group.rows, row)
      end
    end
  end
  table.sort(groups, function(a, b)
    if a.rank ~= b.rank then return a.rank < b.rank end
    if #a.rows ~= #b.rows then return #a.rows > #b.rows end
    return a.place < b.place
  end)
  return { groups = groups, counts = counts }
end

---Puts every pickup for an instance on the map through Clairvoyance (again: takes them off).
---Returns "on", "off" or "noclairvoyance".
function Quests.TrackAll(key)
  local inst = Core.DB:Instance(key)
  local e = O.Model:Get(key)
  local ids = {}
  for _, id in ipairs(inst and inst.quests or {}) do
    if forMe(id) then ids[#ids + 1] = id end
  end
  local spec = { key = key, name = ((e and e.name) or key) .. " quests", ids = ids }
  for _, action in ipairs(Core:ActionsFor("quests", spec)) do
    if action.id == "clairvoyance.trackquests" then
      return action.run("quests", spec) and "on" or "off"
    end
  end
  return "noclairvoyance"
end

---Whether Clairvoyance shows an instance's pickups now.
function Quests.TrackingAll(key)
  local CV = rawget(_G, "Clairvoyance")
  return CV and CV.char and CV.IsTracked and CV:IsTracked("quests:" .. key) or false
end

-------------------------------------------------------------------------------------------
-- The pane
-------------------------------------------------------------------------------------------

local pane, area, bar, cards, headers = nil, nil, nil, {}, {}

local function markButton(parent, text, style, markKey, accentKey, onClick)
  local b = UI.Button(parent, text, style, onClick)
  if accentKey then b:ApplyAccent(UI.Accent(accentKey)) end
  b.mark = UI.Mark(b, markKey, 15)
  b.mark:SetPoint("LEFT", 8, 0)
  b.label:SetFontObject(UI.Font("title", 12))
  b.label:ClearAllPoints()
  b.label:SetPoint("LEFT", b.mark, "RIGHT", 5, 0)
  b:SetHeight(22)
  b:SetWidth(math.floor(b.label:GetStringWidth() + 8 + 15 + 5 + 10))
  return b
end

local function newCard()
  local f = CreateFrame("Frame", nil, area.content)
  f.box = UI.Box(f, "BACKGROUND", 0)
  f.box:Set(C.lineStrong, { .114, .09, .067 }, { .07, .055, .04 })
  f.stripe = f:CreateTexture(nil, "ARTWORK")       -- a one-sided quest's edge, in the side's colour
  f.stripe:SetPoint("TOPLEFT", 1, -1)
  f.stripe:SetPoint("BOTTOMLEFT", 1, 1)
  f.stripe:SetWidth(3)
  f.level = UI.Text(f, "body", 14)
  f.level:SetPoint("TOPLEFT", CARD_PAD, -10)
  f.name = UI.Text(f, "title", 15)
  f.name:SetPoint("BOTTOMLEFT", f.level, "BOTTOMRIGHT", 8, 0)
  f.name:SetWordWrap(false)
  f.sidePill = CreateFrame("Frame", nil, f)
  f.sidePill:SetHeight(16)
  f.sidePill:SetPoint("TOPRIGHT", -8, -9)
  f.sidePill.fill = UI.Pill(f.sidePill, 16, "BACKGROUND", 0)
  f.sidePill.label = UI.Text(f.sidePill, "title", 11, C.text, "OVERLAY")
  f.sidePill.label:SetPoint("CENTER", 0, 0)
  -- the questline's rail, left of the card: a line through a numbered disc
  f.rail = f:CreateTexture(nil, "BACKGROUND")
  f.rail:SetWidth(2)
  f.disc = f:CreateTexture(nil, "ARTWORK")
  f.disc:SetTexture(UI.TEX.circle)
  f.disc:SetSize(20, 20)
  f.disc:SetPoint("CENTER", f, "TOPLEFT", -RAIL / 2, -18)
  f.discNum = UI.Text(f, "title", 12, { 1, 1, 1 }, "OVERLAY")
  f.discNum:SetPoint("CENTER", f.disc, "CENTER", 0, 0)
  f.from = UI.Text(f, "body", 13, C.muted)
  f.from:SetWordWrap(true)
  f.from:SetJustifyH("LEFT")
  f.rewards = {}
  f.choose = UI.Text(f, "body", 12, C.faint)
  f.choose:SetText("Choose one:")
  f.track = markButton(f, "Track in Clairvoyance", "accent", "clairvoyance", "clairvoyance", function(self)
    local result, target = Quests.Track(self:GetParent().card)
    if result == "noclairvoyance" then O:Print("Clairvoyance shows where quests start; it isn't loaded.")
    elseif result == "nostarter" then O:Print("NorgannonDB doesn't know who starts this quest yet.")
    elseif result == "trackedfirst" then
      O:Print("On your map: where " .. questName(target) .. " starts. It comes before this quest.")
    end
  end)
  f.xp = UI.Text(f, "body", 12, C.faint)
  f.xp:SetJustifyH("RIGHT")
  return f
end

local function rewardRow(f, i)
  local r = f.rewards[i]
  if r then return r end
  r = CreateFrame("Button", nil, f)
  r:SetHeight(36)
  r.rightInset = 2
  O.Items.Build(r)
  O.Items.Hook(r)
  f.rewards[i] = r
  return r
end

-- the faction marks and the questline's rail on a card
local function markCard(f, card, inner)
  local color = card.side and SIDE_COLOR[card.side]
  f.stripe:SetShown(color ~= nil)
  f.sidePill:SetShown(color ~= nil)
  local pillWidth = 0
  if color then
    f.stripe:SetColorTexture(color[1], color[2], color[3], 1)
    f.sidePill.label:SetText(card.side)
    f.sidePill.label:SetTextColor(color[1], color[2], color[3])
    f.sidePill.fill:SetColor(color, .18)
    pillWidth = math.floor((f.sidePill.label:GetStringWidth() or 40) + 14)
    f.sidePill:SetWidth(pillWidth)
  end
  f.name:SetWidth(math.max(40, inner - 30 - pillWidth))
  local me = mySide()
  f:SetAlpha((card.side and me and card.side ~= me) and .55 or 1)  -- you can't take it

  local step = card.step
  f.rail:SetShown(step ~= nil and not card.lastInLine)
  f.disc:SetShown(step ~= nil)
  f.discNum:SetShown(step ~= nil)
  if step then
    local rc = color or LINE_COLOR
    f.disc:SetVertexColor(rc[1] * .55, rc[2] * .55, rc[3] * .55, 1)
    f.discNum:SetText(tostring(step))
    f.rail:SetColorTexture(rc[1], rc[2], rc[3], .45)
    f.rail:ClearAllPoints()
    f.rail:SetPoint("TOP", f, "TOPLEFT", -RAIL / 2, -18)
    f.rail:SetPoint("BOTTOM", f, "BOTTOMLEFT", -RAIL / 2, -26)   -- on to the next card's disc
  end
end

local function fillCard(f, card, width)
  f.card = card
  f:SetWidth(width)
  markCard(f, card, width - 2 * CARD_PAD)
  local c = card.color
  f.level:SetText(card.level and tostring(card.level) or "?")
  f.level:SetTextColor(c[1], c[2], c[3])
  f.name:SetText(card.name)
  f.name:SetTextColor(c[1], c[2], c[3])
  local inner = width - 2 * CARD_PAD
  f.from:SetWidth(inner)
  local lines = {}
  local status = Quests.StatusText(card.status)
  if status then lines[#lines + 1] = status end
  lines[#lines + 1] = card.from
  if card.after then lines[#lines + 1] = card.after end
  for _, note in ipairs(card.notes or {}) do lines[#lines + 1] = note end
  f.from:SetText(table.concat(lines, "\n"))
  f.from:ClearAllPoints()
  f.from:SetPoint("TOPLEFT", CARD_PAD, -32)
  local y = -32 - math.max(14, f.from:GetStringHeight() or 14) - 6
  f.choose:SetShown(card.choice and #card.rewards > 1)
  if f.choose:IsShown() then
    f.choose:ClearAllPoints()
    f.choose:SetPoint("TOPLEFT", CARD_PAD, y)
    y = y - 16
  end
  local half = math.floor(inner / 2)
  for i, id in ipairs(card.rewards) do
    local r = rewardRow(f, i)
    r:SetWidth(half - 2)
    r:ClearAllPoints()
    r:SetPoint("TOPLEFT", CARD_PAD - 6 + ((i - 1) % 2) * half, y - math.floor((i - 1) / 2) * 38)
    O.Items.Fill(r, id)
    r.itemId = id
    r:Show()
  end
  for i = #card.rewards + 1, #f.rewards do f.rewards[i]:Hide() f.rewards[i].itemId = nil end
  y = y - math.ceil(#card.rewards / 2) * 38 - 4
  f.track:ClearAllPoints()
  f.track:SetPoint("TOPLEFT", CARD_PAD, y)
  local inLog = Core.Player:HasQuest(card.id)
  f.track.label:SetText(inLog and "In your quest log" or "Track in Clairvoyance")
  f.track:SetAlpha((inLog or not card.starter or Core:AddonState("clairvoyance") ~= "loaded") and .5 or 1)
  f.xp:ClearAllPoints()
  f.xp:SetPoint("RIGHT", f, "TOPRIGHT", -CARD_PAD, y - 11)
  f.xp:SetText(card.xp and (BreakUpLargeNumbers and BreakUpLargeNumbers(card.xp) or tostring(card.xp)) .. " XP" or "")
  local height = -y + 22 + 10
  f:SetHeight(height)
  return height
end

local function header(i)
  local h = headers[i]
  if h then return h end
  h = CreateFrame("Frame", nil, area.content)
  h.title = UI.Text(h, "title", 14, LINE_COLOR)
  h.title:SetPoint("TOPLEFT", 4, 0)
  h.ends = UI.Text(h, "body", 12, C.muted)
  h.ends:SetPoint("TOPLEFT", h.title, "BOTTOMLEFT", 0, -1)
  h.ends:SetJustifyH("LEFT")
  h.ends:SetWordWrap(true)
  headers[i] = h
  return h
end

local function fillHeader(h, entry, width)
  h:SetWidth(width)
  h.title:SetText("Questline · " .. entry.steps .. " steps")
  local first, last = entry.cards[1], entry.cards[#entry.cards]
  local text = first.name .. " → " .. last.name
  if entry.lead and entry.lead > 0 then
    local name = Core.DB:Name("quests", entry.leadFirst) or ("Quest " .. entry.leadFirst)
    text = text .. "\n" .. (entry.lead == 1 and ("Begins earlier with " .. name)
      or ("Begins " .. entry.lead .. " quests earlier with " .. name))
  end
  h.ends:SetWidth(width - 8)
  h.ends:SetText(text)
  local height = 18 + math.max(14, h.ends:GetStringHeight() or 14) + 6
  h:SetHeight(height)
  return height
end

-- "Before you go": the pickups on top of the cards, by where you pick them up
local plan

local function buildPlan()
  plan = CreateFrame("Frame", nil, area.content)
  plan.box = UI.Box(plan, "BACKGROUND", 0)
  plan.box:Set(C.line, { .09, .07, .05 }, { .06, .045, .03 })
  plan.fold = CreateFrame("Button", nil, plan)
  plan.fold:SetPoint("TOPLEFT", 8, -6)
  plan.fold:SetHeight(18)
  plan.title = UI.Text(plan.fold, "title", 14, C.goldSoft)
  plan.title:SetPoint("LEFT", 0, 0)
  plan.title:SetText("Before you go")
  plan.chev = UI.Text(plan.fold, "body", 12, C.faint)
  plan.chev:SetPoint("LEFT", plan.title, "RIGHT", 6, 0)
  plan.fold:SetScript("OnClick", function()
    O.db.planFolded = not O.db.planFolded
    Quests:Refresh()
  end)
  plan.summary = UI.Text(plan, "body", 12, C.muted)
  plan.summary:SetPoint("TOPLEFT", 8, -26)
  plan.summary:SetJustifyH("LEFT")
  plan.summary:SetWordWrap(true)
  plan.map = markButton(plan, "Track these quests", "accent", "clairvoyance", "clairvoyance", function()
    local key = O.db.selected
    if not key then return end
    local result = Quests.TrackAll(key)
    if result == "noclairvoyance" then O:Print("Clairvoyance shows where quests start; it isn't loaded.")
    elseif result == "on" then O:Print("Tracked: this instance's quests have their own section in the tracker, and their givers are on your map.") end
    Quests:Refresh()
  end)
  plan.map:SetPoint("TOPRIGHT", -8, -4)
  plan.heads, plan.rows = {}, {}
end

local function planHead(i)
  local h = plan.heads[i]
  if h then return h end
  h = UI.Text(plan, "title", 12, C.faint)
  h:SetJustifyH("LEFT")
  plan.heads[i] = h
  return h
end

local function planRow(i)
  local r = plan.rows[i]
  if r then return r end
  r = CreateFrame("Button", nil, plan)
  r:SetHeight(18)
  r.hl = r:CreateTexture(nil, "BACKGROUND")
  r.hl:SetAllPoints()
  r.hl:SetColorTexture(1, 1, 1, .05)
  r.hl:Hide()
  r.mark = r:CreateTexture(nil, "ARTWORK")
  r.mark:SetSize(13, 13)
  r.mark:SetPoint("LEFT", 2, 0)
  r.detail = UI.Text(r, "body", 12, C.faint)
  r.detail:SetPoint("RIGHT", -2, 0)
  r.detail:SetJustifyH("RIGHT")
  r.detail:SetWordWrap(false)
  r.name = UI.Text(r, "body", 13)
  r.name:SetPoint("LEFT", r.mark, "RIGHT", 5, 0)
  r.name:SetPoint("RIGHT", r.detail, "LEFT", -6, 0)
  r.name:SetJustifyH("LEFT")
  r.name:SetWordWrap(false)
  r:SetScript("OnClick", function(self) if self.row then Quests:Focus(self.row.quest) end end)
  r:SetScript("OnEnter", function(self)
    self.hl:Show()
    local row = self.row
    if not row then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:AddLine(questName(row.target), 1, 1, 1)
    local from = starterText(row.target)
    if from then GameTooltip:AddLine((from:gsub("^%l", string.upper)), C.muted[1], C.muted[2], C.muted[3], true) end
    if row.target ~= row.quest then
      local names = { questName(row.quest) }
      for _, id in ipairs(row.alsoFor) do names[#names + 1] = questName(id) end
      GameTooltip:AddLine("Comes before: " .. table.concat(names, ", "), C.warn[1], C.warn[2], C.warn[3], true)
    end
    GameTooltip:AddLine("Click: show the quest", C.faint[1], C.faint[2], C.faint[3])
    GameTooltip:Show()
  end)
  r:SetScript("OnLeave", function(self) self.hl:Hide() GameTooltip:Hide() end)
  plan.rows[i] = r
  return r
end

local function fillRow(r, row)
  r.row = row
  local st = row.status
  local grey = st.code == "level"
  Core.Map.SetIcon(r.mark, grey and "exclaimGrey" or "exclaim")
  local name = questName(row.target)
  local c = grey and C.faint or C.text
  if row.target == row.quest then
    local card = Quests.Card(row.quest)
    if card and not grey then c = card.color end
  end
  r.name:SetText(name)
  r.name:SetTextColor(c[1], c[2], c[3])
  if row.target ~= row.quest then
    local more = #row.alsoFor > 0 and (" +" .. #row.alsoFor) or ""
    r.detail:SetText("first for " .. questName(row.quest) .. more)
  elseif grey then
    r.detail:SetText("level " .. st.level)
  else
    local s = starterOf(row.target)
    r.detail:SetText(s and s.kind ~= "item" and Core.DB:Name(s.kind .. "s", s.id) or "")
  end
end

-- lays the "Before you go" box out at the top of the list; returns its height (0: nothing for you)
local function fillPlan(key, list, width)
  if not plan then buildPlan() end
  local p = Quests.Plan(key, list)
  Quests.plan = p
  local n = p.counts
  local total = n.pickup + n.chain + n.level + n.inlog + n.done
  if total == 0 then plan:Hide() return 0 end
  plan:SetWidth(width)
  local parts = {}
  if n.pickup > 0 then parts[#parts + 1] = UI.Code(C.good) .. n.pickup .. " to pick up|r" end
  if n.chain > 0 then parts[#parts + 1] = UI.Code(C.warn) .. n.chain .. (n.chain == 1 and " needs" or " need") .. " earlier quests|r" end
  if n.level > 0 then parts[#parts + 1] = n.level .. " above your level" end
  if n.inlog > 0 then parts[#parts + 1] = UI.Code(C.info) .. n.inlog .. " in your log|r" end
  if n.done > 0 then parts[#parts + 1] = n.done .. " done" end
  if n.pickup + n.chain + n.level == 0 then table.insert(parts, 1, "Nothing left to pick up") end
  plan.summary:SetWidth(width - 16)
  plan.summary:SetText(table.concat(parts, " · "))
  local folded = O.db.planFolded
  plan.chev:SetText(folded and "show" or "hide")
  local on = Quests.TrackingAll(key)
  plan.map.label:SetText(on and "Tracked" or "Track these quests")
  plan.map:SetWidth(math.floor(plan.map.label:GetStringWidth() + 8 + 15 + 5 + 10))
  plan.map:SetAlpha(Core:AddonState("clairvoyance") == "loaded" and 1 or .5)
  plan.map:SetShown(#p.groups > 0 or on)

  local y = -26 - math.max(14, plan.summary:GetStringHeight() or 14) - 6
  local nh, nr = 0, 0
  if not folded then
    local e = O.Model:Get(key)
    for _, group in ipairs(p.groups) do
      nh = nh + 1
      local h = planHead(nh)
      h:SetText(group.place == "inside" and ("Inside " .. ((e and e.name) or "the instance")) or group.place)
      h:ClearAllPoints()
      h:SetPoint("TOPLEFT", 10, y - 2)
      h:Show()
      y = y - 18
      for _, row in ipairs(group.rows) do
        nr = nr + 1
        local r = planRow(nr)
        fillRow(r, row)
        r:ClearAllPoints()
        r:SetPoint("TOPLEFT", 8, y)
        r:SetPoint("TOPRIGHT", -8, y)
        r:Show()
        y = y - 18
      end
      y = y - 4
    end
  end
  for i = nh + 1, #plan.heads do plan.heads[i]:Hide() end
  for i = nr + 1, #plan.rows do plan.rows[i]:Hide() plan.rows[i].row = nil end
  local height = -y + 4
  plan:SetHeight(height)
  plan:ClearAllPoints()
  plan:SetPoint("TOPLEFT", area.content, "TOPLEFT", 0, -6)
  plan:Show()
  return height
end

local fill

local function build(frame)
  pane = frame
  local me = mySide() or "Alliance"
  local other = me == "Alliance" and "Horde" or "Alliance"
  bar = CreateFrame("Frame", nil, pane)
  bar:SetHeight(26)
  bar:SetPoint("TOPLEFT")
  bar:SetPoint("TOPRIGHT")
  bar.side = UI.Segmented(bar, {
    { key = "mine", label = me }, { key = "other", label = other }, { key = "all", label = "All" },
  }, function(key)
    O.db.questSide = key
    peek = nil
    fill(nil, O.Model:Get(O.db.selected))
  end, 20)
  bar.side:SetPoint("LEFT", 2, 0)
  if bar.side.ApplyAccent then bar.side:ApplyAccent(UI.Accent("oracle")) end
  bar.hidden = UI.Text(bar, "body", 12, C.faint)
  bar.hidden:SetPoint("RIGHT", -6, 0)
  bar.hidden:SetJustifyH("RIGHT")
  Quests.bar = bar
  area = UI.ScrollArea(pane)
  Quests.area = area
  Quests.empty = UI.Text(pane, "body", 13, C.faint)
  Quests.empty:SetPoint("TOPLEFT", 10, -34)
  Quests.empty:SetText("No quests send you here that NorgannonDB knows of.")
end

fill = function(_, e)
  local all = Quests.Cards(e.key)
  local mode = sideMode(e.key)
  local list, hidden = Quests.Filter(all, mode)

  -- the side bar, when the instance has quests for one side only
  local oneSided = false
  for _, card in ipairs(all) do if card.side then oneSided = true break end end
  bar:SetShown(oneSided)
  bar.side:Select(mode, true)
  bar.hidden:SetText(hidden > 0 and (hidden == 1 and "1 quest hidden" or (hidden .. " quests hidden")) or "")
  area:ClearAllPoints()
  area:SetPoint("TOPLEFT", 0, oneSided and -28 or 0)
  area:SetPoint("BOTTOMRIGHT", 0, 0)

  local width = (pane:GetWidth() or 392)
  if width < 50 then width = 392 end
  area.content:SetWidth(width)
  local y, nCards, nHeaders = -6, 0, 0
  local planHeight = fillPlan(e.key, list, width - 6)
  if planHeight > 0 then y = y - planHeight - 10 end
  local flat = {}
  local function place(card, x)
    nCards = nCards + 1
    local f = cards[nCards] or newCard()
    cards[nCards] = f
    local h = fillCard(f, card, width - 6 - x)
    f:ClearAllPoints()
    f:SetPoint("TOPLEFT", area.content, "TOPLEFT", x, y)
    f:Show()
    y = y - h - 8
    flat[#flat + 1] = card
  end
  local entries = Quests.Lines(list)
  for _, entry in ipairs(entries) do
    if entry.line then
      nHeaders = nHeaders + 1
      local h = header(nHeaders)
      local height = fillHeader(h, entry, width - 6)
      h:ClearAllPoints()
      h:SetPoint("TOPLEFT", area.content, "TOPLEFT", 0, y)
      h:Show()
      y = y - height
      for _, card in ipairs(entry.cards) do place(card, RAIL) end
      y = y - 6
    else
      place(entry.card, 0)
    end
  end
  for i = nCards + 1, #cards do cards[i]:Hide() cards[i].card = nil end
  for i = nHeaders + 1, #headers do headers[i]:Hide() end
  area.content:SetHeight(-y)
  area:SetVerticalScroll(Quests.keepScroll or 0)
  Quests.keepScroll = nil

  Quests.empty:SetShown(#list == 0)
  if #list == 0 then
    Quests.empty:SetText(#all > 0 and "No quests for this side here. Choose All to see the others."
      or "No quests send you here that NorgannonDB knows of.")
  end
  Quests.shown, Quests.entries = flat, entries
  local win = O.Window.frame
  if win and win.tabs then win.tabs:SetCount("quests", #list) end
end

---Fills the tab again where it stands (your quest log or level changed, the plan folded).
function Quests:Refresh()
  if not (pane and pane:IsShown() and O.db.selected) then return end
  self.keepScroll = area:GetVerticalScroll()
  fill(nil, O.Model:Get(O.db.selected))
end

---The card showing a quest (the harness and "Open in Oracle" use it).
function Quests:CardFor(id)
  for _, f in ipairs(cards) do
    if f:IsShown() and f.card and f.card.id == id then return f end
  end
end

---Scrolls the Quests tab to a quest and outlines its card for a moment.
function Quests:Focus(id)
  local f = self:CardFor(id)
  if not f and O.db.selected then           -- the side view hides it: show all for this instance
    peek = O.db.selected
    fill(nil, O.Model:Get(O.db.selected))
    f = self:CardFor(id)
  end
  if not f then return end
  local top = -(select(5, f:GetPoint(1)) or 0)
  area:SetVerticalScroll(math.max(0, top - 6))
  f.box:Set(UI.Accent("oracle"), { .114, .09, .067 }, { .07, .055, .04 })
  C_Timer.After(2, function() f.box:Set(C.lineStrong, { .114, .09, .067 }, { .07, .055, .04 }) end)
  self.focused = id
end

-- your quest log, completed quests and level change what each card and the plan say
local refreshing
local function refreshSoon()
  if refreshing then return end
  refreshing = true
  C_Timer.After(.3, function() refreshing = nil Quests:Refresh() end)
end
for _, msg in ipairs({ "NORGANNON_QUESTLOG_UPDATED", "NORGANNON_QUEST_TURNED_IN", "NORGANNON_LEVEL_CHANGED" }) do
  Core:Listen(msg, "oracle.quests", refreshSoon)
end
O:Listen("ITEMS_LOADED", "quests", function() if pane and pane:IsShown() and O.db.selected then fill(nil, O.Model:Get(O.db.selected)) end end)
O.Window:RegisterPane("quests", build, fill)
