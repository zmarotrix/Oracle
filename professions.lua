-- Professions (docs/oracle-redesign.md 4.2): AtlasLoot's crafting pages with Oracle's facts.
--
--   navigator  your professions first (skill), the rest, then every specialization
--   header     rank, skill, recipes, how many you know; the next rank you can train; your specialization
--   views      By rank (Apprentice ... Artisan), By type (what it makes: weapons, armour by slot, ...),
--              By specialization (where the profession has them), Trainers
--   list       a category rail beside the recipes: what it makes (icon, quality colour), the skill to learn
--              it and its four skill-up colours, where it's learned (Trainer and price, Vendor, Drop,
--              Quest), ✓ when you know it. Filters: All, Learnable now, Not known, Skill-ups now.
--   Inspector  the recipe (crafts.lua's DrawRecipe): reagents and their sources, where to learn it
--
-- Facts only: no "craft this next" (suite decision 9).

local Core = NorgannonCore
local DB = NorgannonDB
local O = Oracle
if O.disabled then return end
local UI = Core.UI
local C = UI.C

local P = { label = "Professions", order = 2 }
O.Professions = P

local RAIL, ROW = 200, 42
local RANKS = { { "Apprentice", 0, 74 }, { "Journeyman", 75, 149 }, { "Expert", 150, 224 }, { "Artisan", 225, 300 } }
-- the rank you can train at a skill: { name, from skill, cap }
local TRAIN = { { "Journeyman", 50, 150 }, { "Expert", 125, 225 }, { "Artisan", 200, 300 } }
local FILTERS = { { key = "all", label = "All" }, { key = "learnable", label = "Learnable now" },
  { key = "unknown", label = "Not known" }, { key = "skillups", label = "Skill-ups now" } }
local VIEWS_ALL = { { key = "rank", label = "By rank" }, { key = "type", label = "By type" },
  { key = "spec", label = "By specialization" }, { key = "trainers", label = "Trainers" } }

local function skillOf(skill) return Core.Player:GetSkill(skill) end
local function knows(id) return Core.Player.KnowsRecipe and Core.Player:KnowsRecipe(id) == true end
local function name(skill) return O.Crafts.ProfessionName(skill) end
local function specs(skill) return Core.DB.Specializations and Core.DB:Specializations(skill) or {} end
local function specOf(id) return Core.DB.RecipeSpec and Core.DB:RecipeSpec(id) or nil end
local function hasSpell(id)
  return Core.Global("IsPlayerSpell", id) == true or Core.Global("IsSpellKnown", id) == true
end

-------------------------------------------------------------------------------------------
-- Model
-------------------------------------------------------------------------------------------

local cache = {}   -- skill -> { rows = { { id, rec } }, byType }

local SLOT_ORDER = { "INVTYPE_HEAD", "INVTYPE_NECK", "INVTYPE_SHOULDER", "INVTYPE_CLOAK", "INVTYPE_CHEST", "INVTYPE_ROBE",
  "INVTYPE_WRIST", "INVTYPE_HAND", "INVTYPE_WAIST", "INVTYPE_LEGS", "INVTYPE_FEET", "INVTYPE_FINGER", "INVTYPE_TRINKET" }
local ARMOR = { [1] = "Cloth", [2] = "Leather", [3] = "Mail", [4] = "Plate" }

---What a recipe makes, as a category for By type: "Weapons", "Mail: Chest", "Consumables", ...
function P.TypeOf(rec)
  if not rec.item then return "Enchantments and other" end
  local item = DB:Get("items", rec.item) or {}
  local cls, sub = item.class, item.subClass
  local _, _, _, equipLoc = Core.Global("GetItemInfoInstant", rec.item)
  if cls == 2 then return "Weapons" end
  if cls == 4 then
    if sub == 6 then return "Shields" end
    local slot = type(equipLoc) == "string" and equipLoc ~= "" and _G[equipLoc]
    if ARMOR[sub] then return ARMOR[sub] .. (slot and (": " .. slot) or "") end
    return slot and ("Gear: " .. slot) or "Other gear"
  end
  if cls == 0 then return "Consumables" end
  if cls == 7 then return "Trade goods" end
  if cls == 1 then return "Bags" end
  if cls == 6 then return "Ammunition" end
  return "Other"
end

local function rowsFor(skill)
  local c = cache[skill]
  if c then return c end
  c = { rows = {} }
  for _, id in ipairs(Core.DB:Recipes(skill)) do
    local rec = Core.DB:Recipe(id)
    if rec then c.rows[#c.rows + 1] = { id = id, rec = rec, learn = rec.learn or (rec.levels and rec.levels[1]) or 1,
      spec = specOf(id), name = Core.DB:RecipeName(id) or rec.name or ("Recipe " .. id) } end
  end
  cache[skill] = c
  return c
end
P.RowsFor = rowsFor

---Whether a recipe passes the filter at your skill.
function P.Passes(r, filter, skill)
  if filter == "learnable" then
    return skill and not knows(r.id) and r.learn <= skill and (not r.spec or hasSpell(r.spec)) or false
  elseif filter == "unknown" then
    return not knows(r.id)
  elseif filter == "skillups" then
    local color = skill and Core.DB.RecipeColor(r.rec, skill)
    return knows(r.id) and (color == "orange" or color == "yellow" or color == "green") or false
  end
  return true
end

---The categories of a view: { { key, label, rows } }.
function P.Categories(skill, view)
  local all = rowsFor(skill).rows
  local out = {}
  if view == "rank" then
    for _, r in ipairs(RANKS) do
      local rows = {}
      for _, row in ipairs(all) do if row.learn >= r[2] and row.learn <= r[3] then rows[#rows + 1] = row end end
      out[#out + 1] = { key = r[1], label = r[1], rows = rows, meta = r[2] .. "–" .. r[3] }
    end
  elseif view == "type" then
    local by, order = {}, {}
    for _, row in ipairs(all) do
      local t = P.TypeOf(row.rec)
      if not by[t] then by[t] = {} order[#order + 1] = t end
      table.insert(by[t], row)
    end
    table.sort(order, function(a, b) return #by[a] > #by[b] or (#by[a] == #by[b] and a < b) end)
    for _, t in ipairs(order) do out[#out + 1] = { key = t, label = t, rows = by[t] } end
  elseif view == "spec" then
    local open = {}
    for _, row in ipairs(all) do if not row.spec then open[#open + 1] = row end end
    out[1] = { key = "open", label = "Any " .. string.lower(name(skill)), rows = open, meta = "no specialization" }
    for _, s in ipairs(specs(skill)) do
      local rows = {}
      for _, row in ipairs(all) do if row.spec == s.id then rows[#rows + 1] = row end end
      out[#out + 1] = { key = tostring(s.id), label = (s.parent and "   " or "") .. s.name, rows = rows, spec = s,
        meta = hasSpell(s.id) and "yours" or nil }
    end
  end
  for _, cat in ipairs(out) do
    table.sort(cat.rows, function(a, b) if a.learn ~= b.learn then return a.learn < b.learn end return a.name < b.name end)
  end
  return out
end

-------------------------------------------------------------------------------------------
-- The navigator
-------------------------------------------------------------------------------------------

function P:nav()
  local rows, mine, rest = {}, {}, {}
  for _, e in ipairs(O.Crafts:Entries()) do
    e.navMeta = e.count .. " recipes"
    e.navRight = e.skill and tostring(e.skill) or ""
    e.navRightColor = e.skill and C.gold or C.faint
    if e.skill then mine[#mine + 1] = e else rest[#rest + 1] = e end
  end
  if #mine > 0 then
    rows[#rows + 1] = { group = "Your professions" }
    for _, e in ipairs(mine) do rows[#rows + 1] = e end
  end
  rows[#rows + 1] = { group = "All professions" }
  for _, e in ipairs(rest) do rows[#rows + 1] = e end
  local first = true
  for _, e in ipairs(O.Crafts:Entries()) do
    for _, s in ipairs(specs(e.craft)) do
      if first then rows[#rows + 1] = { group = "Specializations" } first = false end
      rows[#rows + 1] = { name = s.name, specRow = s.id, craft = e.craft,
        navMeta = e.name .. " · " .. s.count .. " recipes", navRight = hasSpell(s.id) and "yours" or "",
        navRightColor = C.good }
    end
  end
  return rows
end
function P:navSelected(e)
  if e.specRow then return O.db.profView == "spec" and O.db.profCat == tostring(e.specRow) and O.db.craft == e.craft end
  return e.craft == O.db.craft and not (O.db.profView == "spec" and O.db.profCat ~= "open")
end
function P:navClick(e)
  if e.specRow then return O:Go({ space = "professions", skill = e.craft, view = "spec", cat = tostring(e.specRow) }) end
  O:Go({ space = "professions", skill = e.craft })
end
function P:navTop(top) top:SetHeight(1) end

-------------------------------------------------------------------------------------------
-- The page
-------------------------------------------------------------------------------------------

local SOURCE_COLORS = { T = C.goldSoft, V = C.info, D = C.bad, Q = C.gold, A = C.good }

---A recipe's sources as short words: "Trainer 5s · Vendor · Drop · Quest".
function P.SourcesText(rec)
  local parts, seen = {}, {}
  local function add(code, text)
    if seen[text] then return end
    seen[text] = true
    parts[#parts + 1] = UI.Code(SOURCE_COLORS[code]) .. text .. "|r"
  end
  if rec.auto then add("A", "Automatic") end
  local cheapest
  for _, cost in pairs(rec.trainers or {}) do if not cheapest or cost < cheapest then cheapest = cost end end
  if cheapest then add("T", "Trainer " .. O.Crafts.Money(cheapest)) end
  for _, it in ipairs(rec.items or {}) do
    local info = Core.DB:ItemInfo(it)
    if info then
      if next(info.vendors) then add("V", "Vendor") end
      if next(info.drops.npcs or {}) or next(info.drops.objects or {}) then add("D", "Drop") end
      if #info.rewardOf > 0 then add("Q", "Quest") end
    end
  end
  if rec.quests and #rec.quests > 0 then add("Q", "Quest") end
  return table.concat(parts, UI.Code(C.faint) .. " · |r")
end

local function ladderText(rec)
  local l = rec.levels
  if not l then return "" end
  local K = O.Crafts.COLORS
  return string.format("%s%d|r %s%d|r %s%d|r %s%d|r", UI.Code(K.orange), l[1], UI.Code(K.yellow), l[2],
    UI.Code(K.green), l[3], UI.Code(K.grey), l[4])
end

local function buildList(parent)
  local f = CreateFrame("Frame", nil, parent)
  f:SetAllPoints()
  local railPane = UI.Pane(f)
  railPane:SetPoint("TOPLEFT")
  railPane:SetPoint("BOTTOMLEFT")
  railPane:SetWidth(RAIL)
  f.rail = UI.List(railPane, {
    rowHeight = 32,
    createRow = function(row, content)
      row.name = UI.Text(content, "body", 13, C.text)
      row.name:SetPoint("TOPLEFT", 10, -3)
      row.name:SetPoint("TOPRIGHT", content, "TOPRIGHT", -34, -3)
      row.name:SetWordWrap(false)
      row.meta = UI.Text(content, "body", 11, C.faint)
      row.meta:SetPoint("TOPLEFT", row.name, "BOTTOMLEFT", 0, -1)
      row.count = UI.Text(content, "body", 12, C.faint)
      row.count:SetPoint("TOPRIGHT", -8, -4)
    end,
    updateRow = function(row, cat)
      row.name:SetText(cat.label)
      row.meta:SetText(cat.meta or "")
      row.count:SetText(#cat.rows)
    end,
    onClick = function(cat)
      O.db.profCat = cat.key
      P:Fill()
    end,
  })
  f.rail:SetPoint("TOPLEFT", 1, -4)
  f.rail:SetPoint("BOTTOMRIGHT", -1, 4)
  f.rail:ApplyAccent(UI.Accent("oracle"))

  local listPane = UI.Pane(f)
  listPane:SetPoint("TOPLEFT", railPane, "TOPRIGHT", 8, 0)
  listPane:SetPoint("BOTTOMRIGHT")
  f.list = UI.List(listPane, {
    rowHeight = ROW,
    createRow = function(row, content)
      content.rightInset = 230
      O.Items.Build(content)
      row.itemFrame = content
      row.ladder = UI.Text(content, "body", 12, C.text)
      row.ladder:SetPoint("TOPRIGHT", -30, -5)
      row.ladder:SetJustifyH("RIGHT")
      row.sources = UI.Text(content, "body", 11, C.faint)
      row.sources:SetPoint("TOPRIGHT", row.ladder, "BOTTOMRIGHT", 0, -3)
      row.sources:SetWidth(200)
      row.sources:SetJustifyH("RIGHT")
      row.sources:SetWordWrap(false)
      row.known = UI.Icon(content, "check", 14, C.good)
      row.known:SetPoint("RIGHT", -10, 0)
    end,
    updateRow = function(row, r)
      local skill = skillOf(r.rec.skill)
      local color = O.Crafts.COLORS[Core.DB.RecipeColor(r.rec, skill) or ""] or C.muted
      local parts = { UI.Code(color) .. "learn " .. r.learn .. "|r" }
      if r.spec then
        local s
        for _, x in ipairs(specs(r.rec.skill)) do if x.id == r.spec then s = x end end
        parts[#parts + 1] = UI.Code(C.warn) .. (s and s.name or "a specialization") .. "|r"
      end
      if r.rec.forever then parts[#parts + 1] = UI.Code(UI.Accent("oracle")) .. "Forever|r" end
      if r.rec.item then
        row.itemFrame.spellId = nil
        local info = O.Items.Fill(row.itemFrame, r.rec.item, "")
        row.itemFrame.itemName:SetText(info.name .. ((r.rec.count or 1) > 1 and (" ×" .. r.rec.count) or ""))
        row.itemFrame.itemMeta:SetText(table.concat(parts, " · ") .. (info.kind ~= "" and (" · " .. info.kind) or ""))
      else
        row.itemFrame.itemId = nil
        row.itemFrame.spellId = r.id                 -- the icon shows the recipe's spell instead
        row.itemFrame.tile.icon:SetTexture(Core.Global("GetSpellTexture", r.id) or 134400)
        row.itemFrame.itemName:SetText(r.name)
        row.itemFrame.itemName:SetTextColor(C.text[1], C.text[2], C.text[3])
        row.itemFrame.itemMeta:SetText(table.concat(parts, " · "))
      end
      row.ladder:SetText(ladderText(r.rec))
      row.sources:SetText(P.SourcesText(r.rec))
      row.known:SetShown(knows(r.id))
    end,
    onClick = function(r, _, button)
      if button == "RightButton" and r.rec.item and O.Wants then return O.Wants:Toggle(r.rec.item) end
      if IsShiftKeyDown() and r.rec.item then
        local link = select(2, (C_Item and C_Item.GetItemInfo or GetItemInfo)(r.rec.item))
        if link and ChatEdit_InsertLink then ChatEdit_InsertLink(link) end
        return
      end
      O.db.recipe = r.id
      O.Inspector:Show("recipe", r.id)
      f.list:Select(r)
    end,
  })
  f.list:SetPoint("TOPLEFT", 1, -4)
  f.list:SetPoint("BOTTOMRIGHT", -1, 4)
  f.list:ApplyAccent(UI.Accent("oracle"))
  f.empty = UI.Text(listPane, "body", 13, C.faint)
  f.empty:SetPoint("TOPLEFT", 14, -14)
  f.empty:SetPoint("TOPRIGHT", -14, -14)
  f.empty:SetWordWrap(true)
  -- the specialization's note over the list
  f.note = UI.Text(listPane, "body", 12, C.muted)
  f.note:Hide()
  return f
end

local function buildTrainers(parent)
  local f = CreateFrame("Frame", nil, parent)
  f:SetAllPoints()
  local pane = UI.Pane(f)
  pane:SetAllPoints()
  f.list = UI.List(pane, {
    rowHeight = 40,
    groupBand = true,
    createRow = function(row, content)
      row.name = UI.Text(content, "body", 14, C.text)
      row.name:SetPoint("TOPLEFT", 12, -4)
      row.meta = UI.Text(content, "body", 12, C.muted)
      row.meta:SetPoint("TOPLEFT", row.name, "BOTTOMLEFT", 0, -1)
      row.right = UI.Text(content, "body", 12, C.faint)
      row.right:SetPoint("RIGHT", -12, 0)
      row.right:SetJustifyH("RIGHT")
    end,
    updateRow = function(row, t)
      row.name:SetText(t.name)
      row.meta:SetText(t.where or "")
      row.right:SetText(string.format("teaches up to %d · %d recipes", t.max, t.count))
    end,
    onClick = function(t) O.Sheet.Track("npc", t.npc) end,
    onEnter = function(row)
      GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
      GameTooltip:AddLine("Click: show on your map", 1, 1, 1)
      GameTooltip:Show()
    end,
    onLeave = function() GameTooltip:Hide() end,
  })
  f.list:SetPoint("TOPLEFT", 1, -4)
  f.list:SetPoint("BOTTOMRIGHT", -1, 4)
  f.list:ApplyAccent(UI.Accent("oracle"))
  return f
end

---A profession's trainers: yours first, by the highest skill they teach.
function P.Trainers(skill)
  local by = {}
  for _, row in ipairs(rowsFor(skill).rows) do
    for npc in pairs(row.rec.trainers or {}) do
      local t = by[npc] or { npc = npc, max = 0, count = 0 }
      t.max = math.max(t.max, row.learn)
      t.count = t.count + 1
      by[npc] = t
    end
  end
  local f = UnitFactionGroup and UnitFactionGroup("player")
  local mine = f == "Alliance" and "A" or (f == "Horde" and "H") or nil
  local yours, others = {}, {}
  for _, t in pairs(by) do
    local rec = DB:Get("npcs", t.npc) or {}
    t.name = Core.DB:Name("npcs", t.npc) or ("Trainer " .. t.npc)
    t.where = (rec.subName and (rec.subName .. " · ") or "") .. (rec.zone and O.Model.AreaName(rec.zone) or "")
    if not (rec.reaction and mine) or rec.reaction:find(mine) then yours[#yours + 1] = t else others[#others + 1] = t end
  end
  local function order(a, b) if a.max ~= b.max then return a.max > b.max end return a.name < b.name end
  table.sort(yours, order)
  table.sort(others, order)
  local rows = {}
  if #yours > 0 then rows[#rows + 1] = { group = "Your faction's trainers" } end
  for _, t in ipairs(yours) do rows[#rows + 1] = t end
  if #others > 0 then rows[#rows + 1] = { group = "The other faction's" } end
  for _, t in ipairs(others) do rows[#rows + 1] = t end
  return rows
end

function P:Build(page)
  self.page = page
  self.views = O.Shell:Views(VIEWS_ALL, function(key)
    O.db.profView = key
    O.db.profCat = nil
    P:Fill()
  end)
  self.list = buildList(page.content)
  self.trainers = buildTrainers(page.content)
  self.tools = CreateFrame("Frame", nil, page.tools)
  self.tools:SetAllPoints()
  self.filter = UI.Segmented(self.tools, FILTERS, function(key)
    O.db.profFilter = key
    P:Fill()
  end, 22)
  self.filter:SetPoint("RIGHT", 0, 0)
  self:Hide()
end

local function headerFor(skill)
  local v = skillOf(skill)
  local all = rowsFor(skill).rows
  local known = 0
  for _, r in ipairs(all) do if knows(r.id) then known = known + 1 end end
  local facts = {}
  if v then
    local rank = v <= 75 and "Apprentice" or v <= 150 and "Journeyman" or v <= 225 and "Expert" or "Artisan"
    facts[#facts + 1] = UI.Code(C.goldSoft) .. rank .. "|r · skill " .. UI.Code(C.text) .. v .. "|r"
  else
    facts[#facts + 1] = "You don't have this profession"
  end
  facts[#facts + 1] = #all .. " recipes"
  if v then facts[#facts + 1] = "you know " .. UI.Code(C.text) .. known .. "|r" end
  local badges = {}
  if v then
    local cap = v <= 75 and 75 or v <= 150 and 150 or v <= 225 and 225 or 300
    for _, t in ipairs(TRAIN) do
      if v >= t[2] and t[3] > cap then
        badges[#badges + 1] = UI.Code(C.good) .. "You can train " .. t[1] .. " now (up to " .. t[3] .. ")|r"
        break
      end
    end
  end
  local list = specs(skill)
  if #list > 0 then
    local yours = {}
    for _, s in ipairs(list) do if hasSpell(s.id) then yours[#yours + 1] = s.name end end
    if #yours > 0 then
      badges[#badges + 1] = "Your specialization: " .. UI.Code(C.warn) .. table.concat(yours, ", ") .. "|r"
    else
      local names = {}
      for _, s in ipairs(list) do if not s.parent then names[#names + 1] = s.name end end
      badges[#badges + 1] = "Not specialized" .. (#names > 0 and (": " .. table.concat(names, " or ")) or "")
    end
  end
  return name(skill), table.concat(facts, "  ·  "), #badges > 0 and table.concat(badges, "   ") or nil
end

---Draws the page for the profession in O.db.craft.
function P:Fill()
  local skill = O.db.craft
  if not skill then return end
  O.Shell:SetHeader(headerFor(skill))
  local hasSpecs = #specs(skill) > 0
  for _, t in ipairs(self.views.tabs) do t:SetShown(t.key ~= "spec" or hasSpecs) end
  local view = O.db.profView or "rank"
  if view == "spec" and not hasSpecs then view = "rank" end
  self.views:Select(view, true)
  self.list:SetShown(view ~= "trainers")
  self.trainers:SetShown(view == "trainers")
  self.tools:SetShown(view ~= "trainers")
  self.filter:Select(O.db.profFilter or "all", true)
  if view == "trainers" then
    self.trainers.list:SetData(P.Trainers(skill))
    return
  end
  local cats = P.Categories(skill, view)
  local cat
  for _, c in ipairs(cats) do if c.key == O.db.profCat then cat = c end end
  if not cat then
    -- by rank: yours; else the first with recipes
    local v = skillOf(skill)
    for _, c in ipairs(cats) do
      if not cat and #c.rows > 0 then cat = c end
      if view == "rank" and v then for _, r in ipairs(RANKS) do if r[1] == c.key and v >= r[2] and v <= r[3] and #c.rows > 0 then cat = c end end end
    end
    if view == "spec" and cats[2] then cat = cats[2] end
    cat = cat or cats[1]
  end
  O.db.profCat = cat and cat.key
  self.list.rail:SetData(cats)
  self.list.rail:Select(cat)
  local rows, filter, v = {}, O.db.profFilter or "all", skillOf(skill)
  for _, r in ipairs(cat and cat.rows or {}) do if P.Passes(r, filter, v) then rows[#rows + 1] = r end end
  self.list.list:SetData(rows)
  self.shown = rows
  local selected
  for _, r in ipairs(rows) do if r.id == O.db.recipe then selected = r end end
  self.list.list:Select(selected)
  self.list.empty:SetShown(#rows == 0)
  self.list.empty:SetText(filter ~= "all" and "Nothing here with this filter." or "No recipes here.")
end

---Opens a profession, a view and category, a recipe: { skill, view, cat, recipe }.
function P:Go(where)
  if where.recipe then
    local rec = Core.DB:Recipe(where.recipe)
    if rec then
      where.skill = where.skill or rec.skill
      local spec = specOf(where.recipe)
      if spec then
        O.db.profView, O.db.profCat = "spec", tostring(spec)
      else
        O.db.profView = "rank"
        for _, r in ipairs(RANKS) do
          local learn = rec.learn or (rec.levels and rec.levels[1]) or 1
          if learn >= r[2] and learn <= r[3] then O.db.profCat = r[1] end
        end
      end
      O.db.profFilter = "all"
      O.db.recipe = where.recipe
    end
  end
  if where.view then O.db.profView, O.db.profCat = where.view, where.cat end
  local skill = where.skill or O.db.craft or O.Sidebar.FirstCraft()
  if skill ~= O.db.craft and not where.recipe and not where.view then O.db.profCat = nil end
  O.db.craft = skill
  self:Fill()
  if where.recipe then O.Inspector:Show("recipe", where.recipe) end
end

function P:Show()
  self.views:Show()
  self:Go({})
end

function P:Hide()
  self.views:Hide()
  self.list:Hide()
  self.trainers:Hide()
  self.tools:Hide()
end

-- your skill or your recipes changed: the colours, ✓ and filters change
local function refresh()
  if O.Shell.current == "professions" and P.list and P.list:IsVisible() then P:Fill() end
end
Core:Listen("NORGANNON_SKILLS_CHANGED", "oracle.professions", refresh)
Core:Listen("NORGANNON_RECIPES_SCANNED", "oracle.professions", refresh)
O:Listen("ITEMS_LOADED", "professions", function()
  if P.list and P.list:IsVisible() then P.list.list:Refresh() end
end)

O.Shell:AddSpace("professions", P)
