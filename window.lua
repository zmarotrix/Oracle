-- Oracle's window (design/suite/oracle.html): the suite frame, then three columns: the sidebar
-- (search, Dungeons / Raids, sort, the list), the map column (the instance's name and facts over
-- the schematic) and the detail column (Bosses, Loot, Quests, Info tabs), and the footer
-- (a hint, window opacity, Lock).
--
-- The mockup's layout is 1320 x 790; the window keeps those numbers and is scaled to take the
-- same share of the screen (88% of its height), so every gap and type size keeps its proportion.
-- Dragging the bottom-right corner zooms the whole window (saved as OracleDB.scale).

local Core = NorgannonCore
local O = Oracle
if O.disabled then return end
local UI = Core.UI
local C = UI.C

local Window = {}
O.Window = Window

local W, H = 1320, 790
local SIDE, DETAIL, GAP, PAD = 262, 392, 10, 10
local SCREEN_SHARE = .88
local GRID = 32
local MIN_ZOOM, MAX_ZOOM = .6, 1.6   -- the size grip's range, on top of the fit-to-screen scale

local win
local panes = {}

local function accent() return UI.Accent("oracle") end

-------------------------------------------------------------------------------------------
-- Scale, opacity, lock
-------------------------------------------------------------------------------------------

---The window's scale: the mockup's share of the screen, times the player's own size setting.
function Window.Scale()
  local screen = UIParent:GetHeight() or 768
  return math.min(1.25, screen * SCREEN_SHARE / H) * (O.db.scale or 1)
end

function Window:ApplyLook()
  if not win then return end
  win:SetSize(W, H)
  win:SetScale(Window.Scale())
  win:SetAlpha(O.db.opacity or 1)
  win.locked = O.db.locked and true or false
  if win.lockButton then win.lockButton:SetLabel(O.db.locked and "Unlock" or "Lock") end
  if win.grip then win.grip:SetShown(not O.db.locked) end
end

---Zooms the window (1 = the mockup's share of the screen), keeping its top-left corner at
---left, top (UIParent units); saves the zoom and the position.
function Window:SetZoom(zoom, left, top)
  O.db.scale = math.max(MIN_ZOOM, math.min(MAX_ZOOM, zoom))
  O.db.width, O.db.height = nil, nil   -- from builds that resized instead of zooming
  local s = Window.Scale()
  win:SetScale(s)
  if left and top then
    win:ClearAllPoints()
    win:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left / s, top / s)
    if Core.db and Core.db.windows then
      Core.db.windows.OracleWindow = { point = "TOPLEFT", relativePoint = "BOTTOMLEFT", x = left / s, y = top / s }
    end
  end
end

-------------------------------------------------------------------------------------------
-- The map column: header and the schematic's panel
-------------------------------------------------------------------------------------------

local function mapPanel(parent)
  local map = CreateFrame("Frame", nil, parent)
  map:SetClipsChildren(true)
  map.bg = UI.Tex(map, "BACKGROUND", 0, { .051, .043, .071 })
  map.bg:SetAllPoints()
  -- a soft violet light in the upper middle
  map.light = map:CreateTexture(nil, "BACKGROUND", nil, 1)
  map.light:SetTexture(UI.TEX.glow)
  map.light:SetVertexColor(.706, .549, 1, .08)
  map.light:SetBlendMode("ADD")
  -- the faint grid, every 32 pixels
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
    if O.db.selected and O.Schematic and win and win:IsShown() then O.Schematic:Draw(self, O.db.selected) end
  end)

  -- the empty state: no schematic for this instance yet
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

local function fillHeader(e)
  local col = win.mapcol
  col.title:SetText(e.name)
  local lc = O.Model.LevelColor(e)
  local parts = { UI.Code(lc) .. "Level " .. O.Model.LevelText(e) .. "|r" }
  if e.size then parts[#parts + 1] = e.size .. " players" end
  if e.zone then
    local where = e.zone
    if e.entrance then where = where .. string.format(" (%s, %s)", e.entrance.x, e.entrance.y) end
    parts[#parts + 1] = where
  end
  col.facts:SetText(table.concat(parts, "  ·  "))
  local empty = col.map.empty
  local drawn = O.Schematic and O.Schematic:Draw(col.map, e.key)
  empty:SetShown(not drawn)
  if e.forever and e.bosses == 0 then
    empty.title:SetText("Not mapped yet")
    empty.line1:SetText("WoW Forever added " .. e.name .. "; NorgannonDB learns it from players.")
    empty.line2:SetText("Run it with the NorgannonDB Collector to help map it.")
  else
    empty.title:SetText("Schematic not drawn yet")
    empty.line1:SetText(string.format("%d bosses and %d quests are known for %s.", e.bosses, e.quests, e.name))
    empty.line2:SetText("Its schematic map hasn't been drawn yet.")
  end
end

-------------------------------------------------------------------------------------------
-- The detail column: tabs over panes (Bosses, Loot, Quests until their builds: a note)
-------------------------------------------------------------------------------------------

local TABS = {
  { key = "bosses", label = "Bosses" }, { key = "loot", label = "Loot" },
  { key = "quests", label = "Quests" }, { key = "info", label = "Info" },
}

---Registers a tab's pane: fill(pane, entry) draws it for an instance.
function Window:RegisterPane(key, build, fill)
  panes[key] = { build = build, fill = fill }
end

local function showTab(key)
  O.db.tab = key
  for k, p in pairs(panes) do
    if p.frame then p.frame:SetShown(k == key) end
  end
  win.placeholder:SetShown(not panes[key])
  if not panes[key] then
    local coming = { bosses = "The boss list arrives", loot = "Loot tables arrive", quests = "Quests arrive" }
    win.placeholder:SetText((coming[key] or "This arrives") .. " in the next build. The Info tab has everything else.")
  end
  local e = O.Model:Get(O.db.selected)
  local p = panes[key]
  if p and e then p.fill(p.frame, e) end
end
Window.ShowTab = showTab

-------------------------------------------------------------------------------------------
-- Building
-------------------------------------------------------------------------------------------

local function build()
  win = UI.Window({ name = "OracleWindow", addon = "oracle", title = "Oracle", sub = "Dungeons & raids",
    width = W, height = H, footer = true })
  win:SetAccent("oracle")
  win:Hide()
  local body = win.body

  -- columns
  local side = CreateFrame("Frame", nil, body)
  side:SetPoint("TOPLEFT", PAD, -PAD)
  side:SetPoint("BOTTOMLEFT", PAD, PAD)
  side:SetWidth(SIDE)
  win.side = side
  local detail = CreateFrame("Frame", nil, body)
  detail:SetPoint("TOPRIGHT", -PAD, -PAD)
  detail:SetPoint("BOTTOMRIGHT", -PAD, PAD)
  detail:SetWidth(DETAIL)
  win.detail = detail
  local col = CreateFrame("Frame", nil, body)
  col:SetPoint("TOPLEFT", side, "TOPRIGHT", GAP, 0)
  col:SetPoint("BOTTOMRIGHT", detail, "BOTTOMLEFT", -GAP, 0)
  win.mapcol = col

  -- map column: "The Deadmines   Level 17–26 · 5 players · Westfall (42.5, 71.7)"
  col.title = UI.Text(col, "title", 26, C.gold)
  col.title:SetPoint("TOPLEFT", 4, -2)
  col.facts = UI.Text(col, "body", 13, C.muted)
  col.facts:SetPoint("BOTTOMLEFT", col.title, "BOTTOMRIGHT", 12, 3)
  col.map = mapPanel(col)
  col.map:SetPoint("TOPLEFT", 0, -42)
  col.map:SetPoint("BOTTOMRIGHT", 0, 0)

  -- detail column: tabs and their panes
  win.tabs = UI.Tabs(detail, TABS, function(key) showTab(key) end)
  win.tabs:SetPoint("TOPLEFT")
  win.tabs:SetPoint("TOPRIGHT")
  win.tabs:ApplyAccent(accent())
  win.paneArea = CreateFrame("Frame", nil, detail)
  win.paneArea:SetPoint("TOPLEFT", win.tabs, "BOTTOMLEFT", 0, -6)
  win.paneArea:SetPoint("BOTTOMRIGHT", 0, 0)
  win.placeholder = UI.Text(win.paneArea, "body", 13, C.faint)
  win.placeholder:SetPoint("TOPLEFT", 10, -10)
  win.placeholder:SetPoint("TOPRIGHT", -10, -10)
  win.placeholder:SetWordWrap(true)
  for _, p in pairs(panes) do
    p.frame = CreateFrame("Frame", nil, win.paneArea)
    p.frame:SetAllPoints()
    p.build(p.frame)
    p.frame:Hide()
  end

  -- footer: the hint, window opacity, Lock
  win.footerText:SetText("Click a number on the map or in the list to focus a boss")
  win.lockButton = UI.Button(win.footer, "Lock", "quiet", function()
    O.db.locked = not O.db.locked
    Window:ApplyLook()
  end)
  win.lockButton:SetSize(54, 20)
  win.lockButton:SetPoint("RIGHT", -28, 0)

  -- the size grip in the bottom-right corner: dragging zooms the whole window (the layout stays
  -- the mockup's), with its top-left corner held in place
  local grip = CreateFrame("Button", nil, win)
  grip:SetSize(16, 16)
  grip:SetPoint("BOTTOMRIGHT", -3, 3)
  grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
  grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
  grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
  local function cursorX() return (GetCursorPosition()) / UIParent:GetEffectiveScale() end
  grip:SetScript("OnMouseDown", function(self, button)
    if button ~= "LeftButton" or O.db.locked then return end
    -- hold the top-left corner: re-anchor there in UIParent units
    local s = win:GetScale()
    self.left, self.top = (win:GetLeft() or 0) * s, (win:GetTop() or 0) * s
    self.startX, self.startScale = cursorX(), O.db.scale or 1
    self.width = W * Window.Scale()                    -- the window's width on screen, in UIParent units
    self:SetScript("OnUpdate", function()
      local wanted = self.width + (cursorX() - self.startX)
      Window:SetZoom(self.startScale * wanted / self.width, self.left, self.top)
    end)
  end)
  grip:SetScript("OnMouseUp", function(self)
    self:SetScript("OnUpdate", nil)
  end)
  grip:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:AddLine("Drag to make the window bigger or smaller", 1, 1, 1)
    GameTooltip:AddLine("Right-click: the original size", C.muted[1], C.muted[2], C.muted[3])
    GameTooltip:Show()
  end)
  grip:SetScript("OnLeave", function() GameTooltip:Hide() end)
  grip:RegisterForClicks("RightButtonUp")
  grip:SetScript("OnClick", function()
    local s = win:GetScale()
    Window:SetZoom(1, (win:GetLeft() or 0) * s, (win:GetTop() or 0) * s)
  end)
  win.grip = grip
  win.opacity = UI.Slider(win.footer, .4, 1, .05, function(v)
    O.db.opacity = v
    win:SetAlpha(v)
  end)
  win.opacity:SetWidth(90)
  win.opacity:SetValue(O.db.opacity or 1, true)
  win.opacity:SetPoint("RIGHT", win.lockButton, "LEFT", -12, 0)
  win.opacityLabel = UI.Text(win.footer, "body", 12, C.faint)
  win.opacityLabel:SetPoint("RIGHT", win.opacity, "LEFT", -6, 0)
  win.opacityLabel:SetText("Window opacity")

  if O.Sidebar then O.Sidebar:Build(side) end
  Window:ApplyLook()
  win:HookScript("OnShow", function() Window:ApplyLook() end)
  Window.frame = win
end

---The window (built on first use).
function Window:Get()
  if not win and O.db then build() end
  return win
end

---Shows an instance: the list's selection, the header, the map panel and the open tab.
function Window:Select(key)
  local e = key and O.Model:Get(key)
  if not e then
    local all = O.Model:All()
    e = all[1]
    if not e then return end
  end
  O.db.selected = e.key
  fillHeader(e)
  win.tabs:SetCount("bosses", e.bosses)
  win.tabs:SetCount("quests", e.quests)
  local loot = 0
  for _, b in ipairs(e.inst.bosses or {}) do loot = loot + #(b.loot or {}) end
  win.tabs:SetCount("loot", loot)
  if O.Sidebar then O.Sidebar:SetSelected(e.key) end
  showTab(O.db.tab or "info")
  win.tabs:Select(O.db.tab or "info", true)
  O:Send("SELECTED", e.key)
end

---Opens the window on an instance (or the last one shown).
function Window:Open(key)
  self:Get()
  if not win then return end
  win:Show()
  if O.Sidebar then O.Sidebar:Refresh() end
  self:Select(key or O.db.selected)
end
