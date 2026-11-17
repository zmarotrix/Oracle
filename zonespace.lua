-- Zones (docs/oracle-redesign.md 4.3): a zone is a place like an instance, with the same views.
--
--   Quests  the quest book (questbook.lua): each chain as a heading with where you stand ("3 of 5
--           done") and its next step and where that is, unfolding to its steps (a branch marked "-");
--           then the single quests; then, greyed at the bottom, the other faction's and other classes'. Click a quest: the Inspector; right-click: Track (Clairvoyance).
--   Loot    what the zone gives, on a source rail: Everything (each item once, near your level first),
--           Quest rewards (by quest), Creature drops (by creature, rares first), Rares, Vendors.
--           Filters: For me, Uncommon+, World drops (25+ kinds of creature drop it: off by default).
--   Map     the zone's world map art with its pins (zones.lua)
--   Info    dungeons, services, trainers, rares, gathering, recipes (zones.lua's About)
--
-- Facts only: where each chain stands and where its next step is; never which quests to do.

local Core = NorgannonCore
local DB = NorgannonDB
local O = Oracle
if O.disabled then return end
local UI = Core.UI
local C = UI.C

local Z = { label = "Zones", order = 3 }
O.ZonesSpace = Z

local QROW, LROW = 26, 42
local VIEWS = { { key = "quests", label = "Quests" }, { key = "loot", label = "Loot" }, { key = "map", label = "Map" }, { key = "info", label = "Info" } }
local SOURCES = {
  { key = "all", label = "Everything", meta = "near your level first" },
  { key = "reward", label = "Quest rewards", meta = "by quest" },
  { key = "drop", label = "Creature drops", meta = "by creature" },
  { key = "rare", label = "Rares", meta = "and what they drop" },
  { key = "vendor", label = "Vendors", meta = "gear and recipes" },
}
local STATE_COLOR = { done = C.good, log = C.info, ready = C.clairvoyance or UI.Accent("clairvoyance"), locked = C.faint, nfy = C.faint }
local state = { src = "all", forMe = false, uncommon = true, world = false, showDone = false, othersFolded = false, open = {} }
Z.state = state

local function QB() return O.QuestBook end
local function qname(id) return Core.DB:Name("quests", id) or ("Quest " .. id) end

---A quest state (questbook.lua) in a few words, and its colour.
function O.QuestStateText(st)
  if not st then return "", C.faint end
  local s, why = st.s, st.why
  if s == "done" then return "Done", C.good end
  if s == "log" then return "In your log", C.info end
  if s == "ready" then return "Ready to pick up", STATE_COLOR.ready end
  if s == "locked" then
    if why == "step" then return (st.left == 1 and "after 1 earlier quest" or ("after " .. (st.left or "earlier") .. " earlier quests")), C.faint end
    if why == "level" then return "from level " .. (st.level or "?"), C.warn end
    if why == "skill" then return "needs " .. (DB.professions and st.skill and DB.professions[st.skill[1]] or "a skill") .. " " .. (st.skill and st.skill[2] or ""), C.warn end
    if why == "rep" then return "needs reputation", C.warn end
    if why == "event" then return "a seasonal event", C.faint end
    if why == "blocked" then return "not while " .. qname(st.other) .. " is in your log", C.faint end
    return "not yet", C.faint
  end
  local nfy = { faction = (st.side and (st.side .. " only") or "the other side's"), race = "another race", class = "another class",
    exclusive = "you took its alternative", skipped = "you went past it", ended = "no longer offered", outleveled = "too low for you now" }
  return nfy[why] or "not for you", C.faint
end

local function giverText(g)
  if not g then return nil end
  if g.kind == "items" then return "starts from " .. (g.name or "an item") end
  local where = g.area and QB().AreaName(g.area) or nil
  if where and g.x then where = string.format("%s (%.1f, %.1f)", where, g.x, g.y) end
  return (g.name or "?") .. (where and (", " .. where) or "")
end

-------------------------------------------------------------------------------------------
-- The navigator
-------------------------------------------------------------------------------------------

function Z:nav()
  local rows, groups, order = {}, {}, {}
  for _, e in ipairs(O.Zones:Entries()) do
    if not e.group then
      local g = e.continent or "Other"
      if not groups[g] then groups[g] = {} order[#order + 1] = g end
      e.navMeta = (e.quests or 0) .. " quests"
      e.navRight = e.levels and O.Model.LevelText(e) or ""
      e.navRightColor = O.Model.LevelColor(e)
      table.insert(groups[g], e)
    end
  end
  for _, g in ipairs(order) do
    rows[#rows + 1] = { group = g }
    for _, e in ipairs(groups[g]) do rows[#rows + 1] = e end
  end
  return rows
end
function Z:navSelected(e) return e.zone == O.db.zone end
function Z:navClick(e) O:Go({ space = "zones", area = e.zone }) end
function Z:navTop(top) top:SetHeight(1) end

-------------------------------------------------------------------------------------------
-- Quests: the quest book
-------------------------------------------------------------------------------------------

---The book's rows: per chain a heading ({ group, chain }) and, unfolded, its steps; then single quests;
---then, greyed at the bottom, the other faction's and other classes' (Not for you).
function Z.QuestRows(area)
  local book = QB().Zone(area, "all")
  local rows, finished = {}, 0
  local function addChain(c, greyed)
    local first, last = DB:Get("quests", c.quests[1]) or {}, DB:Get("quests", c.quests[#c.quests]) or {}
    local levels = (first.level or "?") .. ((last.level and last.level ~= first.level) and ("–" .. last.level) or "")
    local open = state.open[c.key]
    local nextId = c.next and c.next[1]
    local nextLine = ""
    if greyed then
      nextLine = UI.Code(C.faint) .. O.QuestStateText(QB().State(c.quests[1])) .. "|r"
    elseif c.state == "done" then nextLine = UI.Code(C.good) .. "Finished|r"
    elseif nextId then
      local words, color = O.QuestStateText(QB().State(nextId))
      local where = (QB().State(nextId).s == "ready") and giverText(c.giver) or nil
      nextLine = "next: " .. UI.Code(C.text) .. qname(nextId) .. "|r · " .. UI.Code(color) .. (where or words) .. "|r"
    end
    local title = c.title or qname(c.titleId or c.quests[#c.quests])
    rows[#rows + 1] = { group = string.format("%s %s[%s]|r %s%s|r  %s%s|r   %s", open and O.ICON.open or O.ICON.folded, UI.Code(C.faint), levels,
      greyed and UI.Code(C.faint) or UI.Code(C.goldSoft), title, UI.Code(C.muted),
      greyed and "" or ((c.done or 0) .. " of " .. (c.total or #c.quests)), nextLine), chain = c, fold = c.key, open = open }
    if open then
      for ri, rail in ipairs(c.rails or { { steps = c.quests } }) do
        for si, id in ipairs(rail.steps) do
          rows[#rows + 1] = { id = id, branch = ri > 1 and si == 1, crumb = c.crumbs and c.crumbs[id], chainKey = c.key, greyed = greyed }
        end
      end
    end
  end
  local others, otherSingles = {}, {}
  for _, c in ipairs(book.chains) do
    if c.state == "nfy" then others[#others + 1] = c
    elseif c.state == "done" and not state.showDone then finished = finished + 1
    else addChain(c) end
  end
  if finished > 0 then rows[#rows + 1] = { group = O.ICON.folded .. " " .. UI.Code(C.faint) .. finished .. " finished chains (Show finished)|r", showDone = true } end
  local singles = {}
  for _, s in ipairs(book.singles) do
    if s.state.s == "nfy" then otherSingles[#otherSingles + 1] = s
    elseif s.state.s ~= "done" or state.showDone then singles[#singles + 1] = s end
  end
  if #singles > 0 then
    rows[#rows + 1] = { group = "Single quests  " .. UI.Code(C.faint) .. #singles .. "|r", singles = true }
    for _, s in ipairs(singles) do rows[#rows + 1] = { id = s.id } end
  end
  local n = #others + #otherSingles
  if n > 0 then
    rows[#rows + 1] = { group = (state.othersFolded and O.ICON.folded or O.ICON.open) .. " " .. UI.Code(C.faint) .. "Not for you  " .. n
      .. "  the other faction's or another class's|r", others = true }
    if not state.othersFolded then
      for _, c in ipairs(others) do addChain(c, true) end
      for _, s in ipairs(otherSingles) do rows[#rows + 1] = { id = s.id, greyed = true } end
    end
  end
  return rows, book
end

local function buildQuests(parent)
  local f = CreateFrame("Frame", nil, parent)
  f:SetAllPoints()
  local pane = UI.Pane(f)
  pane:SetAllPoints()
  f.list = UI.List(pane, {
    rowHeight = QROW,
    groupBand = true,
    createRow = function(row, content)
      row.dot = UI.Icon(content, "circle", 9, C.faint)
      row.dot:SetPoint("LEFT", 26, 0)
      row.name = UI.Text(content, "body", 13, C.text)
      row.name:SetPoint("LEFT", row.dot, "RIGHT", 8, 0)
      row.name:SetWidth(330)
      row.name:SetWordWrap(false)
      row.state = UI.Text(content, "body", 12, C.muted)
      row.state:SetPoint("LEFT", row.name, "RIGHT", 8, 0)
      row.state:SetPoint("RIGHT", content, "RIGHT", -10, 0)
      row.state:SetJustifyH("RIGHT")
      row.state:SetWordWrap(false)
    end,
    updateRow = function(row, r)
      local q = DB:Get("quests", r.id) or {}
      local st = QB().State(r.id)
      local words, color = O.QuestStateText(st)
      local lc = q.level and UI.Difficulty(q.level, Core.Player.level or 1) or C.text
      row.name:SetText((r.branch and (UI.Code(C.faint) .. O.ICON.branch .. "|r") or "") .. UI.Code(lc) .. "[" .. (q.level or "?") .. "]|r "
        .. qname(r.id) .. (r.crumb and (UI.Code(C.faint) .. " (optional lead-in)|r") or ""))
      local g = st.s == "ready" and QB().Giver(r.id)
      row.state:SetText(UI.Code(color) .. words .. "|r" .. (g and (UI.Code(C.faint) .. " · " .. giverText(g) .. "|r") or ""))
      row.dot:SetVertexColor(color[1], color[2], color[3])
      -- done: dimmed; the other faction's and other classes': greyed
      row.name:SetAlpha((r.greyed or st.s == "nfy") and .45 or (st.s == "done" and .6 or 1))
      row.state:SetAlpha((r.greyed or st.s == "nfy") and .45 or 1)
    end,
    onClick = function(r, _, button)
      if button == "RightButton" then
        local card = O.Quests and O.Quests.Card(r.id)
        if card then O.Quests.Track(card) end
        return
      end
      O.Inspector:Show("quest", r.id)
    end,
    onGroupClick = function(g)
      if g.others then state.othersFolded = not state.othersFolded
      elseif g.showDone then state.showDone = true if Z.showDone then Z.showDone:SetOn(true, true) end
      elseif g.fold then state.open[g.fold] = not state.open[g.fold] or nil end
      Z:FillQuests()
    end,
    onEnter = function(row)
      GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
      GameTooltip:AddLine("Click: the quest · right-click: Track (its giver on your map)", .66, .63, .54)
      GameTooltip:Show()
    end,
    onLeave = function() GameTooltip:Hide() end,
  })
  f.list:SetPoint("TOPLEFT", 1, -4)
  f.list:SetPoint("BOTTOMRIGHT", -1, 4)
  f.list:ApplyAccent(UI.Accent("oracle"))
  f.empty = UI.Text(pane, "body", 13, C.faint)
  f.empty:SetPoint("TOPLEFT", 14, -14)
  f.empty:SetPoint("TOPRIGHT", -14, -14)
  f.empty:SetWordWrap(true)
  return f
end

function Z:FillQuests()
  if not (self.quests and O.db.zone and QB()) then return end
  local rows = Z.QuestRows(O.db.zone)
  self.quests.list:SetData(rows, true)
  self.quests.empty:SetShown(#rows == 0)
  self.quests.empty:SetText("No quests here for you.")
  self.questRows = rows
end

-------------------------------------------------------------------------------------------
-- Loot: what the zone gives
-------------------------------------------------------------------------------------------

local function isRare(npc)
  local r = npc and DB:Get("npcs", npc)
  return r and (r.rank == 2 or r.rank == 4)
end

local function passes(r)
  if r.world and not state.world then return false end
  if state.uncommon then
    local q = O.Items.Info(r.item).quality
    if type(q) == "number" and q < 2 and r.kind ~= "recipe" then return false end
  end
  if state.forMe then
    local you = O.Items.ForYou(r.item)
    if not you or not you.ok then return false end
  end
  return true
end

---The Loot list's rows for a source: { group } headings and { item, source, ... } rows.
function Z.LootRows(area, src)
  local all = O.Zones.Items(area)
  local out = {}
  local level = Core.Player.level or UnitLevel("player") or 1
  if src == "all" then
    local best = {}
    for _, r in ipairs(all) do
      if passes(r) then
        local b = best[r.item]
        if not b or (r.source == "reward" and b.source ~= "reward") or (r.source == "drop" and b.source == "drop" and (r.chance or 0) > (b.chance or 0)) then
          best[r.item] = r
        end
      end
    end
    local rows = {}
    for _, r in pairs(best) do rows[#rows + 1] = r end
    local function near(r)
      local rec = DB:Get("items", r.item) or {}
      local l = rec.requiredLevel or rec.level or 0
      return l <= level + 5 and l >= level - 8
    end
    table.sort(rows, function(a, b)
      local na, nb = near(a), near(b)
      if na ~= nb then return na end
      if a.level ~= b.level then return a.level > b.level end
      return a.item < b.item
    end)
    for _, r in ipairs(rows) do out[#out + 1] = r end
    return out
  end
  local groups, order = {}, {}
  for _, r in ipairs(all) do
    local key
    if src == "reward" and r.source == "reward" then key = "q" .. r.quest
    elseif src == "drop" and r.source == "drop" then key = "n" .. r.npc
    elseif src == "rare" and r.source == "drop" and isRare(r.npc) then key = "n" .. r.npc
    elseif src == "vendor" and r.source == "vendor" then key = "n" .. r.npc end
    if key and passes(r) then
      if not groups[key] then groups[key] = { rows = {}, r = r } order[#order + 1] = key end
      table.insert(groups[key].rows, r)
    end
  end
  table.sort(order, function(a, b)
    local ra, rb = groups[a].r, groups[b].r
    if src == "reward" then return (ra.questLevel or 0) < (rb.questLevel or 0) end
    local ea, eb = isRare(ra.npc) and 1 or 0, isRare(rb.npc) and 1 or 0
    if ea ~= eb then return ea > eb end
    local la, lb = (DB:Get("npcs", ra.npc) or {}).maxLevel or 0, (DB:Get("npcs", rb.npc) or {}).maxLevel or 0
    if la ~= lb then return la < lb end
    return a < b
  end)
  for _, key in ipairs(order) do
    local g = groups[key]
    local heading
    if src == "reward" then
      local st = QB() and QB().State(g.r.quest)
      local words, color = O.QuestStateText(st)
      heading = string.format("%s[%d]|r %s  %s%s|r%s", UI.Code(C.faint), g.r.questLevel or 0, qname(g.r.quest), UI.Code(color), words,
        g.r.choice and (UI.Code(C.faint) .. " · choose one|r") or "")
    else
      local n = DB:Get("npcs", g.r.npc) or {}
      local where = ""
      for a, pts in pairs(n.spawns or {}) do
        if a == area and pts[1] and pts[1][1] and pts[1][1] >= 0 then where = string.format(" (%.1f, %.1f)", pts[1][1], pts[1][2]) end
      end
      heading = (Core.DB:Name("npcs", g.r.npc) or "?") .. (isRare(g.r.npc) and (UI.Code(UI.Hex("ff8a3d")) .. "  rare|r") or "")
        .. "  " .. UI.Code(C.faint) .. (n.maxLevel and ("Level " .. n.maxLevel) or "") .. where .. "|r"
    end
    out[#out + 1] = { group = heading, quest = src == "reward" and g.r.quest or nil, npc = src ~= "reward" and g.r.npc or nil }
    table.sort(g.rows, function(a, b) return (a.chance or 0) > (b.chance or 0) or ((a.chance or 0) == (b.chance or 0) and a.level > b.level) end)
    for _, r in ipairs(g.rows) do out[#out + 1] = r end
  end
  return out
end

local function sourceWords(r)
  if r.source == "reward" then
    local st = QB() and QB().State(r.quest)
    local words, color = O.QuestStateText(st)
    return "quest " .. qname(r.quest) .. " · " .. UI.Code(color) .. words .. "|r"
  elseif r.source == "drop" then
    return (r.world and "world drop · " or "") .. (Core.DB:Name("npcs", r.npc) or "?") .. (isRare(r.npc) and (UI.Code(UI.Hex("ff8a3d")) .. " rare|r") or "")
  end
  return "sold by " .. (Core.DB:Name("npcs", r.npc) or "?") .. (r.limited and " · limited" or "")
end

local function buildLoot(parent)
  local f = CreateFrame("Frame", nil, parent)
  f:SetAllPoints()
  local railPane = UI.Pane(f)
  railPane:SetPoint("TOPLEFT")
  railPane:SetPoint("BOTTOMLEFT")
  railPane:SetWidth(190)
  f.rail = UI.List(railPane, {
    rowHeight = 34,
    createRow = function(row, content)
      row.name = UI.Text(content, "body", 13, C.text)
      row.name:SetPoint("TOPLEFT", 10, -3)
      row.meta = UI.Text(content, "body", 11, C.faint)
      row.meta:SetPoint("TOPLEFT", row.name, "BOTTOMLEFT", 0, -1)
    end,
    updateRow = function(row, s)
      row.name:SetText(s.label)
      row.meta:SetText(s.meta)
    end,
    onClick = function(s) state.src = s.key Z:FillLoot() end,
  })
  f.rail:SetPoint("TOPLEFT", 1, -4)
  f.rail:SetPoint("BOTTOMRIGHT", -1, 4)
  f.rail:ApplyAccent(UI.Accent("oracle"))
  local listPane = UI.Pane(f)
  listPane:SetPoint("TOPLEFT", railPane, "TOPRIGHT", 8, 0)
  listPane:SetPoint("BOTTOMRIGHT")
  f.list = UI.List(listPane, {
    rowHeight = LROW,
    groupBand = true,
    createRow = function(row, content)
      content.rightInset = 60
      O.Items.Build(content)
      row.itemFrame = content
      row.chance = UI.Text(content, "body", 12, C.muted)
      row.chance:SetPoint("RIGHT", -12, 0)
      row.chance:SetJustifyH("RIGHT")
    end,
    updateRow = function(row, r)
      local you = O.Items.ForYou(r.item)
      local extra = ""
      if you and not you.ok then extra = " · " .. UI.Code(C.bad) .. you.why .. "|r"
      elseif you and you.later then extra = " · " .. UI.Code(C.warn) .. "you can use it at " .. you.later .. "|r"
      elseif you then extra = " · " .. UI.Code(C.good) .. "for you|r" end
      if state.src == "all" then extra = extra .. " · " .. sourceWords(r) end
      if O.Wants and O.Wants:Has(r.item) then extra = extra .. " · " .. O.ICON.star end
      O.Items.Fill(row.itemFrame, r.item, extra)
      row.itemFrame:SetAlpha(you and not you.ok and .5 or 1)
      row.chance:SetText(r.source == "drop" and r.chance and r.chance > 0 and O.Loot.ChanceText(r.chance) or "")
    end,
    onClick = function(r, _, button)
      if button == "RightButton" then return O.Wants and O.Wants:Toggle(r.item) end
      if IsShiftKeyDown() then
        local link = select(2, (C_Item and C_Item.GetItemInfo or GetItemInfo)(r.item))
        if link and ChatEdit_InsertLink then ChatEdit_InsertLink(link) end
        return
      end
      O.Inspector:Show("item", r.item)
    end,
    onGroupClick = function(g)
      if g.quest then O.Inspector:Show("quest", g.quest) elseif g.npc then O.Inspector:Show("npc", g.npc) end
    end,
    onEnter = function(row, r)
      GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
      GameTooltip:SetItemByID(r.item)
      GameTooltip:AddLine("Right-click: want it", .66, .63, .54)
      GameTooltip:Show()
    end,
    onLeave = function() GameTooltip:Hide() end,
  })
  f.list:SetPoint("TOPLEFT", 1, -4)
  f.list:SetPoint("BOTTOMRIGHT", -1, 4)
  f.list:ApplyAccent(UI.Accent("oracle"))
  f.empty = UI.Text(listPane, "body", 13, C.faint)
  f.empty:SetPoint("TOPLEFT", 14, -14)
  f.empty:SetPoint("TOPRIGHT", -14, -14)
  f.empty:SetWordWrap(true)
  return f
end

local LOOT_CAP = 300   -- rows drawn in Everything (the filters narrow it)

function Z:FillLoot()
  if not (self.loot and O.db.zone) then return end
  self.loot.rail:SetData(SOURCES)
  for _, s in ipairs(SOURCES) do if s.key == state.src then self.loot.rail:Select(s) end end
  local rows = Z.LootRows(O.db.zone, state.src)
  local more = 0
  if #rows > LOOT_CAP then
    more = #rows - LOOT_CAP
    local cut = {}
    for i = 1, LOOT_CAP do cut[i] = rows[i] end
    rows = cut
  end
  self.loot.list:SetData(rows)
  self.lootRows = rows
  self.loot.empty:SetShown(#rows == 0)
  self.loot.empty:SetText("Nothing here with these filters" .. (state.world and "." or " (world drops are hidden)."))
  if more > 0 then self.loot.empty:SetShown(false) end
end

-------------------------------------------------------------------------------------------
-- The page
-------------------------------------------------------------------------------------------

function Z:Build(page, win)
  self.page = page
  self.views = O.Shell:Views(VIEWS, function(key) Z:ShowView(key) end)
  self.quests = buildQuests(page.content)
  self.loot = buildLoot(page.content)
  -- zones.lua's map column and About sheet, hosted as the Map and Info views
  O.Zones:Build(win)
  local col = O.Zones.col
  col:SetParent(page.content)
  col:ClearAllPoints()
  col:SetAllPoints(page.content)
  col.title:Hide()
  col.facts:Hide()
  O.Zones.panel:ClearAllPoints()
  O.Zones.panel:SetPoint("TOPLEFT", 0, 0)
  O.Zones.panel:SetPoint("BOTTOMRIGHT", 0, 30)
  local d = O.Zones.detail
  d:SetParent(page.content)
  d:ClearAllPoints()
  d:SetAllPoints(page.content)
  O.Zones.tabs:Hide()
  O.Zones.tabs:Select("about")
  self.tools = CreateFrame("Frame", nil, page.tools)
  self.tools:SetAllPoints()
  self.showDone = UI.Chip(self.tools, "Show finished", nil, function(on) state.showDone = on Z:FillQuests() end)
  self.showDone:SetPoint("RIGHT", 0, 0)
  self.lootTools = CreateFrame("Frame", nil, page.tools)
  self.lootTools:SetAllPoints()
  self.forMe = UI.Chip(self.lootTools, "For me", nil, function(on) state.forMe = on Z:FillLoot() end)
  self.forMe:SetPoint("RIGHT", -200, 0)
  self.uncommon = UI.Chip(self.lootTools, "Uncommon+", nil, function(on) state.uncommon = on Z:FillLoot() end)
  self.uncommon:SetPoint("LEFT", self.forMe, "RIGHT", 6, 0)
  self.uncommon:SetOn(state.uncommon, true)
  self.world = UI.Chip(self.lootTools, "World drops", nil, function(on) state.world = on Z:FillLoot() end)
  self.world:SetPoint("LEFT", self.uncommon, "RIGHT", 6, 0)
  self:Hide()
end

local function header(e)
  local book = QB() and QB().Zone(e.zone, "mine")
  local done, log, ready, total = 0, 0, 0, 0
  if book then
    for _, c in ipairs(book.chains) do
      for _, id in ipairs(c.quests) do
        local s = QB().State(id).s
        if s ~= "nfy" then total = total + 1 end
        if s == "done" then done = done + 1 elseif s == "log" then log = log + 1 elseif s == "ready" then ready = ready + 1 end
      end
    end
    for _, s in ipairs(book.singles) do
      if s.state.s ~= "nfy" then total = total + 1 end
      if s.state.s == "done" then done = done + 1 elseif s.state.s == "log" then log = log + 1 elseif s.state.s == "ready" then ready = ready + 1 end
    end
  end
  local facts = { e.continent or "" }
  if e.levels then facts[#facts + 1] = UI.Code(O.Model.LevelColor(e)) .. "Level " .. O.Model.LevelText(e) .. "|r" end
  facts[#facts + 1] = string.format("%d quests for you: %s%d|r done, %s%d|r in your log", total, UI.Code(C.text), done, UI.Code(C.text), log)
  local badges = {}
  if ready > 0 then badges[#badges + 1] = UI.Code(STATE_COLOR.ready) .. ready .. " ready to pick up|r" end
  for _, i in ipairs(O.Model:All()) do
    if i.entrance and i.entrance.area == e.zone then badges[#badges + 1] = i.name end
  end
  return e.name, table.concat(facts, "  ·  "), #badges > 0 and table.concat(badges, "   ") or nil, total
end

function Z:ShowView(view)
  view = view or O.db.zoneView or "quests"
  O.db.zoneView = view
  self.view = view
  self.views:Select(view, true)
  self.quests:SetShown(view == "quests")
  self.loot:SetShown(view == "loot")
  O.Zones.col:SetShown(view == "map")
  O.Zones.detail:SetShown(view == "info")
  self.tools:SetShown(view == "quests")
  self.lootTools:SetShown(view == "loot")
  if view == "quests" then self:FillQuests()
  elseif view == "loot" then self:FillLoot()
  elseif view == "map" then O.Zones:Draw() end
end

---Opens a zone: { area, view }.
function Z:Go(where)
  local area = where.area or O.db.zone or O.Sidebar.HereZone()
  local e = area and O.Zones:Entry(area)
  if not e then
    for _, item in ipairs(O.Zones:Entries()) do if not item.group then e = item break end end
  end
  if not e then return end
  if e.zone ~= O.db.zone then state.open = {} end
  O.db.zone = e.zone
  O.Zones:Select(e.zone)          -- zones.lua draws its map and About for this zone
  local title, facts, badges, total = header(e)
  O.Shell:SetHeader(title, facts, badges)
  self.views:SetCount("quests", total)
  self:ShowView(where.view)
end

function Z:Show()
  self.views:Show()
  self:Go({})
end

function Z:Hide()
  if not self.views then return end
  self.views:Hide()
  self.quests:Hide()
  self.loot:Hide()
  self.tools:Hide()
  self.lootTools:Hide()
  if O.Zones.col then O.Zones.col:Hide() O.Zones.detail:Hide() end
end

-- your quest log changed: the book and the header
Core:Listen("ORACLE_QUESTBOOK_CHANGED", "oracle.zonespace", function()
  if O.Shell.current == "zones" and Z.views and Z.views:IsVisible() then Z:Go({ view = Z.view }) end
end)
O:Listen("ITEMS_LOADED", "zonespace", function()
  if Z.loot and Z.loot:IsVisible() then Z.loot.list:Refresh() end
end)

O.Shell:AddSpace("zones", Z)
