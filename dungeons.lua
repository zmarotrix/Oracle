-- Dungeons & Raids (docs/oracle-redesign.md 4.1): the navigator lists dungeons or raids by level band
-- (yours first); an instance's page has a header (levels, size, entrance, keys, attunement, your
-- lockout) and four views:
--   Loot   a boss rail (numbered as on the map; All bosses; Trash and shared) beside the item list:
--          icon, name in its quality colour, kind line with "for you", drop chance with a bar.
--          Filters: For me, Uncommon and better. Click: the Inspector; shift-click: link it;
--          right-click: want it (wants.lua).
--          A boss clicked on the map shows in the Inspector; Its loot opens it here.
--   Quests the Ready check (readycheck.lua, on questbook.lua)
--   Map    the game map (or the schematic) on the map panel
--   Info   Oracle 0.12's Info pane: the facts, Getting there, About this data

local Core = NorgannonCore
local DB = NorgannonDB
local O = Oracle
if O.disabled then return end
local UI = Core.UI
local C = UI.C

local D = { label = "Dungeons & Raids", order = 1 }
O.Dungeons = D

local RAIL, ROW, RAIL_ROW = 220, 42, 34
local CHANCE_W = 150
local VIEWS = { { key = "loot", label = "Loot" }, { key = "quests", label = "Quests" }, { key = "map", label = "Map" }, { key = "info", label = "Info" } }

local state = { boss = "all", forMe = false, uncommon = false }
D.state = state

-------------------------------------------------------------------------------------------
-- The navigator
-------------------------------------------------------------------------------------------

local function levelsOf(e) return e.levels or e.bossLevels end

function D:nav()
  local raids = O.db.raids and true or false
  local level = Core.Player.level or UnitLevel("player") or 1
  local bands = raids and { { "Raids", function() return true end } } or {
    { "Around your level", function(l) return l.max >= level - 3 and l.min <= level + 6 end },
    { "Lower", function(l) return l.max < level - 3 end },
    { "Higher", function(l) return l.min > level + 6 end },
  }
  local rows, forever = {}, {}
  local pool = {}
  for _, e in ipairs(O.Model:All()) do
    if e.forever and not levelsOf(e) then
      if not raids then forever[#forever + 1] = e end
    elseif e.raid == raids then
      pool[#pool + 1] = e
    end
  end
  for _, band in ipairs(bands) do
    local inBand = {}
    for _, e in ipairs(pool) do
      local l = levelsOf(e)
      if l and band[2](l) then inBand[#inBand + 1] = e end
    end
    if #inBand > 0 then
      rows[#rows + 1] = { group = band[1] .. "  |cff6e6552" .. #inBand .. "|r" }
      for _, e in ipairs(inBand) do rows[#rows + 1] = e end
    end
  end
  if #forever > 0 then
    rows[#rows + 1] = { group = "WoW Forever's own" }
    for _, e in ipairs(forever) do rows[#rows + 1] = e end
  end
  for _, e in ipairs(rows) do
    if not e.group then
      local count = e.bosses == 1 and "1 boss" or (e.bosses .. " bosses")
      if e.forever and e.bosses == 0 then count = "being mapped" end
      e.navMeta = (e.zone or "Unknown") .. " · " .. count
      local wants = O.Wants and O.Wants:In(e.key) or 0
      if wants > 0 then e.navMeta = e.navMeta .. "  " .. O.ICON.star .. UI.Code(C.gold) .. wants .. "|r" end
      e.navRight = levelsOf(e) and O.Model.LevelText(e) or ""
      e.navRightColor = O.Model.LevelColor(e)
    end
  end
  return rows
end

function D:navSelected(e) return e.key == O.db.selected end
function D:navClick(e) O:Go({ space = "dungeons", key = e.key }) end

function D:navTop(top)
  if not self.seg then
    self.seg = UI.Segmented(top, { { key = "dungeons", label = "Dungeons" }, { key = "raids", label = "Raids" } }, function(key)
      O.db.raids = key == "raids" or nil
      O.Shell:RefreshNav()
    end, 24)
    self.seg:SetPoint("TOPLEFT")
    self.seg:SetPoint("TOPRIGHT")
  end
  top:SetHeight(24)
  self.seg:Select(O.db.raids and "raids" or "dungeons", true)
  self.seg:Show()
end

-------------------------------------------------------------------------------------------
-- Loot
-------------------------------------------------------------------------------------------

local function railRows(key)
  local rows = { { all = true, name = "All bosses" } }
  for _, b in ipairs(O.Bosses.Rows(key)) do rows[#rows + 1] = b end
  local inst = Core.DB:Instance(key)
  if inst and inst.trash and #inst.trash > 0 then rows[#rows + 1] = { trash = true, name = "Trash and shared", loot = inst.trash } end
  return rows
end

---Whether a loot row passes the filters.
local function passes(id)
  if state.forMe then
    local you = O.Items.ForYou(id)
    if not you or not you.ok then return false end
  end
  if state.uncommon then
    local info = O.Items.Info(id)
    if type(info.quality) == "number" and info.quality < 2 then return false end
  end
  return true
end

---The list's rows: boss headers ({ group }) and items ({ item, npc }).
function D.LootRows(key)
  local out = {}
  for _, b in ipairs(railRows(key)) do
    if not b.all and (state.boss == "all" or state.boss == (b.trash and "trash" or b.npc)) then
      local items = {}
      for _, id in ipairs(b.loot or {}) do
        if passes(id) then items[#items + 1] = { item = id, npc = not b.trash and b.npc or nil } end
      end
      if #items > 0 then
        local num = b.num and (UI.Code(UI.Hex("b48cff")) .. b.num .. "|r  ") or ""
        local meta = b.level and ("  " .. UI.Code(C.faint) .. "Level " .. b.level .. "|r") or ""
        out[#out + 1] = { group = num .. b.name .. meta }
        for _, it in ipairs(items) do out[#out + 1] = it end
      end
    end
  end
  return out
end

local function buildLoot(parent)
  local f = CreateFrame("Frame", nil, parent)
  f:SetAllPoints()
  -- the boss rail
  local railPane = UI.Pane(f)
  railPane:SetPoint("TOPLEFT")
  railPane:SetPoint("BOTTOMLEFT")
  railPane:SetWidth(RAIL)
  f.rail = UI.List(railPane, {
    rowHeight = RAIL_ROW,
    createRow = function(row, content)
      row.num = UI.Text(content, "title", 13, C.text)
      row.num:SetPoint("LEFT", 10, 0)
      row.num:SetWidth(20)
      row.num:SetJustifyH("CENTER")
      row.name = UI.Text(content, "body", 13, C.text)
      row.name:SetPoint("TOPLEFT", 36, -3)
      row.name:SetPoint("TOPRIGHT", content, "TOPRIGHT", -6, -3)
      row.name:SetWordWrap(false)
      row.meta = UI.Text(content, "body", 11, C.faint)
      row.meta:SetPoint("TOPLEFT", row.name, "BOTTOMLEFT", 0, -1)
    end,
    updateRow = function(row, b)
      row.num:SetText((b.all or b.trash) and "" or (b.num or ""))
      local nc = b.final and UI.Hex("ff8a3d") or UI.Hex("b48cff")
      if b.all or b.trash then nc = C.muted end
      row.num:SetTextColor(nc[1], nc[2], nc[3])
      row.name:SetText(b.name or "")
      local n = b.loot and #b.loot or 0
      row.meta:SetText(b.all and "" or ((b.level and ("Level " .. b.level .. " · ") or "") .. n .. (n == 1 and " drop" or " drops")))
    end,
    onClick = function(b)
      state.boss = b.all and "all" or (b.trash and "trash" or b.npc)
      D:FillLoot()
    end,
    onEnter = function(_, b) if b.npc then O.Schematic:SetHot(b.npc) end end,
    onLeave = function() O.Schematic:SetHot(nil) end,
  })
  f.rail:SetPoint("TOPLEFT", 1, -4)
  f.rail:SetPoint("BOTTOMRIGHT", -1, 4)
  f.rail:ApplyAccent(UI.Accent("oracle"))

  -- the items
  local listPane = UI.Pane(f)
  listPane:SetPoint("TOPLEFT", railPane, "TOPRIGHT", 8, 0)
  listPane:SetPoint("BOTTOMRIGHT")
  f.list = UI.List(listPane, {
    rowHeight = ROW,
    groupBand = true,
    createRow = function(row, content)
      content.rightInset = CHANCE_W + 8
      O.Items.Build(content)
      row.itemFrame = content
      row.chance = UI.Text(content, "body", 12, C.muted)
      row.chance:SetPoint("RIGHT", -10, 0)
      row.chance:SetWidth(44)
      row.chance:SetJustifyH("RIGHT")
      -- (not row.bar: UI.List draws its selection stripe with that)
      row.chanceBar = UI.Bar(content, nil, 5)
      row.chanceBar:SetPoint("RIGHT", row.chance, "LEFT", -6, 0)
      row.chanceBar:SetWidth(CHANCE_W - 60)
    end,
    updateRow = function(row, it)
      local you = O.Items.ForYou(it.item)
      local extra = ""
      if you and not you.ok then extra = " · " .. UI.Code(C.bad) .. you.why .. "|r"
      elseif you and you.later then extra = " · " .. UI.Code(C.warn) .. "you can use it at " .. you.later .. "|r"
      elseif you then extra = " · " .. UI.Code(C.good) .. "for you|r" end
      if O.Wants and O.Wants:Has(it.item) then extra = extra .. " · " .. O.ICON.star .. UI.Code(C.gold) .. " wanted|r" end
      O.Items.Fill(row.itemFrame, it.item, extra)
      row.itemFrame:SetAlpha(you and not you.ok and .5 or 1)
      local chance = it.npc and O.Loot.Chance(it.npc, it.item)
      row.chance:SetText(it.npc and O.Loot.ChanceText(chance) or "")
      row.chanceBar:SetShown(chance ~= nil)
      if chance then row.chanceBar:SetProgress(math.min(100, chance * 2), 100) end
    end,
    onClick = function(it, _, button)
      if button == "RightButton" then return O.Wants:Toggle(it.item) end
      if IsShiftKeyDown() then
        local link = select(2, (C_Item and C_Item.GetItemInfo or GetItemInfo)(it.item))
        if link and ChatEdit_InsertLink then ChatEdit_InsertLink(link) end
        return
      end
      if IsControlKeyDown() then
        local link = select(2, (C_Item and C_Item.GetItemInfo or GetItemInfo)(it.item))
        if link and DressUpItemLink then DressUpItemLink(link) end
        return
      end
      O.Inspector:Show("item", it.item)
    end,
    onEnter = function(row, it)
      GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
      GameTooltip:SetItemByID(it.item)
      GameTooltip:AddLine(O.Wants:Has(it.item) and "Right-click: no longer wanted" or "Right-click: want it", .66, .63, .54)
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

function D:FillLoot()
  local f = self.loot
  local key = O.db.selected
  if not (f and key) then return end
  local rail = railRows(key)
  f.rail:SetData(rail)
  for _, b in ipairs(rail) do
    if (state.boss == "all" and b.all) or (state.boss == "trash" and b.trash) or (b.npc and b.npc == state.boss) then f.rail:Select(b) end
  end
  local rows = D.LootRows(key)
  f.list:SetData(rows)
  f.empty:SetShown(#rows == 0)
  f.empty:SetText(#((Core.DB:Instance(key) or {}).bosses or {}) == 0 and "No loot known yet for this instance."
    or "Nothing here with these filters.")
  self.lootCount = 0
  for _, r in ipairs(rows) do if not r.group then self.lootCount = self.lootCount + 1 end end
end

-------------------------------------------------------------------------------------------
-- The page
-------------------------------------------------------------------------------------------

local function factsLine(e)
  local parts = { UI.Code(O.Model.LevelColor(e)) .. "Level " .. O.Model.LevelText(e) .. "|r" }
  if e.size then parts[#parts + 1] = e.size .. " players" end
  if e.zone then
    local where = e.zone
    if e.entrance then where = where .. string.format(" (%s, %s)", e.entrance.x, e.entrance.y) end
    parts[#parts + 1] = where
  end
  parts[#parts + 1] = e.bosses == 1 and "1 boss" or (e.bosses .. " bosses")
  return table.concat(parts, "  ·  ")
end

local function badgesLine(e)
  local parts = {}
  for _, f in ipairs(O.Info and O.Info.Facts and O.Info.Facts(e) or {}) do
    local label, text, gap = f[1], f[2], f[3]
    if not gap and (label == "Keys" or label == "Attunement" or label == "Lockout" or label == "Your lockout") and text and text ~= "None" then
      parts[#parts + 1] = label .. ": " .. UI.Code(C.text) .. text .. "|r"
    end
  end
  local wants = O.Wants and O.Wants:In(e.key) or 0
  if wants > 0 then parts[#parts + 1] = O.ICON.star .. " " .. UI.Code(C.gold) .. wants .. (wants == 1 and " of your wants drops here" or " of your wants drop here") .. "|r" end
  return #parts > 0 and table.concat(parts, "   ") or nil
end

function D:Build(page, win)
  self.page, self.win = page, win
  self.views = O.Shell:Views(VIEWS, function(key) D:ShowView(key) end)
  win.tabs = self.views                          -- the old panes count and pick tabs through this
  local content = page.content
  self.loot = buildLoot(content)
  self.map = O.MapPanel.New(content)
  self.map:SetAllPoints()
  self.ready = O.ReadyCheck:Build(content)
  -- Oracle 0.12's Info pane, hosted
  self.legacy = {}
  for _, key in ipairs({ "info" }) do
    local p = O.Window.panes[key]
    if p then
      local frame = CreateFrame("Frame", nil, content)
      frame:SetAllPoints()
      p.frame = frame
      p.build(frame)
      frame:Hide()
      self.legacy[key] = p
    end
  end
  -- the filters, on the views' row
  self.tools = CreateFrame("Frame", nil, page.tools)
  self.tools:SetAllPoints()
  self.forMe = UI.Chip(self.tools, "For me", nil, function(on) state.forMe = on D:FillLoot() end)
  self.forMe:SetPoint("RIGHT", -110, 0)
  self.uncommon = UI.Chip(self.tools, "Uncommon+", nil, function(on) state.uncommon = on D:FillLoot() end)
  self.uncommon:SetPoint("LEFT", self.forMe, "RIGHT", 6, 0)
  self:Hide()
end

function D:ShowView(view)
  view = view or O.db.view or "loot"
  O.db.view = view
  self.view = view
  self.views:Select(view, true)
  self.loot:SetShown(view == "loot")
  self.map:SetShown(view == "map")
  self.ready:SetShown(view == "quests")
  for key, p in pairs(self.legacy) do p.frame:SetShown(view == key) end
  self.tools:SetShown(view == "loot")
  local e = O.Model:Get(O.db.selected)
  if not e then return end
  if view == "loot" then self:FillLoot()
  elseif view == "map" then O.MapPanel:Draw(self.map, e.key)
  elseif view == "quests" then O.ReadyCheck:Fill(e.key)
  elseif self.legacy[view] then self.legacy[view].fill(self.legacy[view].frame, e) end
  if O.MapEdit and O.MapEdit.active and view ~= "map" then O.MapEdit:SetActive(false) end
end

---Draws the map panel (the old Window:DrawMap, for the game map and its editor).
function D:DrawMap(key)
  key = key or O.db.selected
  if not (self.map and key) then return false end
  return O.MapPanel:Draw(self.map, key)
end

---Goes to an instance: { key, view, boss }.
function D:Go(where)
  local key = where.key or O.db.selected or O.CurrentInstance() or (O.Model:All()[1] or {}).key
  local e = O.Model:Get(key) or O.Model:All()[1]
  if not e then return end
  local changed = e.key ~= O.db.selected
  O.db.selected = e.key
  O.db.raids = e.raid or nil
  if changed then state.boss = "all" end
  if where.boss then state.boss = where.boss end
  O.Shell:SetHeader(e.name, factsLine(e), badgesLine(e))
  local loot = 0
  for _, b in ipairs(e.inst.bosses or {}) do loot = loot + #(b.loot or {}) end
  self.views:SetCount("loot", loot)
  local ready = O.QuestBook and O.QuestBook.Ready(e.key)
  self.views:SetCount("quests", ready and (ready.counts.total) or e.quests)
  local view = where.view or (O.MapEdit and O.MapEdit.active and "map") or O.db.view or "loot"
  self:ShowView(view)
  O:Send("SELECTED", e.key)
end

function D:Show()
  self.views:Show()
  self.page.content:Show()
  self.page.title:Show()
  if self.seg then self.seg:Show() end
  self:Go({})
end

function D:Hide()
  self.views:Hide()
  self.loot:Hide()
  self.map:Hide()
  self.ready:Hide()
  self.tools:Hide()
  for _, p in pairs(self.legacy or {}) do p.frame:Hide() end
  if self.seg then self.seg:Hide() end
end

-- a boss clicked on the map: it shows in the Inspector (with "Its loot") and the map stays; the
-- map editor uses the same click to pick a boss to place
O:Listen("FOCUS", "dungeons", function(_, npc)
  if O.Shell.current ~= "dungeons" then return end
  state.boss = npc
  if D.view == "map" then
    if not (O.MapEdit and O.MapEdit.active) and type(npc) == "number" then O.Inspector:Show("npc", npc) end
    return
  end
  D:ShowView("loot")
end)
O:Listen("ITEMS_LOADED", "dungeons", function()
  if D.loot and D.loot:IsVisible() then D.loot.list:Refresh() end
end)

O.Shell:AddSpace("dungeons", D)
