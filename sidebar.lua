-- The sidebar (mockup .side): search over instances, bosses and loot; Dungeons / Raids / Zones /
-- Crafts; Sort Level / Name / Continent; and the list: each instance's name, "zone · N bosses"
-- and its level range in your difficulty colour. Under Crafts: the professions with your skill,
-- and the search finds recipes (crafts.lua).

local Core = NorgannonCore
local O = Oracle
if O.disabled then return end
local UI = Core.UI
local C = UI.C

local Sidebar = {}
O.Sidebar = Sidebar

local CATEGORIES = {
  { key = "dungeons", label = "Dungeons" }, { key = "raids", label = "Raids" },
  { key = "zones", label = "Zones" }, { key = "crafts", label = "Crafts" },
}
local SORTS = { { "level", "Level" }, { "name", "Name" }, { "continent", "Continent" } }
local ROW = 38

local side, search, seg, list, emptyText
local query = ""

local function accent() return UI.Accent("oracle") end

-------------------------------------------------------------------------------------------
-- Dungeons / Raids / Zones / Crafts: four equal cells in one rounded box (mockup .seg)
-------------------------------------------------------------------------------------------

local function segmented(parent, onSelect)
  local f = CreateFrame("Frame", nil, parent)
  f:SetHeight(26)
  f.fill = UI.Round(f, "BACKGROUND", 0, 4)
  f.fill:SetColor(C.inset, 1)
  f.cells = {}
  for i, cat in ipairs(CATEGORIES) do
    local b = CreateFrame("Button", nil, f)
    b.key, b.later = cat.key, cat.later
    -- the selected cell's fill: rounded where it meets the box's corners
    b.on = UI.Round(b, "BACKGROUND", 1, 3)
    b.label = UI.Text(b, "body", 13, C.muted)
    b.label:SetPoint("CENTER", 0, 0)
    b.label:SetJustifyH("CENTER")
    b.label:SetText(cat.label)
    if i > 1 then
      b.divider = UI.Tex(b, "BORDER", 0, C.lineStrong)
      b.divider:SetWidth(1)
      b.divider:SetPoint("TOPLEFT")
      b.divider:SetPoint("BOTTOMLEFT")
    end
    b:SetScript("OnClick", function(self)
      if self.later then return end
      f:Select(self.key)
    end)
    b:SetScript("OnEnter", function(self)
      if self.later then
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:AddLine(cat.label, 1, 1, 1)
        GameTooltip:AddLine("Coming in Phase B", C.faint[1], C.faint[2], C.faint[3])
        GameTooltip:Show()
      elseif f.selected ~= self.key then
        self.label:SetTextColor(C.text[1], C.text[2], C.text[3])
      end
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() f:Paint() end)
    f.cells[i] = b
  end
  f.outline = UI.Round(f, "OVERLAY", 0, 4, "line")
  f.outline:SetColor(C.lineStrong, 1)

  function f:Layout()
    local w = (self:GetWidth() or 0) / #self.cells
    for i, b in ipairs(self.cells) do
      b:ClearAllPoints()
      b:SetPoint("TOPLEFT", (i - 1) * w, 0)
      b:SetPoint("BOTTOMLEFT", (i - 1) * w, 0)
      b:SetWidth(w)
    end
  end
  function f:Paint()
    local a = accent()
    for _, b in ipairs(self.cells) do
      local on = b.key == self.selected
      b.on:SetShown(on)
      b.on:SetColor(UI.Mix(C.inset, a, .26), 1)
      local c = b.later and C.faint or (on and { 1, 1, 1 } or C.muted)
      b.label:SetTextColor(c[1], c[2], c[3])
    end
  end
  function f:Select(key, silent)
    self.selected = key
    self:Paint()
    if not silent and onSelect then onSelect(key) end
  end
  f:SetScript("OnSizeChanged", function(self) self:Layout() end)
  return f
end

-------------------------------------------------------------------------------------------
-- The list
-------------------------------------------------------------------------------------------

local function rows()
  if O.db.category == "zones" and O.Zones then return O.Zones:Entries() end
  if O.db.category == "crafts" and O.Crafts then
    local out = {}
    for _, e in ipairs(O.Crafts:Entries()) do
      if not e.matches or e.matches > 0 then out[#out + 1] = e end
    end
    return out
  end
  local out = {}
  local raids = O.db.category == "raids"
  for _, e in ipairs(O.Model:All()) do
    if e.raid == raids and O.Model.Matches(e, query) then out[#out + 1] = e end
  end
  local sort = O.db.sort
  if sort == "name" then
    table.sort(out, function(a, b) return a.name < b.name end)
  elseif sort == "continent" then
    table.sort(out, function(a, b)
      local ca, cb = a.continent or "~", b.continent or "~"
      if ca ~= cb then return ca < cb end
      local la, lb = (a.levels or a.bossLevels or { min = 99 }).min, (b.levels or b.bossLevels or { min = 99 }).min
      if la ~= lb then return la < lb end
      return a.name < b.name
    end)
    local grouped, last = {}, nil
    for _, e in ipairs(out) do
      local group = e.continent or (e.forever and "WoW Forever" or "Other")
      if group ~= last then
        grouped[#grouped + 1] = { group = group }
        last = group
      end
      grouped[#grouped + 1] = e
    end
    out = grouped
  end
  return out
end
Sidebar.Rows = rows

function Sidebar:Refresh()
  if not list then return end
  local items = rows()
  list:SetData(items, true)
  local selected = O.Model:Get(O.db.selected)
  if O.db.category == "crafts" and O.Crafts then selected = O.Crafts:Entry(O.db.craft) end
  if O.db.category == "zones" and O.Zones then selected = O.db.zone and O.Zones:Entry(O.db.zone) end
  list:Select(selected)
  local any = false
  for _, item in ipairs(items) do if not item.group then any = true break end end
  emptyText:SetShown(not any)
  if not any then
    local what = O.db.category == "crafts" and "No recipe matches" or (O.db.category == "zones" and "No zone matches" or "No instance matches")
    emptyText:SetText(string.format("%s \"%s\".", what, query))
  end
end

function Sidebar:SetSelected(key)
  if not list then return end
  local zone = type(key) == "string" and key:match("^zone:(%d+)$")
  if zone then
    if O.db.category ~= "zones" then
      O.db.category = "zones"
      seg:Select("zones", true)
      Sidebar:Placeholder()
      self:Refresh()
    end
    local e = O.Zones:Entry(tonumber(zone))
    list:Select(e)
    for i, item in ipairs(list.items) do
      if item == e then list:ScrollToIndex(i) break end
    end
    return
  end
  local craft = type(key) == "string" and key:match("^craft:(%d+)$")
  if craft then
    if O.db.category ~= "crafts" then
      O.db.category = "crafts"
      seg:Select("crafts", true)
      Sidebar:Placeholder()
      self:Refresh()
    end
    local e = O.Crafts:Entry(tonumber(craft))
    list:Select(e)
    return
  end
  local e = O.Model:Get(key)
  if e and (O.db.category == "crafts" or O.db.category == "zones" or e.raid ~= (O.db.category == "raids")) then
    O.db.category = e.raid and "raids" or "dungeons"
    seg:Select(O.db.category, true)
    Sidebar:Placeholder()
    self:Refresh()
  end
  list:Select(e)
  for i, item in ipairs(list.items) do
    if item == e then list:ScrollToIndex(i) break end
  end
end

function Sidebar:Build(parent)
  side = parent

  search = UI.Search(side, "Search instances, bosses, loot…", function(text)
    query = text or ""
    if O.Crafts then O.Crafts:SetQuery(query) end
    if O.Zones then O.Zones:SetQuery(query) end
    Sidebar:Refresh()
  end)
  search:ApplyAccent(accent())
  search:SetPoint("TOPLEFT")
  search:SetPoint("TOPRIGHT")
  Sidebar.search = search

  seg = segmented(side, function(key)
    O.db.category = key
    Sidebar:Placeholder()
    if key == "crafts" then
      Sidebar:Refresh()
      return O.Crafts:Select(O.db.craft or Sidebar.FirstCraft())
    end
    if key == "zones" then
      Sidebar:Refresh()
      return O.Zones:Select(O.db.zone or Sidebar.HereZone())
    end
    Sidebar:Refresh()
    local first
    for _, item in ipairs(list.items) do if not item.group then first = item break end end
    if first then O.Window:Select(first.key) end
  end)
  seg:SetPoint("TOPLEFT", search, "BOTTOMLEFT", 0, -8)
  seg:SetPoint("TOPRIGHT", search, "BOTTOMRIGHT", 0, -8)
  seg:Select(O.db.category, true)
  Sidebar.segmented = seg

  -- "Sort  Level  Name  Continent"
  local sortRow = CreateFrame("Frame", nil, side)
  sortRow:SetHeight(20)
  sortRow:SetPoint("TOPLEFT", seg, "BOTTOMLEFT", 0, -8)
  sortRow:SetPoint("TOPRIGHT", seg, "BOTTOMRIGHT", 0, -8)
  sortRow.label = UI.Text(sortRow, "body", 12, C.faint)
  sortRow.label:SetPoint("LEFT", 0, 0)
  sortRow.label:SetText("Sort")
  sortRow.chips = {}
  local previous = sortRow.label
  for _, s in ipairs(SORTS) do
    local chip = UI.Chip(sortRow, s[2], nil)
    chip.label:SetFontObject(UI.Font("body", 12))
    chip:SetHeight(18)
    chip:SetWidth(math.floor(chip.label:GetStringWidth() + 18))
    chip:ApplyAccent(accent())
    chip:SetPoint("LEFT", previous, "RIGHT", 6, 0)
    chip.key = s[1]
    chip:SetScript("OnClick", function(self)
      O.db.sort = self.key
      for _, c in ipairs(sortRow.chips) do c:SetOn(c.key == O.db.sort, true) end
      Sidebar:Refresh()
    end)
    chip:SetOn(O.db.sort == s[1], true)
    sortRow.chips[#sortRow.chips + 1] = chip
    previous = chip
  end
  Sidebar.sortRow = sortRow

  -- the list, in an inset pane
  local pane = UI.Pane(side)
  pane:SetPoint("TOPLEFT", sortRow, "BOTTOMLEFT", 0, -8)
  pane:SetPoint("BOTTOMRIGHT", 0, 0)
  list = UI.List(pane, {
    rowHeight = ROW,
    createRow = function(row, content)
      row.name = UI.Text(content, "body", 14, C.text)
      row.name:SetPoint("TOPLEFT", 12, -5)
      row.name:SetPoint("TOPRIGHT", content, "TOPRIGHT", -52, -5)
      row.meta = UI.Text(content, "body", 12, C.faint)
      row.meta:SetPoint("TOPLEFT", row.name, "BOTTOMLEFT", 0, -1)
      row.meta:SetPoint("TOPRIGHT", row.name, "BOTTOMRIGHT", 0, -1)
      row.levels = UI.Text(content, "body", 13)
      row.levels:SetPoint("RIGHT", -10, 0)
      row.levels:SetJustifyH("RIGHT")
    end,
    updateRow = function(row, e)
      row.name:SetText(e.name)
      if e.isZone then
        row.meta:SetText(string.format("%s · %d quests", e.continent or "", e.quests or 0))
        row.levels:SetText(e.levels and O.Model.LevelText(e) or "–")
        local c = O.Model.LevelColor(e)
        row.levels:SetTextColor(c[1], c[2], c[3])
        return
      end
      if e.craft then
        local count = e.matches and string.format("%d of %d recipes match", e.matches, e.count) or (e.count .. " recipes")
        row.meta:SetText(count)
        row.levels:SetText(e.skill and tostring(e.skill) or "–")
        local c = e.skill and C.gold or C.faint
        row.levels:SetTextColor(c[1], c[2], c[3])
        return
      end
      local where = e.zone or "Unknown"
      local count = e.bosses == 1 and "1 boss" or (e.bosses .. " bosses")
      if e.forever and e.bosses == 0 then count = "being mapped" end
      row.meta:SetText(where .. " · " .. count)
      row.levels:SetText(O.Model.LevelText(e))
      local c = O.Model.LevelColor(e)
      row.levels:SetTextColor(c[1], c[2], c[3])
    end,
    onClick = function(e)
      if e.craft then return O.Crafts:Select(e.craft) end
      if e.isZone then return O.Zones:Select(e.zone) end
      O.Window:Select(e.key)
    end,
  })
  list:SetPoint("TOPLEFT", 1, -5)
  list:SetPoint("BOTTOMRIGHT", -1, 4)
  list:ApplyAccent(accent())
  Sidebar.list = list
  emptyText = UI.Text(pane, "body", 13, C.faint)
  emptyText:SetPoint("TOPLEFT", 12, -12)
  emptyText:SetPoint("TOPRIGHT", -12, -12)
  emptyText:SetWordWrap(true)
  emptyText:Hide()
  Sidebar:Placeholder()
  Sidebar:Refresh()
end

---The search's hint for the category shown.
function Sidebar:Placeholder()
  if search and search.placeholder then
    local hints = { crafts = "Search recipes…", zones = "Search zones…" }
    search.placeholder:SetText(hints[O.db.category] or "Search instances, bosses, loot…")
  end
end

---The zone you're in (its area id), for the first look at Zones.
function Sidebar.HereZone()
  local uiMap = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
  return uiMap and Core.Map.UiMapToArea(uiMap)
end

---The profession to show first: one you have, else the first.
function Sidebar.FirstCraft()
  local entries = O.Crafts:Entries()
  for _, e in ipairs(entries) do if e.skill then return e.craft end end
  return entries[1] and entries[1].craft
end
