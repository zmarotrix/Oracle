-- A detail sheet: a scrolling column of headings, text, item rows and lines with "Show on map",
-- drawn top to bottom and reused on every redraw (the Crafts and Zones detail columns).
--
--   local sheet = O.Sheet.New(parent)      -- fills parent, in an inset pane
--   sheet:Begin()
--   sheet:Text("Fine Leather Boots", 22, color, "title")
--   sheet:Heading("Reagents")
--   sheet:Item(itemId, "×7 · Sold by 4 vendors", 7, function() ... end)
--   sheet:Line("Hula'mahi", "Trainer · The Barrens · 50s", { kind = "npc", id = 3013 })
--   sheet:End()

local Core = NorgannonCore
local O = Oracle
if O.disabled then return end
local UI = Core.UI
local C = UI.C

local Sheet = {}
Sheet.__index = Sheet
O.Sheet = Sheet

---Shows an entity on your map through Clairvoyance; false when Clairvoyance isn't there.
function Sheet.Track(kind, id)
  for _, action in ipairs(Core:ActionsFor(kind, id)) do
    if action.id == "clairvoyance.track" then
      action.run(kind, id)
      return true
    end
  end
  O:Print("Clairvoyance shows things on your map; it isn't loaded.")
  return false
end

local function trackButton(parent)
  local b = UI.Button(parent, "Show on map", "quiet", function(self)
    if self.kind then Sheet.Track(self.kind, self.id) end
  end)
  b:SetSize(92, 20)
  b:ApplyAccent(UI.Accent("clairvoyance"))
  return b
end

---Whether Clairvoyance could show an item's sources on the map: something drops or sells it.
function Sheet.Findable(item)
  local info = Core.DB:ItemInfo(item)
  if not info then return false end
  if next(info.vendors) or next(info.drops.npcs or {}) or next(info.drops.objects or {}) then return true end
  return false
end

function Sheet.New(parent)
  local self = setmetatable({ pool = { text = {}, item = {}, line = {} }, used = {} }, Sheet)
  self.box = UI.Pane(parent)
  self.box:SetAllPoints()
  self.area = UI.ScrollArea(self.box)
  self.area:SetPoint("TOPLEFT", 4, -4)
  self.area:SetPoint("BOTTOMRIGHT", -4, 4)
  self.placeholder = UI.Text(self.box, "body", 13, C.faint)
  self.placeholder:SetPoint("TOPLEFT", 14, -14)
  self.placeholder:SetPoint("TOPRIGHT", -14, -14)
  self.placeholder:SetWordWrap(true)
  return self
end

function Sheet:take(kind, make)
  self.used[kind] = (self.used[kind] or 0) + 1
  local list = self.pool[kind]
  local f = list[self.used[kind]]
  if not f then
    f = make(self)
    list[self.used[kind]] = f
  end
  f:ClearAllPoints()
  f:Show()
  return f
end

local function makeText(self)
  local t = UI.Text(self.area.content, "body", 13, C.text)
  t:SetWordWrap(true)
  t:SetJustifyH("LEFT")
  return t
end

local function makeItem(self)
  local f = CreateFrame("Button", nil, self.area.content)
  f:SetHeight(40)
  f.rightInset = 100
  f.hover = UI.Tex(f, "BACKGROUND", 0, { 1, 1, 1, .04 })
  f.hover:SetAllPoints()
  f.hover:Hide()
  O.Items.Build(f)
  f.count = UI.Text(f.tile, "title", 12, { 1, 1, 1 }, "OVERLAY")
  f.count:SetPoint("BOTTOMRIGHT", -1, 1)
  f.track = trackButton(f)
  f.track:SetPoint("RIGHT", -4, 0)
  O.Items.Hook(f)
  f:HookScript("OnClick", function(row)
    if IsShiftKeyDown() or IsControlKeyDown() then return end
    if row.onClick then row.onClick() end
  end)
  return f
end

local function makeLine(self)
  local f = CreateFrame("Button", nil, self.area.content)
  f:SetHeight(34)
  f.hover = UI.Tex(f, "BACKGROUND", 0, { 1, 1, 1, .04 })
  f.hover:SetAllPoints()
  f.hover:Hide()
  f.name = UI.Text(f, "body", 14, C.text)
  f.name:SetPoint("TOPLEFT", 6, -2)
  f.name:SetPoint("TOPRIGHT", -100, -2)
  f.name:SetWordWrap(false)
  f.meta = UI.Text(f, "body", 12, C.muted)
  f.meta:SetPoint("TOPLEFT", f.name, "BOTTOMLEFT", 0, -1)
  f.meta:SetPoint("TOPRIGHT", f.name, "BOTTOMRIGHT", 0, -1)
  f.meta:SetWordWrap(false)
  f.track = trackButton(f)
  f.track:SetPoint("RIGHT", -4, 0)
  f:SetScript("OnEnter", function(row) if row.onClick then row.hover:Show() end end)
  f:SetScript("OnLeave", function(row) row.hover:Hide() end)
  f:SetScript("OnClick", function(row) if row.onClick then row.onClick() end end)
  return f
end

---Starts a redraw: everything from the last one is put away. placeholder: shown instead, when set.
function Sheet:Begin(placeholder)
  for _, kind in pairs(self.pool) do for _, f in ipairs(kind) do f:Hide() end end
  self.used = {}
  self.y = -8
  self.width = math.max(200, (self.area:GetWidth() or 380) - 4)
  self.placeholder:SetShown(placeholder ~= nil)
  self.placeholder:SetText(placeholder or "")
end

function Sheet:Text(str, size, color, role, gap)
  local t = self:take("text", makeText)
  t:SetFontObject(UI.Font(role or "body", size or 13))
  color = color or C.text
  t:SetTextColor(color[1], color[2], color[3])
  t:SetText(str)
  self.y = self.y - (gap or 0)
  t:SetPoint("TOPLEFT", self.area.content, "TOPLEFT", 10, self.y)
  t:SetWidth(self.width - 20)
  self.y = self.y - (t:GetStringHeight() or 14) - 4
  return t
end

function Sheet:Heading(str) return self:Text(str, 15, C.goldSoft, "title", 10) end

---An item row: icon, name in its quality colour, meta; hover for the tooltip, "Show on map".
function Sheet:Item(item, meta, count, onClick)
  local f = self:take("item", makeItem)
  f:SetPoint("TOPLEFT", self.area.content, "TOPLEFT", 4, self.y)
  f:SetWidth(self.width - 8)
  O.Items.Fill(f, item)
  if meta then f.itemMeta:SetText(meta) end
  f.count:SetText(count and count > 1 and count or "")
  f.onClick = onClick
  f.track.kind, f.track.id = "item", item
  f.track:SetShown(Sheet.Findable(item))
  self.y = self.y - 42
  return f
end

---A line: name and meta; track = { kind, id } adds "Show on map"; dim greys the name.
function Sheet:Line(name, meta, track, dim, onClick, color)
  local f = self:take("line", makeLine)
  f:SetPoint("TOPLEFT", self.area.content, "TOPLEFT", 4, self.y)
  f:SetWidth(self.width - 8)
  f.name:SetText(name)
  local c = color or (dim and C.faint or C.text)
  f.name:SetTextColor(c[1], c[2], c[3])
  f.meta:SetText(meta or "")
  f.track.kind, f.track.id = track and track.kind, track and track.id
  f.track:SetShown(track ~= nil)
  f.onClick = onClick
  self.y = self.y - 36
  return f
end

function Sheet:End()
  self.area.content:SetHeight(-self.y + 10)
  self.area:SetVerticalScroll(0)
end
