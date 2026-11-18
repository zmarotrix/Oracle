-- The global search (docs/oracle-redesign.md 3.2): one box in the top bar finds instances, bosses, items,
-- recipes, professions, specializations, quests and zones, grouped by kind, five of each, names that
-- start with the text first. A recipe is also found by its specialization's name ("armorsmith"). Up and Down move through the results, Enter opens one, Escape closes the list.
--
-- Where a result goes: an instance or boss opens on its loot, an item on the boss that drops it
-- (else the Inspector), a recipe or profession in Professions, a quest in its dungeon's Quests (else
-- the Inspector), a zone in Zones.

local Core = NorgannonCore
local O = Oracle
if O.disabled then return end
local UI = Core.UI
local C = UI.C

local Search = {}
O.Search = Search

local PER_KIND, ROW = 5, 26
local ORDER = { "Specializations", "Instances", "Bosses", "Items", "Recipes", "Professions", "PvP & Factions", "Quests", "Zones" }

local box, drop, list, text, results, cursor = nil, nil, nil, "", {}, 1
local bosses, recipes, specs   -- name indexes, built on the first search

local function lower(s) return string.lower(s or "") end

-- a match's rank: 0 starts with the text, 1 a word starts with it, 2 anywhere; nil no match
local function rank(name, t)
  local n = lower(name)
  local at = n:find(t, 1, true)
  if not at then return nil end
  if at == 1 then return 0 end
  if n:sub(at - 1, at - 1):match("[%s%-'(]") then return 1 end
  return 2
end

local function buildIndexes()
  bosses = {}
  for _, e in ipairs(O.Model:All()) do
    for _, b in ipairs(e.inst.bosses or {}) do
      if b.id then bosses[#bosses + 1] = { name = Core.DB:Name("npcs", b.id) or "", key = e.key, npc = b.id, where = e.name } end
    end
  end
  recipes, specs = {}, {}
  for _, c in ipairs(O.Crafts and O.Crafts:Entries() or {}) do
    local specName = {}
    for _, s in ipairs(Core.DB.Specializations and Core.DB:Specializations(c.craft) or {}) do
      specName[s.id] = s.name
      specs[#specs + 1] = { name = s.name, id = s.id, skill = c.craft, prof = c.name, count = s.count }
    end
    for _, id in ipairs(Core.DB:Recipes(c.craft)) do
      local spec = Core.DB.RecipeSpec and Core.DB:RecipeSpec(id)
      recipes[#recipes + 1] = { name = Core.DB:RecipeName(id) or "", id = id, skill = c.craft, prof = c.name,
        spec = spec, specName = spec and specName[spec] }
    end
  end
end

---Every result for a text: { kind, name, meta, go, item? }, grouped in ORDER, PER_KIND each.
function Search.Find(query)
  local t = lower(strtrim and strtrim(query or "") or query or "")
  if #t < 2 then return {} end
  if not bosses then buildIndexes() end
  local found = {}
  local function add(kind, name, meta, go, extra)
    local r = rank(name, t)
    if not r and extra and extra.also then r = rank(extra.also, t) and 3 end   -- found by its specialization
    if not r then return end
    found[kind] = found[kind] or {}
    local hit = { kind = kind, name = name, meta = meta, go = go, rank = r }
    if extra then for k, v in pairs(extra) do hit[k] = v end end
    table.insert(found[kind], hit)
  end
  for _, e in ipairs(O.Model:All()) do
    add("Instances", e.name, (e.zone or "") .. " · " .. O.Model.LevelText(e), { space = "dungeons", key = e.key, view = "loot" })
  end
  for _, b in ipairs(bosses) do
    add("Bosses", b.name, b.where, { space = "dungeons", key = b.key, view = "loot", boss = b.npc, inspect = { "npc", b.npc } })
  end
  for _, s in ipairs(specs) do
    add("Specializations", s.name, s.prof .. " · " .. s.count .. " recipes",
      { space = "professions", skill = s.skill, view = "spec", cat = tostring(s.id) })
  end
  for _, r in ipairs(recipes) do
    add("Recipes", r.name, r.prof .. (r.specName and (" · " .. r.specName) or ""),
      { space = "professions", skill = r.skill, recipe = r.id }, r.spec and { spec = r.spec, also = r.specName } or nil)
  end
  for _, c in ipairs(O.Crafts and O.Crafts:Entries() or {}) do
    add("Professions", c.name, c.count .. " recipes", { space = "professions", skill = c.craft })
  end
  for _, z in ipairs(O.Zones and O.Zones:Entries() or {}) do
    if not z.group then add("Zones", z.name, z.continent or "", { space = "zones", area = z.zone }) end
  end
  -- honor ranks (both sides' titles) and factions
  if O.Rewards then
    for _, e in ipairs(O.Rewards.PvPNav()) do
      if not e.group then add("PvP & Factions", e.name, "Rank " .. e.rank .. " · " .. (e.side == "A" and "Alliance" or "Horde"),
        { space = "rewards", rank = e.rank, side = e.side }) end
    end
    for _, e in ipairs(O.Rewards.FactionNav()) do
      if not e.group then add("PvP & Factions", e.name, "Faction · " .. (e.navMeta or ""), { space = "rewards", faction = e.faction }) end
    end
  end
  -- items and quests: the Core's name index
  for _, hit in ipairs((Core.DB:Search(query, { kinds = { items = true }, limit = 12 }))) do
    local id = hit.ids and hit.ids[1]
    if id then
      local where = O.Links and O.Links.Find("item", id)
      local go = where and { space = "dungeons", key = where.key, view = "loot", boss = where.npc, inspect = { "item", id } }
        or { inspect = { "item", id } }
      local meta = where and (O.Model:Get(where.key) or {}).name or ""
      -- a PvP or reputation reward opens its rank's or faction's page
      local rec = not where and NorgannonDB and NorgannonDB:Get("items", id)
      if rec and rec.pvpRank and O.Rewards then
        go = { space = "rewards", rank = rec.pvpRank, side = rec.side, inspect = { "item", id } }
        meta = O.Rewards.RankName(rec.pvpRank, rec.side or O.Rewards.MySide() or "A")
      elseif rec and rec.repFaction and O.Rewards and O.Rewards.Faction(rec.repFaction) then
        go = { space = "rewards", faction = rec.repFaction, inspect = { "item", id } }
        meta = O.Rewards.Faction(rec.repFaction).name
      end
      add("Items", hit.name, meta, go, { item = id })
    end
  end
  for _, hit in ipairs((Core.DB:Search(query, { kinds = { quests = true }, limit = 12 }))) do
    local id = hit.ids and hit.ids[1]
    if id then
      local where = O.Links and O.Links.Find("quest", id)
      local go = where and { space = "dungeons", key = where.key, view = "quests", inspect = { "quest", id } } or { inspect = { "quest", id } }
      add("Quests", hit.name, where and (O.Model:Get(where.key) or {}).name or "", go)
    end
  end
  local out = {}
  for _, kind in ipairs(ORDER) do
    local hits = found[kind]
    if hits then
      table.sort(hits, function(a, b)
        if a.rank ~= b.rank then return a.rank < b.rank end
        if #a.name ~= #b.name then return #a.name < #b.name end
        return a.name < b.name
      end)
      out[#out + 1] = { group = kind }
      for i = 1, math.min(PER_KIND, #hits) do out[#out + 1] = hits[i] end
    end
  end
  return out
end

local function firstFrom(i, step)
  while results[i] and results[i].group do i = i + step end
  return results[i] and i or nil
end

local function paint()
  if not list then return end
  list:Select(results[cursor])
end

local function close()
  if drop then drop:Hide() end
end

---Opens a result.
function Search.Open(hit)
  if not hit or hit.group then return end
  close()
  if box then box:SetText("") end
  O:Go(hit.go)
end

local function update(t)
  text = t or ""
  results = Search.Find(text)
  if #results == 0 then
    close()
    return
  end
  cursor = firstFrom(1, 1) or 1
  list:SetData(results)
  drop:SetHeight(math.min(#results, 16) * ROW + 10)
  drop:Show()
  paint()
end

function Search:Build(parent)
  box = UI.Search(parent, "Search items, bosses, recipes, quests, zones…", function(t) update(t) end,
    function() Search.Open(results[cursor]) end)
  -- the results float under the box, over the window
  drop = UI.Pane(UIParent)
  drop:SetFrameStrata("DIALOG")
  drop:SetPoint("TOPLEFT", box, "BOTTOMLEFT", 0, -4)
  drop:SetWidth(480)
  drop:Hide()
  list = UI.List(drop, {
    rowHeight = ROW,
    createRow = function(row, content)
      row.name = UI.Text(content, "body", 13, C.text)
      row.name:SetPoint("LEFT", 12, 0)
      row.name:SetPoint("RIGHT", content, "RIGHT", -170, 0)
      row.name:SetWordWrap(false)
      row.meta = UI.Text(content, "body", 12, C.faint)
      row.meta:SetPoint("RIGHT", -10, 0)
      row.meta:SetWidth(160)
      row.meta:SetJustifyH("RIGHT")
      row.meta:SetWordWrap(false)
    end,
    updateRow = function(row, hit)
      row.name:SetText(hit.name)
      local c = C.text
      if hit.item then c = O.Items.Info(hit.item).color end
      row.name:SetTextColor(c[1], c[2], c[3])
      row.meta:SetText(hit.meta or "")
    end,
    onClick = function(hit) Search.Open(hit) end,
  })
  list:SetPoint("TOPLEFT", 1, -5)
  list:SetPoint("BOTTOMRIGHT", -1, 5)
  list:ApplyAccent(UI.Accent("oracle"))
  local edit = box.edit
  if edit then
    edit:HookScript("OnEscapePressed", close)
    edit:HookScript("OnEditFocusLost", function() C_Timer.After(.2, close) end)
    if edit.SetAltArrowKeyMode then edit:SetAltArrowKeyMode(false) end
    edit:HookScript("OnArrowPressed", function(_, key)
      if not drop:IsShown() then return end
      if key == "DOWN" then cursor = firstFrom(cursor + 1, 1) or cursor end
      if key == "UP" then cursor = firstFrom(cursor - 1, -1) or cursor end
      paint()
    end)
  end
  Search.box, Search.drop, Search.list = box, drop, list
  return box
end

---Puts the cursor in the search box.
function Search:Focus()
  if box and box.SetFocus then box:SetFocus() end
end

function Search:Results() return results end
