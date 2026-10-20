-- The schematic map (mockup renderMap): an instance as connected nodes on the map panel.
--
--   boss              disc 34, violet ring (gold for elites, as the mockup), numbered in route order
--   final boss        disc 40, orange ring and glow (the last numbered boss)
--   missing           dashed ring: the layout names a boss NorgannonDB's instance doesn't have
--   entrance          rounded square 30, green, a down arrow
--   point of interest blue diamond 22 (key doors, ships, portals)
--
-- Nodes carry a label (and "Level N" for bosses) below; paths are dotted quadratic curves bowing
-- a little to one side; the legend sits bottom-left and the "Schematic" stamp bottom-right.
-- Hovering a node lights it (and announces ORACLE_HOT with the boss's npc id); clicking a boss
-- announces ORACLE_FOCUS.
--
-- Layouts (data/layouts.lua) place nodes at x, y in 0-100 of the panel; boss nodes are npc ids.

local Core = NorgannonCore
local O = Oracle
if O.disabled then return end
local UI = Core.UI
local C = UI.C

local Schematic = {}
O.Schematic = Schematic

local VIOLET = UI.Hex("b48cff")
local GOLD = UI.Hex("ffd100")
local ORANGE = UI.Hex("ff8a3d")
local GREEN, GREEN_BG = UI.Hex("6fdc6f"), UI.Hex("12200f")
local BLUE, BLUE_BG = UI.Hex("8fb8ff"), UI.Hex("10172a")
local MISSING, MISSING_BG, MISSING_TEXT = UI.Hex("8a7d62"), UI.Hex("17130e"), UI.Hex("b9ad90")
local DISC_TOP, DISC_BOTTOM = UI.Hex("4a3a6e"), UI.Hex("1a1426")
local LABEL = UI.Hex("e9e2ff")
local DOT, DOT_GAP, BOW = 3, 8, .12

Schematic.COLORS = { violet = VIOLET, gold = GOLD, orange = ORANGE, green = GREEN, blue = BLUE, missing = MISSING }

-------------------------------------------------------------------------------------------
-- The legend: which nodes go where in route order, which bosses the map doesn't place
-------------------------------------------------------------------------------------------

---The layout joined with the instance: nodes in route order (bosses numbered 1, 2, ...; the last
---one is the final boss) and the bosses the map doesn't place (lettered A, B, ...).
function Schematic.Legend(key)
  local layout = O.Layouts and O.Layouts[key]
  local inst = Core.DB:Instance(key)
  if not (layout and inst) then return nil end
  local known = {}
  for _, b in ipairs(inst.bosses or {}) do if b.id then known[b.id] = b end end
  local nodes, used, n = {}, {}, 0
  for _, node in ipairs(layout.nodes) do
    local copy = {}
    for k, v in pairs(node) do copy[k] = v end
    if node.npc then
      n = n + 1
      copy.num = n
      copy.boss = known[node.npc]
      copy.missing = copy.boss == nil
      copy.label = node.label or Core.DB:Name("npcs", node.npc) or ("Creature " .. node.npc)
      copy.key = node.npc
      used[node.npc] = true
    else
      copy.key = node.key
    end
    nodes[#nodes + 1] = copy
  end
  for i = #nodes, 1, -1 do
    if nodes[i].num then nodes[i].final = true break end
  end
  local extra, letter = {}, 0
  for _, b in ipairs(inst.bosses or {}) do
    if not (b.id and used[b.id]) then
      letter = letter + 1
      extra[#extra + 1] = { npc = b.id or b.name, boss = b, letter = string.char(64 + letter), unplaced = true,
        label = (b.id and Core.DB:Name("npcs", b.id)) or b.name or "?" }
    end
  end
  return { nodes = nodes, extra = extra, edges = layout.edges or {} }
end

-------------------------------------------------------------------------------------------
-- Nodes
-------------------------------------------------------------------------------------------

local canvas, legendFrame, stamp
local nodePool, dotPool = {}, {}
local current      -- { key, legend, byKey }

local function texture(parent, layer, sub, file)
  local t = parent:CreateTexture(nil, layer, nil, sub or 0)
  if file then t:SetTexture(file) end
  return t
end

local function newNode()
  local f = CreateFrame("Button", nil, canvas)
  f:RegisterForClicks("LeftButtonUp")
  f.glow = texture(f, "BACKGROUND", 0, UI.TEX.glow)
  f.glow:SetBlendMode("ADD")
  f.glow:SetPoint("CENTER")
  f.shadow = texture(f, "BACKGROUND", 1, UI.TEX.circle)   -- the 2px black outline beyond the ring
  f.shadow:SetVertexColor(0, 0, 0, 1)
  f.shadow:SetPoint("CENTER")
  f.fill = texture(f, "BORDER", 0, UI.TEX.circle)
  f.fill:SetPoint("CENTER")
  f.light = texture(f, "BORDER", 1, UI.TEX.glow)          -- the disc's radial highlight, upper left
  f.ring = texture(f, "ARTWORK", 0, UI.TEX.ring)
  f.ring:SetPoint("CENTER")
  f.dashes = {}
  for i = 1, 12 do
    local d = texture(f, "ARTWORK", 1, UI.TEX.circle)
    d:SetSize(4, 4)
    f.dashes[i] = d
  end
  -- entrance: a rounded square; point of interest: a diamond
  f.square = UI.Round(f, "BORDER", 2, 6)
  f.squareLine = UI.Round(f, "ARTWORK", 2, 6, "line")
  f.diamondBack = texture(f, "BORDER", 3, UI.TEX.pinDiamond)
  f.diamondBack:SetPoint("CENTER")
  f.diamond = texture(f, "ARTWORK", 3, UI.TEX.pinDiamond)
  f.diamond:SetPoint("CENTER")
  f.arrow = UI.Icon(f, "arrow", 14, { 1, 1, 1 })
  f.arrow:SetPoint("CENTER")
  f.arrow:SetRotation(math.pi)
  f.num = UI.Text(f, "title", 16, { 1, 1, 1 }, "OVERLAY")
  f.num:SetPoint("CENTER", 0, 0)
  f.num:SetJustifyH("CENTER")
  f.label = UI.Text(f, "body", 13, LABEL, "OVERLAY")
  f.label:SetPoint("TOP", f, "BOTTOM", 0, -4)
  f.label:SetJustifyH("CENTER")
  UI.Glow(f.label)
  f.sub = UI.Text(f, "body", 11, C.faint, "OVERLAY")
  f.sub:SetPoint("TOP", f.label, "BOTTOM", 0, -1)
  f.sub:SetJustifyH("CENTER")
  UI.Glow(f.sub)
  f:SetScript("OnEnter", function(self) Schematic:SetHot(self.node and self.node.key) end)
  f:SetScript("OnLeave", function() Schematic:SetHot(nil) end)
  f:SetScript("OnClick", function(self)
    local node = self.node
    if O.MapEdit and O.MapEdit.active then return end    -- the map editor drags and selects instead
    if node and node.npc then O:Send("FOCUS", node.npc) end
  end)
  f:SetScript("OnMouseDown", function(self, button) if O.MapEdit then O.MapEdit:NodeDown(self, button) end end)
  f:SetScript("OnMouseUp", function(self, button) if O.MapEdit then O.MapEdit:NodeUp(self, button) end end)
  return f
end

-- the node's look for its kind, at a size (hover grows it 15%)
local function paint(f, node, hot)
  local grow = hot and 1.15 or 1
  local kind = node.kind
  local isBoss = node.npc ~= nil
  for _, d in ipairs(f.dashes) do d:Hide() end
  f.square:SetShown(false)
  f.squareLine:SetShown(false)
  f.diamondBack:Hide()
  f.diamond:Hide()
  f.arrow:Hide()
  f.fill:Hide()
  f.light:Hide()
  f.ring:Hide()
  f.shadow:Hide()
  f.glow:Hide()
  f.num:SetText("")

  if isBoss then
    local size = (node.final and 40 or 34) * grow
    local ring = node.final and ORANGE or (node.missing and MISSING) or (node.elite and GOLD) or VIOLET
    f:SetSize(size, size)
    f.shadow:SetSize(size + 4, size + 4)
    f.shadow:Show()
    f.fill:SetSize(size - 2, size - 2)
    if node.missing then
      f.fill:SetVertexColor(MISSING_BG[1], MISSING_BG[2], MISSING_BG[3], 1)
      for i, d in ipairs(f.dashes) do
        local a = (i - 1) / #f.dashes * math.pi * 2
        d:ClearAllPoints()
        d:SetPoint("CENTER", f, "CENTER", math.cos(a) * (size / 2 - 1), math.sin(a) * (size / 2 - 1))
        d:SetVertexColor(MISSING[1], MISSING[2], MISSING[3], 1)
        d:Show()
      end
      f.num:SetTextColor(MISSING_TEXT[1], MISSING_TEXT[2], MISSING_TEXT[3])
    else
      f.fill:SetVertexColor(DISC_BOTTOM[1], DISC_BOTTOM[2], DISC_BOTTOM[3], 1)
      f.light:SetSize(size * .9, size * .9)
      f.light:ClearAllPoints()
      f.light:SetPoint("CENTER", f, "CENTER", -size * .1, size * .15)
      f.light:SetVertexColor(DISC_TOP[1], DISC_TOP[2], DISC_TOP[3], 1)
      f.light:Show()
      f.ring:SetSize(size, size)
      f.ring:SetVertexColor(ring[1], ring[2], ring[3], 1)
      f.ring:Show()
      f.num:SetTextColor(1, 1, 1)
    end
    f.fill:Show()
    local glow = node.final and ORANGE or VIOLET
    f.glow:SetSize(size + (node.final and 40 or 28) * (hot and 1.6 or 1), size + (node.final and 40 or 28) * (hot and 1.6 or 1))
    f.glow:SetVertexColor(glow[1], glow[2], glow[3], hot and .8 or (node.final and .45 or .35))
    f.glow:Show()
    f.num:SetFontObject(UI.Font("title", 16))
    f.num:SetText(node.num)
    local level = node.level
    f.sub:SetText(node.missing and "not in NorgannonDB yet" or (level and ("Level " .. level) or (node.note or "")))
  elseif kind == "entrance" then
    local size = 30 * grow
    f:SetSize(size, size)
    f.square:SetColor(GREEN_BG, 1)
    f.squareLine:SetColor(GREEN, 1)
    f.square:SetShown(true)
    f.squareLine:SetShown(true)
    f.arrow:SetSize(14 * grow, 14 * grow)
    f.arrow:Show()
    f.glow:SetSize(size + 24, size + 24)
    f.glow:SetVertexColor(GREEN[1], GREEN[2], GREEN[3], hot and .6 or .2)
    f.glow:Show()
    f.sub:SetText(node.note or "")
  else -- point of interest
    local size = 22 * grow
    f:SetSize(size, size)
    f.diamondBack:SetSize(size + 6, size + 6)
    f.diamondBack:SetVertexColor(BLUE[1], BLUE[2], BLUE[3], 1)
    f.diamondBack:Show()
    f.diamond:SetSize(size, size)
    f.diamond:SetVertexColor(BLUE_BG[1], BLUE_BG[2], BLUE_BG[3], 1)
    f.diamond:Show()
    f.glow:SetSize(size + 22, size + 22)
    f.glow:SetVertexColor(BLUE[1], BLUE[2], BLUE[3], hot and .6 or .15)
    f.glow:Show()
    f.sub:SetText(node.note or "")
  end
  f.label:SetText(node.label or "")
end

-------------------------------------------------------------------------------------------
-- Paths: dotted quadratic curves between node centres
-------------------------------------------------------------------------------------------

local function dot(i)
  local d = dotPool[i]
  if not d then
    d = canvas.paths:CreateTexture(nil, "ARTWORK")
    d:SetTexture(UI.TEX.circle)
    d:SetSize(DOT, DOT)
    dotPool[i] = d
  end
  return d
end

---The points of a path from (x1, y1) to (x2, y2) (pixels, y down), one every DOT_GAP pixels along
---a curve that bows to one side (the mockup's quadratic, control point offset by 12%).
function Schematic.PathPoints(x1, y1, x2, y2)
  local mx = (x1 + x2) / 2 + (y2 - y1) * BOW
  local my = (y1 + y2) / 2 - (x2 - x1) * BOW
  local function at(t)
    local u = 1 - t
    return u * u * x1 + 2 * u * t * mx + t * t * x2, u * u * y1 + 2 * u * t * my + t * t * y2
  end
  local length, px, py = 0, x1, y1
  for i = 1, 24 do
    local x, y = at(i / 24)
    length = length + math.sqrt((x - px) ^ 2 + (y - py) ^ 2)
    px, py = x, y
  end
  local points = {}
  local n = math.max(1, math.floor(length / DOT_GAP))
  for i = 0, n do points[#points + 1] = { at(i / n) } end
  return points, length
end

-------------------------------------------------------------------------------------------
-- Drawing
-------------------------------------------------------------------------------------------

local function build(map)
  canvas = CreateFrame("Frame", nil, map)
  canvas:SetAllPoints()
  canvas:SetFrameLevel(map:GetFrameLevel() + 2)
  canvas.paths = CreateFrame("Frame", nil, canvas)
  canvas.paths:SetAllPoints()

  legendFrame = CreateFrame("Frame", nil, canvas)
  legendFrame:SetSize(400, 16)
  legendFrame:SetPoint("BOTTOMLEFT", 12, 10)
  legendFrame:SetFrameLevel(canvas:GetFrameLevel() + 30)
  local items = {
    { "Boss", "ring", VIOLET }, { "Final boss", "ring", ORANGE },
    { "Entrance", "square", GREEN }, { "Point of interest", "diamond", BLUE },
  }
  local previous
  legendFrame.items = {}
  for _, it in ipairs(items) do
    local icon
    if it[2] == "ring" then
      icon = texture(legendFrame, "ARTWORK", 0, UI.TEX.ring)
      icon:SetSize(12, 12)
      icon:SetVertexColor(it[3][1], it[3][2], it[3][3], 1)
    elseif it[2] == "square" then
      icon = CreateFrame("Frame", nil, legendFrame)
      icon:SetSize(12, 12)
      UI.Round(icon, "ARTWORK", 0, 3, "line"):SetColor(it[3], 1)
    else
      icon = texture(legendFrame, "ARTWORK", 0, UI.TEX.pinDiamond)
      icon:SetSize(12, 12)
      icon:SetVertexColor(it[3][1], it[3][2], it[3][3], 1)
    end
    icon:SetPoint("LEFT", previous or legendFrame, previous and "RIGHT" or "LEFT", previous and 12 or 0, 0)
    local text = UI.Text(legendFrame, "body", 12, C.muted)
    text:SetPoint("LEFT", icon, "RIGHT", 5, 0)
    text:SetText(it[1])
    previous = text
    legendFrame.items[#legendFrame.items + 1] = text
  end

  stamp = UI.Text(canvas, "body", 12, C.faint, "OVERLAY")
  stamp:SetPoint("BOTTOMRIGHT", -10, 8)
  stamp:SetJustifyH("RIGHT")
  stamp:SetText("Schematic · draft layout")
  Schematic.canvas, Schematic.legendFrame, Schematic.stamp = canvas, legendFrame, stamp
end

---Draws an instance's schematic on the map panel; returns false when it has no layout. overReal:
---the game map is drawn underneath (O.RealMap), so the nodes stand where the game puts them
---(bosses at their spawns, on the floor shown; ones without a known spot are left off), the
---bosses the layout leaves out join them with their letters, and the dotted route and the
---"Schematic" stamp stay hidden.
function Schematic:Draw(map, key, overReal)
  if not canvas then build(map) end
  local legend = self.Legend(key)
  if legend and overReal then
    local nodes = {}
    for _, node in ipairs(legend.nodes) do nodes[#nodes + 1] = node end
    for _, x in ipairs(legend.extra) do
      x.num, x.key = x.letter, x.npc
      nodes[#nodes + 1] = x
    end
    legend = { nodes = nodes, extra = {}, edges = {} }
  end
  for _, f in ipairs(nodePool) do f:Hide() f.node = nil end
  for _, d in ipairs(dotPool) do d:Hide() end
  if not legend then
    canvas:Hide()
    current = nil
    return false
  end
  canvas:Show()
  canvas.paths:SetShown(not overReal)
  stamp:SetShown(not overReal)
  current = { key = key, legend = legend, byKey = {} }
  for _, node in ipairs(legend.nodes) do
    if node.npc then
      local npc = NorgannonDB:Get("npcs", node.npc)
      node.level = npc and (npc.maxLevel or npc.minLevel)
      node.elite = npc and npc.rank == 1
    end
  end
  local w, h = map:GetWidth() or 0, map:GetHeight() or 0
  local view = O.View
  local function pos(node)
    local x, y
    if overReal then x, y = O.RealMap:NodePos(key, node) else x, y = node.x / 100 * w, node.y / 100 * h end
    if x and view then x, y = view.ToView(x, y) end   -- zoomed or moved: the markers keep their size
    return x, y
  end

  -- paths under the nodes
  local nd = 0
  local byKey = current.byKey
  for _, node in ipairs(legend.nodes) do byKey[node.key] = node end
  for _, e in ipairs(legend.edges) do
    local a, b = byKey[e[1]], byKey[e[2]]
    if a and b then
      local x1, y1 = pos(a)
      local x2, y2 = pos(b)
      for _, p in ipairs((Schematic.PathPoints(x1, y1, x2, y2))) do
        nd = nd + 1
        local d = dot(nd)
        d:ClearAllPoints()
        d:SetPoint("CENTER", canvas.paths, "TOPLEFT", p[1], -p[2])
        d:SetVertexColor(VIOLET[1], VIOLET[2], VIOLET[3], .45)
        d:Show()
      end
    end
  end

  -- the nodes
  local shown = 0
  for _, node in ipairs(legend.nodes) do
    local x, y = pos(node)
    if x then
      shown = shown + 1
      local f = nodePool[shown] or newNode()
      nodePool[shown] = f
      f.node = node
      f:SetFrameLevel(canvas:GetFrameLevel() + 10)
      paint(f, node, Schematic.hot ~= nil and node.key == Schematic.hot)   -- a redraw keeps the hover
      f.sub:SetShown(not overReal)    -- over the game map: names only, the levels are in the boss list
      f:ClearAllPoints()
      f:SetPoint("CENTER", canvas, "TOPLEFT", x, -y)
      f:Show()
    end
  end
  Schematic.stats = { nodes = shown, dots = nd }
  return true
end

---Lights one node (a boss's npc id or a node key); nil puts every node back.
function Schematic:SetHot(key)
  if not current then return end
  self.hot = key
  for _, f in ipairs(nodePool) do
    if f:IsShown() and f.node then paint(f, f.node, key ~= nil and f.node.key == key) end
  end
  O:Send("HOT", key)
end

---The node frame showing a boss or key (for the boss list's hover and the harness).
function Schematic:NodeFor(key)
  for _, f in ipairs(nodePool) do
    if f:IsShown() and f.node and f.node.key == key then return f end
  end
end
