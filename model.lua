-- The instances as Oracle shows them: name, where the entrance is, level range, group size,
-- counts, and (built on the first search) the words a search can match: the instance, its zone,
-- its bosses and their loot.

local Core = NorgannonCore
local DB = NorgannonDB
local O = Oracle
if O.disabled then return end

local Model = {}
O.Model = Model

local entries, byKey

local function areaName(area)
  if not area then return nil end
  if C_Map and C_Map.GetAreaInfo then
    local ok, name = pcall(C_Map.GetAreaInfo, area)
    if ok and type(name) == "string" and name ~= "" then return name end
  end
  local z = DB.zones and DB.zones[area]
  return z and z.name
end
Model.AreaName = areaName

-- the continent a zone is on, from the client's map tree (Eastern Kingdoms, Kalimdor)
local CONTINENT = Enum and Enum.UIMapType and Enum.UIMapType.Continent or 2
local function continentOf(area)
  local uiMap = Core.Map.AreaToUiMap(area)
  if not (uiMap and C_Map and C_Map.GetMapInfo) then return nil end
  for _ = 1, 8 do
    local ok, info = pcall(C_Map.GetMapInfo, uiMap)
    if not ok or not info then return nil end
    if info.mapType == CONTINENT then return info.name end
    if not info.parentMapID or info.parentMapID == 0 then return nil end
    uiMap = info.parentMapID
  end
end

local function build()
  entries, byKey = {}, {}
  for _, key in ipairs(Core.DB:InstanceKeys()) do
    local inst = Core.DB:Instance(key)
    local entrance = inst.entrance
    local e = {
      key = key, inst = inst,
      name = Core.DB:InstanceName(key) or key,
      raid = inst.raid == true,
      forever = inst.forever == true,
      size = inst.size,
      levels = inst.levels, bossLevels = inst.bossLevels,
      bosses = #(inst.bosses or {}), quests = #(inst.quests or {}),
      entrance = entrance,
      zone = entrance and areaName(entrance.area) or (inst.forever and "WoW Forever" or nil),
      continent = entrance and continentOf(entrance.area) or nil,
    }
    entries[#entries + 1] = e
    byKey[key] = e
  end
end

---Every instance entry, by recommended level then name.
function Model:All()
  if not entries then build() end
  return entries
end

function Model:Get(key)
  if not byKey then build() end
  return byKey[key]
end

---"17–26", "60", or "?" when no level is known.
function Model.LevelText(e)
  local l = e.levels or e.bossLevels
  if not l then return "?" end
  if l.min == l.max then return tostring(l.min) end
  return l.min .. "–" .. l.max
end

---The level range in the game's difficulty colour for you (the middle of the range, as the mockup).
function Model.LevelColor(e)
  local l = e.levels or e.bossLevels
  if not l then return Core.UI.C.faint end
  return Core.UI.Difficulty(math.floor((l.min + l.max) / 2 + .5), Core.Player.level or UnitLevel("player") or 1)
end

-- the words a search can match, lower-cased (built once, on the first search)
local function haystack(e)
  if e.haystack then return e.haystack end
  local words = { e.name, e.zone or "" }
  for _, b in ipairs(e.inst.bosses or {}) do
    words[#words + 1] = Core.DB:Name("npcs", b.id) or ""
    for _, item in ipairs(b.loot or {}) do words[#words + 1] = Core.DB:Name("items", item) or "" end
  end
  e.haystack = string.lower(table.concat(words, "\n"))
  return e.haystack
end

---Whether an instance matches a search: its name, zone, a boss or a boss's loot.
function Model.Matches(e, text)
  text = string.lower(strtrim(text or ""))
  if text == "" then return true end
  return haystack(e):find(text, 1, true) ~= nil
end
