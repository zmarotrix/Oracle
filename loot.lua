-- The Loot tab (mockup renderLoot): a boss dropdown ("All bosses" or one), Gear / Quest items /
-- Other chips, then each boss's own loot under its name: the item row and, on the right, its
-- drop chance with a thin violet bar ("chance ?" when NorgannonDB doesn't know it yet).
-- Clicking a boss on the map or in the Bosses tab opens its loot here.

local Core = NorgannonCore
local DB = NorgannonDB
local O = Oracle
if O.disabled then return end
local UI = Core.UI
local C = UI.C

local Loot = {}
O.Loot = Loot

local VIOLET = UI.Hex("b48cff")
local ROW = 40
local CHANCE_W = 70
local KINDS = { { "gear", "Gear" }, { "quest", "Quest items" }, { "other", "Other" } }

local state = { boss = "all", kinds = { gear = true, quest = true, other = false } }
Loot.state = state

---An item's drop chance from a boss (percent), or nil when unknown.
function Loot.Chance(npc, item)
  if type(npc) ~= "number" then return nil end
  local record = DB:Get("npcs", npc)
  local c = record and record.drops and record.drops[item]
  if type(c) == "number" and c > 0 then return c end
end

local function chanceText(c)
  if not c then return "chance ?" end
  if c >= 10 then return string.format("%d%%", math.floor(c + .5)) end
  return (string.format("%.1f", c):gsub("%.0$", "")) .. "%"
end
Loot.ChanceText = chanceText

---The rows the list shows: { group = boss name } headers and { npc, item } rows, filtered.
function Loot.Rows(key)
  local out = {}
  for _, row in ipairs(O.Bosses.Rows(key)) do
    if state.boss == "all" or state.boss == row.npc then
      local items = {}
      for _, id in ipairs(row.loot) do
        if state.kinds[O.Items.Kind(id)] then items[#items + 1] = { npc = row.npc, item = id } end
      end
      if #items > 0 then
        out[#out + 1] = { group = row.name }
        for _, it in ipairs(items) do out[#out + 1] = it end
      end
    end
  end
  -- what the instance's ordinary enemies drop
  local inst = Core.DB:Instance(key)
  if state.boss == "all" and inst and inst.trash then
    local items = {}
    for _, id in ipairs(inst.trash) do
      if state.kinds[O.Items.Kind(id)] then items[#items + 1] = { item = id, trash = true } end
    end
    if #items > 0 then
      out[#out + 1] = { group = "Trash" }
      for _, it in ipairs(items) do out[#out + 1] = it end
    end
  end
  return out
end

-------------------------------------------------------------------------------------------
-- The pane
-------------------------------------------------------------------------------------------

local pane, dropdown, chips, list, empty

local function refresh()
  if not list then return end
  local key = O.db.selected
  if not key then return end
  local options = { { "all", "All bosses" } }
  for _, row in ipairs(O.Bosses.Rows(key)) do options[#options + 1] = { row.npc, row.name } end
  dropdown.options = options
  local valid = state.boss == "all"
  for _, o in ipairs(options) do if o[1] == state.boss then valid = true end end
  if not valid then state.boss = "all" end
  dropdown:SetValue(state.boss, true)
  for _, chip in ipairs(chips) do chip:SetOn(state.kinds[chip.key], true) end
  local rows = Loot.Rows(key)
  list:SetData(rows)
  empty:SetShown(#rows == 0)
  Loot.rows = rows
end
Loot.Refresh = refresh

local function build(frame)
  pane = frame
  local bar = CreateFrame("Frame", nil, pane)
  bar:SetHeight(26)
  bar:SetPoint("TOPLEFT", 4, -4)
  bar:SetPoint("TOPRIGHT", -4, -4)
  dropdown = UI.Dropdown(bar, { { "all", "All bosses" } }, function(value)
    state.boss = value
    refresh()
  end)
  dropdown:SetWidth(170)
  dropdown:SetPoint("LEFT", 0, 0)
  chips = {}
  local previous = dropdown
  for _, k in ipairs(KINDS) do
    local chip = UI.Chip(bar, k[2], nil)
    chip.label:SetFontObject(UI.Font("body", 12))
    chip:SetHeight(20)
    chip:SetWidth(math.floor(chip.label:GetStringWidth() + 18))
    chip:ApplyAccent(VIOLET)
    chip:SetPoint("LEFT", previous, "RIGHT", 6, 0)
    chip.key = k[1]
    chip:SetScript("OnClick", function(self)
      state.kinds[self.key] = not state.kinds[self.key]
      refresh()
    end)
    chips[#chips + 1] = chip
    previous = chip
  end
  Loot.dropdown, Loot.chips = dropdown, chips

  list = UI.List(pane, {
    rowHeight = ROW,
    createRow = function(row, content)
      -- the item parts go on the content frame, which the list hides on boss-name rows
      content.rightInset = CHANCE_W + 12
      O.Items.Build(content)
      row.item = content
      row.chance = UI.Text(content, "body", 12, C.muted)
      row.chance:SetPoint("TOPRIGHT", content, "RIGHT", -8, 10)
      row.chance:SetJustifyH("RIGHT")
      row.chanceBar = CreateFrame("Frame", nil, content)
      row.chanceBar:SetSize(CHANCE_W - 8, 3)
      row.chanceBar:SetPoint("TOPRIGHT", row.chance, "BOTTOMRIGHT", 0, -3)
      row.chanceBar.track = UI.Pill(row.chanceBar, 3, "BACKGROUND", 0)
      row.chanceBar.track:SetColor(UI.Hex("2a2235"), 1)
      row.chanceBar.fillFrame = CreateFrame("Frame", nil, row.chanceBar)
      row.chanceBar.fillFrame:SetPoint("TOPLEFT")
      row.chanceBar.fillFrame:SetPoint("BOTTOMLEFT")
      row.chanceBar.fill = UI.Pill(row.chanceBar.fillFrame, 3, "ARTWORK", 0)
      row.chanceBar.fill:SetColor(VIOLET, 1)
      row.groupLabel:SetFontObject(UI.Font("title", 12))
      row.groupLabel:SetTextColor(C.faint[1], C.faint[2], C.faint[3])
      O.Items.Hook(row)
    end,
    updateRow = function(row, it)
      local info = O.Items.Fill(row.item, it.item)
      row.itemId, row.itemLink = it.item, info.link
      local c = Loot.Chance(it.npc, it.item)
      row.chance:SetText(chanceText(c))
      local w = (CHANCE_W - 8) * math.min(100, c or 0) / 100
      row.chanceBar.fillFrame:SetWidth(math.max(.01, w))
      row.chanceBar.fillFrame:SetShown(w >= 1)
    end,
  })
  list:SetPoint("TOPLEFT", bar, "BOTTOMLEFT", -4, -6)
  list:SetPoint("BOTTOMRIGHT", pane, "BOTTOMRIGHT", 0, 0)
  list:ApplyAccent(VIOLET)
  Loot.list = list
  empty = UI.Text(pane, "body", 13, C.faint)
  empty:SetPoint("TOPLEFT", bar, "BOTTOMLEFT", 6, -12)
  empty:SetText("Nothing here with these filters.")
  empty:Hide()
end

local function fill() refresh() end

-- a boss clicked on the map or in the Bosses tab: its loot
O:Listen("FOCUS", "loot", function(_, npc)
  state.boss = npc
  if O.Window.frame and O.Window.frame.tabs then O.Window.frame.tabs:Select("loot") end
end)
-- another instance: back to every boss
O:Listen("SELECTED", "loot", function() state.boss = "all" end)
O:Listen("ITEMS_LOADED", "loot", function() if list and pane:IsShown() then list:Refresh() end end)

O.Window:RegisterPane("loot", build, fill)
