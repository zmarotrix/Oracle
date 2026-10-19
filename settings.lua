-- Oracle's settings page, under NorgannonDB in the game's Settings window (/oracle settings).

local Core = NorgannonCore
local O = Oracle
if O.disabled then return end
local UI = Core.UI

local function corner()
  local win = O.Window:Get()
  local s = win:GetScale()
  return (win:GetLeft() or 0) * s, (win:GetTop() or 0) * s
end

Core:OnLogin(function()
  if not O.db then return end
  local page = CreateFrame("Frame")
  page:Hide()
  local list = UI.SettingsList(page)

  list:Header("Window")
  list:Slider("Window size", "Zooms the whole window; dragging its bottom-right corner does the same.", .6, 1.6, .05,
    function() return O.db.scale or 1 end,
    function(v)
      local win = O.Window:Get()
      if win and win:GetLeft() then O.Window:SetZoom(v, corner()) else O.db.scale = v end
    end, "%.0f%%", 100)
  list:Slider("Window opacity", nil, .4, 1, .05,
    function() return O.db.opacity or 1 end,
    function(v)
      O.db.opacity = v
      O.Window:ApplyLook()
    end, "%.0f%%", 100)
  list:Toggle("Lock the window", "Stops it from being moved or resized.",
    function() return O.db.locked end,
    function(on) O.db.locked = on O.Window:ApplyLook() end)
  list:Buttons("Position", "Puts the window back in the middle of the screen.", { { "Reset position", function()
    if Core.db and Core.db.windows then Core.db.windows.OracleWindow = nil end
    local win = O.Window:Get()
    if win then
      win:ClearAllPoints()
      win:SetPoint("CENTER")
    end
  end } })

  list:Header("Opening")
  list:Toggle("Open when I enter a dungeon or raid", "Oracle always opens on the instance you're in; this also opens it as you enter.",
    function() return O.db.openOnEnter end,
    function(on) O.db.openOnEnter = on end)

  list:Header("Tooltips")
  list:Toggle("Oracle line in tooltips", "On bosses and their loot: which instance (and boss) they belong to.",
    function() return O.db.tooltips ~= false end,
    function(on) O.db.tooltips = on end)

  list:Header("Key binding")
  list:Buttons("Open or close Oracle", "Set a key in the game's Key Bindings, under AddOns.", {})

  page:SetScript("OnShow", function() list:Refresh() end)
  O.settingsPage, O.settingsList = page, list
  O.settingsCategory = Core:AddSettingsPage(page, "Oracle")

  -- Oracle's hot paths for /norg perf (wrapped only while measuring)
  local function perf(label, tbl, method) Core:RegisterPerf("Oracle: " .. label, tbl, method, "oracle") end
  perf("schematic map", O.Schematic, "Draw")
  perf("showing an instance", O.Window, "Select")
  perf("instance list", O.Sidebar, "Refresh")
  perf("tooltip lines", O.Links, "TooltipLine")
end)

function O:OpenSettings()
  if self.settingsCategory and Settings and Settings.OpenToCategory then
    Settings.OpenToCategory(self.settingsCategory:GetID())
  else
    Core:OpenSettings()
  end
end
