-- The Info tab (mockup renderInfo): the facts (location, level range, group size, bosses,
-- quests, keys and attunement, lockout), "Getting there" (show the entrance on the map, plan a
-- run with Foresight) and "About this data". Unknown facts are said plainly, in the gap colour.

local Core = NorgannonCore
local O = Oracle
if O.disabled then return end
local UI = Core.UI
local C = UI.C

local Info = {}
O.Info = Info

local GAP_COLOR = UI.Hex("d9a066")   -- a fact NorgannonDB doesn't have yet
local LABEL_W = 120
local ROW_GAP = 7

local function itemName(id)
  local name = Core.DB:Name("items", id) or ("Item " .. id)
  local quality = C_Item and C_Item.GetItemQualityByID and select(2, pcall(C_Item.GetItemQualityByID, id))
  local color = type(quality) == "number" and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality]
  if color and color.hex then return color.hex .. name .. "|r" end
  return name
end

-- your own lockout for this instance, from the game's saved instances
local function savedReset(e)
  if not (GetNumSavedInstances and GetSavedInstanceInfo) then return nil end
  local base = e.inst.groupName or e.name
  for i = 1, GetNumSavedInstances() or 0 do
    local name, _, reset, _, locked = GetSavedInstanceInfo(i)
    if not Core.IsSecret(name) and locked and type(reset) == "number" and reset > 0
      and (name == e.name or name == base) then
      return reset
    end
  end
end

local function duration(seconds)
  local d, h = math.floor(seconds / 86400), math.floor(seconds % 86400 / 3600)
  if d > 0 then return string.format("%d day%s %d hour%s", d, d == 1 and "" or "s", h, h == 1 and "" or "s") end
  local m = math.floor(seconds % 3600 / 60)
  return string.format("%d hour%s %d min", h, h == 1 and "" or "s", m)
end

---The facts as { label, text, gap }: gap = true when it's a fact NorgannonDB doesn't have yet.
function Info.Facts(e)
  local inst, facts = e.inst, {}
  local function add(label, text, gap) facts[#facts + 1] = { label, text, gap } end
  if e.zone and e.entrance then
    add("Location", string.format("%s (%s, %s)", e.zone, e.entrance.x, e.entrance.y))
  else
    add("Location", "Not known yet", true)
  end
  if inst.levels then
    local lc = O.Model.LevelColor(e)
    add("Level range", UI.Code(lc) .. O.Model.LevelText(e) .. "|r" .. UI.Code(C.faint) .. "  (recommended)|r")
  else
    add("Level range", "Not known yet", true)
  end
  if inst.bossLevels then
    local b = inst.bossLevels
    add("Boss levels", b.min == b.max and tostring(b.min) or (b.min .. "–" .. b.max))
  end
  add("Group size", e.size and (e.size .. " players") or "Not known yet", not e.size)
  add("Bosses", tostring(e.bosses))
  add("Quests", tostring(e.quests))
  local keys = {}
  for _, id in ipairs(inst.keys or {}) do keys[#keys + 1] = itemName(id) end
  if #keys > 0 then add("Keys", table.concat(keys, ", ")) end
  if inst.attunement then add("Attunement", inst.attunement) end
  if #keys == 0 and not inst.attunement then
    add("Keys, attunement", e.forever and "Not known yet" or "None needed", e.forever)
  end
  local reset = savedReset(e)
  if reset then
    add("Lockout", "You're saved: resets in " .. duration(reset))
  elseif e.raid then
    add("Lockout", "Not in NorgannonDB yet", true)
  else
    add("Lockout", "None")
  end
  if inst.note then add("Note", inst.note) end
  return facts
end

-------------------------------------------------------------------------------------------
-- The pane
-------------------------------------------------------------------------------------------

local pane, rows, heading1, heading2, about, showButton, planButton

local function button(parent, text, markKey, onClick)
  local b = UI.Button(parent, text, markKey == "clairvoyance" and "accent" or "quiet", onClick)
  if markKey == "clairvoyance" then b:ApplyAccent(UI.Accent("clairvoyance")) end
  b.mark = UI.Mark(b, markKey, 15)
  b.mark:SetPoint("LEFT", 9, 0)
  b.label:ClearAllPoints()
  b.label:SetPoint("LEFT", b.mark, "RIGHT", 5, 0)
  b:SetHeight(24)
  b:SetWidth(math.floor(b.label:GetStringWidth() + 9 + 15 + 5 + 12))
  return b
end

local function heading(parent, text)
  local h = UI.Text(parent, "title", 14, C.goldSoft)
  h:SetText(text)
  return h
end

---Shows the instance's entrance on the world map (and the minimap and compass).
function Info.ShowEntrance(e)
  local en = e and e.entrance
  if not en then return false end
  local pin = { area = en.area, x = en.x, y = en.y, icon = "diamond", color = UI.Accent("oracle"), size = 16,
    layer = 6, title = e.name, compass = "oracle.entrance", highlight = "oracle.entrance",
    tooltip = function(_, tt) tt:AddLine(e.name, 1, 1, 1) tt:AddLine("Entrance", C.muted[1], C.muted[2], C.muted[3]) end }
  Core.Map:SetPins("oracle.entrance", { pin })
  local uiMap = Core.Map.AreaToUiMap(en.area)
  if uiMap then
    if OpenWorldMap then OpenWorldMap(uiMap) elseif WorldMapFrame then WorldMapFrame:Show() WorldMapFrame:SetMapID(uiMap) end
  end
  Core.Map:Pulse("oracle.entrance")
  return true
end

local function build(frame)
  pane = frame
  rows = {}
  heading1 = heading(pane, "Getting there")
  heading2 = heading(pane, "About this data")
  showButton = button(pane, "Show entrance on map", "clairvoyance", function()
    Info.ShowEntrance(O.Model:Get(O.db.selected))
  end)
  planButton = button(pane, "Plan a run", "foresight", function() end)
  planButton:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:AddLine("Plan a run", 1, 1, 1)
    GameTooltip:AddLine("Foresight, the suite's planner, will plan runs here.", C.muted[1], C.muted[2], C.muted[3])
    GameTooltip:Show()
  end)
  planButton:SetScript("OnLeave", function() GameTooltip:Hide() end)
  about = UI.Text(pane, "body", 13, C.faint)
  about:SetWordWrap(true)
  about:SetJustifyH("LEFT")
  Info.pane = pane
end

local function row(i)
  local r = rows[i]
  if r then return r end
  r = { label = UI.Text(pane, "body", 14, C.muted), text = UI.Text(pane, "body", 14, C.text) }
  r.text:SetWordWrap(true)
  r.text:SetJustifyH("LEFT")
  rows[i] = r
  return r
end

local function fill(_, e)
  local facts = Info.Facts(e)
  local y = -8
  local width = (pane:GetWidth() or 392) - 20 - LABEL_W - 10
  for i, f in ipairs(facts) do
    local r = row(i)
    r.label:SetText(f[1])
    r.label:ClearAllPoints()
    r.label:SetPoint("TOPLEFT", 10, y)
    r.text:SetText(f[2])
    local c = f[3] and GAP_COLOR or C.text
    r.text:SetTextColor(c[1], c[2], c[3])
    r.text:ClearAllPoints()
    r.text:SetPoint("TOPLEFT", 10 + LABEL_W + 10, y)
    r.text:SetWidth(width)
    r.label:Show()
    r.text:Show()
    y = y - math.max(16, r.text:GetStringHeight() or 16) - ROW_GAP
  end
  for i = #facts + 1, #rows do rows[i].label:Hide() rows[i].text:Hide() end

  y = y - 10
  heading1:ClearAllPoints()
  heading1:SetPoint("TOPLEFT", 10, y)
  y = y - 24
  showButton:ClearAllPoints()
  showButton:SetPoint("TOPLEFT", 10, y)
  showButton:SetEnabled(e.entrance ~= nil)
  showButton:SetAlpha(e.entrance and 1 or .45)
  planButton:ClearAllPoints()
  planButton:SetPoint("LEFT", showButton, "RIGHT", 6, 0)
  planButton:SetAlpha(Core:AddonState("foresight") == "loaded" and 1 or .45)
  y = y - 24 - 16
  heading2:ClearAllPoints()
  heading2:SetPoint("TOPLEFT", 10, y)
  y = y - 22
  about:ClearAllPoints()
  about:SetPoint("TOPLEFT", 10, y)
  about:SetWidth((pane:GetWidth() or 392) - 20)
  if e.forever then
    about:SetText("WoW Forever added this instance, so no classic guide has it. NorgannonDB learns its bosses, loot "
      .. "and lockout from players running the NorgannonDB Collector.")
  else
    local map = O.RealMap and O.RealMap.For(e.key)
      and "The map is the game's own minimap; boss positions are spawn points from the cmangos classic-db (GPL). "
      or "The map is a hand-drawn schematic. "
    about:SetText("Bosses, loot and quests come from NorgannonDB, the open database. " .. map
      .. "Something wrong in game? The NorgannonDB Collector notices and reports it.")
  end
  if e.inst.credits then
    about:SetText(about:GetText() .. " WoW Forever's dungeon data from DungeonJournal by Exehn, with thanks.")
  end
end

O.Window:RegisterPane("info", build, fill)
