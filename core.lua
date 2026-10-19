-- Oracle: every dungeon and raid in WoW Forever, built on NorgannonDB and NorgannonDB_Core.
-- Plan: docs/oracle-v1.md in the suite workspace; the look: design/suite/oracle.html.

local ADDON = ...
local Core = NorgannonCore
local DB = NorgannonDB

Oracle = { addonName = ADDON or "Oracle" }
local O = Oracle

if not (Core and Core:Require(1, 12)) or not (DB and DB:RequireSchema(1, 3)) then
  O.disabled = true
  C_Timer.After(5, function()
    print("|cffb48cffOracle|r needs NorgannonDB 1.3 and NorgannonDB Core 1.12 or newer; it is turned off.")
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
function O.CurrentInstance()
  if not GetInstanceInfo then return nil end
  local _, itype, _, _, _, _, _, instanceId = GetInstanceInfo()
  if Core.IsSecret(itype) or not itype or itype == "none" or Core.IsSecret(instanceId) then return nil end
  local area = DB.maps and DB.maps.instanceToArea and DB.maps.instanceToArea[instanceId]
  local keys = area and Core.DB:InstancesAt(area) or {}
  return keys[1]
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
