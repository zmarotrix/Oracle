-- Oracle: every dungeon and raid in WoW Forever, built on NorgannonDB and NorgannonDB_Core.
-- Plan: docs/oracle-v1.md in the suite workspace; the look: design/suite/oracle.html.

local ADDON = ...
local Core = NorgannonCore
local DB = NorgannonDB

Oracle = { addonName = ADDON or "Oracle" }
local O = Oracle

if not (Core and Core:Require(1, 13)) or not (DB and DB:RequireSchema(1, 3)) then
  O.disabled = true
  C_Timer.After(5, function()
    print("|cffb48cffOracle|r needs NorgannonDB 1.3 and NorgannonDB Core 1.13 or newer; it is turned off.")
  end)
  return
end

O.PREFIX = "|cffb48cffOracle|r"
function O:Print(msg) Core:Print(msg, self.PREFIX) end

-------------------------------------------------------------------------------------------
-- Saved settings (account-wide)
-------------------------------------------------------------------------------------------

local DEFAULTS = {
  category = "dungeons",   -- the sidebar's Dungeons / Raids
  sort = "level",          -- Level / Name / Continent
  selected = nil,          -- the instance key last shown
  tab = "info",
  scale = 1,               -- on top of the fit-to-screen scale
  opacity = 1,
  locked = false,
  tooltips = true,         -- the Oracle line in NPC and item tooltips
  openOnEnter = false,     -- open the window when you enter a dungeon or raid
  -- lastWing[areaId]: the wing last shown for an instance whose wings share a map
}

local function fill(target, defaults)
  for k, v in pairs(defaults) do
    if target[k] == nil then target[k] = v end
  end
  return target
end

Core:On("ADDON_LOADED", O, function(_, name)
  if name ~= O.addonName then return end
  Core:Off("ADDON_LOADED", O)
  local saved = rawget(_G, "OracleDB")
  OracleDB = fill(type(saved) == "table" and saved or {}, DEFAULTS)
  O.db = OracleDB
end)

-- Messages inside Oracle ride on the Core's bus, prefixed ORACLE_
function O:Send(message, ...) Core:Send("ORACLE_" .. message, ...) end
function O:Listen(message, owner, fn) Core:Listen("ORACLE_" .. message, owner, fn) end

-------------------------------------------------------------------------------------------
-- Opening
-------------------------------------------------------------------------------------------

---The instance you're standing in, if NorgannonDB knows it (its first wing for wing instances).
-- Wings that share one game map (Scarlet Monastery, Dire Maul, Blackrock Spire, Stratholme):
-- the sub-zone names you see inside each one
local WING_PLACES = {
  ["sm-graveyard"] = { "Graveyard", "Chamber of Atonement", "Forlorn Cloister", "Honor's Tomb" },
  ["sm-library"] = { "Library", "Huntsman's Cloister", "Gallery of Treasures", "Athenaeum" },
  ["sm-armory"] = { "Armory", "Training Grounds", "Footman's Armory", "Crusader's Armory", "Hall of Champions" },
  ["sm-cathedral"] = { "Cathedral", "Chapel Gardens", "Crusader's Chapel" },
  ["dm-east"] = { "Warpwood Quarter", "The Hidden Reach", "The Conservatory", "The Shrine of Eldretharr" },
  ["dm-west"] = { "Capital Gardens", "Court of the Highborne", "Prison of Immol'thar", "Athenaeum" },
  ["dm-north"] = { "Gordok's Seat", "Halls of Destruction" },
  ["lbrs"] = { "Hordemar City", "Mok'Doom", "Tazz'Alaor", "Skitterweb Tunnels", "The Storehouse", "Chamber of Battle" },
  ["ubrs"] = { "Dragonspire Hall", "Hall of Binding", "The Rookery", "Hall of Blackhand", "Blackrock Stadium", "The Furnace", "Spire Throne" },
  ["strat-live"] = { "King's Square", "Market Row", "Crusaders' Square", "The Scarlet Bastion", "The Hall of Lights", "The Hoard" },
  ["strat-undead"] = { "Elders' Square", "The Gauntlet", "Slaughter Square", "The Slaughter House" },
}
O.WING_PLACES = WING_PLACES

local function zoneText(fn)
  local f = rawget(_G, fn)
  if not f then return nil end
  local ok, text = pcall(f)
  if ok and type(text) == "string" and not Core.IsSecret(text) and text ~= "" then return text end
end

---The instance you're standing in, if NorgannonDB knows it. For wings that share a map: the
---wing you last chose for it in Oracle, else the one whose sub-zone you're in, else the first.
function O.CurrentInstance()
  if not GetInstanceInfo then return nil end
  local _, itype, _, _, _, _, _, instanceId = GetInstanceInfo()
  if Core.IsSecret(itype) or not itype or itype == "none" or Core.IsSecret(instanceId) then return nil end
  local area = DB.maps and DB.maps.instanceToArea and DB.maps.instanceToArea[instanceId]
  local keys = area and Core.DB:InstancesAt(area) or {}
  if #keys <= 1 then return keys[1] end
  local sub = zoneText("GetSubZoneText") or zoneText("GetMinimapZoneText")
  if sub then
    for _, key in ipairs(keys) do
      for _, place in ipairs(WING_PLACES[key] or {}) do
        if place == sub then return key end
      end
    end
  end
  local last = O.db and O.db.lastWing and O.db.lastWing[area]
  for _, key in ipairs(keys) do if key == last then return key end end
  return keys[1]
end

-- choosing a wing in Oracle remembers it for that instance's map
Core:Listen("ORACLE_SELECTED", "oracle.wings", function(_, key)
  local inst = Core.DB:Instance(key)
  if inst and inst.group and inst.area and O.db then
    O.db.lastWing = O.db.lastWing or {}
    O.db.lastWing[inst.area] = key
  end
end)

-- entering an instance: follow it in the window, or open on it (setting: OracleDB.openOnEnter)
local lastInstance
local function entered()
  if not O.db then return end
  local key = O.CurrentInstance()
  if key == lastInstance then return end
  lastInstance = key
  if not key then return end
  local win = O.Window and O.Window.frame
  if win and win:IsShown() then
    O.Window:Select(key)
  elseif O.db.openOnEnter and not InCombatLockdown() then
    O.Window:Open(key)
  end
end
O.Entered = entered
for _, event in ipairs({ "PLAYER_ENTERING_WORLD", "ZONE_CHANGED_NEW_AREA", "ZONE_CHANGED_INDOORS", "ZONE_CHANGED" }) do
  Core:On(event, "oracle.enter", function() C_Timer.After(.5, entered) end)
end

---Opens Oracle (on an instance key, else the one you're in, else the last one shown); again closes it.
function O:Toggle(key)
  local win = self.Window and self.Window:Get()
  if not win then return end
  if win:IsShown() and not key then
    win:Hide()
    return
  end
  self.Window:Open(key or O.CurrentInstance() or self.db.selected)
end

Core:RegisterAddon("oracle", {
  version = C_AddOns and C_AddOns.GetAddOnMetadata(O.addonName, "Version") or "0.1.0",
  open = function() O:Toggle() end,
})

SLASH_ORACLE1 = "/oracle"
SlashCmdList["ORACLE"] = function(msg)
  msg = strtrim(string.lower(msg or ""))
  if msg == "" then
    O:Toggle()
  elseif msg == "settings" or msg == "options" then
    O:OpenSettings()
  else
    -- /oracle deadmines, /oracle scarlet: the first instance whose name or key matches
    for _, key in ipairs(Core.DB:InstanceKeys()) do
      local name = string.lower(Core.DB:InstanceName(key) or "")
      if key:find(msg, 1, true) or name:find(msg, 1, true) then
        O.Window:Open(key)
        return
      end
    end
    O:Print("no instance matches \"" .. msg .. "\"")
  end
end

-- the minimap button and the client's addon menu: click opens or closes, right-click the settings
local function onClick(button)
  if button == "RightButton" then O:OpenSettings() else O:Toggle() end
end
local function tooltip(tt)
  tt:AddLine("Oracle", .706, .549, 1)
  tt:AddLine("Every dungeon and raid: maps, bosses, loot, quests", 1, 1, 1)
  tt:AddLine("Click: open or close  ·  Right-click: settings  ·  Drag: move", .43, .4, .32)
end
Core:OnLogin(function() Core.MinimapButton:Add("oracle", { onClick = onClick, tooltip = tooltip }) end)
function Oracle_OnAddonCompartmentClick(_, button) onClick(button) end
function Oracle_OnAddonCompartmentEnter(_, frame)
  GameTooltip:SetOwner(frame, "ANCHOR_LEFT")
  tooltip(GameTooltip)
  GameTooltip:Show()
end
function Oracle_OnAddonCompartmentLeave() GameTooltip:Hide() end

BINDING_HEADER_ORACLE = "Oracle"
BINDING_NAME_ORACLE_TOGGLE = "Open or close Oracle"
