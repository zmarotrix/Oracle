-- PvP & Factions: AtlasLoot's PvP and reputation pages. PvP lists what each honor rank lets you buy
-- (your side's ranks first, the other side's greyed under them); Factions lists each faction's rewards
-- by the standing they need, with your own standing. From NorgannonDB 1.8 (index.rewards, and the
-- items' pvpRank, repFaction, repStanding and side).

local Core = NorgannonCore
local O = Oracle
if O.disabled then return end
local UI = Core.UI
local C = UI.C
local DB = NorgannonDB

local R = { label = "PvP & Factions", order = 4 }
O.Rewards = R

local ROW = 42
local RANK_OFFSET = 4          -- UnitPVPRank / GetPVPRankInfo number ranks 4 higher (5 = Private)
local NOT_RECORDED = 0         -- index.rewards standing for the battleground factions' rewards

-- the classic rank titles (enUS), for the side you aren't on (GetPVPRankInfo names your own)
local TITLES = {
  A = { "Private", "Corporal", "Sergeant", "Master Sergeant", "Sergeant Major", "Knight", "Knight-Lieutenant",
    "Knight-Captain", "Knight-Champion", "Lieutenant Commander", "Commander", "Marshal", "Field Marshal", "Grand Marshal" },
  H = { "Scout", "Grunt", "Sergeant", "Senior Sergeant", "First Sergeant", "Stone Guard", "Blood Guard",
    "Legionnaire", "Centurion", "Champion", "Lieutenant General", "General", "Warlord", "High Warlord" },
}
local SIDE_NAME = { A = "Alliance", H = "Horde" }
local STANDINGS = { [3] = "Neutral", [4] = "Friendly", [5] = "Honored", [6] = "Revered", [7] = "Exalted" }

local state = { mode = "pvp", rank = nil, side = nil, faction = nil, forMe = false }

-- folded sections, kept across ranks and factions (fold Plate once, it stays folded): "pvp:Plate", "faction:5"
local function folds()
  O.db.rewardsFolded = O.db.rewardsFolded or {}
  return O.db.rewardsFolded
end
function R.Folded(key) return folds()[key] == true end
function R.SetFolded(key, folded)
  folds()[key] = folded or nil
  R:Fill()
end

-- a section's header row: the fold icon, its name, how many it holds
local function header(key, label, count)
  local folded = R.Folded(key)
  return { group = (folded and O.ICON.folded or O.ICON.open) .. " " .. label .. "  " .. UI.Code(C.faint) .. count .. "|r",
    fold = key, folded = folded }
end

local function index() return DB and DB.index and DB.index.rewards end

---Your side's letter ("A" / "H"), or nil.
local function mySide()
  local f = UnitFactionGroup and UnitFactionGroup("player")
  return f == "Alliance" and "A" or (f == "Horde" and "H") or nil
end
R.MySide = mySide

---A rank's title on a side (1-14).
function R.RankName(rank, side)
  if side == mySide() and GetPVPRankInfo then
    local ok, name = pcall(GetPVPRankInfo, rank + RANK_OFFSET)
    if ok and type(name) == "string" and name ~= "" then return name end
  end
  return (TITLES[side or "A"] or TITLES.A)[rank] or ("Rank " .. rank)
end

---The highest honor rank you've reached (1-14), or 0.
function R.MyRank()
  local best = 0
  if UnitPVPRank then best = UnitPVPRank("player") or 0 end
  if GetPVPLifetimeStats then
    local _, _, highest = GetPVPLifetimeStats()
    if type(highest) == "number" and highest > best then best = highest end
  end
  return math.max(0, best - RANK_OFFSET)
end

---A standing's name (3 Neutral ... 7 Exalted).
function R.StandingName(standing)
  local label = _G["FACTION_STANDING_LABEL" .. ((standing or 0) + 1)]
  return type(label) == "string" and label or STANDINGS[standing] or "Unknown"
end

-- where each standing begins, in the game's reputation values (Hated ... Exalted)
local THRESHOLDS = { [0] = -42000, -6000, -3000, 0, 3000, 9000, 21000, 42000, 43000 }

---Your standing for a reputation value: standing (0-7), progress in it, its size.
function R.StandingOf(value)
  local s = 0
  while s < 7 and value >= THRESHOLDS[s + 1] do s = s + 1 end
  return s, value - THRESHOLDS[s], THRESHOLDS[s + 1] - THRESHOLDS[s]
end

-- the faction's name in your client's language, if the game tells it
local function localName(id)
  if C_Reputation and C_Reputation.GetFactionDataByID then
    local ok, data = pcall(C_Reputation.GetFactionDataByID, id)
    if ok and type(data) == "table" and type(data.name) == "string" and data.name ~= "" then return data.name end
  end
  if GetFactionInfoByID then
    local ok, name = pcall(GetFactionInfoByID, id)
    if ok and type(name) == "string" and name ~= "" then return name end
  end
end

---A faction: { id, name, side, group, standing (yours, 0-7, or nil if you haven't met it), value, max }.
function R.Faction(id)
  local entry = (index() or {}).factions and index().factions[id]
  if not entry then return nil end
  local f = { id = id, name = localName(id) or entry.name or ("Faction " .. id), side = entry.side,
    parentName = entry.parentName, items = entry.items }
  local value = Core.Player and Core.Player.GetReputation and Core.Player:GetReputation(id)
  if type(value) == "number" then f.standing, f.value, f.max = R.StandingOf(value) end
  if id >= 2500 then f.group = "WoW Forever's own"
  elseif entry.parentName == "Alliance Forces" or entry.parentName == "Horde Forces" then f.group = "Battlegrounds"
  elseif entry.parentName == "Steamwheedle Cartel" then f.group = "Steamwheedle Cartel"
  elseif id == 469 or id == 67 or entry.parentName == "Alliance" or entry.parentName == "Horde" then f.group = "Your side"
  else f.group = "Azeroth" end
  return f
end

-- an item's sources, short: the first vendor, else a quest, a drop, "source not known yet"
local function sourceText(id)
  local src = Core.DB:ItemInfo(id) or {}
  for npc in pairs(src.vendors or {}) do return Core.DB:Name("npcs", npc) or "a vendor" end
  if src.rewardOf and src.rewardOf[1] then return "quest: " .. (Core.DB:Name("quests", src.rewardOf[1]) or "?") end
  if src.drops and src.drops.npcs and next(src.drops.npcs) then return "dropped by creatures" end
  return "source not known yet"
end
R.SourceText = sourceText

---What an item needs, as Inspector lines: { text, met } for its rank, standing and side.
function R.Needs(id)
  local rec = DB and DB:Get("items", id)
  if not rec then return {} end
  local out, side = {}, mySide()
  if rec.side and SIDE_NAME[rec.side] then
    out[#out + 1] = { SIDE_NAME[rec.side] .. " only", not side or side == rec.side }
  end
  if rec.pvpRank then
    local s = rec.side or side or "A"
    out[#out + 1] = { string.format("Needs rank %d, %s", rec.pvpRank, R.RankName(rec.pvpRank, s)), R.MyRank() >= rec.pvpRank,
      { mode = "pvp", rank = rec.pvpRank, side = s } }
  end
  if rec.repFaction then
    local f = R.Faction(rec.repFaction)
    local name = f and f.name or ("faction " .. rec.repFaction)
    if rec.repStanding then
      out[#out + 1] = { "Needs " .. R.StandingName(rec.repStanding) .. " with " .. name,
        f and f.standing and f.standing >= rec.repStanding or false, { mode = "factions", faction = rec.repFaction } }
    end
  end
  return out
end

-------------------------------------------------------------------------------------------
-- The navigator: ranks (yours, then the other side's greyed) or factions by group
-------------------------------------------------------------------------------------------

local function rankItems(rank, side)
  local out = {}
  for _, id in ipairs(((index() or {}).pvp or {})[rank] or {}) do
    local rec = DB:Get("items", id)
    if rec and (not rec.side or rec.side == side) then out[#out + 1] = id end
  end
  return out
end
R.RankItems = rankItems

local function countItems(standings)
  local n = 0
  for _, ids in pairs(standings or {}) do n = n + #ids end
  return n
end

---The PvP navigator's rows.
function R.PvPNav()
  local mine = mySide() or "A"
  local other = mine == "A" and "H" or "A"
  local reached = R.MyRank()
  local rows = {}
  for _, side in ipairs({ mine, other }) do
    rows[#rows + 1] = { group = SIDE_NAME[side] .. (side == mine and "" or " (the other side)") }
    for rank = 1, 14 do
      local n = #rankItems(rank, side)
      if n > 0 then
        rows[#rows + 1] = { mode = "pvp", rank = rank, side = side, greyed = side ~= mine,
          name = R.RankName(rank, side), navMeta = "Rank " .. rank .. " · " .. n .. (n == 1 and " reward" or " rewards"),
          navRight = side == mine and reached >= rank and O.ICON.check or "" }
      end
    end
  end
  return rows
end

local GROUPS = { "Battlegrounds", "Azeroth", "Steamwheedle Cartel", "WoW Forever's own", "Your side" }

---The Factions navigator's rows.
function R.FactionNav()
  local mine = mySide()
  local by, others = {}, {}
  for id in pairs((index() or {}).factions or {}) do
    local f = R.Faction(id)
    if f then
      local e = { mode = "factions", faction = id, name = f.name, greyed = f.side and mine and f.side ~= mine or nil }
      local n = countItems(f.items)
      e.navMeta = (f.standing and (R.StandingName(f.standing) .. " · ") or "") .. n .. (n == 1 and " reward" or " rewards")
      e.navRight = ""
      if e.greyed then others[#others + 1] = e
      else by[f.group] = by[f.group] or {} table.insert(by[f.group], e) end
    end
  end
  local rows = {}
  local function sorted(list)
    table.sort(list, function(a, b) return a.name < b.name end)
    return list
  end
  for _, g in ipairs(GROUPS) do
    if by[g] then
      rows[#rows + 1] = { group = g }
      for _, e in ipairs(sorted(by[g])) do rows[#rows + 1] = e end
    end
  end
  if #others > 0 then
    rows[#rows + 1] = { group = "The other side" }
    for _, e in ipairs(sorted(others)) do rows[#rows + 1] = e end
  end
  return rows
end

function R:nav() return state.mode == "factions" and R.FactionNav() or R.PvPNav() end
function R:navSelected(e)
  if e.mode == "pvp" then return state.mode == "pvp" and e.rank == state.rank and e.side == state.side end
  return state.mode == "factions" and e.faction == state.faction
end
function R:navClick(e) O:Go({ space = "rewards", mode = e.mode, rank = e.rank, side = e.side, faction = e.faction }) end
function R:navRow(row, e)
  local a = e.greyed and .45 or 1
  row.name:SetAlpha(a)
  row.meta:SetAlpha(a)
end

function R:navTop(top)
  if not self.seg then
    self.seg = UI.Segmented(top, { { key = "pvp", label = "PvP" }, { key = "factions", label = "Factions" } }, function(key)
      O:Go({ space = "rewards", mode = key })
    end, 24)
    self.seg:SetPoint("TOPLEFT")
    self.seg:SetPoint("TOPRIGHT")
  end
  top:SetHeight(24)
  self.seg:Select(state.mode, true)
  self.seg:Show()
end

-------------------------------------------------------------------------------------------
-- The page: a rank's or a faction's rewards
-------------------------------------------------------------------------------------------

-- PvP rewards grouped the way players shop for them: weapons, then armour by type, then the rest
local ARMOR = { [1] = "Cloth", [2] = "Leather", [3] = "Mail", [4] = "Plate", [6] = "Shields" }
local function kindOf(id)
  local rec = DB:Get("items", id) or {}
  if rec.class == 2 then return 1, "Weapons" end
  if rec.class == 4 and ARMOR[rec.subClass] then return 1 + rec.subClass, ARMOR[rec.subClass] end
  if rec.class == 4 then return 10, "Accessories" end
  if rec.class == 0 then return 11, "Consumables" end
  return 12, "Mounts and more"
end

local function passes(id)
  if not state.forMe then return true end
  local you = O.Items.ForYou(id)
  return not you or you.ok
end

local function byName(a, b) return (O.Items.Info(a.item).name or "") < (O.Items.Info(b.item).name or "") end

---A rank's rows: { group } per kind, then { item }.
function R.RankRows(rank, side)
  local groups, order = {}, {}
  for _, id in ipairs(rankItems(rank, side)) do
    if passes(id) then
      local at, label = kindOf(id)
      if not groups[label] then groups[label] = { at = at, items = {} } order[#order + 1] = label end
      table.insert(groups[label].items, { item = id })
    end
  end
  table.sort(order, function(a, b) return groups[a].at < groups[b].at end)
  local rows = {}
  for _, label in ipairs(order) do
    local head = header("pvp:" .. label, label, #groups[label].items)
    rows[#rows + 1] = head
    if not head.folded then
      table.sort(groups[label].items, byName)
      for _, r in ipairs(groups[label].items) do rows[#rows + 1] = r end
    end
  end
  return rows
end

---A faction's rows: { group } per standing (Neutral first; not recorded last), then { item, standing }.
function R.FactionRows(id)
  local f = R.Faction(id)
  if not f then return {} end
  local standings = {}
  for s in pairs(f.items or {}) do standings[#standings + 1] = s end
  table.sort(standings, function(a, b)
    if a == NOT_RECORDED then return false end
    if b == NOT_RECORDED then return true end
    return a < b
  end)
  local rows = {}
  for _, s in ipairs(standings) do
    local items = {}
    for _, item in ipairs(f.items[s]) do
      if passes(item) then items[#items + 1] = { item = item, standing = s, faction = id } end
    end
    if #items > 0 then
      local label
      if s == NOT_RECORDED then label = "Sold by their supply officers"
      else
        label = R.StandingName(s)
        if f.standing and f.standing >= s then label = label .. "  " .. O.ICON.check end
      end
      local head = header("faction:" .. s, label, #items)
      rows[#rows + 1] = head
      if not head.folded then
        table.sort(items, byName)
        for _, r in ipairs(items) do rows[#rows + 1] = r end
      end
    end
  end
  return rows
end

R.Pairs = O.Items.Pairs

-- an item's second line: what kind, where it's sold; "at 60" when you can't use it yet
local function metaFor(r, info)
  local you = O.Items.ForYou(r.item)
  local parts = {}
  if info.kind ~= "" then parts[#parts + 1] = info.kind end
  parts[#parts + 1] = sourceText(r.item)
  local line = table.concat(parts, " · ")
  if you and you.ok and you.later then line = line .. " · " .. UI.Code(C.warn) .. "at " .. you.later .. "|r" end
  return line
end

-- the tooltip's extra lines: why it isn't for you, then what a click does
local function hintFor(id)
  local you = O.Items.ForYou(id)
  local why = you and not you.ok and (you.why .. "\n") or ""
  return why .. (O.Wants:Has(id) and "Right-click: no longer wanted" or "Right-click: want it")
end

local function clickItem(r, button)
  if button == "RightButton" then return O.Wants:Toggle(r.item) end
  O.Inspector:Show("item", r.item)
end

local function fillCell(cell, r)
  local info = O.Items.Fill(cell, r.item)
  if O.Wants and O.Wants:Has(r.item) then cell.itemName:SetText(O.ICON.star .. " " .. info.name) end
  cell.itemMeta:SetText(metaFor(r, info))
  local you = O.Items.ForYou(r.item)
  cell:SetAlpha(you and not you.ok and .5 or 1)
end

function R:Build(page)
  self.page = page
  local f = CreateFrame("Frame", nil, page.content)
  f:SetAllPoints()
  local pane = UI.Pane(f)
  pane:SetAllPoints()
  f.list = UI.List(pane, {
    rowHeight = ROW,
    groupBand = true,
    onGroupClick = function(g) if g.fold then R.SetFolded(g.fold, not g.folded) end end,
    createRow = function(row, content) O.Items.GridRow(row, content, { onClick = clickItem, hint = hintFor }) end,
    updateRow = function(row, r) O.Items.FillPair(row, r, fillCell) end,
  })
  f.list:SetPoint("TOPLEFT", 1, -4)
  f.list:SetPoint("BOTTOMRIGHT", -1, 4)
  f.list:ApplyAccent(UI.Accent("oracle"))
  f.empty = UI.Text(pane, "body", 13, C.faint)
  f.empty:SetPoint("TOPLEFT", 14, -14)
  f.empty:SetPoint("TOPRIGHT", -14, -14)
  f.empty:SetWordWrap(true)
  self.frame = f
  -- the filter, on the views' row
  self.tools = CreateFrame("Frame", nil, page.tools)
  self.tools:SetAllPoints()
  self.forMe = UI.Chip(self.tools, "For me", nil, function(on) state.forMe = on R:Fill() end)
  self.forMe:SetPoint("RIGHT", -10, 0)
  f:Hide()
  self.tools:Hide()
end

local function pvpHeader()
  local side, rank = state.side, state.rank
  local n = #rankItems(rank, side)
  local facts = string.format("Rank %d  ·  %s  ·  %d %s", rank, SIDE_NAME[side] or "", n, n == 1 and "reward" or "rewards")
  local badges
  if side == mySide() then
    local mine = R.MyRank()
    if mine >= rank then badges = O.ICON.check .. " " .. UI.Code(C.good) .. "You've reached this rank|r"
    elseif mine > 0 then badges = "Your highest rank: " .. UI.Code(C.text) .. R.RankName(mine, side) .. "|r (rank " .. mine .. ")"
    else badges = "You haven't earned a rank yet" end
  else
    badges = UI.Code(C.faint) .. "The other side's quartermasters sell these|r"
  end
  O.Shell:SetHeader(R.RankName(rank, side), facts, badges)
end

local function factionHeader()
  local f = R.Faction(state.faction)
  if not f then return O.Shell:SetHeader("Factions", nil, nil) end
  local n = countItems(f.items)
  local parts = { f.group }
  if f.side then parts[#parts + 1] = SIDE_NAME[f.side] end
  parts[#parts + 1] = n .. (n == 1 and " reward" or " rewards")
  local badges
  if f.standing then
    badges = "You: " .. UI.Code(C.text) .. R.StandingName(f.standing) .. "|r"
    if f.value and f.max and f.max > 0 then badges = badges .. string.format(" (%d / %d)", f.value, f.max) end
  end
  if f.items and f.items[NOT_RECORDED] then
    badges = (badges and (badges .. "   ") or "") .. UI.Code(C.faint) .. "The game's data doesn't say which standing their supply officers ask for|r"
  end
  O.Shell:SetHeader(f.name, table.concat(parts, "  ·  "), badges)
end

-- picks a rank or faction when none is chosen: your next rank, or the first faction
local function defaults()
  if state.mode == "pvp" and not state.rank then
    state.side = mySide() or "A"
    state.rank = math.min(14, math.max(1, R.MyRank() + 1))
    while state.rank > 1 and #rankItems(state.rank, state.side) == 0 do state.rank = state.rank - 1 end
  elseif state.mode == "factions" and not state.faction then
    for _, e in ipairs(R.FactionNav()) do if e.faction then state.faction = e.faction break end end
  end
end

function R:Fill()
  if not self.frame then return end
  defaults()
  local rows
  if state.mode == "pvp" then
    pvpHeader()
    rows = R.RankRows(state.rank, state.side)
  else
    factionHeader()
    rows = R.FactionRows(state.faction)
  end
  self.frame.list:SetData(R.Pairs(rows))
  self.frame.empty:SetShown(#rows == 0)
  self.frame.empty:SetText(state.forMe and "Nothing here for your class. Turn off For me to see everything."
    or "No rewards known here yet.")
end

---Goes to a page: { mode = "pvp", rank, side } or { mode = "factions", faction }.
function R:Go(where)
  if where.faction then where.mode = "factions" end
  if where.rank then where.mode = "pvp" end
  if where.mode and where.mode ~= state.mode then
    state.mode = where.mode
    O.db.rewardsMode = where.mode
  end
  if where.rank then state.rank, state.side = where.rank, where.side or mySide() or "A" end
  if where.faction then state.faction = where.faction end
  self:Fill()
end

function R:Show()
  state.mode = O.db.rewardsMode or state.mode
  self.frame:Show()
  self.tools:Show()
  self.page.content:Show()
  if self.seg then self.seg:Show() end
  self:Fill()
end

function R:Hide()
  if self.frame then self.frame:Hide() end
  if self.tools then self.tools:Hide() end
  if self.seg then self.seg:Hide() end
end

R.state = state

O:Listen("ITEMS_LOADED", "rewards", function()
  if R.frame and R.frame:IsVisible() then R.frame.list:Refresh() end
end)
Core:Listen("NORGANNON_REPUTATION_CHANGED", "oracle-rewards", function()
  if O.Shell.current == "rewards" and R.frame and R.frame:IsVisible() then R:Fill() O.Shell:RefreshNav() end
end)
O:Listen("WANTS", "rewards", function()
  if O.Shell.current == "rewards" and R.frame then R.frame.list:Refresh() end
end)

O.Shell:AddSpace("rewards", R)
