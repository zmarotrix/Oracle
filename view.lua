-- The map panel's view: zoom with the mouse wheel (toward the cursor), drag to move around,
-- double-click to see the whole map again. Shared by the game map and the schematic.
--
-- Coordinates: "panel" points are the map panel's own pixels at zoom 1, from its top-left (what
-- RealMap and the schematic lay out in); "view" points are where they show now.
--   view = (panel - corner) * zoom
-- The game map's tiles sit on map.stage, a frame scaled by the zoom, so they scale for free and
-- RealMap's cursor conversions (made through its layer, on the stage) stay in panel points. The
-- schematic's markers stay their size: they're placed through View.ToView and redrawn on change.

local O = Oracle

local View = { zoom = 1, x = 0, y = 0, MIN = 1, MAX = 4, STEP = 1.25 }
O.View = View

local map, stage, driver, drag, lastDown

local function size()
  return (map and map:GetWidth() or 0), (map and map:GetHeight() or 0)
end

---A panel point -> where it shows in the panel now.
function View.ToView(px, py)
  return (px - View.x) * View.zoom, (py - View.y) * View.zoom
end

---A point shown in the panel -> the panel point there.
function View.FromView(vx, vy)
  return View.x + vx / View.zoom, View.y + vy / View.zoom
end

-- the cursor in view points from the panel's top-left
local function cursor()
  local x, y = GetCursorPosition()
  local s = map:GetEffectiveScale() or 1
  return x / s - (map:GetLeft() or 0), (map:GetTop() or 0) - y / s
end
View.Cursor = cursor

local function apply()
  local w, h = size()
  stage:SetSize(w, h)
  stage:SetScale(View.zoom)
  stage:ClearAllPoints()
  -- a scaled frame's offsets are in its own (scaled) units: panel points
  stage:SetPoint("TOPLEFT", map, "TOPLEFT", -View.x, View.y)
end

---Sets the zoom and the panel point at the view's top-left (kept inside the map), and redraws the
---markers when the view changed. No arguments: the whole map.
function View:Set(zoom, x, y, quiet)
  local w, h = size()
  zoom = math.max(self.MIN, math.min(self.MAX, zoom or 1))
  x = math.max(0, math.min(w - w / zoom, x or 0))
  y = math.max(0, math.min(h - h / zoom, y or 0))
  local changed = zoom ~= self.zoom or x ~= self.x or y ~= self.y
  self.zoom, self.x, self.y = zoom, x, y
  if stage then apply() end
  if changed and not quiet and O.Window and O.Window.DrawMarkers then O.Window:DrawMarkers() end
  return changed
end

function View:Reset(quiet) return self:Set(1, 0, 0, quiet) end

function View:Zoomed() return self.zoom > 1 end

---Zooms by a factor, keeping the panel point under a view point (the cursor) where it is.
function View:ZoomAt(factor, vx, vy)
  local px, py = View.FromView(vx, vy)
  local zoom = math.max(self.MIN, math.min(self.MAX, self.zoom * factor))
  if math.abs(zoom - 1) < .01 then zoom = 1 end
  return self:Set(zoom, px - vx / zoom, py - vy / zoom)
end

---Whether the last left press moved the view (the click that ends it is not a click).
function View.Dragged() return drag ~= nil and drag.moved end

local function dragMove()
  if not drag then driver:Hide() return end
  local cx, cy = cursor()
  local dx, dy = cx - drag.cx, cy - drag.cy
  if not drag.moved and math.abs(dx) + math.abs(dy) < 4 then return end
  drag.moved = true
  View:Set(View.zoom, drag.x - dx / View.zoom, drag.y - dy / View.zoom)
end

---A left press on the map (the panel, or the editor's catcher over it): starts moving the view;
---a second press soon after shows the whole map.
function View:Down(which)
  if which ~= "LeftButton" then return end
  local now = GetTime()
  if lastDown and now - lastDown < .3 then
    lastDown = nil
    drag = nil
    return self:Reset()
  end
  lastDown = now
  if not self:Zoomed() then drag = nil return end
  local cx, cy = cursor()
  drag = { cx = cx, cy = cy, x = self.x, y = self.y, moved = false }
  driver:Show()
end

function View:Up(which)
  if which ~= "LeftButton" or not drag then return end
  dragMove()
  driver:Hide()
  -- drag stays until the next press, so a click handler running after this can ask Dragged()
end

---Makes a frame over the panel take part: wheel to zoom, left-drag to move.
function View:Hook(f)
  f:EnableMouseWheel(true)
  f:SetScript("OnMouseWheel", function(_, delta)
    local vx, vy = cursor()
    View:ZoomAt(delta > 0 and View.STEP or 1 / View.STEP, vx, vy)
  end)
  f:HookScript("OnMouseDown", function(_, which) View:Down(which) end)
  f:HookScript("OnMouseUp", function(_, which) View:Up(which) end)
end

---Sets up the view on the map panel (window.lua): its stage, and the panel's mouse.
function View:Attach(panel)
  map = panel
  stage = CreateFrame("Frame", nil, map)
  stage:SetFrameLevel(map:GetFrameLevel())
  map.stage = stage
  map:EnableMouse(true)
  self:Hook(map)
  driver = CreateFrame("Frame", nil, map)
  driver:SetScript("OnUpdate", dragMove)
  driver:Hide()
  apply()
  return stage
end

---The panel changed size: keep the view in it.
function View:Resized()
  if stage then self:Set(self.zoom, self.x, self.y, true) end
end
