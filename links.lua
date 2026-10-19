-- Oracle and the rest of the suite:
--   * the action "Open in Oracle" for a quest that sends you to an instance, an instance's boss
--     and a boss's loot (Clairvoyance's quest menu and other suite menus list it), opening the
--     instance on the right tab;
--   * a quiet line in NPC and item tooltips: "Oracle: The Deadmines · Edwin VanCleef"
--     (setting: OracleDB.tooltips).

local Core = NorgannonCore
local O = Oracle
if O.disabled then return end
local UI = Core.UI

local Links = {}
O.Links = Links

local VIOLET = UI.Hex("b48cff")
local byQuest, byNpc, byItem   -- id -> { key, npc }

local function index()
  if byQuest then return end
  byQuest, byNpc, byItem = {}, {}, {}
  for _, key in ipairs(Core.DB:InstanceKeys()) do
    local inst = Core.DB:Instance(key)
    for _, q in ipairs(inst.quests or {}) do byQuest[q] = byQuest[q] or { key = key } end
    for _, b in ipairs(inst.bosses or {}) do
      if b.id then
        byNpc[b.id] = byNpc[b.id] or { key = key, npc = b.id }
        for _, item in ipairs(b.loot or {}) do byItem[item] = byItem[item] or { key = key, npc = b.id } end
      end
    end
  end
end

---Where an entity belongs in Oracle: { key = instance, npc = boss } or nil.
---kind: "quest", "npc", "item" (or the plural kinds).
function Links.Find(kind, id)
  index()
  kind = kind and kind:gsub("s$", "")
  if kind == "quest" then return byQuest[id] end
  if kind == "npc" then return byNpc[id] end
  if kind == "item" then return byItem[id] end
end

---Opens Oracle where an entity belongs: a quest on the Quests tab, a boss on Bosses, loot on Loot.
function Links.Open(kind, id)
  local hit = Links.Find(kind, id)
  if not hit then return false end
  kind = kind:gsub("s$", "")
  O.Window:Open(hit.key)
  local tabs = O.Window.frame.tabs
  if kind == "quest" then
    tabs:Select("quests")
    O.Quests:Focus(id)
  elseif kind == "npc" then
    tabs:Select("bosses")
    O.Schematic:SetHot(id)
  else
    O:Send("FOCUS", hit.npc)
  end
  return true
end

Core:RegisterAction("oracle.open", {
  addon = "oracle", label = "Open in Oracle", kinds = { "quest", "npc", "item" },
  available = function(kind, id) return Links.Find(kind, id) ~= nil end,
  run = function(kind, id) Links.Open(kind, id) end,
})

-------------------------------------------------------------------------------------------
-- Tooltips
-------------------------------------------------------------------------------------------

---The tooltip line for an entity, or nil: "Oracle: The Deadmines · Edwin VanCleef".
function Links.TooltipLine(kind, id)
  if O.db and O.db.tooltips == false then return nil end
  local hit = Links.Find(kind, id)
  if not hit then return nil end
  local text = "Oracle: " .. (Core.DB:InstanceName(hit.key) or hit.key)
  if kind:gsub("s$", "") == "item" and hit.npc then text = text .. " · " .. (Core.DB:Name("npcs", hit.npc) or "") end
  return text
end

local function add(tt, kind, id)
  local line = Links.TooltipLine(kind, id)
  if line then
    tt:AddLine(line, VIOLET[1], VIOLET[2], VIOLET[3])
    tt:Show()
  end
end

local function public(t) return type(t) == "table" and not Core.IsSecret(t) end

if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType then
  local T = Enum.TooltipDataType
  if T.Unit then
    TooltipDataProcessor.AddTooltipPostCall(T.Unit, function(tt, data)
      if not public(data) or type(data.guid) ~= "string" or Core.IsSecret(data.guid) then return end
      local kind, _, _, _, _, id = strsplit("-", data.guid)
      id = tonumber(id)
      if (kind == "Creature" or kind == "Vehicle") and id then add(tt, "npc", id) end
    end)
  end
  if T.Item then
    TooltipDataProcessor.AddTooltipPostCall(T.Item, function(tt, data)
      if not public(data) or type(data.id) ~= "number" or Core.IsSecret(data.id) then return end
      add(tt, "item", data.id)
    end)
  end
end
