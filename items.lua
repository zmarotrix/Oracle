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
-- the 1.15+ clients (WoW Forever, interface 16001) have only C_Item.GetItemInfo; the global is gone
local GetItemInfo = C_Item and C_Item.GetItemInfo or GetItemInfo

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

---Which loot filter an item falls under: "gear" (weapons, armour), "quest", or "other" (recipes too).
function Items.Kind(id)
  local cls = (DB:Get("items", id) or {}).class
  if cls == 2 or cls == 4 then return "gear" end   -- recipes are "other" (they sort apart from the gear)
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

-------------------------------------------------------------------------------------------
-- For you: can your class use it, and at what level (the "for me" lens, docs/oracle-redesign.md 3.3)
-------------------------------------------------------------------------------------------

-- armour (class 4) and weapon (class 2) subclasses each class can use; plate and mail come at 40
local ARMOR = {
  WARRIOR = { 1, 2, 3, 6, late = { [4] = 40 } }, PALADIN = { 1, 2, 3, 6, late = { [4] = 40 } },
  HUNTER = { 1, 2, late = { [3] = 40 } }, SHAMAN = { 1, 2, 6, late = { [3] = 40 } },
  ROGUE = { 1, 2 }, DRUID = { 1, 2 }, PRIEST = { 1 }, MAGE = { 1 }, WARLOCK = { 1 },
}
local WEAPON = {
  WARRIOR = { 0, 1, 2, 3, 4, 5, 6, 7, 8, 10, 13, 15, 16, 18 },
  PALADIN = { 0, 1, 4, 5, 6, 7, 8 },
  HUNTER = { 0, 1, 2, 3, 6, 7, 8, 10, 13, 15, 16, 18 },
  ROGUE = { 2, 3, 4, 7, 13, 15, 16, 18 },
  PRIEST = { 4, 10, 15, 19 }, MAGE = { 7, 10, 15, 19 }, WARLOCK = { 7, 10, 15, 19 },
  SHAMAN = { 0, 1, 4, 5, 10, 13, 15 }, DRUID = { 4, 5, 10, 13, 15 },
}
local WEAPON_NAMES = { [2] = "bows", [3] = "guns", [6] = "polearms", [10] = "staves", [13] = "fist weapons",
  [15] = "daggers", [16] = "thrown weapons", [18] = "crossbows", [19] = "wands", [0] = "axes", [1] = "two-handed axes",
  [4] = "maces", [5] = "two-handed maces", [7] = "swords", [8] = "two-handed swords" }
local ARMOR_NAMES = { [1] = "cloth", [2] = "leather", [3] = "mail", [4] = "plate", [6] = "shields" }

local function has(list, v) for _, x in ipairs(list) do if x == v then return true end end return false end

---Whether you can use a weapon or piece of armour: { ok, later = level, why } or nil for other items.
function Items.ForYou(id, class, level)
  local record = DB:Get("items", id)
  if not record or (record.class ~= 2 and record.class ~= 4) then return nil end
  class = class or Core.Player.class or select(2, UnitClass("player"))
  level = level or Core.Player.level or UnitLevel("player") or 1
  local sub = record.subClass
  if record.class == 4 and sub and sub >= 1 and sub <= 6 and ARMOR[class] then
    local a = ARMOR[class]
    local at = a.late and a.late[sub]
    if not has(a, sub) and not at then return { ok = false, why = (ARMOR_NAMES[sub] or "this armour") .. " isn't for your class" } end
    if at and level < at then return { ok = true, later = math.max(at, record.requiredLevel or 0) } end
  elseif record.class == 2 and sub and WEAPON_NAMES[sub] and WEAPON[class] and not has(WEAPON[class], sub) then
    return { ok = false, why = "your class can't use " .. WEAPON_NAMES[sub] }
  end
  if record.requiredLevel and record.requiredLevel > level then return { ok = true, later = record.requiredLevel } end
  return { ok = true }
end
