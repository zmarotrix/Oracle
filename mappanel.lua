-- The map panel: the near-black panel with the faint violet grid and inner shadow that the game map
-- (realmap.lua) and the schematic (schematic.lua) draw on, with View's zoom and drag. Oracle shows
-- it as an instance's Map view and as the small map in the instance header.
--
--   local map = O.MapPanel.New(parent)    -- a frame; Layout() runs on resize
--   O.MapPanel:Draw(map, key)              -- the game map where there is one, the schematic over it

local Core = NorgannonCore
local O = Oracle
if O.disabled then return end
local UI = Core.UI
local C = UI.C

local MapPanel = {}
O.MapPanel = MapPanel

local GRID = 32

function MapPanel.New(parent)
  local map = CreateFrame("Frame", nil, parent)
  map:SetClipsChildren(true)
  map.bg = UI.Tex(map, "BACKGROUND", 0, { .051, .043, .071 })
  map.bg:SetAllPoints()
  -- a soft violet light in the upper middle
  map.light = map:CreateTexture(nil, "BACKGROUND", nil, 1)
  map.light:SetTexture(UI.TEX.glow)
  map.light:SetVertexColor(.706, .549, 1, .08)
  map.light:SetBlendMode("ADD")
  map.grid = {}
  -- the inner shadow: dark edges fading in 40 pixels
  local function edge(a, b, horizontal)
    local t = map:CreateTexture(nil, "BORDER", nil, 0)
    t:SetColorTexture(1, 1, 1, 1)
    t:SetPoint(a)
    t:SetPoint(b)
    if horizontal then t:SetWidth(40) else t:SetHeight(40) end
    return t
  end
  local dark, clear = CreateColor(0, 0, 0, .8), CreateColor(0, 0, 0, 0)
  map.shadeL = edge("TOPLEFT", "BOTTOMLEFT", true)
  map.shadeL:SetGradient("HORIZONTAL", dark, clear)
  map.shadeR = edge("TOPRIGHT", "BOTTOMRIGHT", true)
  map.shadeR:SetGradient("HORIZONTAL", clear, dark)
  map.shadeT = edge("TOPLEFT", "TOPRIGHT", false)
  map.shadeT:SetGradient("VERTICAL", clear, dark)
  map.shadeB = edge("BOTTOMLEFT", "BOTTOMRIGHT", false)
  map.shadeB:SetGradient("VERTICAL", dark, clear)
  map.outline = UI.Round(map, "OVERLAY", 0, 4, "line")
  map.outline:SetColor(C.line, 1)
  O.View:Attach(map)   -- the stage the game map's tiles sit on, wheel zoom and drag

  function map:Layout()
    local w, h = self:GetWidth() or 0, self:GetHeight() or 0
    self.light:ClearAllPoints()
    self.light:SetPoint("CENTER", self, "TOPLEFT", w * .5, -h * .4)
    self.light:SetSize(w * 1.3, h * 1.1)
    local n = 0
    local function line(vertical, at)
      n = n + 1
      local t = self.grid[n]
      if not t then
        t = self:CreateTexture(nil, "BACKGROUND", nil, 2)
        self.grid[n] = t
      end
      t:SetColorTexture(.706, .549, 1, .045)
      t:ClearAllPoints()
      if vertical then
        t:SetPoint("TOPLEFT", at, 0)
        t:SetPoint("BOTTOMLEFT", at, 0)
        t:SetWidth(1)
      else
        t:SetPoint("TOPLEFT", 0, -at)
        t:SetPoint("TOPRIGHT", 0, -at)
        t:SetHeight(1)
      end
      t:Show()
    end
    for x = GRID, w, GRID do line(true, x) end
    for y = GRID, h, GRID do line(false, y) end
    for i = n + 1, #self.grid do self.grid[i]:Hide() end
  end
  map:SetScript("OnSizeChanged", function(self)
    self:Layout()
    O.View:Resized()
    if self.key and self:IsVisible() then MapPanel:Draw(self, self.key) end
  end)

  -- the empty state: no game map and no schematic for this instance yet
  map.empty = CreateFrame("Frame", nil, map)
  map.empty:SetAllPoints()
  map.empty.title = UI.Text(map.empty, "title", 18, C.muted)
  map.empty.title:SetPoint("BOTTOM", map.empty, "CENTER", 0, 10)
  map.empty.title:SetJustifyH("CENTER")
  map.empty.line1 = UI.Text(map.empty, "body", 13, C.faint)
  map.empty.line1:SetPoint("TOP", map.empty.title, "BOTTOM", 0, -8)
  map.empty.line1:SetJustifyH("CENTER")
  map.empty.line2 = UI.Text(map.empty, "body", 13, C.faint)
  map.empty.line2:SetPoint("TOP", map.empty.line1, "BOTTOM", 0, -4)
  map.empty.line2:SetJustifyH("CENTER")
  return map
end

---Draws an instance on a panel: the game map when it has one and the switch says so, the
---schematic's nodes over it. Returns whether anything was drawn.
function MapPanel:Draw(map, key)
  if not (map and key) then return false end
  if key ~= map.key then O.View:Reset(true) end   -- another instance: the whole map again
  map.key = key
  local real = O.RealMap and O.RealMap:Draw(map, key) or false
  map.real = real
  local drawn = O.Schematic and O.Schematic:Draw(map, key, real) or false
  local e = O.Model:Get(key)
  map.empty:SetShown(not (real or drawn))
  if e and e.forever and e.bosses == 0 then
    map.empty.title:SetText("Not mapped yet")
    map.empty.line1:SetText("WoW Forever added " .. e.name .. "; NorgannonDB learns it from players.")
    map.empty.line2:SetText("Run it with the NorgannonDB Collector to help map it.")
  elseif e then
    map.empty.title:SetText("No map yet")
    map.empty.line1:SetText(string.format("%d bosses and %d quests are known for %s.", e.bosses, e.quests, e.name))
    map.empty.line2:SetText("Its map hasn't been drawn yet.")
  end
  return real or drawn
end

---Places the markers again for the view (zoomed or moved); the game map's tiles move by themselves.
function MapPanel:DrawMarkers(map)
  if not (map and map.key and O.Schematic) then return end
  O.Schematic:Draw(map, map.key, map.real)
  if O.MapEdit and O.MapEdit.active then O.MapEdit:Update() end
end
