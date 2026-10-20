-- Zones (Phase B): every zone of the world as an Oracle page.
--
--   the sidebar     the zones on each continent, with their level range in your difficulty colour
--   the map column  the game's own world map art for the zone (C_Map's art layers, drawn as the
--                   world map draws them), with dungeon entrances, flight masters, innkeepers and
--                   rares pinned on it; the legend turns each kind on and off
--   the detail      Items: what you can get there, the quest rewards, what its creatures drop
--                   (world drops left out unless asked for) and what its vendors sell, filtered by
--                   source and kind (gear, recipes, everything), best item level first;
--                   About: levels, dungeons, services, rares, gathering, the recipes its
--                   creatures drop and its quests by level
--
-- Facts only: no routes or "go here next" (no guides, decision 9).

local Core = NorgannonCore
local DB = NorgannonDB
local O = Oracle
if O.disabled then return end
local UI = Core.UI
local C = UI.C

local Zones = {}
O.Zones = Zones

local ZONE = Enum and Enum.UIMapType and Enum.UIMapType.Zone or 3
-- the pins: { kind, label, icon, colour } (the legend's order)
local KINDS = {
  { "entrance", "Dungeons", nil, UI.Hex("b48cff") },
  { "flight", "Flight masters", "flight" },
  { "innkeeper", "Innkeepers", "innkeeper" },
  { "rare", "Rares", "diamond", UI.Hex("ff8f3d") },
}
local SERVICES = {   -- the detail's services, by NorgannonDB category
  { "flight", "Flight master" }, { "innkeeper", "Innkeeper" }, { "repair", "Repairs" },
  { "banker", "Banker" }, { "auctioneer", "Auctioneer" }, { "stablemaster", "Stable master" },
  { "mailbox", "Mailbox" }, { "spirithealer", "Spirit healer" }, { "meetingstone", "Meeting stone" },
}

local col, sheet, panel, legend, tabs, itemPane, itemList, itemEmpty, sourceChips, kindChips
local WORLD_DROP = 25      -- dropped by this many kinds of creature: a world drop
local SOURCES = { { "reward", "Quest rewards" }, { "drop", "Drops" }, { "vendor", "Vendors" } }
local ITEM_KINDS = { { "gear", "Gear" }, { "recipe", "Recipes" }, { "all", "Everything" } }
local tiles, pins, overlays = {}, {}, {}
local OVERLAY_TILE = 256     -- the world map's overlay textures come in 256 px pieces
local entries, byKey
local query = ""

local function accent() return UI.Accent("oracle") end
local function npcName(id) return Core.DB:Name("npcs", id) or ("NPC " .. id) end

-------------------------------------------------------------------------------------------
-- Model
-------------------------------------------------------------------------------------------

-- the zone's level range: the middle 80% of its quests' levels (outliers left out)
local function levelsOf(area)
  local lv = {}
  for _, q in ipairs(Core.DB:Zone(area).quests) do
    local rec = DB:Get("quests", q)
    if rec and rec.level and rec.level > 0 and not Core.DB:IsQuestHidden(q) then lv[#lv + 1] = rec.level end
  end
  if #lv == 0 then return nil, 0 end
  table.sort(lv)
  local lo = lv[math.max(1, math.floor(#lv * .1 + .5))]
  local hi = lv[math.max(1, math.min(#lv, math.ceil(#lv * .9)))]
  return { min = lo, max = hi }, #lv
end

local function build()
  entries, byKey = {}, {}
  for area, z in pairs(DB.zones or {}) do
    -- a zone the client has a map for, on a continent (later expansions' zones aren't in it)
    if not z.parent and z.uiMapId and C_Map and C_Map.GetMapInfo then
      local ok, info = pcall(C_Map.GetMapInfo, z.uiMapId)
      local continent = ok and info and info.mapType == ZONE and O.Model.ContinentOf(area)
      if continent then
        local e = { key = "zone:" .. area, isZone = true, zone = area, uiMap = z.uiMapId, name = O.Model.AreaName(area) or z.name,
                    continent = continent }
        e.levels, e.quests = levelsOf(area)
        entries[#entries + 1] = e
        byKey[area] = e
      end
    end
  end
end

---The zones as sidebar entries, by level (or name, or continent).
function Zones:Entries()
  if not entries then build() end
  local out = {}
  local text = query:lower()
  for _, e in ipairs(entries) do
    if text == "" or e.name:lower():find(text, 1, true) then out[#out + 1] = e end
  end
  local sort = O.db.sort
  table.sort(out, function(a, b)
    if sort == "continent" and a.continent ~= b.continent then return a.continent < b.continent end
    if sort ~= "name" then
      local la, lb = a.levels and a.levels.min or 99, b.levels and b.levels.min or 99
      if la ~= lb then return la < lb end
    end
    return a.name < b.name
  end)
  if sort == "continent" then
    local grouped, last = {}, nil
    for _, e in ipairs(out) do
      if e.continent ~= last then
        grouped[#grouped + 1] = { group = e.continent }
        last = e.continent
      end
      grouped[#grouped + 1] = e
    end
    out = grouped
  end
  return out
end

function Zones:Entry(area)
  if not byKey then build() end
  return byKey[area]
end

---Where an NPC first stands in a zone (percent), or nil.
local function spawnIn(rec, area)
  local list = rec and rec.spawns and rec.spawns[area]
  local p = list and list[1]
  if p then return p[1], p[2] end
end

---What a zone holds, for its page: { pins = {...}, services = {...}, rares, trainers, gathering,
---recipes, dungeons, quests }.
function Zones.Facts(area)
  local facts = { pins = {}, services = {}, rares = {}, trainers = {}, gathering = {}, recipes = {}, dungeons = {} }
  local cats = DB.categories or {}
  local here = {}
  for _, id in ipairs(Core.DB:Zone(area).npcs) do here[id] = true end
  for _, s in ipairs(SERVICES) do
    local list = {}
    for id in pairs(cats[s[1]] and cats[s[1]].npcs or {}) do
      if here[id] then list[#list + 1] = id end
    end
    for id in pairs(cats[s[1]] and cats[s[1]].objects or {}) do
      local rec = DB:Get("objects", id)
      if rec and rec.spawns and rec.spawns[area] then list[#list + 1] = -id end   -- objects: negative
    end
    if #list > 0 then
      table.sort(list)
      facts.services[#facts.services + 1] = { key = s[1], label = s[2], ids = list }
      if s[1] == "flight" or s[1] == "innkeeper" then
        for _, id in ipairs(list) do
          local x, y = spawnIn(id > 0 and DB:Get("npcs", id), area)
          if x then facts.pins[#facts.pins + 1] = { kind = s[1], x = x, y = y, npc = id, title = npcName(id) } end
        end
      end
    end
  end
  for id, level in pairs(cats.rares and cats.rares.npcs or {}) do
    if here[id] then
      facts.rares[#facts.rares + 1] = { npc = id, level = level }
      local x, y = spawnIn(DB:Get("npcs", id), area)
      if x then facts.pins[#facts.pins + 1] = { kind = "rare", x = x, y = y, npc = id, title = npcName(id) } end
    end
  end
  table.sort(facts.rares, function(a, b) return (a.level or 0) < (b.level or 0) end)
  for id in pairs(cats.trainer and cats.trainer.npcs or {}) do
    if here[id] then facts.trainers[#facts.trainers + 1] = id end
  end
  table.sort(facts.trainers, function(a, b) return npcName(a) < npcName(b) end)
  for _, kind in ipairs({ "herbs", "mines" }) do
    for id, skill in pairs(cats[kind] and cats[kind].objects or {}) do
      local rec = DB:Get("objects", id)
      if rec and rec.spawns and rec.spawns[area] then
        facts.gathering[#facts.gathering + 1] = { object = id, skill = skill, kind = kind, count = #rec.spawns[area] }
      end
    end
  end
  table.sort(facts.gathering, function(a, b) return (a.skill or 0) < (b.skill or 0) end)
  -- recipes its creatures drop (world drops left out: they're everywhere)
  local seen = {}
  for id in pairs(here) do
    local rec = DB:Get("npcs", id)
    for item in pairs(rec and rec.drops or {}) do
      local spell = not seen[item] and Core.DB:RecipeTaughtBy(item)
      if spell then
        seen[item] = true
        local sources = 0
        for _ in pairs((Core.DB:ItemInfo(item) or { drops = {} }).drops.npcs or {}) do sources = sources + 1 end
        if sources < 25 then facts.recipes[#facts.recipes + 1] = { item = item, spell = spell, from = id } end
      end
    end
  end
  table.sort(facts.recipes, function(a, b) return (Core.DB:Recipe(a.spell).learn or 0) < (Core.DB:Recipe(b.spell).learn or 0) end)
  for _, e in ipairs(O.Model:All()) do
    local en = e.entrance
    if en and en.area == area then
      facts.dungeons[#facts.dungeons + 1] = e
      if en.x and en.y then facts.pins[#facts.pins + 1] = { kind = "entrance", x = en.x, y = en.y, key = e.key, title = e.name } end
    end
  end
  local quests = {}
  for _, q in ipairs(Core.DB:Zone(area).quests) do
    local rec = DB:Get("quests", q)
    if rec and not Core.DB:IsQuestHidden(q) then quests[#quests + 1] = { id = q, level = rec.level or 0, name = Core.DB:Name("quests", q) or rec.name } end
  end
  table.sort(quests, function(a, b)
    if a.level ~= b.level then return a.level < b.level end
    return (a.name or "") < (b.name or "")
  end)
  facts.quests = quests
  return facts
end

-- how many kinds of creature drop an item (once per item)
local dropSources = {}
local function sourcesOf(item)
  local n = dropSources[item]
  if n then return n end
  n = 0
  local info = Core.DB:ItemInfo(item)
  for _ in pairs(info and info.drops.npcs or {}) do n = n + 1 end
  dropSources[item] = n
  return n
end

---What an item is for the filters: "gear" (weapons, armour), "recipe", "quest" or "other".
function Zones.ItemKind(item)
  local rec = DB:Get("items", item)
  local cls = rec and rec.class
  if cls == 2 or cls == 4 then return "gear" end
  if cls == 9 then return "recipe" end
  if cls == 12 then return "quest" end
  return "other"
end

---Everything a zone gives: { {item, source = "reward" / "drop" / "vendor", quest, npc, chance,
---limited, level, kind, world}, ... }, one row per item and source, best item level first.
function Zones.Items(area)
  local out, seen = {}, {}
  local function add(row)
    local key = row.item .. ":" .. row.source
    local old = seen[key]
    if old then
      if row.source == "drop" and (row.chance or 0) > (old.chance or 0) then old.npc, old.chance = row.npc, row.chance end
      return
    end
    local rec = DB:Get("items", row.item)
    row.level = rec and rec.level or 0
    row.kind = Zones.ItemKind(row.item)
    seen[key] = row
    out[#out + 1] = row
  end
  for _, q in ipairs(Core.DB:Zone(area).quests) do
    local rec = DB:Get("quests", q)
    local rewards = rec and not Core.DB:IsQuestHidden(q) and rec.rewards
    for _, item in ipairs(rewards and rewards.items or {}) do
      add({ item = item, source = "reward", quest = q, questLevel = rec.level, choice = rewards.choice })
    end
  end
  for _, npc in ipairs(Core.DB:Zone(area).npcs) do
    local rec = DB:Get("npcs", npc)
    for item, chance in pairs(rec and rec.drops or {}) do
      add({ item = item, source = "drop", npc = npc, chance = chance, world = sourcesOf(item) >= WORLD_DROP })
    end
    for item, count in pairs(rec and rec.sells or {}) do
      add({ item = item, source = "vendor", npc = npc, limited = count and count > 0 })
    end
  end
  table.sort(out, function(a, b)
    if a.level ~= b.level then return a.level > b.level end
    return a.item < b.item
  end)
  return out
end

---A zone's items through the filters (OracleDB.zoneSources, zoneKind, zoneWorldDrops).
function Zones.FilterItems(rows)
  local sources = O.db.zoneSources or {}
  local kind = O.db.zoneKind or "gear"
  local out = {}
  for _, r in ipairs(rows) do
    local keep = sources[r.source] ~= false
    if keep and kind ~= "all" then keep = r.kind == kind end
    if keep and r.world and not O.db.zoneWorldDrops then keep = false end
    if keep then out[#out + 1] = r end
  end
  return out
end

---Where an item row comes from, in a few words.
function Zones.ItemSource(r)
  if r.source == "reward" then
    local name = Core.DB:Name("quests", r.quest) or ("Quest " .. r.quest)
    return string.format("%s · [%d] %s", r.choice and "Reward (a choice)" or "Reward", r.questLevel or 0, name)
  elseif r.source == "drop" then
    local chance = r.chance and r.chance > 0 and string.format(" (%s%%)", r.chance >= 1 and string.format("%.0f", r.chance) or string.format("%.1f", r.chance)) or ""
    return (r.world and "World drop · " or "Drop · ") .. npcName(r.npc) .. chance
  end
  return "Sold by " .. npcName(r.npc) .. (r.limited and " · limited supply" or "")
end

-------------------------------------------------------------------------------------------
-- The map column: the zone's map art and its pins
-------------------------------------------------------------------------------------------

local function pinFrame(i)
  local p = pins[i]
  if p then return p end
  p = CreateFrame("Button", nil, panel.art)
  p:SetSize(18, 18)
  p.icon = p:CreateTexture(nil, "ARTWORK")
  p.icon:SetAllPoints()
  p.ring = p:CreateTexture(nil, "OVERLAY")
  p.ring:SetTexture(UI.TEX.ring)
  p.ring:SetAllPoints()
  p:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:AddLine(self.pin.title, 1, 1, 1)
    local hint = self.pin.key and "Click: open in Oracle" or "Click: show on your map (Clairvoyance)"
    GameTooltip:AddLine(hint, C.muted[1], C.muted[2], C.muted[3])
    GameTooltip:Show()
  end)
  p:SetScript("OnLeave", function() GameTooltip:Hide() end)
  p:SetScript("OnClick", function(self)
    if self.pin.key then return O.Window:Select(self.pin.key) end
    if self.pin.npc then O.Sheet.Track("npc", self.pin.npc) end
  end)
  pins[i] = p
  return p
end

local function kindOf(name)
  for _, k in ipairs(KINDS) do if k[1] == name then return k end end
end

---Draws a zone's map art in the panel (fitted, centred) and returns where it went.
function Zones:DrawArt(uiMap)
  for _, t in ipairs(tiles) do t:Hide() end
  for _, t in ipairs(overlays) do t:Hide() end
  self.drawn = nil
  local layers = C_Map and C_Map.GetMapArtLayers and C_Map.GetMapArtLayers(uiMap)
  local layer = layers and layers[1]
  local textures = layer and C_Map.GetMapArtLayerTextures(uiMap, 1)
  if not (layer and textures and textures[1]) then
    panel.none:Show()
    return nil
  end
  panel.none:Hide()
  local w, h = panel:GetWidth() or 0, panel:GetHeight() or 0
  local scale = math.min((w - 16) / layer.layerWidth, (h - 16) / layer.layerHeight)
  if scale <= 0 then return nil end   -- not laid out yet: drawn again when the panel gets its size
  local x0, y0 = (w - layer.layerWidth * scale) / 2, (h - layer.layerHeight * scale) / 2
  local cols = math.ceil(layer.layerWidth / layer.tileWidth)
  for i, file in ipairs(textures) do
    local t = tiles[i]
    if not t then
      t = panel.art:CreateTexture(nil, "ARTWORK")
      tiles[i] = t
    end
    local c, r = (i - 1) % cols, math.floor((i - 1) / cols)
    t:SetTexture(file)
    t:ClearAllPoints()
    t:SetPoint("TOPLEFT", panel.art, "TOPLEFT", x0 + c * layer.tileWidth * scale, -(y0 + r * layer.tileHeight * scale))
    t:SetSize(layer.tileWidth * scale, layer.tileHeight * scale)
    t:Show()
  end
  self.drawn = { left = x0, top = y0, width = layer.layerWidth * scale, height = layer.layerHeight * scale, tiles = #textures }
  self.drawn.overlays = self:DrawOverlays(uiMap, x0, y0, scale)
  return self.drawn
end

-- the smallest power of two that holds n pixels (an overlay piece's texture file size)
local function fileSize(n)
  local s = 16
  while s < n do s = s * 2 end
  return s
end

---Draws every one of the zone's world map overlays (the detail the game shows once explored) over
---its base art, the way the world map lays them out; returns how many pieces it drew.
function Zones:DrawOverlays(uiMap, x0, y0, scale)
  for _, t in ipairs(overlays) do t:Hide() end
  local list = O.Reveal and O.Reveal[uiMap]
  local n = 0
  for _, o in ipairs(list or {}) do
    local width, height, ox, oy, files = o[1], o[2], o[3], o[4], o[5]
    local cols = math.ceil(width / OVERLAY_TILE)
    local rows = math.ceil(height / OVERLAY_TILE)
    for r = 1, rows do
      local h = r < rows and OVERLAY_TILE or (height - OVERLAY_TILE * (rows - 1))
      for c = 1, cols do
        local file = files[(r - 1) * cols + c]
        if file then
          local w = c < cols and OVERLAY_TILE or (width - OVERLAY_TILE * (cols - 1))
          n = n + 1
          local t = overlays[n]
          if not t then
            t = panel.art:CreateTexture(nil, "ARTWORK", nil, 1)
            overlays[n] = t
          end
          t:SetTexture(file)
          -- a last piece is narrower than its file: show only the part it covers
          t:SetTexCoord(0, w / fileSize(w), 0, h / fileSize(h))
          t:ClearAllPoints()
          t:SetPoint("TOPLEFT", panel.art, "TOPLEFT", x0 + (ox + (c - 1) * OVERLAY_TILE) * scale,
            -(y0 + (oy + (r - 1) * OVERLAY_TILE) * scale))
          t:SetSize(w * scale, h * scale)
          t:Show()
        end
      end
    end
  end
  return n
end

---Places the pins of the kinds shown (the legend's switches, OracleDB.zonePins).
function Zones:DrawPins(facts)
  for _, p in ipairs(pins) do p:Hide() end
  local d = self.drawn
  if not d then return 0 end
  local shown = O.db.zonePins or {}
  local n = 0
  for _, pin in ipairs(facts.pins) do
    if shown[pin.kind] ~= false then
      n = n + 1
      local p = pinFrame(n)
      p.pin = pin
      local k = kindOf(pin.kind)
      if k[3] then
        Core.Map.SetIcon(p.icon, k[3])
        p.icon:Show()
      else
        p.icon:Hide()
      end
      local c = k[4]
      p.ring:SetShown(c ~= nil and k[3] == nil)
      if c and k[3] then p.icon:SetVertexColor(c[1], c[2], c[3], 1) elseif k[3] then p.icon:SetVertexColor(1, 1, 1, 1) end
      if c then p.ring:SetVertexColor(c[1], c[2], c[3], 1) end
      p:ClearAllPoints()
      p:SetPoint("CENTER", panel.art, "TOPLEFT", d.left + pin.x / 100 * d.width, -(d.top + pin.y / 100 * d.height))
      p:SetFrameLevel(panel.art:GetFrameLevel() + (pin.kind == "entrance" and 6 or 4))
      p:Show()
    end
  end
  self.stats = { pins = n }
  return n
end

local function buildColumn(parent)
  col = CreateFrame("Frame", nil, parent)
  col.title = UI.Text(col, "title", 26, C.gold)
  col.title:SetPoint("TOPLEFT", 4, -2)
  col.facts = UI.Text(col, "body", 13, C.muted)
  col.facts:SetPoint("BOTTOMLEFT", col.title, "BOTTOMRIGHT", 12, 3)

  panel = CreateFrame("Frame", nil, col)
  panel:SetPoint("TOPLEFT", 0, -42)
  panel:SetPoint("BOTTOMRIGHT", 0, 30)
  panel:SetClipsChildren(true)
  panel.bg = UI.Tex(panel, "BACKGROUND", 0, { .051, .043, .071 })
  panel.bg:SetAllPoints()
  panel.outline = UI.Round(panel, "OVERLAY", 0, 4, "line")
  panel.outline:SetColor(C.line, 1)
  panel.art = CreateFrame("Frame", nil, panel)
  panel.art:SetAllPoints()
  panel.none = UI.Text(panel, "body", 13, C.faint)
  panel.none:SetPoint("CENTER")
  panel.none:SetText("The game has no map for this zone.")
  panel.none:Hide()
  panel:SetScript("OnSizeChanged", function() if col:IsShown() and O.db.zone then Zones:Draw() end end)

  -- the legend: a switch per kind of pin
  legend = CreateFrame("Frame", nil, col)
  legend:SetHeight(22)
  legend:SetPoint("BOTTOMLEFT", 0, 0)
  legend:SetPoint("BOTTOMRIGHT", 0, 0)
  legend.chips = {}
  local previous
  for _, k in ipairs(KINDS) do
    local chip = UI.Chip(legend, k[2], k[4] or { 1, 1, 1 })
    chip.label:SetFontObject(UI.Font("body", 12))
    chip:SetHeight(20)
    chip:SetWidth(math.floor(chip.label:GetStringWidth() + 34))
    chip:ApplyAccent(accent())
    if previous then chip:SetPoint("LEFT", previous, "RIGHT", 6, 0) else chip:SetPoint("LEFT", 0, 0) end
    chip.key = k[1]
    chip:SetScript("OnClick", function(self)
      O.db.zonePins = O.db.zonePins or {}
      O.db.zonePins[self.key] = (O.db.zonePins[self.key] == false) and true or false
      Zones:Draw()
    end)
    legend.chips[#legend.chips + 1] = chip
    previous = chip
  end
  return col
end

-------------------------------------------------------------------------------------------
-- The detail column
-------------------------------------------------------------------------------------------

local function showDetail(e, facts)
  sheet:Begin()
  sheet:Text(e.name, 22, C.gold, "title")
  local parts = { e.continent }
  if e.levels then parts[#parts + 1] = "Level " .. O.Model.LevelText(e) end
  parts[#parts + 1] = string.format("%d quests", #facts.quests)
  sheet:Text(table.concat(parts, "  ·  "), 13, C.muted)

  if #facts.dungeons > 0 then
    sheet:Heading("Dungeons and raids")
    for _, d in ipairs(facts.dungeons) do
      local where = d.entrance and d.entrance.x and string.format("entrance %.1f, %.1f", d.entrance.x, d.entrance.y) or "entrance"
      sheet:Line(d.name, string.format("Level %s  ·  %s", O.Model.LevelText(d), where), nil, false,
        function() O.Window:Select(d.key) end, O.Model.LevelColor(d))
    end
  end

  if #facts.services > 0 then
    sheet:Heading("Services")
    for _, s in ipairs(facts.services) do
      local first = s.ids[1]
      local name = first > 0 and npcName(first) or (Core.DB:Name("objects", -first) or s.label)
      local more = #s.ids > 1 and string.format(" (+%d more)", #s.ids - 1) or ""
      local track = first > 0 and { kind = "npc", id = first } or { kind = "object", id = -first }
      sheet:Line(s.label, name .. more, track)
    end
  end

  if #facts.trainers > 0 then
    sheet:Heading("Trainers")
    for i, id in ipairs(facts.trainers) do
      if i > 12 then sheet:Text(string.format("+%d more trainers", #facts.trainers - 12), 12, C.faint) break end
      local rec = DB:Get("npcs", id)
      sheet:Line(npcName(id), rec and rec.subName or "Trainer", { kind = "npc", id = id })
    end
  end

  if #facts.rares > 0 then
    sheet:Heading("Rares")
    for _, r in ipairs(facts.rares) do
      local c = Core.UI.Difficulty(r.level or 1, Core.Player.level or 1)
      sheet:Line(npcName(r.npc), r.level and ("Level " .. r.level) or "Rare", { kind = "npc", id = r.npc }, false, nil, c)
    end
  end

  if #facts.gathering > 0 then
    sheet:Heading("Gathering")
    for _, g in ipairs(facts.gathering) do
      local what = g.kind == "herbs" and "Herbalism" or "Mining"
      sheet:Line(Core.DB:Name("objects", g.object) or "Node", string.format("%s %d  ·  %d spots", what, g.skill or 0, g.count),
        { kind = "object", id = g.object })
    end
  end

  if #facts.recipes > 0 then
    sheet:Heading("Recipes that drop here")
    for i, r in ipairs(facts.recipes) do
      if i > 12 then sheet:Text(string.format("+%d more", #facts.recipes - 12), 12, C.faint) break end
      local rec = Core.DB:Recipe(r.spell)
      local meta = string.format("%s %d  ·  from %s", O.Crafts.ProfessionName(rec.skill), rec.learn or 0, npcName(r.from))
      sheet:Item(r.item, meta, nil, function() O.Crafts:SelectRecipe(r.spell) end)
    end
  end

  if #facts.quests > 0 then
    sheet:Heading("Quests")
    for i, q in ipairs(facts.quests) do
      if i > 40 then sheet:Text(string.format("+%d more quests", #facts.quests - 40), 12, C.faint) break end
      local c = Core.UI.Difficulty(q.level, Core.Player.level or 1)
      local inInstance = O.Links and O.Links.Find("quest", q.id)
      sheet:Line(string.format("[%d] %s", q.level, q.name or ("Quest " .. q.id)), inInstance and "For a dungeon: click to open it" or nil,
        nil, false, inInstance and function() O.Links.Open("quest", q.id) end or nil, c)
    end
  end
  sheet:End()
end

-------------------------------------------------------------------------------------------
-- Selection
-------------------------------------------------------------------------------------------

---Draws the zone shown: the header, the map and its pins, the detail.
function Zones:Draw()
  local e = O.db.zone and self:Entry(O.db.zone)
  if not (e and col) then return end
  local facts = self.facts and self.factsFor == e.zone and self.facts or Zones.Facts(e.zone)
  self.facts, self.factsFor = facts, e.zone
  col.title:SetText(e.name)
  local parts = { e.continent }
  if e.levels then parts[#parts + 1] = "Level " .. O.Model.LevelText(e) end
  if #facts.dungeons > 0 then parts[#parts + 1] = #facts.dungeons == 1 and "1 dungeon" or (#facts.dungeons .. " dungeons") end
  col.facts:SetText(table.concat(parts, "  ·  "))
  local shown = O.db.zonePins or {}
  for _, chip in ipairs(legend.chips) do chip:SetOn(shown[chip.key] ~= false, true) end
  self:DrawArt(e.uiMap)
  self:DrawPins(facts)
  return facts
end

---Shows a zone (an area id).
function Zones:Select(area)
  local e = area and self:Entry(area)
  if not e then
    local list = self:Entries()
    for _, item in ipairs(list) do if not item.group then e = item break end end
  end
  if not e then return end
  O.db.zone = e.zone
  O.Window:SetMode("zones")
  if O.Sidebar then O.Sidebar:SetSelected(e.key) end
  local facts = self:Draw()
  showDetail(e, facts)
  self:FillItems()
end

function Zones:SetQuery(text) query = text or "" end

local function buildItems(parent)
  itemPane = CreateFrame("Frame", nil, parent)
  itemPane:SetAllPoints()
  local box = UI.Pane(itemPane)
  box:SetAllPoints()
  -- the filters: the sources (each on or off), then Gear / Recipes / Everything
  local function chipRow(y)
    local row = CreateFrame("Frame", nil, box)
    row:SetHeight(20)
    row:SetPoint("TOPLEFT", 10, y)
    row:SetPoint("TOPRIGHT", -10, y)
    return row
  end
  local function chips(row, list, onClick)
    local out, previous = {}, nil
    for _, it in ipairs(list) do
      local chip = UI.Chip(row, it[2], nil)
      chip.label:SetFontObject(UI.Font("body", 12))
      chip:SetHeight(18)
      chip:SetWidth(math.floor(chip.label:GetStringWidth() + 18))
      chip:ApplyAccent(accent())
      if previous then chip:SetPoint("LEFT", previous, "RIGHT", 6, 0) else chip:SetPoint("LEFT", 0, 0) end
      chip.key = it[1]
      chip:SetScript("OnClick", function(self) onClick(self.key) end)
      out[#out + 1] = chip
      previous = chip
    end
    return out
  end
  local r1, r2 = chipRow(-10), chipRow(-34)
  sourceChips = chips(r1, SOURCES, function(key)
    O.db.zoneSources = O.db.zoneSources or {}
    O.db.zoneSources[key] = (O.db.zoneSources[key] == false) and true or false
    Zones:FillItems()
  end)
  kindChips = chips(r2, ITEM_KINDS, function(key)
    O.db.zoneKind = key
    Zones:FillItems()
  end)
  local world = UI.Chip(r2, "World drops", nil)
  world.label:SetFontObject(UI.Font("body", 12))
  world:SetHeight(18)
  world:SetWidth(math.floor(world.label:GetStringWidth() + 18))
  world:ApplyAccent(accent())
  world:SetPoint("RIGHT", 0, 0)
  world:SetScript("OnClick", function()
    O.db.zoneWorldDrops = not O.db.zoneWorldDrops or nil
    Zones:FillItems()
  end)
  world:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:AddLine("World drops", 1, 1, 1)
    GameTooltip:AddLine("Items most creatures of their level can drop. Off: only what this zone's creatures drop.",
      C.muted[1], C.muted[2], C.muted[3], true)
    GameTooltip:Show()
  end)
  world:SetScript("OnLeave", function() GameTooltip:Hide() end)
  Zones.worldChip = world

  itemList = UI.List(box, {
    rowHeight = 42,
    createRow = function(row, content)
      O.Items.Build(content)
      row.box = content
    end,
    updateRow = function(row, r)
      local info = O.Items.Fill(row.box, r.item)
      local kind = info.kind ~= "" and (info.kind .. "  ·  ") or ""
      row.box.itemMeta:SetText(kind .. Zones.ItemSource(r))
    end,
    onEnter = function(row, r)
      GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
      GameTooltip:SetItemByID(r.item)
      GameTooltip:AddLine(Zones.ItemSource(r), C.muted[1], C.muted[2], C.muted[3], true)
      local hint = r.source == "reward" and "Click: show the quest giver on your map" or "Click: show it on your map"
      GameTooltip:AddLine(hint, C.faint[1], C.faint[2], C.faint[3])
      GameTooltip:Show()
    end,
    onLeave = function() GameTooltip:Hide() end,
    onClick = function(r)
      local link = O.Items.Info(r.item).link
      if IsShiftKeyDown() and link and ChatEdit_InsertLink then return ChatEdit_InsertLink(link) end
      if IsControlKeyDown() and link and DressUpItemLink then return DressUpItemLink(link) end
      Zones.ShowSource(r)
    end,
  })
  itemList:SetPoint("TOPLEFT", 1, -60)
  itemList:SetPoint("BOTTOMRIGHT", -1, 4)
  itemList:ApplyAccent(accent())
  Zones.itemList = itemList
  itemEmpty = UI.Text(box, "body", 13, C.faint)
  itemEmpty:SetPoint("TOPLEFT", 14, -70)
  itemEmpty:SetPoint("TOPRIGHT", -14, -70)
  itemEmpty:SetWordWrap(true)
  itemEmpty:Hide()
  return itemPane
end

---Shows where an item row comes from on your map: the creature or vendor, or the quest's giver.
function Zones.ShowSource(r)
  if r.npc then return O.Sheet.Track("npc", r.npc) end
  local q = r.quest and DB:Get("quests", r.quest)
  local giver = q and q.starters and ((q.starters.npcs or {})[1])
  if giver then return O.Sheet.Track("npc", giver) end
  local object = q and q.starters and ((q.starters.objects or {})[1])
  if object then return O.Sheet.Track("object", object) end
  return false
end

---Fills the Items tab for the zone shown.
function Zones:FillItems()
  if not itemList then return end
  local area = O.db.zone
  if not area then return end
  if self.itemsFor ~= area then
    self.items, self.itemsFor = Zones.Items(area), area
  end
  local sources = O.db.zoneSources or {}
  for _, chip in ipairs(sourceChips) do chip:SetOn(sources[chip.key] ~= false, true) end
  local kind = O.db.zoneKind or "gear"
  for _, chip in ipairs(kindChips) do chip:SetOn(chip.key == kind, true) end
  self.worldChip:SetOn(O.db.zoneWorldDrops == true, true)
  local rows = Zones.FilterItems(self.items)
  itemList:SetData(rows)
  tabs:SetCount("items", #rows)
  itemEmpty:SetShown(#rows == 0)
  if #rows == 0 then itemEmpty:SetText("Nothing here for these filters.") end
end

local function showTab(key)
  O.db.zoneTab = key
  itemPane:SetShown(key == "items")
  sheet.box:SetShown(key == "about")
end

function Zones:Build(win)
  local c = buildColumn(win.body)
  c:SetAllPoints(win.mapcol)
  local d = CreateFrame("Frame", nil, win.body)
  d:SetAllPoints(win.detail)
  tabs = UI.Tabs(d, { { key = "items", label = "Items" }, { key = "about", label = "About" } }, showTab)
  tabs:SetPoint("TOPLEFT")
  tabs:SetPoint("TOPRIGHT")
  tabs:ApplyAccent(accent())
  local area = CreateFrame("Frame", nil, d)
  area:SetPoint("TOPLEFT", tabs, "BOTTOMLEFT", 0, -6)
  area:SetPoint("BOTTOMRIGHT", 0, 0)
  buildItems(area)
  local about = CreateFrame("Frame", nil, area)
  about:SetAllPoints()
  sheet = O.Sheet.New(about)
  Zones.tabs, Zones.itemPane = tabs, itemPane
  tabs:Select(O.db.zoneTab or "items", true)
  showTab(O.db.zoneTab or "items")
  c:Hide()
  d:Hide()
  Zones.col, Zones.detail, Zones.sheet, Zones.panel = c, d, sheet, panel
end

function Zones:SetShown(on)
  if col then
    col:SetShown(on)
    Zones.detail:SetShown(on)
  end
end
