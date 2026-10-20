-- The map editor: fix the game map in game (/oracle edit, or "Edit map" beside the map switch).
--
--   drag a boss or the entrance     moves it on the floor shown
--   click a marker                  selects it (gold ring): send it to another floor, or reset it
--   click a room                    selects it (tinted): send it to another floor or a new one
--   a boss the map doesn't place    click its chip in the bar (or the boss in the Bosses list),
--                                   then the map where it stands (summoned bosses: Ragnaros, ...)
--   the floor name box              names the floor shown (Enter)
--   right-click the map             cancels placing, clears the selection
--
-- Every change is saved at once in OracleDB.mapEdits and drawn at once (realmap.lua applies them
-- over data/maps.lua). To make them the add-on's own data ("lock in"): /reload or log out, so the
-- game writes the saved variables, then run tools/oracle_maps/edits.py and tools/oracle_maps/build.py.

local Core = NorgannonCore
local O = Oracle
if O.disabled then return end
local UI = Core.UI
local C = UI.C

local Edit = { BAR_HEIGHT = 92 }
O.MapEdit = Edit

local R = O.RealMap
local GOLD = UI.Hex("ffd100")
local mapFrame, button, catcher, bar, ring, driver
local sel        -- { kind = "marker", who = npc or "entrance" } or { kind = "room", room = index }
local placing    -- npc id or "entrance": the next click on the map puts it there
local drag       -- { frame, who, x0, y0, moved }
local note       -- a line about the last change, shown until the selection changes
local confirmAt  -- "Reset all" asks twice

local function key() return O.db and O.db.selected end

local function whoName(who)
  if who == "entrance" then return "The entrance" end
  return Core.DB:Name("npcs", who) or ("Creature " .. tostring(who))
end

local function pointOf(m, who)
  if who == "entrance" then return m.entrance end
  return m.bosses and m.bosses[who]
end

-- what a marker or room is reset to: the shipped data's place, or nothing
local function edited(id, s)
  local ed = R.Edits(id)
  if not (ed and s) then return false end
  if s.kind == "marker" then
    if s.who == "entrance" then return ed.entrance ~= nil end
    return ed.bosses ~= nil and ed.bosses[s.who] ~= nil
  end
  local raw = O.MapData.sheets[id]
  return ed.groups ~= nil and ed.groups[raw.units[s.room]] ~= nil
end

---The bosses (and the entrance) an instance's map doesn't place yet.
function Edit.Unplaced(k)
  local m = R.For(k)
  if not m then return {} end
  local out = {}
  if not m.entrance then out[1] = "entrance" end
  local inst = Core.DB:Instance(k)
  for _, b in ipairs(inst and inst.bosses or {}) do
    if b.id and not (m.bosses and m.bosses[b.id]) then out[#out + 1] = b.id end
  end
  return out
end

-------------------------------------------------------------------------------------------
-- The bar
-------------------------------------------------------------------------------------------

local buttons = {}
local function control(i)
  local b = buttons[i]
  if not b then
    b = UI.Button(bar, "", "quiet", function(self) if self.fn then self.fn() end end)
    b:SetHeight(22)
    buttons[i] = b
  end
  return b
end

-- lays out row 3: items are { text, fn, on } (a button) or { label = text } or { edit = true }
local function layout(items)
  local x, n = 10, 0
  local width = (bar:GetWidth() or 600) - 20
  bar.label2:Hide()
  bar.edit:Hide()
  bar.more:Hide()
  for i, it in ipairs(items) do
    if it.label then
      local t = i == 1 and bar.label1 or bar.label2
      t:SetText(it.label)
      t:ClearAllPoints()
      t:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT", x, 13)
      t:Show()
      x = x + (t:GetStringWidth() or 40) + 8
    elseif it.edit then
      bar.edit:ClearAllPoints()
      bar.edit:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT", x, 8)
      bar.edit:Show()
      x = x + bar.edit:GetWidth() + 12
    else
      local b = control(n + 1)
      b:SetLabel(it[1])
      b:SetHeight(22)
      if x + b:GetWidth() > width and it.chip then
        bar.more:SetText("+" .. (#items - i + 1) .. " more: choose them in the Bosses list")
        bar.more:ClearAllPoints()
        bar.more:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT", x, 13)
        bar.more:Show()
        break
      end
      n = n + 1
      b.fn = it[2]
      b.style = it.on and "accent" or "quiet"
      b:Paint()
      b:ClearAllPoints()
      b:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT", x, 8)
      b:Show()
      x = x + b:GetWidth() + 6
    end
  end
  if not (items[1] and items[1].label) then bar.label1:Hide() end
  for i = n + 1, #buttons do buttons[i]:Hide() buttons[i].fn = nil end
end

local function floorButtons(m, current, fn, items)
  for i = 1, #m.floors do
    items[#items + 1] = { R.FloorLabel(m, i), function() fn(i) end, on = i == current }
  end
  return items
end

---Fills the bar for the selection (or the placing, or nothing chosen) and marks the selection.
function Edit:Update()
  if not (bar and self.active) then return end
  local k = key()
  local m, id = R.For(k)
  local d = R.Drawn()
  if not (m and d) then return end
  local n = R.EditCount(id)
  bar.status:SetText(n == 0 and "Nothing changed yet"
    or (n == 1 and "1 change" or (n .. " changes")) .. " saved · lock in: /reload, then tools/oracle_maps/edits.py")
  bar.reset:SetShown(n > 0)
  if not (confirmAt and GetTime() - confirmAt < 5) then
    confirmAt = nil
    bar.reset:SetLabel("Reset all")
  end

  ring:Hide()
  R.Highlight(sel and sel.kind == "room" and sel.room or nil)
  local floor = d.floor
  if placing then
    bar.hint:SetText(("Click the map where %s stands (on %s). Right-click cancels.")
      :format(whoName(placing), R.FloorLabel(m, floor)))
    layout({ { "Cancel", function() placing = nil Edit:Update() end } })
  elseif sel and sel.kind == "marker" then
    local p = pointOf(m, sel.who)
    local node = O.Schematic:NodeFor(sel.who)
    if node then
      ring:ClearAllPoints()
      ring:SetPoint("CENTER", node, "CENTER")
      ring:SetSize((node:GetWidth() or 34) + 14, (node:GetHeight() or 34) + 14)
      ring:Show()
    end
    bar.hint:SetText(note or (whoName(sel.who) .. ": drag it to move it."
      .. (#m.floors > 1 and " Send it to another floor:" or "")))
    local items = {}
    if #m.floors > 1 and p then
      items[1] = { label = "Floor" }
      floorButtons(m, p[3], function(f)
        R:SetFloor(k, f)
        R:SetPoint(k, sel.who, p[1], p[2], f)
      end, items)
    end
    if edited(id, sel) then
      items[#items + 1] = { "Reset", function()
        R:SetPoint(k, sel.who, nil)
        sel = nil
      end }
    end
    layout(items)
  elseif sel and sel.kind == "room" then
    local unit = m.units and m.units[sel.room] or "?"
    local now = R.RoomFloor(m, sel.room) or floor
    bar.hint:SetText(note or ("Room %s (tinted) is on %s. Send it to:"):format(unit, R.FloorLabel(m, now)))
    local room = sel.room
    local items = floorButtons(m, now, function(f)
      if f == now then return end
      R:SetRoomFloor(k, room, f)
      sel, note = nil, nil
      note = ("Room %s moved to %s."):format(unit, R.FloorLabel(R.For(k), f))
      Edit:Update()
    end, {})
    items[#items + 1] = { "New floor", function()
      local f = #m.floors + 1
      R:SetRoomFloor(k, room, f)
      sel = nil
      note = ("Room %s moved to a new floor, %s."):format(unit, R.FloorLabel(R.For(k), f))
      Edit:Update()
    end }
    if edited(id, sel) then
      items[#items + 1] = { "Reset", function() R:SetRoomFloor(k, room, nil) sel = nil end }
    end
    layout(items)
  else
    bar.hint:SetText(note or "Drag a boss or the entrance to move it. Click a room to send it to another floor.")
    local items = {}
    if #m.floors > 1 then
      items[1] = { label = "Floor name" }
      items[2] = { edit = true }
      bar.edit:SetText(R.FloorLabel(m, floor))
      bar.edit.floor = floor
    end
    local unplaced = self.Unplaced(k)
    if #unplaced > 0 then
      items[#items + 1] = { label = "Place" }
      for _, who in ipairs(unplaced) do
        items[#items + 1] = { whoName(who), function() placing = who Edit:Update() end, chip = true }
      end
    end
    layout(items)
  end
end

local function build(map)
  mapFrame = map
  button = UI.Button(map, "Edit map", "quiet", function() Edit:SetActive(true) end)
  button:SetHeight(20)
  button:SetPoint("RIGHT", R.switch, "LEFT", -8, 0)
  button:SetFrameLevel(map:GetFrameLevel() + 40)
  button:Hide()

  -- clicks on the map itself (under the markers, over the tiles): place, or pick a room
  catcher = CreateFrame("Button", nil, map)
  catcher:SetAllPoints()
  catcher:SetFrameLevel(map:GetFrameLevel() + 2)
  catcher:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  catcher:SetScript("OnClick", function(_, which) Edit:MapClick(which) end)
  O.View:Hook(catcher)   -- it covers the panel while editing: zoom and drag through it too
  catcher:Hide()

  -- the selected marker's ring, on a frame above the nodes so it shows over the disc's glow
  local ringFrame = CreateFrame("Frame", nil, map)
  ringFrame:SetAllPoints()
  ringFrame:SetFrameLevel(map:GetFrameLevel() + 30)
  ring = ringFrame:CreateTexture(nil, "OVERLAY")
  ring:SetTexture(UI.TEX.ring)
  ring:SetVertexColor(GOLD[1], GOLD[2], GOLD[3], 1)
  ring:Hide()

  bar = CreateFrame("Frame", nil, map)
  bar:SetPoint("BOTTOMLEFT", 10, 10)
  bar:SetPoint("BOTTOMRIGHT", -10, 10)
  bar:SetHeight(Edit.BAR_HEIGHT - 12)
  bar:SetFrameLevel(map:GetFrameLevel() + 45)
  bar:EnableMouse(true)
  bar.box = UI.Box(bar, "BACKGROUND", 0)
  bar.box:Set(UI.Accent("oracle"), { .07, .06, .1, .97 }, { .04, .035, .06, .97 })
  bar.title = UI.Text(bar, "title", 14, UI.Accent("oracle"))
  bar.title:SetPoint("TOPLEFT", 10, -8)
  bar.title:SetText("Editing the map")
  bar.status = UI.Text(bar, "body", 12, C.muted)
  bar.status:SetPoint("LEFT", bar.title, "RIGHT", 10, 0)
  bar.done = UI.Button(bar, "Done", "accent", function() Edit:SetActive(false) end)
  bar.done:SetHeight(22)
  bar.done:SetPoint("TOPRIGHT", -8, -6)
  bar.reset = UI.Button(bar, "Reset all", "quiet", function(self)
    if confirmAt and GetTime() - confirmAt < 5 then
      confirmAt, sel, placing, note = nil, nil, nil, nil
      R:ResetAll(key())
    else
      confirmAt = GetTime()
      self:SetLabel("Click again to reset")
    end
  end)
  bar.reset:SetHeight(22)
  bar.reset:SetPoint("RIGHT", bar.done, "LEFT", -6, 0)
  bar.hint = UI.Text(bar, "body", 12, C.text)
  bar.hint:SetPoint("TOPLEFT", 10, -32)
  bar.hint:SetPoint("TOPRIGHT", -10, -32)
  bar.hint:SetJustifyH("LEFT")
  bar.label1 = UI.Text(bar, "body", 12, C.muted)
  bar.label2 = UI.Text(bar, "body", 12, C.muted)
  bar.more = UI.Text(bar, "body", 12, C.faint)

  -- the floor name box
  local box = CreateFrame("Frame", nil, bar)
  box:SetSize(150, 22)
  box.bg = UI.Box(box, "BACKGROUND", 0)
  box.bg:Set(C.lineStrong, C.inset)
  local edit = CreateFrame("EditBox", nil, box)
  edit:SetPoint("LEFT", 6, 0)
  edit:SetPoint("RIGHT", -6, 0)
  edit:SetHeight(20)
  edit:SetFontObject(UI.Font("body", 12))
  edit:SetTextColor(C.text[1], C.text[2], C.text[3])
  edit:SetAutoFocus(false)
  edit:SetMaxLetters(40)
  local function save(self)
    local d = R.Drawn()
    if d and box.floor and self:GetText() ~= R.FloorLabel(d.sheet, box.floor) then
      R:SetFloorName(d.key, box.floor, self:GetText())
    end
  end
  edit:SetScript("OnEnterPressed", function(self) save(self) self:ClearFocus() end)
  edit:SetScript("OnEscapePressed", function(self) self:ClearFocus() Edit:Update() end)
  box.edit = edit
  function box:SetText(text) edit:SetText(text or "") end
  function box:Save() save(edit) end
  bar.edit = box
  bar:Hide()

  -- a dragged marker follows the cursor
  driver = CreateFrame("Frame", nil, map)
  driver:SetScript("OnUpdate", function() Edit:DragMove() end)
  driver:Hide()
  Edit.button, Edit.bar, Edit.catcher, Edit.ring, Edit.buttons = button, bar, catcher, ring, buttons
end

---Called after every map draw (realmap.lua): shows the button or the bar for what's drawn.
function Edit:Refresh(map, k, real)
  if not mapFrame then build(map) end
  if not real then
    if self.active then self.active, sel, placing, drag = false, nil, nil, nil end
    button:Hide()
    bar:Hide()
    catcher:Hide()
    ring:Hide()
    driver:Hide()
    return
  end
  button:SetShown(not self.active)
  bar:SetShown(self.active)
  catcher:SetShown(self.active)
  if self.active then self:Update() else ring:Hide() end
end

---Turns the editor on or off (on only over a game map).
function Edit:SetActive(on)
  local k = key()
  if on and not (k and R.For(k)) then return false end
  self.active = on and true or false
  sel, placing, drag, note, confirmAt = nil, nil, nil, nil, nil
  if on then O.db.mapView = "real" end
  if O.Window and O.Window.Select then O.Window:Select(k) end
  return true
end

---/oracle edit: opens Oracle on the instance you're in (or the last one) and the editor on its map.
function Edit:Toggle()
  local win = O.Window:Get()
  if not win then return end
  if not win:IsShown() then O.Window:Open(O.CurrentInstance and O.CurrentInstance() or nil) end
  if self.active then return self:SetActive(false) end
  if not self:SetActive(true) then
    O:Print("there's no game map to edit for " .. (Core.DB:InstanceName(key() or "") or "this instance"))
  end
end

-------------------------------------------------------------------------------------------
-- Mouse
-------------------------------------------------------------------------------------------

---A node pressed (schematic.lua): starts dragging a boss or the entrance.
function Edit:NodeDown(f, which)
  if not (self.active and which == "LeftButton" and f.node) then return end
  -- (a second entrance, "entrance2", stands where the data puts it: the editor keeps one entrance)
  local who = f.node.npc or (f.node.key == "entrance" and "entrance") or nil
  if not who then return end
  local x, y = R.CursorPanel()
  drag = { frame = f, who = who, x0 = x, y0 = y, moved = false }
  driver:Show()
end

-- the panel point under the cursor, kept on the sheet
local function clampedCursor()
  local d = R.Drawn()
  local px, py = R.CursorPanel()
  local x0, y0 = R.SheetToPanel(0, 0)
  local x1, y1 = R.SheetToPanel(d.sheet.width, d.sheet.height)
  return math.max(x0, math.min(x1, px)), math.max(y0, math.min(y1, py))
end

function Edit:DragMove()
  if not drag then driver:Hide() return end
  local px, py = clampedCursor()
  if not drag.moved and math.abs(px - drag.x0) + math.abs(py - drag.y0) < 4 then return end
  drag.moved = true
  drag.frame:ClearAllPoints()
  local vx, vy = O.View.ToView(px, py)
  drag.frame:SetPoint("CENTER", O.Schematic.canvas, "TOPLEFT", vx, -vy)
  if sel and sel.kind == "marker" and sel.who == drag.who then
    ring:ClearAllPoints()
    ring:SetPoint("CENTER", drag.frame, "CENTER")
  end
end

---A node released: drops a dragged marker where the cursor is (a click without moving selects it).
function Edit:NodeUp(f, which)
  local d = drag
  if not (self.active and d and which == "LeftButton") then return end
  self:DragMove()
  drag = nil
  driver:Hide()
  sel, placing, note = { kind = "marker", who = d.who }, nil, nil
  if d.moved then
    local drawn = R.Drawn()
    local x, y = R.PanelToSheet(clampedCursor())
    note = ("%s moved. Drag again to adjust; it's saved."):format(whoName(d.who))
    R:SetPoint(drawn.key, d.who, x, y, drawn.floor)
  else
    self:Update()
  end
end

---A click on the map (not on a marker): places the boss being placed, else selects the room there.
function Edit:MapClick(which)
  if not self.active or O.View.Dragged() then return end   -- the end of a drag isn't a click
  local d = R.Drawn()
  if not d then return end
  if which == "RightButton" then
    placing, sel, note = nil, nil, nil
    return self:Update()
  end
  local px, py = R.CursorPanel()
  if placing then
    local who = placing
    placing = nil
    sel, note = { kind = "marker", who = who }, ("%s placed. Drag it to adjust."):format(whoName(who))
    local x, y = R.PanelToSheet(px, py)
    R:SetPoint(d.key, who, x, y, d.floor)
    return
  end
  local room = R.RoomAt(px, py)
  sel, note = room and { kind = "room", room = room } or nil, nil
  self:Update()
end

-- a boss chosen in the Bosses list while editing: place it when the map doesn't, else select it
O:Listen("FOCUS", Edit, function(_, npc)
  if not Edit.active then return end
  local m = R.For(key())
  if not m then return end
  if m.bosses and m.bosses[npc] then
    sel, placing, note = { kind = "marker", who = npc }, nil, nil
  else
    sel, placing, note = nil, npc, nil
  end
  Edit:Update()
end)

-- another instance: start fresh there
O:Listen("SELECTED", Edit, function(_, k)
  if Edit.shown ~= k then
    Edit.shown = k
    sel, placing, drag, note, confirmAt = nil, nil, nil, nil, nil
    if Edit.active then Edit:Update() end
  end
end)
