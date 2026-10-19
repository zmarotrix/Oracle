-- Item rows (the suite's .az-item): the item's icon in a 30 px tile, its name in its quality
-- colour, and "kind · slot · ilvl" under it. Hover shows the game's tooltip; shift-click links
-- it in chat; ctrl-click tries it on. Items the client hasn't cached yet show NorgannonDB's name
-- and fill in when the game sends their data (ORACLE_ITEMS_LOADED).

local Core = NorgannonCore
local DB = NorgannonDB
local O = Oracle
if O.disabled then return end
local UI = Core.UI
local C = UI.C

local Items = {}
O.Items = Items

local KIND_COLOR = { [2] = UI.Hex("ff9a4d"), [4] = UI.Hex("9fd0ff"), [12] = UI.Hex("ffd100"), [9] = UI.Hex("8ef0a0") }
local OTHER = UI.Hex("d8d0bc")
local QUEST_ICON = 134400      -- the question mark, while an item's icon isn't known

---What the game knows about an item: name, quality, icon, kind line (or NorgannonDB's fallbacks).
function Items.Info(id)
  local record = DB:Get("items", id) or {}
  local name, link, quality, _, _, _, subType, _, equipLoc, icon = GetItemInfo(id)
  if not name and C_Item and C_Item.RequestLoadItemDataByID then pcall(C_Item.RequestLoadItemDataByID, id) end
  if not icon and C_Item and C_Item.GetItemIconByID then icon = C_Item.GetItemIconByID(id) end
  local cls = record.class
  local parts = {}
  if cls == 12 then
    parts[1] = "Quest item"
  elseif cls == 9 then
    parts[1] = "Recipe"
  else
    if type(subType) == "string" and subType ~= "" then parts[#parts + 1] = subType end
    local slot = type(equipLoc) == "string" and equipLoc ~= "" and _G[equipLoc]
    if type(slot) == "string" and slot ~= subType then parts[#parts + 1] = slot end
  end
  if (cls == 2 or cls == 4) and record.level then parts[#parts + 1] = "ilvl " .. record.level end
  local color = KIND_COLOR[cls] or OTHER
  if type(quality) == "number" and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality] then
    local q = ITEM_QUALITY_COLORS[quality]
    color = { q.r, q.g, q.b }
  end
  return {
    id = id, name = name or Core.DB:Name("items", id) or ("Item " .. id), link = link, quality = quality,
    icon = icon or QUEST_ICON, kind = table.concat(parts, " · "), color = color, cls = cls, loaded = name ~= nil,
  }
end

---Which loot filter an item falls under: "gear" (weapons, armour, recipes), "quest", or "other".
function Items.Kind(id)
  local cls = (DB:Get("items", id) or {}).class
  if cls == 2 or cls == 4 or cls == 9 then return "gear" end
  if cls == 12 then return "quest" end
  return "other"
end

---Builds an item row's parts on a frame (its height is the caller's).
function Items.Build(f)
  f.tile = CreateFrame("Frame", nil, f)
  f.tile:SetSize(30, 30)
  f.tile:SetPoint("LEFT", 6, 0)
  f.tile.border = UI.Tex(f.tile, "BACKGROUND", 0, C.black)
  f.tile.border:SetAllPoints()
  f.tile.icon = f.tile:CreateTexture(nil, "ARTWORK")
  f.tile.icon:SetPoint("TOPLEFT", 1, -1)
  f.tile.icon:SetPoint("BOTTOMRIGHT", -1, 1)
  f.tile.icon:SetTexCoord(.08, .92, .08, .92)
  f.tile.shine = UI.Round(f.tile, "OVERLAY", 0, 3, "line")   -- the tile's faint inner edge
  f.tile.shine:SetColor({ 1, 1, 1 }, .12)
  f.itemName = UI.Text(f, "body", 14)
  f.itemName:SetPoint("TOPLEFT", f.tile, "TOPRIGHT", 8, -1)
  -- the tile is centred on the row, so its top is 15 above the row's middle
  f.itemName:SetPoint("TOPRIGHT", f, "RIGHT", -(f.rightInset or 6), 14)
  f.itemMeta = UI.Text(f, "body", 12, C.muted)
  f.itemMeta:SetPoint("TOPLEFT", f.itemName, "BOTTOMLEFT", 0, -1)
  f.itemMeta:SetPoint("TOPRIGHT", f.itemName, "BOTTOMRIGHT", 0, -1)
end

---Fills an item row; extra is appended to the kind line (" · req 20").
function Items.Fill(f, id, extra)
  local info = Items.Info(id)
  f.itemId, f.itemLink = id, info.link
  f.tile.icon:SetTexture(info.icon)
  f.itemName:SetText(info.name)
  f.itemName:SetTextColor(info.color[1], info.color[2], info.color[3])
  f.itemMeta:SetText(info.kind .. (extra or ""))
  return info
end

---Hover, shift-click and ctrl-click for a frame showing an item (f.itemId).
function Items.Hook(f)
  f:HookScript("OnEnter", function(self)
    if self.hover then self.hover:Show() end
    if not self.itemId then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetItemByID(self.itemId)
    GameTooltip:Show()
  end)
  f:HookScript("OnLeave", function(self)
    if self.hover then self.hover:Hide() end
    GameTooltip:Hide()
  end)
  f:HookScript("OnClick", function(self)
    if not self.itemId then return end
    local link = self.itemLink or select(2, GetItemInfo(self.itemId))
    if not link then return end
    if IsShiftKeyDown() and ChatEdit_InsertLink then ChatEdit_InsertLink(link)
    elseif IsControlKeyDown() and DressUpItemLink then DressUpItemLink(link) end
  end)
end

-- the game sends item data a moment after it's asked for: redraw then (once per frame)
local pending = false
Core:On("GET_ITEM_INFO_RECEIVED", "oracle.items", function()
  if pending then return end
  pending = true
  C_Timer.After(0, function()
    pending = false
    O:Send("ITEMS_LOADED")
  end)
end)
