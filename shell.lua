-- Oracle's window (docs/oracle-redesign.md section 4; mockup design/suite/oracle-redesign.html): the top bar
-- (the mark, the global search, the spaces), then three columns: the navigator (the space's list),
-- the page (a header, its views, the content) and the Inspector (the selected item, quest, recipe or
-- boss, with its actions).
--
-- Spaces register themselves with Shell:AddSpace(key, space), where space has
--   label, order, nav(): the navigator's rows ({ group = "..." } headers, else entries),
--   navRow(row, e) / navClick(e) / navSelected(e), and Show(), Hide().
-- O:Go{ space, ... } switches space and hands the rest to the space's Go.
--
-- O.Window and O.Sidebar keep the names the kept modules call (the game map and its editor, and
-- zones.lua's map and About, hosted by the Zones space): see "Compatibility" below.

local Core = NorgannonCore
local O = Oracle
if O.disabled then return end
local UI = Core.UI
local C = UI.C

local Shell = { spaces = {}, order = {} }
O.Shell = Shell
local Window = {}
O.Window = Window

local W, H = 1320, 790
local NAV, INSPECT, PAD, GAP = 240, 340, 10, 10
local SCREEN_SHARE = .88
local MIN_ZOOM, MAX_ZOOM = .6, 1.6
local NAV_ROW = 40

local win
local function accent() return UI.Accent("oracle") end

-------------------------------------------------------------------------------------------
-- Spaces and routing
-------------------------------------------------------------------------------------------

function Shell:AddSpace(key, space)
  space.key = key
  self.spaces[key] = space
  self.order[#self.order + 1] = key
  table.sort(self.order, function(a, b) return (self.spaces[a].order or 9) < (self.spaces[b].order or 9) end)
end

---The space shown now.
function Shell:Space() return self.spaces[self.current] end

---Shows a space (and refreshes the navigator).
function Shell:ShowSpace(key)
  local space = self.spaces[key]
  if not (space and win) then return end
  if self.current ~= key then
    local old = self.spaces[self.current]
    if old and old.Hide then old:Hide() end
    self.current = key
    O.db.space = key
  end
  if win.spaces then win.spaces:Select(key, true) end
  if space.Show then space:Show() end
  self:RefreshNav()
end

---Goes somewhere: { space = "dungeons", key = "deadmines", view = "loot", boss = 639 }, or for the
---Inspector { inspect = { kind, id } } on its own or with a place.
function O:Go(where)
  Window:Get()
  if not win then return end
  if not win:IsShown() then win:Show() end
  if where.space then
    Shell:ShowSpace(where.space)
    local space = Shell.spaces[where.space]
    if space and space.Go then space:Go(where) end
    Shell:RefreshNav()
  end
  if where.inspect and O.Inspector then O.Inspector:Show(where.inspect[1], where.inspect[2]) end
end

-------------------------------------------------------------------------------------------
-- The navigator
-------------------------------------------------------------------------------------------

function Shell:RefreshNav()
  if not (win and win.navList) then return end
  local space = self:Space()
  local rows = space and space.nav and space:nav() or {}
  win.navList:SetData(rows, true)
  local selected
  for _, e in ipairs(rows) do
    if not e.group and space.navSelected and space:navSelected(e) then selected = e break end
  end
  win.navList:Select(selected)
  win.navEmpty:SetShown(#rows == 0)
  if space and space.navTop then space:navTop(win.navTop) end
end

local function buildNav(parent)
  local nav = CreateFrame("Frame", nil, parent)
  -- a strip above the list a space can fill (Dungeons / Raids)
  win.navTop = CreateFrame("Frame", nil, nav)
  win.navTop:SetPoint("TOPLEFT")
  win.navTop:SetPoint("TOPRIGHT")
  win.navTop:SetHeight(1)
  local pane = UI.Pane(nav)
  pane:SetPoint("TOPLEFT", win.navTop, "BOTTOMLEFT", 0, -6)
  pane:SetPoint("BOTTOMRIGHT")
  win.navList = UI.List(pane, {
    rowHeight = NAV_ROW,
    createRow = function(row, content)
      row.name = UI.Text(content, "body", 14, C.text)
      row.name:SetPoint("TOPLEFT", 12, -5)
      row.name:SetPoint("TOPRIGHT", content, "TOPRIGHT", -58, -5)
      row.name:SetWordWrap(false)
      row.meta = UI.Text(content, "body", 12, C.faint)
      row.meta:SetPoint("TOPLEFT", row.name, "BOTTOMLEFT", 0, -1)
      row.meta:SetPoint("TOPRIGHT", content, "TOPRIGHT", -10, -21)
      row.meta:SetWordWrap(false)
      row.right = UI.Text(content, "body", 13)
      row.right:SetPoint("TOPRIGHT", -10, -6)
      row.right:SetJustifyH("RIGHT")
    end,
    updateRow = function(row, e)
      row.name:SetText(e.name or "")
      row.meta:SetText(e.navMeta or "")
      row.right:SetText(e.navRight or "")
      local c = e.navRightColor or C.muted
      row.right:SetTextColor(c[1], c[2], c[3])
      local space = Shell:Space()
      if space and space.navRow then space:navRow(row, e) end
    end,
    onClick = function(e)
      local space = Shell:Space()
      if space and space.navClick then space:navClick(e) end
    end,
  })
  win.navList:SetPoint("TOPLEFT", 1, -5)
  win.navList:SetPoint("BOTTOMRIGHT", -1, 4)
  win.navList:ApplyAccent(accent())
  win.navEmpty = UI.Text(pane, "body", 13, C.faint)
  win.navEmpty:SetPoint("TOPLEFT", 12, -12)
  win.navEmpty:SetPoint("TOPRIGHT", -12, -12)
  win.navEmpty:SetText("Nothing here yet.")
  win.navEmpty:Hide()
  return nav
end

-------------------------------------------------------------------------------------------
-- The page: a header (title, facts, badges), view tabs, the content
-------------------------------------------------------------------------------------------

local function buildPage(parent)
  local page = CreateFrame("Frame", nil, parent)
  page.title = UI.Text(page, "title", 26, C.gold)
  page.title:SetPoint("TOPLEFT", 4, -2)
  page.title:SetPoint("TOPRIGHT", page, "TOPRIGHT", -8, -2)
  page.title:SetWordWrap(false)
  page.facts = UI.Text(page, "body", 13, C.muted)
  page.facts:SetPoint("TOPLEFT", page.title, "BOTTOMLEFT", 0, -3)
  page.facts:SetPoint("TOPRIGHT", page.title, "BOTTOMRIGHT", 0, -3)
  page.facts:SetWordWrap(false)
  page.badges = UI.Text(page, "body", 12, C.faint)
  page.badges:SetPoint("TOPLEFT", page.facts, "BOTTOMLEFT", 0, -4)
  page.badges:SetPoint("TOPRIGHT", page.facts, "BOTTOMRIGHT", 0, -4)
  page.badges:SetWordWrap(false)
  -- the views' tabs sit under the header; a space builds them (Shell:Views)
  page.viewsAt = 74
  -- the right end of the tabs' row, for filters
  page.tools = CreateFrame("Frame", nil, page)
  page.tools:SetPoint("TOPRIGHT", page, "TOPRIGHT", 0, -page.viewsAt - 2)
  page.tools:SetSize(360, 26)
  page.content = CreateFrame("Frame", nil, page)
  page.content:SetPoint("TOPLEFT", 0, -page.viewsAt - 36)
  page.content:SetPoint("BOTTOMRIGHT")
  return page
end

---A page's header text: title, the facts line, the badges line.
function Shell:SetHeader(title, facts, badges)
  local page = win.page
  page.title:SetText(title or "")
  page.facts:SetText(facts or "")
  page.badges:SetText(badges or "")
  page.title:SetShown(title ~= nil)
  page.facts:SetShown(facts ~= nil)
  page.badges:SetShown(badges ~= nil)
end

---Tabs for a space's views, under the page header: { { key, label }, ... } (keyed). Returns the UI.Tabs.
function Shell:Views(list, onSelect)
  local tabs = UI.Tabs(win.page, list, onSelect)
  tabs:SetPoint("TOPLEFT", 0, -win.page.viewsAt)
  tabs:SetPoint("TOPRIGHT", win.page.tools, "TOPLEFT", -8, 0)
  tabs:ApplyAccent(accent())
  return tabs
end

-------------------------------------------------------------------------------------------
-- The window
-------------------------------------------------------------------------------------------

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
  if win.grip then win.grip:SetShown(not O.db.locked) end
end

---Zooms the window, keeping its top-left corner at left, top (UIParent units).
function Window:SetZoom(zoom, left, top)
  O.db.scale = math.max(MIN_ZOOM, math.min(MAX_ZOOM, zoom))
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

local function sizeGrip()
  local grip = CreateFrame("Button", nil, win)
  grip:SetSize(16, 16)
  grip:SetPoint("BOTTOMRIGHT", -3, 3)
  grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
  grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
  grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
  local function cursorX() return (GetCursorPosition()) / UIParent:GetEffectiveScale() end
  grip:SetScript("OnMouseDown", function(self, button)
    if button ~= "LeftButton" or O.db.locked then return end
    local s = win:GetScale()
    self.left, self.top = (win:GetLeft() or 0) * s, (win:GetTop() or 0) * s
    self.startX, self.startScale = cursorX(), O.db.scale or 1
    self.width = W * Window.Scale()
    self:SetScript("OnUpdate", function()
      local wanted = self.width + (cursorX() - self.startX)
      Window:SetZoom(self.startScale * wanted / self.width, self.left, self.top)
    end)
  end)
  grip:SetScript("OnMouseUp", function(self) self:SetScript("OnUpdate", nil) end)
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
  return grip
end

local function build()
  win = UI.Window({ name = "OracleWindow", addon = "oracle", title = "Oracle", sub = "", width = W, height = H, footer = true })
  win:SetAccent("oracle")
  win:Hide()
  Window.frame = win
  if win.sub then win.sub:SetText("") win.sub:Hide() end
  -- "Beta" under the name, while Oracle is in beta
  win.title:ClearAllPoints()
  win.title:SetPoint("LEFT", win.mark, "RIGHT", 10, 5)
  win.beta = UI.Text(win.header, "body", 10, C.faint)
  win.beta:SetPoint("TOPLEFT", win.title, "BOTTOMLEFT", 1, 1)
  win.beta:SetText("BETA")

  -- the top bar: the search, then the spaces
  win.search = O.Search and O.Search:Build(win.header) or nil
  if win.search then
    win.search:SetPoint("LEFT", win.title, "RIGHT", 18, 0)
    win.search:SetSize(360, 26)
  end
  local spaces = {}
  for _, key in ipairs(Shell.order) do spaces[#spaces + 1] = { key = key, label = Shell.spaces[key].label } end
  win.spaces = UI.Tabs(win.header, spaces, function(key) Shell:ShowSpace(key) end)
  win.spaces:SetPoint("BOTTOMLEFT", win.header, "BOTTOMLEFT", 420 + 70, 0)
  win.spaces:SetPoint("BOTTOMRIGHT", win.header, "BOTTOMRIGHT", -40, 0)
  win.spaces:ApplyAccent(accent())
  if O.Wants then win.spaces:SetCount("wants", O.Wants:Count()) end

  -- the three columns
  local body = win.body
  win.nav = buildNav(body)
  win.nav:SetPoint("TOPLEFT", PAD, -PAD)
  win.nav:SetPoint("BOTTOMLEFT", PAD, PAD)
  win.nav:SetWidth(NAV)
  win.inspect = CreateFrame("Frame", nil, body)
  win.inspect:SetPoint("TOPRIGHT", -PAD, -PAD)
  win.inspect:SetPoint("BOTTOMRIGHT", -PAD, PAD)
  win.inspect:SetWidth(INSPECT)
  win.page = buildPage(body)
  win.page:SetPoint("TOPLEFT", win.nav, "TOPRIGHT", GAP, 0)
  win.page:SetPoint("BOTTOMRIGHT", win.inspect, "BOTTOMLEFT", -GAP, 0)

  -- Compatibility: the old Crafts and Zones pages fill these two (their column and their detail)
  win.mapcol = CreateFrame("Frame", nil, body)
  win.mapcol:SetPoint("TOPLEFT", win.page, "TOPLEFT")
  win.mapcol:SetPoint("BOTTOMRIGHT", win.page, "BOTTOMRIGHT")
  win.detail = CreateFrame("Frame", nil, body)
  win.detail:SetAllPoints(win.inspect)

  if O.Inspector then O.Inspector:Build(win.inspect) end
  for _, key in ipairs(Shell.order) do
    local space = Shell.spaces[key]
    if space.Build then space:Build(win.page, win) end
  end

  -- footer: a hint, window opacity, Lock; the size grip
  win.footerText:SetText("Search anything above · click an item, quest or boss to see it on the right")
  win.lockButton = UI.Button(win.footer, "Lock", "quiet", function()
    O.db.locked = not O.db.locked
    win.lockButton:SetLabel(O.db.locked and "Unlock" or "Lock")
    Window:ApplyLook()
  end)
  win.lockButton:SetSize(54, 20)
  win.lockButton:SetPoint("RIGHT", -28, 0)
  win.lockButton:SetLabel(O.db.locked and "Unlock" or "Lock")
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
  win.grip = sizeGrip()

  Window:ApplyLook()
  win:HookScript("OnShow", function() Window:ApplyLook() end)
end

---The window (built on first use).
function Window:Get()
  if not win and O.db then build() end
  return win
end

-------------------------------------------------------------------------------------------
-- Compatibility: what the kept modules call
-------------------------------------------------------------------------------------------

local legacyPanes = {}

---Registers an old tab's pane (Quests, Info, Loot, Bosses): build(frame) once, fill(frame, entry).
---Oracle's Dungeons space hosts the ones it still uses.
function Window:RegisterPane(key, build, fill)
  legacyPanes[key] = { build = build, fill = fill }
end
Window.panes = legacyPanes

---Shows an instance (the old name): Dungeons & Raids on that instance, keeping the view.
function Window:Select(key)
  O:Go({ space = "dungeons", key = key })
end

---Opens the window on an instance, else where it was.
function Window:Open(key)
  self:Get()
  if not win then return end
  win:Show()
  if key then return O:Go({ space = "dungeons", key = key }) end
  Shell:ShowSpace(O.db.space and Shell.spaces[O.db.space] and O.db.space or "dungeons")
  local space = Shell:Space()
  if space and space.Go then space:Go({}) end
  Shell:RefreshNav()
end

---The old Crafts and Zones pages call this when they show something.
function Window:SetMode(mode)
  local map = { crafts = "professions", zones = "zones" }
  if map[mode] and Shell.current ~= map[mode] then Shell:ShowSpace(map[mode]) end
  self.mode = mode
end

---The game map: draw it on the Dungeons space's map panel (and its markers).
function Window:DrawMap(key)
  local d = Shell.spaces.dungeons
  return d and d.DrawMap and d:DrawMap(key) or false
end

function Window:DrawMarkers()
  local d = Shell.spaces.dungeons
  if d and d.map then O.MapPanel:DrawMarkers(d.map) end
end

-- The old sidebar's calls, now the navigator's
O.Sidebar = {
  SetSelected = function() Shell:RefreshNav() end,
  Refresh = function() Shell:RefreshNav() end,
  HereZone = function()
    local uiMap = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
    return uiMap and Core.Map.UiMapToArea(uiMap)
  end,
  FirstCraft = function()
    local entries = O.Crafts and O.Crafts:Entries() or {}
    for _, e in ipairs(entries) do if e.skill then return e.craft end end
    return entries[1] and entries[1].craft
  end,
}
