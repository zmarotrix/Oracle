-- The Inspector (docs/oracle-redesign.md section 4): the right-hand column that shows whatever you click,
-- in every space: an item (where it comes from, whether you can use it), a quest (where you stand,
-- its giver, chain and rewards), a boss (its loot, where it is). Its actions run along the bottom.
--
--   O.Inspector:Show("item", 5191)   -- also "quest", "npc"; Show(nil) clears it

local Core = NorgannonCore
local DB = NorgannonDB
local O = Oracle
if O.disabled then return end
local UI = Core.UI
local C = UI.C

local Inspector = {}
O.Inspector = Inspector

local KIND_LABEL = { item = "Item", quest = "Quest", npc = "Boss", recipe = "Recipe" }
local MAX_DROPS = 6

local box, head, close, sheet, actions

local function action(i, text, style, onClick)
  local b = actions.buttons[i]
  if not b then
    b = UI.Button(actions, text, style, function(self) if self.run then self.run() end end)
    b:SetHeight(22)
    actions.buttons[i] = b
  end
  b:SetLabel(text)
  b.run = onClick
  b:SetWidth(math.max(70, (b.label and b.label:GetStringWidth() or 60) + 26))
  b:ClearAllPoints()
  if i == 1 then b:SetPoint("LEFT", 6, 0) else b:SetPoint("LEFT", actions.buttons[i - 1], "RIGHT", 6, 0) end
  b:Show()
  return b
end

local function setActions(list)
  for _, b in ipairs(actions.buttons) do b:Hide() end
  for i, a in ipairs(list) do action(i, a[1], a[2], a[3]) end
  actions:SetShown(#list > 0)
end

function Inspector:Build(parent)
  box = parent
  head = CreateFrame("Frame", nil, parent)
  head:SetPoint("TOPLEFT")
  head:SetPoint("TOPRIGHT")
  head:SetHeight(24)
  head.label = UI.Text(head, "body", 11, C.faint)
  head.label:SetPoint("LEFT", 4, 0)
  close = CreateFrame("Button", nil, head)
  close:SetSize(20, 20)
  close.icon = UI.Icon(close, "close", 10, C.faint)
  close.icon:SetPoint("CENTER")
  close:SetScript("OnClick", function() Inspector:Show(nil) end)
  close:SetPoint("RIGHT", 0, 0)
  actions = CreateFrame("Frame", nil, parent)
  actions:SetPoint("BOTTOMLEFT")
  actions:SetPoint("BOTTOMRIGHT")
  actions:SetHeight(32)
  actions.buttons = {}
  local area = CreateFrame("Frame", nil, parent)
  area:SetPoint("TOPLEFT", head, "BOTTOMLEFT", 0, -4)
  area:SetPoint("BOTTOMRIGHT", actions, "TOPRIGHT", 0, 4)
  sheet = O.Sheet.New(area)
  Inspector.sheet, Inspector.actions = sheet, actions
  self:Show(nil)
end

-- "Westfall (42.5, 71.7)" for a creature or object
local function whereIs(kind, id)
  local record = DB:Get(kind, id)
  for area, points in pairs(record and record.spawns or {}) do
    local p = points[1]
    if p and p[1] and p[1] >= 0 then
      return string.format("%s (%.1f, %.1f)", O.Model.AreaName(area) or "?", p[1], p[2])
    end
    return (O.Model.AreaName(area) or "?") .. " (inside)"
  end
end

-------------------------------------------------------------------------------------------
-- An item
-------------------------------------------------------------------------------------------

local function showItem(id)
  local info = O.Items.Info(id)
  sheet:Text(info.name, 20, info.color, "title")
  sheet:Text(info.kind ~= "" and info.kind or "Item", 13, C.muted)
  local you = O.Items.ForYou and O.Items.ForYou(id)
  if you then
    if you.ok and not you.later then sheet:Text(O.ICON.check .. " You can use it", 13, C.good)
    elseif you.ok then sheet:Text("You can use it at level " .. you.later, 13, C.warn)
    else sheet:Text(O.ICON.cross .. " " .. you.why, 13, C.bad) end
  end

  sheet:Heading("Where it comes from")
  local any = false
  local hit = O.Links and O.Links.Find("item", id)
  if hit then
    any = true
    local e = O.Model:Get(hit.key)
    local chance = hit.npc and O.Loot and O.Loot.Chance(hit.npc, id)
    sheet:Line((Core.DB:Name("npcs", hit.npc) or "A boss") .. ", " .. (e and e.name or hit.key),
      "Boss loot" .. (chance and (" · " .. O.Loot.ChanceText(chance)) or ""), nil, false,
      function() O:Go({ space = "dungeons", key = hit.key, view = "loot", boss = hit.npc }) end, C.text)
  end
  local src = Core.DB:ItemInfo(id) or {}
  for _, q in ipairs(src.rewardOf or {}) do
    any = true
    sheet:Line(Core.DB:Name("quests", q) or ("Quest " .. q), "Quest reward", nil, false,
      function() Inspector:Show("quest", q) end, C.gold)
  end
  local drops = {}
  for npc, chance in pairs(src.drops and src.drops.npcs or {}) do
    if not (hit and hit.npc == npc) then drops[#drops + 1] = { npc, chance } end
  end
  table.sort(drops, function(a, b) return (a[2] or 0) > (b[2] or 0) end)
  for i = 1, math.min(MAX_DROPS, #drops) do
    any = true
    local npc, chance = drops[i][1], drops[i][2]
    sheet:Line(Core.DB:Name("npcs", npc) or ("Creature " .. npc),
      "Drop" .. (chance and chance > 0 and (" · " .. O.Loot.ChanceText(chance)) or "") .. (whereIs("npcs", npc) and (" · " .. whereIs("npcs", npc)) or ""),
      { kind = "npc", id = npc })
  end
  if #drops > MAX_DROPS then sheet:Text(string.format("and %d more creatures", #drops - MAX_DROPS), 12, C.faint) end
  local vendors = 0
  for npc, limited in pairs(src.vendors or {}) do
    vendors = vendors + 1
    if vendors <= 4 then
      any = true
      sheet:Line(Core.DB:Name("npcs", npc) or ("Vendor " .. npc),
        "Sold" .. ((limited and limited ~= 0) and " · limited stock" or "") .. (whereIs("npcs", npc) and (" · " .. whereIs("npcs", npc)) or ""),
        { kind = "npc", id = npc })
    end
  end
  for _, recipe in ipairs(Core.DB.CraftedBy and Core.DB:CraftedBy(id) or {}) do
    any = true
    local rec = Core.DB:Recipe(recipe) or {}
    sheet:Line(Core.DB:RecipeName(recipe) or "A recipe", "Crafted · " .. (DB.professions and DB.professions[rec.skill] or "profession")
      .. " " .. (rec.learn or ""), nil, false, function() O:Go({ space = "professions", skill = rec.skill, recipe = recipe }) end, C.text)
  end
  if not any then sheet:Text("No source known yet.", 13, C.faint) end

  local list = {}
  if O.Wants then list[#list + 1] = { O.Wants:Has(id) and "Wanted" or "Want", O.Wants:Has(id) and "quiet" or "accent",
    function() O.Wants:Toggle(id) Inspector:Show("item", id) end } end
  list[#list + 1] = { "Link", "quiet", function()
    local link = info.link or select(2, (C_Item and C_Item.GetItemInfo or GetItemInfo)(id))
    if link and ChatEdit_InsertLink then ChatEdit_InsertLink(link) end
  end }
  if O.Sheet.Findable(id) then list[#list + 1] = { "Show on map", "quiet", function() O.Sheet.Track("item", id) end } end
  setActions(list)
end

-------------------------------------------------------------------------------------------
-- A quest
-------------------------------------------------------------------------------------------

local function showQuest(id)
  local Q = O.Quests
  local card = Q and Q.Card(id)
  if not card then return sheet:Begin("NorgannonDB doesn't know this quest.") end
  sheet:Text((card.level and ("[" .. card.level .. "] ") or "") .. card.name, 20, card.color, "title")
  local st = Q.StatusText(card.status)
  if st then sheet:Text(st, 13, C.text) end
  sheet:Heading("Starts")
  sheet:Text(card.from, 13, C.text)
  if card.after then sheet:Text(card.after, 13, C.muted) end
  for _, n in ipairs(card.notes or {}) do sheet:Text(n, 12, C.faint) end
  local q = DB:Get("quests", id) or {}
  -- the objective text is a list of lines in NorgannonDB (a string in older data)
  local text = type(q.text) == "table" and q.text.objectives or nil
  if type(text) == "table" then text = table.concat(text, "\n") end
  if type(text) ~= "string" then text = nil end
  if text and text ~= "" then
    sheet:Heading("Objective")
    sheet:Text(text, 13, C.text)
  end
  local path = Q.Path and Q.Path(id) or {}
  if #path > 1 then
    sheet:Heading("Chain")
    for i, step in ipairs(path) do
      local s = Q.Status(step)
      local label = ({ done = "Done", inlog = "In your log", ready = "Ready", level = "Later", chain = "Later", notforyou = "Not for you" })[s.code] or ""
      sheet:Line(i .. ". " .. (Core.DB:Name("quests", step) or ("Quest " .. step)), label, nil, s.code == "done",
        step ~= id and function() Inspector:Show("quest", step) end or nil, step == id and C.gold or nil)
    end
  end
  local rewards = {}
  for _, it in ipairs(card.rewards or {}) do rewards[#rewards + 1] = it end
  for _, it in ipairs(card.choice or {}) do rewards[#rewards + 1] = it end
  if #rewards > 0 then
    sheet:Heading(card.choice and #card.choice > 0 and "Rewards (choose one)" or "Rewards")
    for _, it in ipairs(rewards) do sheet:Item(it, nil, nil, function() Inspector:Show("item", it) end) end
  end
  if card.xp then sheet:Text(BreakUpLargeNumbers and (BreakUpLargeNumbers(card.xp) .. " XP") or (card.xp .. " XP"), 12, C.faint) end

  local list = { { "Track", "accent", function()
    local result = Q.Track(card)
    if result == "noclairvoyance" then O:Print("Clairvoyance shows quest givers on your map; it isn't loaded.") end
  end } }
  local hit = O.Links and O.Links.Find("quest", id)
  if hit then list[#list + 1] = { "Open its dungeon", "quiet", function() O:Go({ space = "dungeons", key = hit.key, view = "quests" }) end } end
  setActions(list)
end

-------------------------------------------------------------------------------------------
-- A boss (or any creature)
-------------------------------------------------------------------------------------------

local function showNpc(id)
  local npc = DB:Get("npcs", id) or {}
  sheet:Text(Core.DB:Name("npcs", id) or ("Creature " .. id), 20, C.gold, "title")
  local parts = {}
  local level = npc.maxLevel or npc.minLevel
  if level then parts[#parts + 1] = "Level " .. level end
  local rank = O.Bosses and O.Bosses.RANK[npc.rank or 0]
  if rank then parts[#parts + 1] = rank[1] end
  if npc.subName then parts[#parts + 1] = npc.subName end
  sheet:Text(table.concat(parts, " · "), 13, C.muted)
  local hit = O.Links and O.Links.Find("npc", id)
  local where = whereIs("npcs", id)
  if hit then
    local e = O.Model:Get(hit.key)
    sheet:Text("In " .. (e and e.name or hit.key), 13, C.text)
  elseif where then
    sheet:Text(where, 13, C.text)
  end
  local loot = {}
  if hit then
    for _, b in ipairs((Core.DB:Instance(hit.key) or {}).bosses or {}) do
      if b.id == id then loot = b.loot or {} end
    end
  end
  if #loot > 0 then
    sheet:Heading("Loot")
    for _, it in ipairs(loot) do
      local c = O.Loot and O.Loot.Chance(id, it)
      sheet:Item(it, c and O.Loot.ChanceText(c) or nil, nil, function() Inspector:Show("item", it) end)
    end
  end
  local list = {}
  if hit then list[#list + 1] = { "Its loot", "accent", function() O:Go({ space = "dungeons", key = hit.key, view = "loot", boss = id }) end } end
  if not hit and where then list[#list + 1] = { "Show on map", "quiet", function() O.Sheet.Track("npc", id) end } end
  setActions(list)
end

-------------------------------------------------------------------------------------------
-- A recipe (what crafts.lua draws: reagents and their sources, where to learn it, what uses it)
-------------------------------------------------------------------------------------------

local function showRecipe(id)
  local rec = Core.DB:Recipe(id)
  if not rec then return sheet:Text("NorgannonDB doesn't know this recipe.", 13, C.faint) end
  O.Crafts.DrawRecipe(sheet, id,
    function(other) O:Go({ space = "professions", recipe = other }) end,
    function(item) Inspector:Show("item", item) end)
  local list = {}
  -- your faction's trainer first
  local f = UnitFactionGroup and UnitFactionGroup("player")
  local mine = f == "Alliance" and "A" or (f == "Horde" and "H") or nil
  local trainer
  for npc in pairs(rec.trainers or {}) do
    local r = DB:Get("npcs", npc) or {}
    if not trainer or (mine and r.reaction and r.reaction:find(mine)) then trainer = npc end
  end
  if trainer then list[#list + 1] = { "Show trainer on map", "accent", function() O.Sheet.Track("npc", trainer) end } end
  if rec.item and O.Wants then
    list[#list + 1] = { O.Wants:Has(rec.item) and "Wanted" or "Want", "quiet", function() O.Wants:Toggle(rec.item) Inspector:Show("recipe", id) end }
  end
  setActions(list)
end

-------------------------------------------------------------------------------------------

---Shows something (kind "item", "quest", "npc", "recipe"), or clears the Inspector (kind nil).
function Inspector:Show(kind, id)
  if not sheet then return end
  self.kind, self.id = kind, id
  head.label:SetText(string.upper(KIND_LABEL[kind] or "Inspector"))
  close:SetShown(kind ~= nil)
  if not kind then
    sheet:Begin("Pick an item, quest or boss to see everything about it here.\n\nTip: type its name in the search box at the top.")
    sheet:End()
    setActions({})
    return
  end
  sheet:Begin()
  if kind == "item" then showItem(id)
  elseif kind == "quest" then showQuest(id)
  elseif kind == "npc" then showNpc(id)
  elseif kind == "recipe" then showRecipe(id) end
  sheet:End()
  O:Send("INSPECTED", kind, id)
end

function Inspector:SetShown(on)
  if box then box:SetShown(on) end
end

-- item data arrives a moment after it's asked for: redraw an item shown
Core:Listen("ORACLE_ITEMS_LOADED", "oracle.inspector", function()
  if Inspector.kind and box and box:IsVisible() then Inspector:Show(Inspector.kind, Inspector.id) end
end)
