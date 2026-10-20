-- The real map: the instance drawn from the game's own indoor minimap tiles (data/maps.lua, made
-- by tools/oracle_maps/build.py: FileDataIDs and positions only; the client draws its textures).
--
-- It sits under the schematic's nodes on the map panel. A "Game map / Schematic" switch in the
-- panel's top-right corner picks the view (OracleDB.mapView); instances without map data show the
-- schematic and no switch. Over the game map the nodes stand where the game puts them: each boss
-- at its spawn and the entrance where the portal leaves you (Schematic:Draw asks NodePos), the
-- dotted route is hidden. Instances whose rooms stack get floor tabs in the top-left corner; the
-- floor last shown is kept per map (OracleDB.floors), and clicking a boss on another floor turns
-- to it.
--
-- Edits: the map editor (mapedit.lua, /oracle edit) saves fixes in OracleDB.mapEdits[sheet id]:
--   bosses = { [npc] = { wx, wy, floor } }, entrance = { wx, wy, floor }   world x (north), y (west)
--   names = { [floor] = name }, groups = { ["wmo:group"] = floor }         a room moved to a floor
-- RealMap.For gives the sheet with them applied, so everything that reads the map follows at once.
-- Points are kept in world coordinates, so a rebuild that re-crops the sheet doesn't move them.
-- tools/oracle_maps/edits.py copies them into edits.json, which build.py applies on every build
-- ("lock in"); once data/maps.lua holds the same, the saved copy is dropped at login (Prune).

local Core = NorgannonCore
local O = Oracle
if O.disabled then return end
local UI = Core.UI
local C = UI.C

local RealMap = {}
O.RealMap = RealMap

local PAD = 28            -- pixels kept clear around the sheet
local layer, switch, floorTabs, stamp
local pool = {}
local drawn               -- { key, sheet, id, floor, scale, left, top, tiles }

-------------------------------------------------------------------------------------------
-- Sheets, with the editor's fixes over them
-------------------------------------------------------------------------------------------

---An instance's map sheet as shipped (O.MapData.sheets entry) and its id, or nil when it has none.
function RealMap.Raw(key)
  local data = O.MapData
  local id = data and key and data.instances[key]
  return id and data.sheets[id], id
end

---world (x north, y west) -> sheet yards (x east, y south); see data/maps.lua's header.
function RealMap.WorldToSheet(m, wx, wy)
  local t, q = math.rad(m.t), math.rad(m.tq)
  local dx, dy = wx - m.origin[1], wy - m.origin[2]
  local lx = math.cos(t) * dx + math.sin(t) * dy
  local ly = -math.sin(t) * dx + math.cos(t) * dy
  local cq, sq = math.floor(math.cos(q) + .5), math.floor(math.sin(q) + .5)
  local ex, ey = m.origin[1] + cq * lx - sq * ly, m.origin[2] + sq * lx + cq * ly
  return -ey - m.offset[1], -ex - m.offset[2]
end

---sheet yards -> world (x north, y west): WorldToSheet turned around.
function RealMap.SheetToWorld(m, sx, sy)
  local t, q = math.rad(m.t), math.rad(m.tq)
  local cq, sq = math.floor(math.cos(q) + .5), math.floor(math.sin(q) + .5)
  local a, b = -(sy + m.offset[2]) - m.origin[1], -(sx + m.offset[1]) - m.origin[2]
  local lx, ly = cq * a + sq * b, -sq * a + cq * b
  return m.origin[1] + math.cos(t) * lx - math.sin(t) * ly, m.origin[2] + math.sin(t) * lx + math.cos(t) * ly
end

local version, cache = 0, {}

---A sheet's saved edits (OracleDB.mapEdits[id]), made when create is set.
function RealMap.Edits(id, create)
  local db = O.db
  if not (db and id) then return nil end
  if create then
    db.mapEdits = db.mapEdits or {}
    db.mapEdits[id] = db.mapEdits[id] or {}
  end
  return db.mapEdits and db.mapEdits[id]
end

-- the sheet with its edits over it (a copy, cached until the next edit)
local function effective(id, raw)
  local ed = RealMap.Edits(id)
  if not (raw and ed and next(ed)) then return raw end
  local c = cache[id]
  if c and c.version == version and c.raw == raw then return c.m end
  local m = {}
  for k, v in pairs(raw) do m[k] = v end
  m.raw = raw
  local function place(e)
    local x, y = RealMap.WorldToSheet(raw, e[1], e[2])
    return { x, y, e[3] }
  end
  m.bosses = {}
  for npc, p in pairs(raw.bosses or {}) do m.bosses[npc] = p end
  for npc, e in pairs(ed.bosses or {}) do m.bosses[npc] = place(e) end
  if ed.entrance then m.entrance = place(ed.entrance) end
  local n = #raw.floors
  for _, f in pairs(ed.groups or {}) do n = math.max(n, f) end
  local floors = {}
  for i = 1, n do
    floors[i] = { name = (ed.names and ed.names[i]) or (raw.floors[i] and raw.floors[i].name),
      shapes = raw.floors[i] and raw.floors[i].shapes }
  end
  for i, floor in ipairs(raw.floors) do
    for _, d in ipairs(floor) do
      local unit = d[14] and raw.units and raw.units[d[14]]
      local to = floors[unit and ed.groups and ed.groups[unit] or i]
      to[#to + 1] = d
    end
  end
  m.floors = floors
  cache[id] = { version = version, raw = raw, m = m }
  return m
end

---An instance's map sheet (with the editor's fixes over it) and its id, or nil when it has none yet.
function RealMap.For(key)
  local raw, id = RealMap.Raw(key)
  return effective(id, raw), id
end

---Whether the panel shows the game map for an instance (it has one and the switch says so).
function RealMap.Active(key)
  return RealMap.For(key) ~= nil and O.db.mapView ~= "schematic"
end

-------------------------------------------------------------------------------------------
-- Editing (mapedit.lua is the UI): every change saves at once and redraws
-------------------------------------------------------------------------------------------

local function round1(v) return math.floor(v * 10 + .5) / 10 end

local function tidy(ed)
  for _, k in ipairs({ "bosses", "names", "groups" }) do
    if ed[k] and next(ed[k]) == nil then ed[k] = nil end
  end
  return next(ed) == nil
end

local function changed(id)
  local ed = RealMap.Edits(id)
  if ed and tidy(ed) then O.db.mapEdits[id] = nil end
  version = version + 1
  O:Send("MAP_EDITED", id)
  if O.Window and O.Window.Select and O.db.selected then O.Window:Select(O.db.selected) end
end

---Puts a boss (npc id) or the entrance ("entrance") at x, y (sheet yards) on a floor; nil x
---puts it back where the shipped data has it.
function RealMap:SetPoint(key, who, x, y, floor)
  local raw, id = self.Raw(key)
  if not raw then return end
  local ed = self.Edits(id, true)
  local value
  if x then
    x = math.max(0, math.min(raw.width, x))
    y = math.max(0, math.min(raw.height, y))
    local wx, wy = self.SheetToWorld(raw, x, y)
    value = { round1(wx), round1(wy), floor or 1 }
  end
  if who == "entrance" then
    ed.entrance = value
  else
    ed.bosses = ed.bosses or {}
    ed.bosses[who] = value
  end
  changed(id)
end

---Moves a room (its index in the sheet's units) to a floor; nil puts it back where the data has it.
function RealMap:SetRoomFloor(key, room, floor)
  local raw, id = self.Raw(key)
  local unit = raw and raw.units and raw.units[room]
  if not unit then return end
  local ed = self.Edits(id, true)
  ed.groups = ed.groups or {}
  ed.groups[unit] = floor ~= RealMap.RoomFloor(raw, room) and floor or nil
  changed(id)
end

---Names a floor; nil or "" puts the shipped name back.
function RealMap:SetFloorName(key, floor, name)
  local raw, id = self.Raw(key)
  if not raw then return end
  name = name and strtrim(name) or ""
  local ed = self.Edits(id, true)
  ed.names = ed.names or {}
  ed.names[floor] = name ~= "" and name ~= (raw.floors[floor] and raw.floors[floor].name) and name or nil
  changed(id)
end

---Drops every edit of an instance's sheet.
function RealMap:ResetAll(key)
  local _, id = self.Raw(key)
  if not id then return end
  if O.db.mapEdits then O.db.mapEdits[id] = nil end
  changed(id)
end

---How many changes a sheet's edits hold (each boss, the entrance, each name and room).
function RealMap.EditCount(id)
  local ed = RealMap.Edits(id)
  if not ed then return 0 end
  local n = ed.entrance and 1 or 0
  for _, k in ipairs({ "bosses", "names", "groups" }) do
    for _ in pairs(ed[k] or {}) do n = n + 1 end
  end
  return n
end

---The floor a room (index in units) is on in a sheet's floors.
function RealMap.RoomFloor(m, room)
  for i, floor in ipairs(m.floors) do
    for _, d in ipairs(floor) do
      if d[14] == room then return i end
    end
  end
end

---Drops the edits the shipped data already holds (locked in by edits.py and build.py, then
---deployed), so the saved copy only ever holds what isn't in the add-on yet.
function RealMap.Prune()
  local all = O.db and O.db.mapEdits
  if not all then return end
  for id, ed in pairs(all) do
    local raw = O.MapData and O.MapData.sheets[id]
    if raw then
      local function same(p, e)
        if not (p and e) or (p[3] or 1) ~= e[3] then return false end
        local x, y = RealMap.WorldToSheet(raw, e[1], e[2])
        return math.abs(x - p[1]) < .6 and math.abs(y - p[2]) < .6
      end
      for npc, e in pairs(ed.bosses or {}) do
        if same(raw.bosses and raw.bosses[npc], e) then ed.bosses[npc] = nil end
      end
      if same(raw.entrance, ed.entrance) then ed.entrance = nil end
      for i, name in pairs(ed.names or {}) do
        if raw.floors[i] and raw.floors[i].name == name then ed.names[i] = nil end
      end
      local index = {}
      for i, unit in ipairs(raw.units or {}) do index[unit] = i end
      for unit, f in pairs(ed.groups or {}) do
        if index[unit] and RealMap.RoomFloor(raw, index[unit]) == f then ed.groups[unit] = nil end
      end
      if tidy(ed) then all[id] = nil end
    end
  end
  version = version + 1
end
Core:OnLogin(RealMap.Prune)

-------------------------------------------------------------------------------------------
-- Floors
-------------------------------------------------------------------------------------------

---The floor shown for an instance: the one last chosen, else the entrance's.
function RealMap.Floor(key)
  local m, id = RealMap.For(key)
  if not m then return 1 end
  local saved = O.db.floors and O.db.floors[id]
  if saved and m.floors[saved] then return saved end
  return m.entrance and m.entrance[3] or m.start or 1
end

function RealMap:SetFloor(key, floor)
  local m, id = self.For(key)
  if not (m and m.floors[floor]) then return end
  O.db.floors = O.db.floors or {}
  O.db.floors[id] = floor
  if O.Window and O.Window.DrawMap then O.Window:DrawMap() end
end

---A floor's name: the one given (in build.py or the editor), else "Floor N".
function RealMap.FloorLabel(m, i)
  local f = m.floors[i]
  return f and f.name or ("Floor " .. i)
end
local floorLabel = RealMap.FloorLabel

---The floors worth a tab: those with rooms or markers (the editor may have emptied one), or every
---floor while editing.
function RealMap.TabFloors(m, all)
  local list, used = {}, {}
  for _, p in pairs(m.bosses or {}) do used[p[3] or 1] = true end
  if m.entrance then used[m.entrance[3] or 1] = true end
  for i, floor in ipairs(m.floors) do
    if all or #floor > 0 or used[i] then list[#list + 1] = i end
  end
  return list
end

local function build(map)
  -- on the view's stage (view.lua): the tiles zoom and move with it, and the cursor conversions
  -- below, made through the layer, stay in panel points
  layer = CreateFrame("Frame", nil, map.stage or map)
  layer:SetAllPoints()
  layer:SetFrameLevel(map:GetFrameLevel() + 1)   -- under the schematic's canvas (+2)

  switch = UI.Segmented(map, {
    { key = "real", label = "Game map" }, { key = "schematic", label = "Schematic" },
  }, function(key)
    O.db.mapView = key
    if O.Window and O.Window.Select then O.Window:Select(O.db.selected) end   -- the boss list says what's on the map
  end, 20)
  switch:SetPoint("TOPRIGHT", -10, -10)
  switch:SetFrameLevel(map:GetFrameLevel() + 40)
  if switch.ApplyAccent then switch:ApplyAccent(UI.Accent("oracle")) end
  switch:Hide()

  stamp = UI.Text(switch, "body", 12, C.faint, "OVERLAY")   -- fixed in the corner, not zoomed
  stamp:SetPoint("BOTTOMRIGHT", map, "BOTTOMRIGHT", -10, 8)
  stamp:SetJustifyH("RIGHT")
  stamp:SetText("Map: game minimap")
  RealMap.layer, RealMap.switch, RealMap.stamp = layer, switch, stamp
end

-- the floor tabs, made for the floors listed (a Segmented's items are fixed)
local tabSets = {}
local function tabsFor(map, list, m)
  for _, t in pairs(tabSets) do t:Hide() end
  if #list < 2 then return nil end
  local names = {}
  for k, i in ipairs(list) do names[k] = i .. "=" .. floorLabel(m, i) end
  local key = table.concat(names, "|")
  local t = tabSets[key]
  if not t then
    local items = {}
    for k, i in ipairs(list) do items[k] = { key = i, label = floorLabel(m, i) } end
    t = UI.Segmented(map, items, function(i)
      if drawn then RealMap:SetFloor(drawn.key, i) end
    end, 20)
    t:SetPoint("TOPLEFT", 10, -10)
    t:SetFrameLevel(map:GetFrameLevel() + 40)
    if t.ApplyAccent then t:ApplyAccent(UI.Accent("oracle")) end
    tabSets[key] = t
  end
  t:Show()
  return t
end

-- open-air parts drawn from the geometry (data/maps.lua "shapes"): flat rectangles under the tiles,
-- slate for the ground (a cove's basin), wood for structures (a ship, docks), lighter where higher
local shapePool = {}
local function shapeColor(band)
  local t = ((band - 1) % 10) / 5
  if band > 10 then return (96 + 70 * t) / 255, (72 + 52 * t) / 255, (50 + 34 * t) / 255 end
  return (34 + 48 * t) / 255, (38 + 50 * t) / 255, (54 + 58 * t) / 255
end

local function shapes(list, x0, y0, scale)
  local n = 0
  for k = 1, #(list or {}) - 4, 5 do
    n = n + 1
    local t = shapePool[n]
    if not t then
      t = layer:CreateTexture(nil, "BACKGROUND")
      shapePool[n] = t
    end
    t:SetColorTexture(shapeColor(list[k + 4]))
    t:ClearAllPoints()
    t:SetPoint("TOPLEFT", layer, "TOPLEFT", x0 + list[k] * scale, -(y0 + list[k + 1] * scale))
    t:SetSize(math.max(1, list[k + 2] * scale), math.max(1, list[k + 3] * scale))
    t:Show()
  end
  return n
end

local function tile(i, d, x0, y0, scale)
  local t = pool[i]
  if not t then
    t = layer:CreateTexture(nil, "ARTWORK")
    pool[i] = t
  end
  t:SetTexture(d[1])
  t:SetTexCoord(d[6], d[7], d[8], d[9], d[10], d[11], d[12], d[13])
  t:SetVertexColor(1, 1, 1, 1)
  t.room, t.d = d[14], d
  t:ClearAllPoints()
  t:SetPoint("TOPLEFT", layer, "TOPLEFT", x0 + d[2] * scale, -(y0 + d[3] * scale))
  t:SetSize(d[4] * scale, d[5] * scale)
  t:Show()
  return t:GetTexture() ~= nil
end

---Draws an instance's game map (its base and the floor shown) on the map panel; returns true when
---it did. Shows the view switch whenever the instance has map data, even while the schematic is chosen.
function RealMap:Draw(map, key)
  if not layer then build(map) end
  local m, id = self.For(key)
  switch:SetShown(m ~= nil)
  if m then switch:Select(O.db.mapView == "schematic" and "schematic" or "real", true) end
  for _, t in ipairs(pool) do t:Hide() t.room = nil end
  for _, t in ipairs(shapePool) do t:Hide() end
  if not (m and self.Active(key)) then
    layer:Hide()
    stamp:Hide()
    tabsFor(map, {})
    floorTabs, drawn, self.stats = nil, nil, nil
    if O.MapEdit then O.MapEdit:Refresh(map, key, false) end
    return false
  end
  layer:Show()
  stamp:Show()
  local editing = O.MapEdit and O.MapEdit.active
  local floor = self.Floor(key)
  floorTabs = tabsFor(map, self.TabFloors(m, editing), m)
  if floorTabs then floorTabs:Select(floor, true) end
  local w, h = map:GetWidth() or 0, map:GetHeight() or 0
  local top = PAD + (floorTabs and 18 or 0)                         -- room for the tabs
  local bottom = PAD + (editing and O.MapEdit.BAR_HEIGHT or 0)      -- and for the editor's bar
  local scale = math.max(.01, math.min((w - 2 * PAD) / m.width, (h - top - bottom) / m.height))
  local x0, y0 = (w - m.width * scale) / 2, top + (h - top - bottom - m.height * scale) / 2
  local n, missing = 0, 0
  local nshapes = shapes(m.floors[floor] and m.floors[floor].shapes, x0, y0, scale)
  for _, d in ipairs(m.base or {}) do
    n = n + 1
    if not tile(n, d, x0, y0, scale) then missing = missing + 1 end
  end
  for _, d in ipairs(m.floors[floor]) do
    n = n + 1
    if not tile(n, d, x0, y0, scale) then missing = missing + 1 end
  end
  drawn = { key = key, sheet = m, id = id, floor = floor, scale = scale, left = x0, top = y0, tiles = n }
  self.floorTabs = floorTabs
  self.stats = { tiles = n, missing = missing, scale = scale, left = x0, top = y0, floor = floor, floors = #m.floors,
    shapes = nshapes }
  if O.MapEdit then O.MapEdit:Refresh(map, key, true) end
  return true
end

---What the panel shows: { key, sheet, id, floor, scale, left, top, tiles }, or nil.
function RealMap.Drawn() return drawn end

---Panel pixels (from the map panel's top-left) <-> sheet yards, for the map drawn.
function RealMap.PanelToSheet(px, py)
  if not drawn then return nil end
  return (px - drawn.left) / drawn.scale, (py - drawn.top) / drawn.scale
end
function RealMap.SheetToPanel(x, y)
  if not drawn then return nil end
  return drawn.left + x * drawn.scale, drawn.top + y * drawn.scale
end

---The cursor in panel pixels from the map panel's top-left.
function RealMap.CursorPanel()
  if not layer then return 0, 0 end
  local x, y = GetCursorPosition()
  local s = layer:GetEffectiveScale() or 1
  return x / s - (layer:GetLeft() or 0), (layer:GetTop() or 0) - y / s
end

---The room under a panel point on the floor shown (the topmost tile there), or nil.
function RealMap.RoomAt(px, py)
  if not drawn then return nil end
  local x, y = RealMap.PanelToSheet(px, py)
  for i = drawn.tiles, 1, -1 do
    local t = pool[i]
    local d = t and t.room and t.d
    if d and x >= d[2] and x <= d[2] + d[4] and y >= d[3] and y <= d[3] + d[5] then return t.room end
  end
end

---Tints one room's tiles (the editor's selection); nil clears it.
function RealMap.Highlight(room)
  for i = 1, drawn and drawn.tiles or 0 do
    local t = pool[i]
    if room and t.room == room then t:SetVertexColor(1, .78, .35, 1) else t:SetVertexColor(1, 1, 1, 1) end
  end
end

---Where a schematic node goes over the game map (panel pixels from the top-left), or nil when the
---game doesn't place it on the floor shown: bosses at their spawns, the entrance at the portal.
function RealMap:NodePos(key, node)
  if not (drawn and drawn.key == key) then return nil end
  local m = drawn.sheet
  local p
  if node.npc then
    p = m.bosses and m.bosses[node.npc]
  elseif node.key == "entrance" then
    p = m.entrance
  elseif node.kind == "entrance" then    -- a second way in ("entrance2", ...: Maraudon, Stratholme)
    p = m.entrances and m.entrances[tonumber(tostring(node.key):match("(%d+)$") or "")]
  end
  if not p or (p[3] or 1) ~= drawn.floor then return nil end
  return drawn.left + p[1] * drawn.scale, drawn.top + p[2] * drawn.scale
end

---The floor a boss stands on in an instance's game map, or nil.
function RealMap.BossFloor(key, npc)
  local m = RealMap.For(key)
  local p = m and m.bosses and m.bosses[npc]
  return p and p[3]
end

-- a boss chosen (in the list or on the map) on another floor: turn to its floor
O:Listen("FOCUS", RealMap, function(_, npc)
  local key = O.db and O.db.selected
  if not (key and RealMap.Active(key)) then return end
  local f = RealMap.BossFloor(key, npc)
  if f and f ~= RealMap.Floor(key) then RealMap:SetFloor(key, f) end
end)
