-- The Quests tab (mockup renderQuests): one card per quest that sends you to the instance, by
-- level: the level and name in your difficulty colour, "From <giver> · zone (x, y) · requires
-- level N" (or where to pick it up), "After: <prerequisites>", the rewards in two columns, then
-- "Track in Clairvoyance" (shows the giver on your map), "Archivum", and the XP.

local Core = NorgannonCore
local DB = NorgannonDB
local O = Oracle
if O.disabled then return end
local UI = Core.UI
local C = UI.C

local Quests = {}
O.Quests = Quests

local ALLIANCE, HORDE = 1 + 4 + 8 + 64, 2 + 16 + 32 + 128   -- race masks
local CARD_PAD = 12

-- bitwise AND of two masks, in plain Lua (no client library needed)
local function band(a, b)
  a = a % 4294967296
  local r, p = 0, 1
  while a > 0 and b > 0 do
    if a % 2 == 1 and b % 2 == 1 then r = r + p end
    a, b, p = math.floor(a / 2), math.floor(b / 2), p * 2
  end
  return r
end

---"Alliance" or "Horde" when only one side can take the quest, else nil.
function Quests.Side(q)
  local races = q and q.races
  if not races or races == 0 then return nil end
  local a, h = band(races, ALLIANCE) ~= 0, band(races, HORDE) ~= 0
  if a and not h then return "Alliance" end
  if h and not a then return "Horde" end
end

-- where a creature or object stands: "Westfall (56.3, 47.6)"
local function whereIs(kind, id)
  local record = DB:Get(kind, id)
  for area, points in pairs(record and record.spawns or {}) do
    local p = points[1]
    if p and p[1] and p[1] >= 0 then
      return string.format("%s (%.1f, %.1f)", O.Model.AreaName(area) or "?", p[1], p[2]), area, p
    end
  end
end

---A quest's card text: { id, name, level, color, from, after, rewards, choice, xp, side, starter }.
function Quests.Card(id)
  local q = DB:Get("quests", id)
  if not q then return nil end
  local level = q.level and q.level > 0 and q.level or nil
  local card = {
    id = id, name = Core.DB:Name("quests", id) or q.name or ("Quest " .. id), level = level,
    color = level and UI.Difficulty(level, Core.Player.level or UnitLevel("player") or 1) or C.text,
    side = Quests.Side(q), rewards = q.rewards and q.rewards.items or {}, choice = q.rewards and q.rewards.choice,
    xp = q.rewards and q.rewards.xp,
  }
  local s = q.starters or {}
  local parts = {}
  if s.npcs and s.npcs[1] then
    card.starter = { kind = "npc", id = s.npcs[1] }
    parts[#parts + 1] = "From |cffffffff" .. (Core.DB:Name("npcs", s.npcs[1]) or "?") .. "|r"
    local where = whereIs("npcs", s.npcs[1])
    if where then parts[#parts + 1] = where end
  elseif s.objects and s.objects[1] then
    card.starter = { kind = "object", id = s.objects[1] }
    parts[#parts + 1] = "From |cffffffff" .. (Core.DB:Name("objects", s.objects[1]) or "?") .. "|r"
    local where = whereIs("objects", s.objects[1])
    if where then parts[#parts + 1] = where end
  elseif s.items and s.items[1] then
    card.starter = { kind = "item", id = s.items[1] }
    parts[#parts + 1] = "Starts from |cffffffff" .. (Core.DB:Name("items", s.items[1]) or "an item") .. "|r"
  elseif q.startNote then
    parts[#parts + 1] = "From " .. q.startNote
  else
    parts[#parts + 1] = "Starts from an item or object"
  end
  if q.minLevel and q.minLevel > 1 then parts[#parts + 1] = "requires level " .. q.minLevel end
  if card.side then parts[#parts + 1] = card.side .. " only" end
  card.from = table.concat(parts, " · ")
  local pre = q.prerequisites or {}
  local names = {}
  for _, p in ipairs(pre.all or {}) do names[#names + 1] = Core.DB:Name("quests", p) or ("Quest " .. p) end
  local any = {}
  for _, p in ipairs(pre.any or {}) do any[#any + 1] = Core.DB:Name("quests", p) or ("Quest " .. p) end
  if #any > 0 then names[#names + 1] = table.concat(any, " or ") end
  if #names > 0 then card.after = "After: " .. table.concat(names, ", ") end
  return card
end

---The instance's quests as cards, by level then name.
function Quests.Cards(key)
  local inst = Core.DB:Instance(key)
  local out = {}
  for _, id in ipairs(inst and inst.quests or {}) do
    local card = Quests.Card(id)
    if card and not Core.DB:IsQuestHidden(id) then out[#out + 1] = card end
  end
  table.sort(out, function(a, b)
    if (a.level or 0) ~= (b.level or 0) then return (a.level or 0) < (b.level or 0) end
    return a.name < b.name
  end)
  return out
end

---Shows a quest's giver on the map through Clairvoyance. Returns what happened.
function Quests.Track(card)
  if Core.Player:HasQuest(card.id) then return "inlog" end
  if not card.starter then return "nostarter" end
  for _, action in ipairs(Core:ActionsFor(card.starter.kind, card.starter.id)) do
    if action.id == "clairvoyance.track" then
      action.run(card.starter.kind, card.starter.id)
      return "tracked"
    end
  end
  return "noclairvoyance"
end

-------------------------------------------------------------------------------------------
-- The pane
-------------------------------------------------------------------------------------------

local pane, area, cards = nil, nil, {}

local function markButton(parent, text, style, markKey, accentKey, onClick)
  local b = UI.Button(parent, text, style, onClick)
  if accentKey then b:ApplyAccent(UI.Accent(accentKey)) end
  b.mark = UI.Mark(b, markKey, 15)
  b.mark:SetPoint("LEFT", 8, 0)
  b.label:SetFontObject(UI.Font("title", 12))
  b.label:ClearAllPoints()
  b.label:SetPoint("LEFT", b.mark, "RIGHT", 5, 0)
  b:SetHeight(22)
  b:SetWidth(math.floor(b.label:GetStringWidth() + 8 + 15 + 5 + 10))
  return b
end

local function newCard()
  local f = CreateFrame("Frame", nil, area.content)
  f.box = UI.Box(f, "BACKGROUND", 0)
  f.box:Set(C.lineStrong, { .114, .09, .067 }, { .07, .055, .04 })
  f.level = UI.Text(f, "body", 14)
  f.level:SetPoint("TOPLEFT", CARD_PAD, -10)
  f.name = UI.Text(f, "title", 15)
  f.name:SetPoint("BOTTOMLEFT", f.level, "BOTTOMRIGHT", 8, 0)
  f.from = UI.Text(f, "body", 13, C.muted)
  f.from:SetWordWrap(true)
  f.from:SetJustifyH("LEFT")
  f.rewards = {}
  f.choose = UI.Text(f, "body", 12, C.faint)
  f.choose:SetText("Choose one:")
  f.track = markButton(f, "Track in Clairvoyance", "accent", "clairvoyance", "clairvoyance", function(self)
    local result = Quests.Track(self:GetParent().card)
    if result == "noclairvoyance" then O:Print("Clairvoyance shows where quests start; it isn't loaded.")
    elseif result == "nostarter" then O:Print("NorgannonDB doesn't know who starts this quest yet.") end
  end)
  f.archivum = markButton(f, "Archivum", "quiet", "archivum", nil, function() end)
  f.archivum:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:AddLine("Archivum", 1, 1, 1)
    GameTooltip:AddLine("The suite's encyclopedia will open this quest's page.", C.muted[1], C.muted[2], C.muted[3])
    GameTooltip:Show()
  end)
  f.archivum:SetScript("OnLeave", function() GameTooltip:Hide() end)
  f.xp = UI.Text(f, "body", 12, C.faint)
  f.xp:SetJustifyH("RIGHT")
  return f
end

local function rewardRow(f, i)
  local r = f.rewards[i]
  if r then return r end
  r = CreateFrame("Button", nil, f)
  r:SetHeight(36)
  r.rightInset = 2
  O.Items.Build(r)
  O.Items.Hook(r)
  f.rewards[i] = r
  return r
end

local function fillCard(f, card, width)
  f.card = card
  f:SetWidth(width)
  local c = card.color
  f.level:SetText(card.level and tostring(card.level) or "?")
  f.level:SetTextColor(c[1], c[2], c[3])
  f.name:SetText(card.name)
  f.name:SetTextColor(c[1], c[2], c[3])
  local inner = width - 2 * CARD_PAD
  f.from:SetWidth(inner)
  f.from:SetText(card.from .. (card.after and ("\n" .. card.after) or ""))
  f.from:ClearAllPoints()
  f.from:SetPoint("TOPLEFT", CARD_PAD, -32)
  local y = -32 - math.max(14, f.from:GetStringHeight() or 14) - 6
  f.choose:SetShown(card.choice and #card.rewards > 1)
  if f.choose:IsShown() then
    f.choose:ClearAllPoints()
    f.choose:SetPoint("TOPLEFT", CARD_PAD, y)
    y = y - 16
  end
  local half = math.floor(inner / 2)
  for i, id in ipairs(card.rewards) do
    local r = rewardRow(f, i)
    r:SetWidth(half - 2)
    r:ClearAllPoints()
    r:SetPoint("TOPLEFT", CARD_PAD - 6 + ((i - 1) % 2) * half, y - math.floor((i - 1) / 2) * 38)
    O.Items.Fill(r, id)
    r.itemId = id
    r:Show()
  end
  for i = #card.rewards + 1, #f.rewards do f.rewards[i]:Hide() f.rewards[i].itemId = nil end
  y = y - math.ceil(#card.rewards / 2) * 38 - 4
  f.track:ClearAllPoints()
  f.track:SetPoint("TOPLEFT", CARD_PAD, y)
  local inLog = Core.Player:HasQuest(card.id)
  f.track.label:SetText(inLog and "In your quest log" or "Track in Clairvoyance")
  f.track:SetAlpha((inLog or not card.starter or Core:AddonState("clairvoyance") ~= "loaded") and .5 or 1)
  f.archivum:ClearAllPoints()
  f.archivum:SetPoint("LEFT", f.track, "RIGHT", 6, 0)
  f.archivum:SetAlpha(Core:AddonState("archivum") == "loaded" and 1 or .5)
  f.xp:ClearAllPoints()
  f.xp:SetPoint("RIGHT", f, "TOPRIGHT", -CARD_PAD, y - 11)
  f.xp:SetText(card.xp and (BreakUpLargeNumbers and BreakUpLargeNumbers(card.xp) or tostring(card.xp)) .. " XP" or "")
  local height = -y + 22 + 10
  f:SetHeight(height)
  return height
end

local function build(frame)
  pane = frame
  area = UI.ScrollArea(pane)
  area:SetAllPoints()
  Quests.area = area
  Quests.empty = UI.Text(pane, "body", 13, C.faint)
  Quests.empty:SetPoint("TOPLEFT", 10, -10)
  Quests.empty:SetText("No quests send you here that NorgannonDB knows of.")
end

local function fill(_, e)
  local list = Quests.Cards(e.key)
  local width = (pane:GetWidth() or 392)
  if width < 50 then width = 392 end
  area.content:SetWidth(width)
  local y = -6
  for i, card in ipairs(list) do
    local f = cards[i] or newCard()
    cards[i] = f
    local h = fillCard(f, card, width - 6)
    f:ClearAllPoints()
    f:SetPoint("TOPLEFT", area.content, "TOPLEFT", 0, y)
    f:Show()
    y = y - h - 8
  end
  for i = #list + 1, #cards do cards[i]:Hide() cards[i].card = nil end
  area.content:SetHeight(-y)
  area:SetVerticalScroll(0)
  Quests.empty:SetShown(#list == 0)
  Quests.shown = list
end

---The card showing a quest (the harness and "Open in Oracle" use it).
function Quests:CardFor(id)
  for _, f in ipairs(cards) do
    if f:IsShown() and f.card and f.card.id == id then return f end
  end
end

---Scrolls the Quests tab to a quest and outlines its card for a moment.
function Quests:Focus(id)
  local f = self:CardFor(id)
  if not f then return end
  local top = -(select(5, f:GetPoint(1)) or 0)
  area:SetVerticalScroll(math.max(0, top - 6))
  f.box:Set(UI.Accent("oracle"), { .114, .09, .067 }, { .07, .055, .04 })
  C_Timer.After(2, function() f.box:Set(C.lineStrong, { .114, .09, .067 }, { .07, .055, .04 }) end)
  self.focused = id
end

O:Listen("ITEMS_LOADED", "quests", function() if pane and pane:IsShown() and O.db.selected then fill(nil, O.Model:Get(O.db.selected)) end end)
O.Window:RegisterPane("quests", build, fill)
