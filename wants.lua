-- Wants (docs/oracle-redesign.md 4.4): AtlasLoot's wishlist. ★ any item (right-click it in a loot list, or
-- Want in the Inspector); the Wants space lists them by where they come from, loot lists mark them,
-- and an instance says how many of your wants drop there. Saved per character (OracleCharDB.wants).

local Core = NorgannonCore
local O = Oracle
if O.disabled then return end
local UI = Core.UI
local C = UI.C

local Wants = { label = "Wants", order = 5 }
O.Wants = Wants

local ROW = 42
local ELSEWHERE = "elsewhere"

local function store()
  if not O.char then return {} end
  O.char.wants = O.char.wants or {}
  return O.char.wants
end

function Wants:Has(id) return id and store()[id] ~= nil or false end

function Wants:Count()
  local n = 0
  for _ in pairs(store()) do n = n + 1 end
  return n
end

---Adds or removes an item; tells the rest of Oracle (ORACLE_WANTS).
function Wants:Toggle(id)
  if not id then return end
  local s = store()
  if s[id] then s[id] = nil else s[id] = time and time() or true end
  local info = O.Items.Info(id)
  O:Print((s[id] and "wanted: " or "no longer wanted: ") .. info.name)
  O:Send("WANTS", id)
end

---Where a wanted item comes from: the instance and boss Oracle knows, else nil.
local function placeOf(id) return O.Links and O.Links.Find("item", id) end

---Your wants in an instance (a count).
function Wants:In(key)
  local n = 0
  for id in pairs(store()) do
    local hit = placeOf(id)
    if hit and hit.key == key then n = n + 1 end
  end
  return n
end

-------------------------------------------------------------------------------------------
-- The Wants space: the navigator by place, the list of items with where they come from
-------------------------------------------------------------------------------------------

local state = { place = "all" }

function Wants:nav()
  local byPlace, order, elsewhere = {}, {}, 0
  for id in pairs(store()) do
    local hit = placeOf(id)
    if hit then
      if not byPlace[hit.key] then byPlace[hit.key] = 0 order[#order + 1] = hit.key end
      byPlace[hit.key] = byPlace[hit.key] + 1
    else
      elsewhere = elsewhere + 1
    end
  end
  table.sort(order, function(a, b) return (O.Model:Get(a) or {}).name < (O.Model:Get(b) or {}).name end)
  local rows = { { place = "all", name = "All your wants", navMeta = self:Count() .. " items" } }
  if #order > 0 then rows[#rows + 1] = { group = "In dungeons and raids" } end
  for _, key in ipairs(order) do
    local e = O.Model:Get(key)
    rows[#rows + 1] = { place = key, name = e and e.name or key, navMeta = byPlace[key] .. (byPlace[key] == 1 and " item" or " items"),
      navRight = e and O.Model.LevelText(e) or "", navRightColor = e and O.Model.LevelColor(e) }
  end
  if elsewhere > 0 then
    rows[#rows + 1] = { group = "Elsewhere" }
    rows[#rows + 1] = { place = ELSEWHERE, name = "Quests, vendors, crafts, the world", navMeta = elsewhere .. (elsewhere == 1 and " item" or " items") }
  end
  return rows
end
function Wants:navSelected(e) return e.place == state.place end
function Wants:navClick(e) state.place = e.place self:Fill() O.Shell:RefreshNav() end
function Wants:navTop(top) top:SetHeight(1) end

---The list's rows: { group } per place, then { item, npc, key }.
function Wants.Rows(place)
  local groups, order = {}, {}
  for id in pairs(store()) do
    local hit = placeOf(id)
    local key = hit and hit.key or ELSEWHERE
    if place == "all" or place == key then
      if not groups[key] then groups[key] = {} order[#order + 1] = key end
      table.insert(groups[key], { item = id, npc = hit and hit.npc, key = hit and hit.key })
    end
  end
  table.sort(order, function(a, b)
    if a == ELSEWHERE then return false end
    if b == ELSEWHERE then return true end
    return (O.Model:Get(a) or {}).name < (O.Model:Get(b) or {}).name
  end)
  local rows = {}
  for _, key in ipairs(order) do
    local e = O.Model:Get(key)
    rows[#rows + 1] = { group = key == ELSEWHERE and "Elsewhere" or (e and e.name or key) }
    table.sort(groups[key], function(a, b) return (O.Items.Info(a.item).name or "") < (O.Items.Info(b.item).name or "") end)
    for _, r in ipairs(groups[key]) do rows[#rows + 1] = r end
  end
  return rows
end

-- a row's source line: the boss and chance, else the first other source
local function sourceText(r)
  if r.npc then
    local chance = O.Loot.Chance(r.npc, r.item)
    return (Core.DB:Name("npcs", r.npc) or "a boss") .. (chance and (" · " .. O.Loot.ChanceText(chance)) or "")
  end
  local src = Core.DB:ItemInfo(r.item) or {}
  if src.rewardOf and src.rewardOf[1] then return "quest: " .. (Core.DB:Name("quests", src.rewardOf[1]) or "?") end
  if Core.DB.CraftedBy and #Core.DB:CraftedBy(r.item) > 0 then return "crafted" end
  if src.vendors and next(src.vendors) then return "sold by vendors" end
  if src.drops and src.drops.npcs and next(src.drops.npcs) then return "dropped by creatures" end
  return "source not known yet"
end

function Wants:Build(page)
  self.page = page
  local f = CreateFrame("Frame", nil, page.content)
  f:SetAllPoints()
  local pane = UI.Pane(f)
  pane:SetAllPoints()
  f.list = UI.List(pane, {
    rowHeight = ROW,
    groupBand = true,
    createRow = function(row, content)
      content.rightInset = 200
      O.Items.Build(content)
      content.tooltipHint = function() return "Click: where it drops · right-click: no longer wanted" end
      row.itemFrame = content
      row.source = UI.Text(content, "body", 12, C.muted)
      row.source:SetPoint("RIGHT", -12, 0)
      row.source:SetWidth(190)
      row.source:SetJustifyH("RIGHT")
      row.source:SetWordWrap(false)
    end,
    updateRow = function(row, r)
      O.Items.Fill(row.itemFrame, r.item)
      row.source:SetText(sourceText(r))
    end,
    onClick = function(r, _, button)
      if button == "RightButton" then return Wants:Toggle(r.item) end
      if r.key then return O:Go({ space = "dungeons", key = r.key, view = "loot", boss = r.npc, inspect = { "item", r.item } }) end
      O.Inspector:Show("item", r.item)
    end,
  })
  f.list:SetPoint("TOPLEFT", 1, -4)
  f.list:SetPoint("BOTTOMRIGHT", -1, 4)
  f.list:ApplyAccent(UI.Accent("oracle"))
  f.empty = UI.Text(pane, "body", 13, C.faint)
  f.empty:SetPoint("TOPLEFT", 14, -14)
  f.empty:SetPoint("TOPRIGHT", -14, -14)
  f.empty:SetWordWrap(true)
  f.empty:SetText("Nothing yet. Right-click an item in a loot list, or press Want in the Inspector, to add it here.")
  self.frame = f
  f:Hide()
end

function Wants:Fill()
  if not self.frame then return end
  local rows = Wants.Rows(state.place)
  self.frame.list:SetData(rows)
  self.frame.empty:SetShown(#rows == 0)
  local n = self:Count()
  O.Shell:SetHeader("Wants", n .. (n == 1 and " item" or " items") .. " you want · saved for this character",
    "Right-click an item in a loot list to add or remove it")
end

function Wants:Show()
  self.frame:Show()
  self:Fill()
end
function Wants:Hide() if self.frame then self.frame:Hide() end end
function Wants:Go() self:Fill() end

-- the count on the Wants tab, and every list that marks wants
local function changed()
  local win = O.Window.frame
  if win and win.spaces then win.spaces:SetCount("wants", Wants:Count()) end
  if O.Shell.current == "wants" then Wants:Fill() O.Shell:RefreshNav() end
  local D = O.Dungeons
  if O.Shell.current == "dungeons" and D and D.view then
    D:Go({ view = D.view })          -- the header's "of your wants drop here" and the list's marks
    O.Shell:RefreshNav()
  end
  if O.Inspector and O.Inspector.kind == "item" then O.Inspector:Show("item", O.Inspector.id) end
end
O:Listen("WANTS", "wants", changed)
Wants.Changed = changed

O.Shell:AddSpace("wants", Wants)
