-- Crafts (Phase B): every profession's recipes, from NorgannonDB 1.4.
--
--   the sidebar     the professions (with your skill), the search finds recipes
--   the map column  the skill ladder: each recipe at the skill where it's learned, coloured for
--                   your skill, with its orange / yellow / green / grey ranges on a 1-300 strip
--                   and your skill as a line down the strips
--   the detail      the recipe: what it makes, the reagents and where each comes from, where to
--                   learn it (trainers, recipe items, quests), "Show on map" through Clairvoyance
--
-- Facts and colours only: nothing says what to craft next (no guides, decision 9).

local Core = NorgannonCore
local O = Oracle
if O.disabled then return end
local UI = Core.UI
local C = UI.C

local Crafts = {}
O.Crafts = Crafts

-- the profession windows' order: crafting, then the secondary skills
local PROFESSIONS = { 171, 164, 333, 202, 165, 197, 186, 185, 129 }
local MAX_SKILL = 300
local BANDS = { { 1, "Apprentice" }, { 75, "Journeyman" }, { 150, "Expert" }, { 225, "Artisan" } }
-- the game's trade skill colours (red: not learnable at your skill yet)
local COLORS = {
  red = UI.Hex("d9534f"), orange = UI.Hex("ff8040"), yellow = UI.Hex("ffff00"),
  green = UI.Hex("40bf40"), grey = UI.Hex("808080"),
}
Crafts.COLORS = COLORS
local COLOR_NAMES = { orange = "Orange", yellow = "Yellow", green = "Green", grey = "Grey" }
local ROW, STRIP = 26, 190
local WORLD_DROP = 25      -- dropped by this many kinds of creature: a world drop
local FILTERS = { { "all", "All" }, { "learnable", "Learnable now" }, { "skillups", "Skill-ups" } }

local col, detail, list, axis, header, filterRow, empty, search
local query = ""
local syncing = false   -- while one search box sets the other

local function accent() return UI.Accent("oracle") end
local function professionName(id)
  local DB = NorgannonDB
  return (DB and DB.L and DB:L("professions", id, "name")) or (DB and DB.professions and DB.professions[id]) or ("Skill " .. id)
end
Crafts.ProfessionName = professionName

local function npcName(id) return Core.DB:Name("npcs", id) or ("NPC " .. id) end
local function itemName(id) return Core.DB:Name("items", id) or ("Item " .. id) end
local function zoneOf(npc)
  local rec = NorgannonDB:Get("npcs", npc)
  return rec and rec.zone and O.Model.AreaName(rec.zone)
end

local function money(copper)
  if not copper or copper <= 0 then return "free" end
  local g, s, c = math.floor(copper / 10000), math.floor(copper / 100) % 100, copper % 100
  local parts = {}
  if g > 0 then parts[#parts + 1] = g .. "g" end
  if s > 0 then parts[#parts + 1] = s .. "s" end
  if c > 0 then parts[#parts + 1] = c .. "c" end
  return table.concat(parts, " ")
end
Crafts.Money = money

---Your faction's letter in NorgannonDB's reactions ("A" / "H"), or nil.
local function myFaction()
  local f = UnitFactionGroup and UnitFactionGroup("player")
  return f == "Alliance" and "A" or (f == "Horde" and "H") or nil
end

---Whether an NPC is friendly to you (no reaction known counts as friendly).
local function friendly(npc)
  local rec = NorgannonDB:Get("npcs", npc)
  local mine = myFaction()
  return not (rec and rec.reaction and mine) or rec.reaction:find(mine) ~= nil
end

-------------------------------------------------------------------------------------------
-- Model
-------------------------------------------------------------------------------------------

local entries   -- the sidebar's rows: one per profession, kept so the list's selection holds

---The professions with recipes, as sidebar entries { key, craft, name, count, skill }.
function Crafts:Entries()
  if not entries then
    entries = {}
    for _, id in ipairs(PROFESSIONS) do
      local n = #Core.DB:Recipes(id)
      if n > 0 then entries[#entries + 1] = { key = "craft:" .. id, craft = id, name = professionName(id), count = n } end
    end
  end
  for _, e in ipairs(entries) do
    e.skill = Core.Player:GetSkill(e.craft)
    e.matches = nil
    if query ~= "" then
      e.matches = 0
      for _, id in ipairs(Core.DB:Recipes(e.craft)) do
        if Crafts.Matches(id, query) then e.matches = e.matches + 1 end
      end
    end
  end
  return entries
end

function Crafts:Entry(skill)
  for _, e in ipairs(self:Entries()) do if e.craft == skill then return e end end
end

---Whether a recipe matches the search: its name, or what it makes.
function Crafts.Matches(id, text)
  if not text or text == "" then return true end
  text = text:lower()
  local rec = Core.DB:Recipe(id)
  local name = (Core.DB:RecipeName(id) or ""):lower()
  if name:find(text, 1, true) then return true end
  return rec and rec.item and itemName(rec.item):lower():find(text, 1, true) ~= nil or false
end

local FOLDED = "|TInterface\\Buttons\\UI-PlusButton-Up:14:14:0:0|t "
local OPEN = "|TInterface\\Buttons\\UI-MinusButton-Up:14:14:0:0|t "

---Whether a band of a profession's ladder is folded (OracleDB.craftFolded[skill][band]).
function Crafts.Folded(skill, band)
  local f = O.db.craftFolded and O.db.craftFolded[skill]
  return f and f[band] == true or false
end

---Folds or unfolds a band (Apprentice 1, Journeyman 2, Expert 3, Artisan 4).
function Crafts:SetFolded(skill, band, folded)
  O.db.craftFolded = O.db.craftFolded or {}
  O.db.craftFolded[skill] = O.db.craftFolded[skill] or {}
  O.db.craftFolded[skill][band] = folded or nil
  self:Refresh()
end

---The ladder's rows for a profession: band headers (folded ones without their recipes), then
---recipes by learning skill.
function Crafts.Rows(skill, filter, text)
  local mine = Core.Player:GetSkill(skill)
  local bands = {}
  for _, id in ipairs(Core.DB:Recipes(skill)) do
    local rec = Core.DB:Recipe(id)
    local color = Core.DB.RecipeColor(rec, mine)
    local keep = Crafts.Matches(id, text)
    if keep and filter == "learnable" then keep = mine ~= nil and color ~= "red" end
    if keep and filter == "skillups" then keep = color == "orange" or color == "yellow" or color == "green" end
    if keep then
      local learn = rec.learn or rec.levels[1]
      local b = 1
      while BANDS[b + 1] and learn >= BANDS[b + 1][1] do b = b + 1 end
      bands[b] = bands[b] or {}
      table.insert(bands[b], { id = id, rec = rec, color = color })
    end
  end
  local out = {}
  for b = 1, #BANDS do
    local list = bands[b]
    if list then
      local folded = Crafts.Folded(skill, b) and text == ""
      local top = BANDS[b + 1] and BANDS[b + 1][1] or MAX_SKILL
      local count = #list == 1 and "1 recipe" or (#list .. " recipes")
      out[#out + 1] = { group = string.format("%s%s  ·  %d–%d  ·  %s", folded and FOLDED or OPEN, BANDS[b][2], BANDS[b][1], top, count),
                        band = b, folded = folded }
      if not folded then
        for _, item in ipairs(list) do out[#out + 1] = item end
      end
    end
  end
  return out
end

-------------------------------------------------------------------------------------------
-- The skill ladder (map column)
-------------------------------------------------------------------------------------------

local function stripX(skill) return math.max(0, math.min(1, (skill - 1) / (MAX_SKILL - 1))) * STRIP end

local function segment(row, i)
  row.segs[i] = row.segs[i] or UI.Tex(row.strip, "ARTWORK", i)
  return row.segs[i]
end

local function paintStrip(row, rec, mine)
  local l = rec.levels
  local spans = {
    { rec.learn or l[1], l[2], COLORS.orange }, { l[2], l[3], COLORS.yellow },
    { l[3], l[4], COLORS.green }, { l[4], MAX_SKILL, COLORS.grey },
  }
  for i, s in ipairs(spans) do
    local t = segment(row, i)
    local x0, x1 = stripX(s[1]), stripX(math.max(s[1], s[2]))
    t:ClearAllPoints()
    if x1 - x0 < .5 then
      t:Hide()
    else
      t:SetPoint("LEFT", row.strip, "LEFT", x0, 0)
      t:SetSize(x1 - x0, 6)
      t:SetColorTexture(s[3][1], s[3][2], s[3][3], .85)
      t:Show()
    end
  end
  row.you:SetShown(mine ~= nil)
  if mine then
    row.you:ClearAllPoints()
    row.you:SetPoint("TOP", row.strip, "TOPLEFT", stripX(mine), ROW / 2)
    row.you:SetPoint("BOTTOM", row.strip, "BOTTOMLEFT", stripX(mine), -ROW / 2)
  end
end

local function buildLadder(parent)
  col = CreateFrame("Frame", nil, parent)
  col.title = UI.Text(col, "title", 26, C.gold)
  col.title:SetPoint("TOPLEFT", 4, -2)
  col.facts = UI.Text(col, "body", 13, C.muted)
  col.facts:SetPoint("BOTTOMLEFT", col.title, "BOTTOMRIGHT", 12, 3)

  -- filters, left; the search, right
  filterRow = CreateFrame("Frame", nil, col)
  filterRow:SetHeight(26)
  filterRow:SetPoint("TOPLEFT", 0, -40)
  filterRow:SetPoint("TOPRIGHT", 0, -40)
  filterRow.chips = {}
  local previous
  for _, fl in ipairs(FILTERS) do
    local chip = UI.Chip(filterRow, fl[2], nil)
    chip.label:SetFontObject(UI.Font("body", 12))
    chip:SetHeight(18)
    chip:SetWidth(math.floor(chip.label:GetStringWidth() + 18))
    chip:ApplyAccent(accent())
    if previous then chip:SetPoint("LEFT", previous, "RIGHT", 6, 0) else chip:SetPoint("LEFT", 0, 0) end
    chip.key = fl[1]
    chip:SetScript("OnClick", function(self)
      O.db.craftFilter = self.key
      Crafts:Refresh()
    end)
    filterRow.chips[#filterRow.chips + 1] = chip
    previous = chip
  end
  -- the profession's own search: the same text as the sidebar's (either box sets both)
  search = UI.Search(filterRow, "Search this profession…", function(text)
    if syncing then return end
    Crafts:SetQuery(text, "ladder")
  end)
  search:ApplyAccent(accent())
  search:SetWidth(210)
  search:SetPoint("RIGHT", 0, 0)
  Crafts.search = search

  local pane = UI.Pane(col)
  pane:SetPoint("TOPLEFT", filterRow, "BOTTOMLEFT", 0, -8)
  pane:SetPoint("BOTTOMRIGHT", 0, 0)
  col.pane = pane

  -- the strip's scale, over the list's strip column
  axis = CreateFrame("Frame", nil, pane)
  axis:SetHeight(18)
  axis:SetPoint("TOPLEFT", 1, -4)
  axis:SetPoint("TOPRIGHT", -1, -4)
  axis.marks = {}
  for i, v in ipairs({ 1, 75, 150, 225, 300 }) do
    local t = UI.Text(axis, "body", 11, C.faint)
    t:SetText(v)
    axis.marks[i] = { text = t, value = v }
  end
  -- the colour key, where the strips' scale is
  local key, last = {}, nil
  for _, name in ipairs({ "orange", "yellow", "green", "grey" }) do
    local label = UI.Text(axis, "body", 11, COLORS[name])
    label:SetText(COLOR_NAMES[name])
    if last then label:SetPoint("LEFT", last, "RIGHT", 10, 0) else label:SetPoint("LEFT", 12, 0) end
    key[#key + 1] = label
    last = label
  end
  axis.key = key

  list = UI.List(pane, {
    rowHeight = ROW,
    createRow = function(row, content)
      row.icon = content:CreateTexture(nil, "ARTWORK")
      row.icon:SetSize(18, 18)
      row.icon:SetPoint("LEFT", 10, 0)
      row.icon:SetTexCoord(.08, .92, .08, .92)
      row.learn = UI.Text(content, "body", 12, C.faint)
      row.learn:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
      row.learn:SetWidth(26)
      row.learn:SetJustifyH("RIGHT")
      row.strip = CreateFrame("Frame", nil, content)
      row.strip:SetSize(STRIP, 6)
      row.strip:SetPoint("RIGHT", -12, 0)
      row.strip.track = UI.Tex(row.strip, "BACKGROUND", 0, { 1, 1, 1, .06 })
      row.strip.track:SetAllPoints()
      row.segs = {}
      row.you = UI.Tex(row.strip, "OVERLAY", 0, { 1, 1, 1, .7 })
      row.you:SetWidth(1)
      row.name = UI.Text(content, "body", 13, C.text)
      row.name:SetPoint("LEFT", row.learn, "RIGHT", 10, 0)
      row.name:SetPoint("RIGHT", row.strip, "LEFT", -12, 0)
      row.name:SetWordWrap(false)
    end,
    updateRow = function(row, item)
      local rec = item.rec
      local info = rec.item and O.Items.Info(rec.item)
      local icon = info and info.icon
      if not icon then
        local tex = rawget(_G, "GetSpellTexture")
        icon = tex and tex(item.id) or 136244
      end
      row.icon:SetTexture(icon)
      row.learn:SetText(rec.learn or rec.levels[1])
      row.name:SetText(Core.DB:RecipeName(item.id) .. (rec.count and (" ×" .. rec.count) or ""))
      local c = COLORS[item.color] or C.text
      row.name:SetTextColor(c[1], c[2], c[3])
      paintStrip(row, rec, Core.Player:GetSkill(rec.skill))
    end,
    onClick = function(item) Crafts:SelectRecipe(item.id) end,
    onGroupClick = function(group) Crafts:SetFolded(O.db.craft, group.band, not group.folded) end,
    onEnter = function(row, item)
      if not item.rec.item then return end
      GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
      GameTooltip:SetItemByID(item.rec.item)
      GameTooltip:Show()
    end,
    onLeave = function() GameTooltip:Hide() end,
  })
  list:SetPoint("TOPLEFT", axis, "BOTTOMLEFT", 0, -2)
  list:SetPoint("BOTTOMRIGHT", pane, "BOTTOMRIGHT", -1, 4)
  list:ApplyAccent(accent())
  Crafts.list = list

  empty = UI.Text(pane, "body", 13, C.faint)
  empty:SetPoint("TOPLEFT", list, "TOPLEFT", 12, -10)
  empty:SetPoint("TOPRIGHT", list, "TOPRIGHT", -12, -10)
  empty:SetWordWrap(true)
  empty:Hide()
  return col
end

-- the axis marks over the strips (the strip's right edge moves with the list's scrollbar)
local function placeAxis(scrollable)
  local right = 12 + (scrollable and 10 or 0)
  for _, m in ipairs(axis.marks) do
    m.text:ClearAllPoints()
    m.text:SetPoint("CENTER", axis, "RIGHT", -right - STRIP + stripX(m.value), 0)
  end
end

-------------------------------------------------------------------------------------------
-- The recipe (detail column)
-------------------------------------------------------------------------------------------

local sheet

---Where an item comes from, in a few words.
local QUALITY_NAMES = { [2] = "uncommon", [3] = "rare", [4] = "epic" }

---"Disenchanted from uncommon items, item level 5–25", or nil when disenchanting doesn't give it.
function Crafts.DisenchantLine(itemId)
  local de = Core.DB:DisenchantedFrom(itemId)
  if not de then return nil end
  local names = {}
  for _, q in ipairs(de.quality) do names[#names + 1] = QUALITY_NAMES[q] or "?" end
  local levels = de.min == de.max and tostring(de.min) or (de.min .. "–" .. de.max)
  return string.format("Disenchanted from %s items, item level %s", table.concat(names, " and "), levels)
end

function Crafts.SourceLine(itemId)
  local de = Crafts.DisenchantLine(itemId)
  if de then return de end      -- an enchanting material: the drops listed would be beside the point
  local parts = {}
  local made = Core.DB:CraftedBy(itemId)
  if made[1] then parts[#parts + 1] = "Crafted (" .. professionName(Core.DB:Recipe(made[1]).skill) .. ")" end
  local info = Core.DB:ItemInfo(itemId)
  if info then
    local vendors = 0
    for _ in pairs(info.vendors) do vendors = vendors + 1 end
    if vendors > 0 then parts[#parts + 1] = vendors == 1 and "Sold by 1 vendor" or ("Sold by " .. vendors .. " vendors") end
    local nodes, mobs = 0, 0
    for _ in pairs(info.drops.objects or {}) do nodes = nodes + 1 end
    for _ in pairs(info.drops.npcs or {}) do mobs = mobs + 1 end
    if nodes > 0 then parts[#parts + 1] = nodes == 1 and "Gathered from 1 kind of node" or ("Gathered from " .. nodes .. " kinds of node") end
    if mobs > 0 then parts[#parts + 1] = mobs == 1 and "Drops from 1 creature" or ("Drops from " .. mobs .. " creatures") end
    if #info.rewardOf > 0 then parts[#parts + 1] = "Quest reward" end
  end
  if #parts == 0 then return "Source not known yet" end
  return table.concat(parts, "  ·  ")
end

---Where a recipe item is found, in a few words: the vendors by name, else the drops.
function Crafts.RecipeItemLine(itemId)
  local info = Core.DB:ItemInfo(itemId)
  if not info then return "Source not known yet" end
  local sellers, limited = {}, false
  for npc, count in pairs(info.vendors) do
    sellers[#sellers + 1] = npc
    if count and count > 0 then limited = true end
  end
  table.sort(sellers, function(a, b)
    local fa, fb = friendly(a), friendly(b)
    if fa ~= fb then return fa end
    return a < b
  end)
  if sellers[1] then
    local where = zoneOf(sellers[1])
    local text = "Sold by " .. npcName(sellers[1]) .. (where and (", " .. where) or "")
    if #sellers > 1 then text = text .. string.format(" (+%d more)", #sellers - 1) end
    return text .. (limited and "  ·  limited supply" or "")
  end
  local mobs, best, bestChance = 0, nil, -1
  for npc, chance in pairs(info.drops.npcs or {}) do
    mobs = mobs + 1
    if chance > bestChance then best, bestChance = npc, chance end
  end
  if mobs == 1 then return "Drops from " .. npcName(best) .. (bestChance > 0 and string.format(" (%.1f%%)", bestChance) or "") end
  if mobs >= WORLD_DROP then return string.format("World drop (%d creatures)", mobs) end
  if mobs > 1 then return string.format("Drops from %d creatures, best: %s", mobs, npcName(best)) end
  if #info.rewardOf > 0 then return "Reward from " .. (Core.DB:Name("quests", info.rewardOf[1]) or "a quest") end
  return "Source not known yet"
end

local function buildDetail(parent)
  detail = CreateFrame("Frame", nil, parent)
  sheet = O.Sheet.New(detail)
  detail.sheet = sheet
  detail.placeholder = sheet.placeholder
  return detail
end

---Draws a recipe in the detail column.
function Crafts:ShowRecipe(id)
  local rec = id and Core.DB:Recipe(id)
  sheet:Begin(not rec and "Pick a recipe on the ladder to see what it takes and where to learn it." or nil)
  if not rec then return sheet:End() end

  local mine = Core.Player:GetSkill(rec.skill)
  local color = Core.DB.RecipeColor(rec, mine)
  sheet:Text(Core.DB:RecipeName(id), 22, COLORS[color] or C.gold, "title")
  local l = rec.levels
  local you = mine and string.format("  ·  you: %d", mine) or ""
  sheet:Text(string.format("%s  ·  learn at %d%s", professionName(rec.skill), rec.learn or l[1], you), 13, C.muted)
  sheet:Text(string.format("%s %d   %s %d   %s %d   %s %d",
    UI.Code(COLORS.orange) .. "Orange|r", l[1], UI.Code(COLORS.yellow) .. "Yellow|r", l[2],
    UI.Code(COLORS.green) .. "Green|r", l[3], UI.Code(COLORS.grey) .. "Grey|r", l[4]), 13, C.text)

  if rec.item then
    sheet:Heading("Makes")
    local info = O.Items.Info(rec.item)
    sheet:Item(rec.item, info.kind ~= "" and info.kind or "Crafted item", rec.count)
  end

  sheet:Heading("Reagents")
  for _, r in ipairs(rec.reagents) do
    local made = Core.DB:CraftedBy(r[1])[1]
    local open = made and made ~= id and function() Crafts:SelectRecipe(made) end or nil   -- a crafted reagent: its recipe
    local row = sheet:Item(r[1], string.format("×%d  ·  %s", r[2], Crafts.SourceLine(r[1])), r[2], open)
    -- nothing to show on a map for what disenchanting gives (the greens that give it drop everywhere)
    if Core.DB:DisenchantedFrom(r[1]) then row.track:Hide() end
  end

  sheet:Heading("Learn it from")
  local any = false
  if rec.auto then
    sheet:Text("You know it when you learn the profession (or as your skill rises).", 13, C.muted)
    any = true
  end
  local trainers = {}
  for npc, cost in pairs(rec.trainers or {}) do trainers[#trainers + 1] = { npc = npc, cost = cost, mine = friendly(npc) } end
  table.sort(trainers, function(a, b)
    if a.mine ~= b.mine then return a.mine end
    return npcName(a.npc) < npcName(b.npc)
  end)
  for i, t in ipairs(trainers) do
    if i > 6 then
      sheet:Text(string.format("+%d more trainers", #trainers - 6), 12, C.faint)
      break
    end
    local where = zoneOf(t.npc) or "Unknown zone"
    sheet:Line(npcName(t.npc), string.format("Trainer  ·  %s  ·  %s", where, money(t.cost)), { kind = "npc", id = t.npc }, not t.mine)
    any = true
  end
  for _, item in ipairs(rec.items or {}) do
    sheet:Item(item, Crafts.RecipeItemLine(item))
    any = true
  end
  for _, q in ipairs(rec.quests or {}) do
    sheet:Line(Core.DB:Name("quests", q) or ("Quest " .. q), "Quest reward")
    any = true
  end
  if not any then sheet:Text("Not known yet. The NorgannonDB Collector records it when someone learns it.", 13, C.faint) end

  local made = rec.item and Core.DB:ReagentOf(rec.item) or {}
  if #made > 0 then
    sheet:Heading("Used in")
    local names = {}
    for i, other in ipairs(made) do
      if i > 8 then names[#names + 1] = string.format("and %d more", #made - 8) break end
      names[#names + 1] = Core.DB:RecipeName(other)
    end
    sheet:Text(table.concat(names, ", "), 13, C.muted)
  end
  sheet:End()
end

-------------------------------------------------------------------------------------------
-- Selection and drawing
-------------------------------------------------------------------------------------------

---Shows a profession: the ladder, and the recipe chosen last (or none).
function Crafts:Select(skill)
  local entry = self:Entry(skill) or self:Entries()[1]
  if not entry then return end
  O.db.craft = entry.craft
  O.Window:SetMode("crafts")
  if O.Sidebar then O.Sidebar:SetSelected(entry.key) end
  self:Refresh()
  local last = O.db.recipe and Core.DB:Recipe(O.db.recipe)
  self:SelectRecipe(last and last.skill == entry.craft and O.db.recipe or nil, true)
end

---Shows a recipe (its profession's ladder too, when it's another's).
function Crafts:SelectRecipe(id, keepScroll)
  local rec = id and Core.DB:Recipe(id)
  if rec and rec.skill ~= O.db.craft then
    O.db.recipe = id
    return self:Select(rec.skill)
  end
  O.db.recipe = id
  local selected
  for i, item in ipairs(list.items) do
    if item.id == id then
      selected = item
      if not keepScroll then list:ScrollToIndex(i) end
    end
  end
  list:Select(selected)
  self:ShowRecipe(id)
end

---Draws the ladder for the profession shown.
function Crafts:Refresh()
  if not col then return end
  local skill = O.db.craft
  local entry = self:Entry(skill)
  if not entry then return end
  local filter = O.db.craftFilter or "all"
  for _, chip in ipairs(filterRow.chips) do chip:SetOn(chip.key == filter, true) end
  col.title:SetText(entry.name)
  local mine = entry.skill
  local parts = {}
  if mine then
    local ups = 0
    for _, id in ipairs(Core.DB:Recipes(skill)) do
      local c = Core.DB.RecipeColor(Core.DB:Recipe(id), mine)
      if c == "orange" or c == "yellow" or c == "green" then ups = ups + 1 end
    end
    parts[1] = string.format("Your skill %d", mine)
    parts[2] = string.format("%d recipes", entry.count)
    parts[3] = string.format("%d give skill-ups", ups)
  else
    parts[1] = string.format("%d recipes", entry.count)
    parts[2] = "you haven't learned " .. entry.name
  end
  col.facts:SetText(table.concat(parts, "  ·  "))
  local rows = Crafts.Rows(skill, filter, query)
  list:SetData(rows, true)
  placeAxis(#rows * ROW > (list:GetHeight() or 0))
  local any = #rows > 0
  empty:SetShown(not any)
  if not any then
    if query ~= "" then empty:SetText(string.format("No %s recipe matches \"%s\".", entry.name, query))
    elseif filter == "learnable" then empty:SetText(mine and "Nothing more to learn at your skill." or ("Learn " .. entry.name .. " to see what you can learn."))
    else empty:SetText(mine and "No recipe gives skill-ups at your skill." or ("Learn " .. entry.name .. " to see its skill-ups.")) end
  end
end

---The search (the sidebar's, or the profession's own: from = "ladder"): finds recipes. The other
---box shows the same text.
function Crafts:SetQuery(text, from)
  if syncing then return end   -- the other box, being set to the same text
  query = text or ""
  syncing = true
  if from == "ladder" then
    if O.Sidebar and O.Sidebar.search and O.Sidebar.search.SetText then O.Sidebar.search:SetText(query) end
  elseif search and search.SetText then
    search:SetText(query)
  end
  syncing = false
  if from == "ladder" and O.Sidebar then O.Sidebar:Refresh() end
  self:Refresh()
end

---Builds the Crafts view's frames over the map and detail columns (window.lua).
function Crafts:Build(win)
  local c = buildLadder(win.body)
  c:SetAllPoints(win.mapcol)
  local d = buildDetail(win.body)
  d:SetAllPoints(win.detail)
  c:Hide()
  d:Hide()
  Crafts.col, Crafts.detail = c, d
end

function Crafts:SetShown(on)
  if col then
    col:SetShown(on)
    detail:SetShown(on)
  end
end

-- your skill changed (a skill-up, a new profession): the colours change
O:Listen("SKILLS", Crafts, function()
  if col and col:IsShown() then
    Crafts:Refresh()
    Crafts:ShowRecipe(O.db.recipe)
  end
end)
Core:Listen("NORGANNON_SKILLS_CHANGED", "oracle.crafts", function() O:Send("SKILLS") end)
O:Listen("ITEMS_LOADED", Crafts, function()
  if col and col:IsShown() then list:Refresh() end
end)
