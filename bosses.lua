-- The Bosses tab (mockup renderBosses): the bosses in route order, numbered as on the map (the
-- final boss's ring orange, missing data dashed), then the ones the map doesn't place, lettered.
-- Each row: the name, a rank badge, "Level N · M drops", and the top three gear drops.
-- Hovering a row lights its node on the map and back; clicking one opens its loot.

local Core = NorgannonCore
local DB = NorgannonDB
local O = Oracle
if O.disabled then return end
local UI = Core.UI
local C = UI.C

local Bosses = {}
O.Bosses = Bosses

local VIOLET, ORANGE, MISSING = UI.Hex("b48cff"), UI.Hex("ff8a3d"), UI.Hex("8a7d62")
-- rank: label and badge colours (mockup RANK and .badge.rare / .badge.boss)
local RANK = {
  [1] = { "Elite" },
  [2] = { "Rare elite", UI.Hex("c9c9ff"), UI.Hex("6a6aa8") },
  [3] = { "Boss", UI.Hex("ffb37a"), UI.Hex("8a5530") },
  [4] = { "Rare", UI.Hex("c9c9ff"), UI.Hex("6a6aa8") },
}
Bosses.RANK = RANK

---An instance's bosses as the tab lists them: the map's numbered nodes in route order, then the
---unplaced ones lettered (every boss numbered in order when the instance has no map).
function Bosses.Rows(key)
  local rows = {}
  local legend = O.Schematic.Legend(key)
  local inst = Core.DB:Instance(key)
  local lootOf = {}
  -- a boss without a creature id (known by name only) is keyed by its name
  local function keyOf(b) return b.id or b.name end
  for _, b in ipairs(inst and inst.bosses or {}) do lootOf[keyOf(b)] = b.loot or {} end
  local function add(row)
    local npc = type(row.npc) == "number" and DB:Get("npcs", row.npc) or nil
    row.level = npc and (npc.maxLevel or npc.minLevel)
    row.rank = npc and npc.rank
    row.loot = lootOf[row.npc] or {}
    row.name = row.label or (type(row.npc) == "number" and Core.DB:Name("npcs", row.npc)) or tostring(row.npc)
    rows[#rows + 1] = row
  end
  if legend then
    for _, n in ipairs(legend.nodes) do
      if n.npc then add({ npc = n.npc, num = tostring(n.num), final = n.final, missing = n.missing, note = n.note, label = n.label }) end
    end
    for _, x in ipairs(legend.extra) do add({ npc = x.npc, num = x.letter, unplaced = true }) end
  else
    for i, b in ipairs(inst and inst.bosses or {}) do add({ npc = keyOf(b), num = tostring(i) }) end
  end
  return rows
end

---The top gear a boss drops (weapons and armour), at most n names.
function Bosses.TopGear(row, n)
  local out = {}
  for _, id in ipairs(row.loot) do
    local cls = (DB:Get("items", id) or {}).class
    if cls == 2 or cls == 4 then
      out[#out + 1] = Core.DB:Name("items", id) or ("Item " .. id)
      if #out >= n then break end
    end
  end
  return out
end

-------------------------------------------------------------------------------------------
-- The pane
-------------------------------------------------------------------------------------------

local pane, area, frames = nil, nil, {}

local function badge(parent)
  local b = CreateFrame("Frame", nil, parent)
  b:SetHeight(15)
  b.box = UI.Box(b, "BACKGROUND", 0)
  b.text = UI.Text(b, "body", 11, C.muted)
  b.text:SetPoint("CENTER", 0, 0)
  function b:Set(rank)
    local r = RANK[rank]
    if not r then self:Hide() return end
    self.text:SetText(string.upper(r[1]))
    local fg, line = r[2] or C.muted, r[3] or C.lineStrong
    self.text:SetTextColor(fg[1], fg[2], fg[3])
    self.box:Set(line, C.inset)
    self:SetWidth(math.floor(self.text:GetStringWidth() + 10))
    self:Show()
  end
  return b
end

local function newRow()
  local f = CreateFrame("Button", nil, area.content)
  f.bg = UI.Round(f, "BACKGROUND", 0, 4)
  f.line = UI.Round(f, "BACKGROUND", 1, 4, "line")
  -- the numbered ring (26, violet; orange for the final boss; dashed for missing data)
  f.ring = f:CreateTexture(nil, "ARTWORK")
  f.ring:SetTexture(UI.TEX.ring)
  f.ring:SetSize(26, 26)
  f.ring:SetPoint("TOPLEFT", 10, -8)
  f.dashes = {}
  for i = 1, 10 do
    local d = f:CreateTexture(nil, "ARTWORK")
    d:SetTexture(UI.TEX.circle)
    d:SetSize(3, 3)
    f.dashes[i] = d
  end
  f.num = UI.Text(f, "title", 13, C.text)
  f.num:SetPoint("CENTER", f.ring, "CENTER", 0, 0)
  f.num:SetJustifyH("CENTER")
  f.name = UI.Text(f, "title", 15, C.text)
  f.name:SetPoint("TOPLEFT", f.ring, "TOPRIGHT", 10, -1)
  f.badge = badge(f)
  f.badge:SetPoint("LEFT", f.name, "RIGHT", 6, 1)
  f.sub = UI.Text(f, "body", 12, C.muted)
  f.sub:SetPoint("TOPLEFT", f.name, "BOTTOMLEFT", 0, -2)
  f.drops = UI.Text(f, "body", 12, C.faint)
  f.drops:SetPoint("TOPLEFT", f.sub, "BOTTOMLEFT", 0, -2)
  f:SetScript("OnEnter", function(self) O.Schematic:SetHot(self.row.npc) Bosses:Paint(self.row.npc) end)
  f:SetScript("OnLeave", function() O.Schematic:SetHot(nil) Bosses:Paint(nil) end)
  f:SetScript("OnClick", function(self) O:Send("FOCUS", self.row.npc) end)
  return f
end

-- a row lit (hovered here or on the map): violet tint and outline (mockup .boss.hot)
function Bosses:Paint(hot)
  for _, f in ipairs(frames) do
    if f:IsShown() and f.row then
      local on = hot ~= nil and f.row.npc == hot
      f.bg:SetColor(VIOLET, on and .08 or 0)
      f.line:SetColor(VIOLET, on and .25 or 0)
    end
  end
end

local function fillRow(f, row, width)
  f.row = row
  local ring = row.final and ORANGE or VIOLET
  for _, d in ipairs(f.dashes) do d:Hide() end
  if row.missing then
    f.ring:Hide()
    for i, d in ipairs(f.dashes) do
      local a = (i - 1) / #f.dashes * math.pi * 2
      d:ClearAllPoints()
      d:SetPoint("CENTER", f.ring, "CENTER", math.cos(a) * 12, math.sin(a) * 12)
      d:SetVertexColor(MISSING[1], MISSING[2], MISSING[3], 1)
      d:Show()
    end
  else
    f.ring:SetVertexColor(ring[1], ring[2], ring[3], 1)
    f.ring:Show()
  end
  f.num:SetText(row.num)
  f.name:SetText(row.name)
  f.badge:Set(row.rank)
  local sub
  if row.missing then
    sub = "Boss data missing from NorgannonDB"
  else
    local drops = #row.loot == 1 and "1 drop" or (#row.loot .. " drops")
    sub = (row.level and ("Level " .. row.level .. " · ") or "") .. drops
  end
  if row.unplaced then sub = sub .. " · not on the map" end
  if row.note then sub = sub .. " · " .. row.note end
  f.sub:SetText(sub)
  local top = Bosses.TopGear(row, 3)
  f.drops:SetText(table.concat(top, ", "))
  f.drops:SetShown(#top > 0)
  f.drops:SetWidth(width - 56)
  f:SetWidth(width)
  local height = 8 + 18 + 2 + 14 + (#top > 0 and (2 + 14) or 0) + 8
  f:SetHeight(height)
  return height
end

local function build(frame)
  pane = frame
  area = UI.ScrollArea(pane)
  area:SetAllPoints()
  Bosses.area = area
end

local function fill(_, e)
  local rows = Bosses.Rows(e.key)
  local width = (pane:GetWidth() or 392)
  if width < 50 then width = 392 end
  area.content:SetWidth(width)
  local y = -2
  for i, row in ipairs(rows) do
    local f = frames[i] or newRow()
    frames[i] = f
    local h = fillRow(f, row, width - 2)
    f:ClearAllPoints()
    f:SetPoint("TOPLEFT", area.content, "TOPLEFT", 0, y)
    f:Show()
    y = y - h - 2
  end
  for i = #rows + 1, #frames do frames[i]:Hide() frames[i].row = nil end
  area.content:SetHeight(-y)
  area:SetVerticalScroll(0)
  Bosses.shown = rows
  Bosses:Paint(O.Schematic.hot)
end

---The row frame for a boss (the harness and the map's hover use it).
function Bosses:FrameFor(npc)
  for _, f in ipairs(frames) do
    if f:IsShown() and f.row and f.row.npc == npc then return f end
  end
end

O:Listen("HOT", "bosses", function(_, key) if pane and pane:IsShown() then Bosses:Paint(key) end end)
O.Window:RegisterPane("bosses", build, fill)
