-- An instance's Quests view (docs/oracle-redesign.md 4.3), on questbook.lua. Two ways to read it:
--
--   Questlines (default)  every quest chain that touches the instance, followed back to where it starts and
--                         on a few steps past the run, across zones. Each step shows where you stand: done,
--                         the step you're on (highlighted), what's coming. Steps done inside the instance
--                         are marked "In the dungeon"; quests that start or end inside say so. A chain that
--                         goes in more than once (Blackrock Depths) shows every visit. A quest that starts
--                         from an item found inside (A Crumpled Up Note) is a step of its chain like any other.
--   Before you go         everything to have in your log before the run (QB.Ready): what to pick up, by where
--                         you go, each with its giver and coordinates; chains partway; in your log; not yet.
--
-- The summary on top: "5 of 9 ready · 3 to pick up in 2 places", and Track pickups (Clairvoyance puts each
-- giver on your map and a section in its tracker). Click a quest: the Inspector; right-click: Track.
-- Facts only: where each chain stands and where its next step is; never which quests to do.

local Core = NorgannonCore
local DB = NorgannonDB
local O = Oracle
if O.disabled then return end
local UI = Core.UI
local C = UI.C

local R = {}
O.ReadyCheck = R

local ROW = 40
local BACK_STEPS, FORWARD_STEPS = 30, 8   -- how far a questline is followed from the instance's quests
local ORANGE = UI.Hex("ff8a3d")
local fold = { done = true, finished = true }   -- "Not for you" starts open, greyed, at the bottom
R.fold = fold

local function QB() return O.QuestBook end
local function qname(id) return Core.DB:Name("quests", id) or ("Quest " .. id) end

local function giverWhere(g)
  if not g then return "where it starts isn't known yet" end
  if g.kind == "items" then return "starts from " .. (g.name or "an item") end
  local where = g.area and QB().AreaName(g.area) or nil
  if where and g.x then where = string.format("%s (%.1f, %.1f)", where, g.x, g.y) end
  return (g.name or "?") .. (where and (", " .. where) or "")
end

-------------------------------------------------------------------------------------------
-- Inside the instance: which steps are done there, start there, end there
-------------------------------------------------------------------------------------------

-- an instance is several areas: the one its record names (where its quests are sorted) and the ones its
-- creatures stand in (Blackrock Depths: 1584 and 1585); `areas` is a set of them
local function npcIn(id, areas)
  local r = DB:Get("npcs", id)
  if not r then return false end
  if r.zone and areas[r.zone] then return true end
  for a in pairs(r.spawns or {}) do if areas[a] then return true end end
  return false
end
local function objectIn(id, areas)
  local r = DB:Get("objects", id)
  for a in pairs(r and r.spawns or {}) do if areas[a] then return true end end
  return false
end
local function itemIn(id, area)
  local r = DB:Get("items", id)
  local drops = r and r.drops
  for npc in pairs(drops and drops.npcs or {}) do if npcIn(npc, area) then return true end end
  for obj in pairs(drops and drops.objects or {}) do if objectIn(obj, area) then return true end end
  return false
end

local areasMemo = {}

---The areas an instance covers: its own, and every area its bosses stand in.
function R.Areas(key)
  if areasMemo[key] then return areasMemo[key] end
  local inst = Core.DB:Instance(key)
  local set = {}
  if inst and inst.area then set[inst.area] = true end
  for _, b in ipairs(inst and inst.bosses or {}) do
    local r = b.id and DB:Get("npcs", b.id)
    if r and r.zone then set[r.zone] = true end
  end
  areasMemo[key] = set
  return set
end

---Where a quest touches an instance (an area id, or a set of them): { inside (its objectives are there),
---starts, ends }.
function R.Inside(id, area)
  local q = DB:Get("quests", id)
  local out = { inside = false, starts = false, ends = false }
  if not (q and area) then return out end
  if type(area) ~= "table" then area = { [area] = true } end
  local o = q.objectives or {}
  for _, x in ipairs(o.npcs or {}) do if npcIn(x.id, area) then out.inside = true end end
  for _, x in ipairs(o.objects or {}) do if not out.inside and objectIn(x.id, area) then out.inside = true end end
  for _, x in ipairs(o.items or {}) do if not out.inside and itemIn(x.id, area) then out.inside = true end end
  for a in pairs(o.explore and o.explore.spawns or {}) do if area[a] then out.inside = true end end
  local s = q.starters or {}
  for _, n in ipairs(s.npcs or {}) do if npcIn(n, area) then out.starts = true end end
  for _, x in ipairs(s.objects or {}) do if objectIn(x, area) then out.starts = true end end
  for _, x in ipairs(s.items or {}) do if itemIn(x, area) then out.starts = true end end
  local f = q.finishers or {}
  for _, n in ipairs(f.npcs or {}) do if npcIn(n, area) then out.ends = true end end
  for _, x in ipairs(f.objects or {}) do if objectIn(x, area) then out.ends = true end end
  return out
end

-------------------------------------------------------------------------------------------
-- Questlines: every chain that touches the instance
-------------------------------------------------------------------------------------------

-- a quest's links: back (what comes before it) and on (what follows)
local function back(id)
  local q = DB:Get("quests", id) or {}
  local out = {}
  local pre = q.prerequisites or {}
  for _, x in ipairs(pre.all or {}) do out[#out + 1] = x end
  for _, x in ipairs(pre.any or {}) do out[#out + 1] = x end
  for _, x in ipairs(q.leadIn or {}) do out[#out + 1] = x end
  for _, x in ipairs(q.breadcrumbs or {}) do out[#out + 1] = x end
  return out
end
local function on(id)
  local q = DB:Get("quests", id) or {}
  local list, nxt = Core.DB:Unlocks(id)
  local out = {}
  for _, x in ipairs(list or {}) do out[#out + 1] = x end
  if nxt then out[#out + 1] = nxt end
  if q.breadcrumbFor then out[#out + 1] = q.breadcrumbFor end
  return out
end

---The quests of an instance's questlines: its own quests, every step before them, and up to
---FORWARD_STEPS after. Returns { ids }, and the set of the instance's own.
function R.Closure(key)
  local inst = Core.DB:Instance(key)
  local own, set, list = {}, {}, {}
  local function add(id)
    if set[id] or not DB:Get("quests", id) or Core.DB:IsQuestHidden(id) then return false end
    set[id] = true
    list[#list + 1] = id
    return true
  end
  local queue = {}
  for _, id in ipairs(inst and inst.quests or {}) do
    own[id] = true
    if add(id) then queue[#queue + 1] = { id, 0 } end
  end
  -- back to where each line starts
  local i = 1
  while queue[i] do
    local id, d = queue[i][1], queue[i][2]
    i = i + 1
    if d < BACK_STEPS then
      for _, x in ipairs(back(id)) do if add(x) then queue[#queue + 1] = { x, d + 1 } end end
    end
  end
  -- on from the instance's quests (and only from them: an earlier step's other branches lead elsewhere)
  local fwd = {}
  for id in pairs(own) do fwd[#fwd + 1] = { id, 0 } end
  i = 1
  while fwd[i] do
    local id, d = fwd[i][1], fwd[i][2]
    i = i + 1
    if d < FORWARD_STEPS then
      for _, x in ipairs(on(id)) do if add(x) then fwd[#fwd + 1] = { x, d + 1 } end end
    end
  end
  return list, own
end

local memo = {}

---An instance's questlines: { lines = { line }, singles = { step }, counts }.
---  line = { chain (QB), title, steps = { step }, done, total, now (index of the first step not done),
---           visits (steps done inside), state }
---  step = { id, rail, branch, state (QB.State), now (one you can act on), inside, starts, ends, own }
function R.Questlines(key)
  local qb = QB()
  local m = memo[key]
  if m and m.revision == qb.revision then return m.data end
  local area = R.Areas(key)
  local ids, own = R.Closure(key)
  -- every side's quests: the ones you can't take are shown greyed, at the bottom
  local book = qb.Chains(ids, "all")
  local function step(id, extra)
    local where = R.Inside(id, area)
    local s = { id = id, state = qb.State(id), inside = where.inside, starts = where.starts, ends = where.ends, own = own[id] }
    for k, v in pairs(extra or {}) do s[k] = v end
    return s
  end
  local data = { lines = {}, singles = {}, others = {}, otherSingles = {} }
  for _, c in ipairs(book.chains) do
    local touches = false
    for _, id in ipairs(c.quests) do if own[id] then touches = true end end
    if touches then
      local now = {}
      for _, id in ipairs(c.next or {}) do now[id] = true end
      local line = { chain = c, title = c.title or qname(c.titleId or c.quests[#c.quests]), steps = {}, done = c.done or 0,
        total = c.total or #c.quests, state = c.state, visits = 0 }
      local seen = {}
      for ri, rail in ipairs(c.rails or { { steps = c.quests } }) do
        for si, id in ipairs(rail.steps) do
          if not seen[id] then
            seen[id] = true
            local s = step(id, { rail = ri, branch = ri > 1 and si == 1, crumb = c.crumbs and c.crumbs[id] or nil,
              now = now[id] and c.state ~= "done" or nil })
            if s.inside then line.visits = line.visits + 1 end
            table.insert(line.steps, s)
            if not line.nowAt and s.state.s ~= "done" then line.nowAt = #line.steps end
          end
        end
      end
      local list = c.state == "nfy" and data.others or data.lines
      list[#list + 1] = line
    end
  end
  for _, s in ipairs(book.singles) do
    if own[s.id] then
      local list = s.state.s == "nfy" and data.otherSingles or data.singles
      list[#list + 1] = step(s.id, { now = s.state.s == "ready" or s.state.s == "log" })
    end
  end
  -- under way first, then ready to start, then not yet; finished ones last
  local rank = { part = 1, new = 2, locked = 3, done = 4 }
  table.sort(data.lines, function(a, b)
    local ra, rb = rank[a.state] or 5, rank[b.state] or 5
    if ra ~= rb then return ra < rb end
    return (a.chain.level or 0) < (b.chain.level or 0)
  end)
  table.sort(data.singles, function(a, b)
    return ((DB:Get("quests", a.id) or {}).level or 0) < ((DB:Get("quests", b.id) or {}).level or 0)
  end)
  memo[key] = { revision = qb.revision, data = data }
  return data
end

---The Questlines layout's rows: a heading per line, then its steps.
function R.LineRows(key)
  local data = R.Questlines(key)
  local rows, finished = {}, {}
  for _, line in ipairs(data.lines) do
    if line.state == "done" then
      finished[#finished + 1] = line
    else
      R.AddLine(rows, line)
    end
  end
  if #data.singles > 0 then
    rows[#rows + 1] = { group = "Single quests  " .. UI.Code(C.faint) .. #data.singles .. "|r", kind = "head" }
    for _, s in ipairs(data.singles) do rows[#rows + 1] = { step = s } end
  end
  if #finished > 0 then
    rows[#rows + 1] = { group = (fold.finished and O.ICON.folded or O.ICON.open) .. " " .. "Finished questlines  " .. UI.Code(C.faint) .. #finished .. "|r",
      foldable = "finished" }
    if not fold.finished then for _, line in ipairs(finished) do R.AddLine(rows, line) end end
  end
  -- the other faction's and other classes' quests: last, greyed
  local n = #data.others + #data.otherSingles
  if n > 0 then
    rows[#rows + 1] = { group = (fold.others and O.ICON.folded or O.ICON.open) .. " " .. UI.Code(C.faint) .. "Not for you  " .. n
      .. "  the other faction's or another class's|r", foldable = "others" }
    if not fold.others then
      for _, line in ipairs(data.others) do R.AddLine(rows, line, true) end
      for _, st in ipairs(data.otherSingles) do rows[#rows + 1] = { step = st, greyed = true } end
    end
  end
  return rows, data
end

function R.AddLine(rows, line, greyed)
  local key = line.chain.key
  local folded = fold["line:" .. key]
  local parts = { string.format("%s%d of %d done|r", UI.Code(C.muted), line.done, line.total) }
  if line.visits > 0 then
    parts[#parts + 1] = UI.Code(ORANGE) .. (line.visits == 1 and "1 step in the dungeon" or (line.visits .. " steps in the dungeon")) .. "|r"
  end
  if greyed then parts = { UI.Code(C.faint) .. O.QuestStateText(line.steps[1] and line.steps[1].state) .. "|r" } end
  rows[#rows + 1] = { group = string.format("%s %s%s|r   %s", folded and O.ICON.folded or O.ICON.open, greyed and UI.Code(C.faint) or UI.Code(C.goldSoft),
    line.title, table.concat(parts, UI.Code(C.faint) .. "  ·  |r")), foldable = "line:" .. key, line = line }
  if not folded then for _, s in ipairs(line.steps) do rows[#rows + 1] = { step = s, line = line, greyed = greyed } end end
end

-------------------------------------------------------------------------------------------
-- Before you go: the pickups (QB.Ready)
-------------------------------------------------------------------------------------------

---The rows: { group } headings and { entry, bucket } rows.
function R.Rows(key)
  local ready = QB().Ready(key)
  local rows = {}
  local function section(bucket, title, list, note)
    if #list == 0 then return end
    local folded = fold[bucket]
    rows[#rows + 1] = { group = string.format("%s%s  %s%d|r%s", folded and (O.ICON.folded .. " ") or "", title, UI.Code(C.faint), #list,
      note and (UI.Code(C.faint) .. "  " .. note .. "|r") or ""), bucket = bucket, foldable = (bucket == "done" or bucket == "nfy") and bucket or nil }
    if not folded then for _, e in ipairs(list) do rows[#rows + 1] = { entry = e, bucket = bucket } end end
  end
  if #ready.pick > 0 then
    rows[#rows + 1] = { group = "Pick up before you go  " .. UI.Code(C.faint) .. ready.counts.pick .. "  by where you go|r", bucket = "pickhead" }
    for _, g in ipairs(ready.pick) do
      local place = g.inside and ("Inside " .. ((O.Model:Get(key) or {}).name or "the instance"))
        or g.name or (g.area == nil and "Starts from an item you find" or "Somewhere not known yet")
      rows[#rows + 1] = { group = UI.Code(UI.Accent("clairvoyance")) .. "   " .. place .. "|r", bucket = "place" }
      for _, e in ipairs(g.entries) do rows[#rows + 1] = { entry = e, bucket = "pick" } end
    end
  end
  section("part", "Partway", ready.part, "chains you've started")
  section("log", "In your log", ready.log, "ready for the run")
  section("later", "Not yet", ready.later, "a level or an earlier step away")
  section("done", "Done", ready.done)
  section("nfy", "Not for you", ready.nfy, "the other faction's or another class's")
  return rows, ready
end

-------------------------------------------------------------------------------------------
-- A row's two lines
-------------------------------------------------------------------------------------------

local function nameOf(id, extra)
  local q = DB:Get("quests", id) or {}
  local lc = q.level and UI.Difficulty(q.level, Core.Player.level or 1) or C.text
  return UI.Code(lc) .. "[" .. (q.level or "?") .. "]|r " .. qname(id) .. (extra or "")
end

---A Questlines step's two lines.
function R.StepLines(s)
  local st = s.state
  local name = (s.branch and (UI.Code(C.faint) .. O.ICON.branch .. "|r") or "") .. nameOf(s.id, s.crumb and (UI.Code(C.faint) .. " (optional lead-in)|r") or "")
  if st.s == "done" then name = UI.Code(C.faint) .. "[" .. ((DB:Get("quests", s.id) or {}).level or "?") .. "] " .. qname(s.id) .. "|r" end
  local tags = {}
  if s.inside then tags[#tags + 1] = UI.Code(ORANGE) .. "In the dungeon|r" end
  if s.starts and not s.inside then tags[#tags + 1] = UI.Code(ORANGE) .. "starts inside|r" end
  if s.ends and not s.inside then tags[#tags + 1] = UI.Code(ORANGE) .. "hand in inside|r" end
  local q = DB:Get("quests", s.id) or {}
  local fromItem = q.starters and q.starters.items and q.starters.items[1]
  local words, color = O.QuestStateText(st)
  local meta
  if st.s == "ready" then
    local g = QB().Giver(s.id)
    if fromItem and s.starts then
      meta = UI.Code(color) .. "drops inside: " .. (Core.DB:Name("items", fromItem) or "an item") .. "|r"
    else
      meta = UI.Code(color) .. "Pick up: " .. giverWhere(g) .. "|r"
    end
  elseif st.s == "locked" and fromItem and s.starts then
    meta = UI.Code(C.faint) .. (Core.DB:Name("items", fromItem) or "Its item") .. " drops inside once you're on this step|r"
  else
    meta = UI.Code(color) .. words .. "|r"
  end
  if #tags > 0 then meta = table.concat(tags, UI.Code(C.faint) .. " · |r") .. UI.Code(C.faint) .. "  ·  |r" .. meta end
  return name, meta
end

---A Before you go row's two lines: the quest (with the steps folded into it) and what to do about it.
function R.Lines(r)
  local e = r.entry
  local name = nameOf(e.id)
  if #e.folded > 0 then
    local names = {}
    for _, f in ipairs(e.folded) do names[#names + 1] = qname(f) end
    name = name .. UI.Code(C.faint) .. "  (with " .. table.concat(names, ", ") .. ")|r"
  end
  local q = DB:Get("quests", e.id) or {}
  local meta
  local steps = e.steps or {}
  local stepOf = ""
  if #steps > 1 and e.next then
    for i, s in ipairs(steps) do if s == e.next then stepOf = UI.Code(C.faint) .. " · step " .. i .. " of " .. #steps .. "|r" end end
  end
  if r.bucket == "pick" then
    if e.next and e.next ~= e.id then
      meta = "first: " .. UI.Code(C.text) .. qname(e.next) .. "|r · " .. UI.Code(UI.Accent("clairvoyance")) .. giverWhere(e.giver) .. "|r" .. stepOf
    else
      meta = UI.Code(UI.Accent("clairvoyance")) .. giverWhere(e.giver) .. "|r"
    end
    if q.shareable == false then meta = meta .. UI.Code(C.faint) .. " · can't be shared|r" end
  elseif r.bucket == "part" then
    local words, color = O.QuestStateText(e.nextState)
    meta = "next: " .. UI.Code(C.text) .. qname(e.next) .. "|r · " .. UI.Code(color)
      .. (e.nextState and e.nextState.s == "ready" and giverWhere(e.giver) or words) .. "|r" .. stepOf
  elseif r.bucket == "later" then
    local words, color = O.QuestStateText(e.nextState or e.state)
    meta = (e.next and e.next ~= e.id and ("first: " .. qname(e.next) .. " · ") or "") .. UI.Code(color) .. words .. "|r"
  else
    local words, color = O.QuestStateText(e.state)
    meta = UI.Code(color) .. words .. "|r"
  end
  return name, meta
end

-------------------------------------------------------------------------------------------
-- The view
-------------------------------------------------------------------------------------------

local MODES = { { key = "lines", label = "Questlines" }, { key = "before", label = "Before you go" } }

function R:Build(parent)
  local f = CreateFrame("Frame", nil, parent)
  f:SetAllPoints()
  -- the summary
  local top = UI.Pane(f)
  top:SetPoint("TOPLEFT")
  top:SetPoint("TOPRIGHT")
  top:SetHeight(52)
  f.big = UI.Text(top, "title", 17, C.gold)
  f.big:SetPoint("TOPLEFT", 14, -8)
  f.stats = UI.Text(top, "body", 12, C.muted)
  f.stats:SetPoint("TOPLEFT", f.big, "BOTTOMLEFT", 0, -3)
  f.track = UI.Button(top, "Track pickups", "accent", function()
    local res = O.Quests.TrackAll(R.key)
    if res == "noclairvoyance" then O:Print("Clairvoyance puts quest givers on your map; it isn't loaded.") end
    R:Fill(R.key)
  end)
  f.track:SetSize(120, 24)
  f.track:SetPoint("RIGHT", -12, 0)
  f.track:ApplyAccent(UI.Accent("clairvoyance"))
  f.mode = UI.Segmented(top, MODES, function(key)
    O.db.readyMode = key
    R:Fill(R.key)
  end, 22)
  f.mode:SetPoint("RIGHT", f.track, "LEFT", -12, 0)
  -- the list
  local pane = UI.Pane(f)
  pane:SetPoint("TOPLEFT", top, "BOTTOMLEFT", 0, -8)
  pane:SetPoint("BOTTOMRIGHT")
  f.list = UI.List(pane, {
    rowHeight = ROW,
    groupBand = true,
    createRow = function(row, content)
      -- the step you're on: a band in the accent and a stripe down its left (not row.bar/sel/hl: UI.List's own)
      row.nowBand = content:CreateTexture(nil, "BACKGROUND", nil, 1)
      row.nowBand:SetAllPoints()
      row.nowStripe = content:CreateTexture(nil, "ARTWORK", nil, 2)
      row.nowStripe:SetPoint("TOPLEFT", 0, -2)
      row.nowStripe:SetPoint("BOTTOMLEFT", 0, 2)
      row.nowStripe:SetWidth(3)
      row.mark = UI.Icon(content, "circle", 10, C.faint)
      row.mark:SetPoint("LEFT", 12, 0)
      row.check = UI.Icon(content, "check", 13, C.good)
      row.check:SetPoint("CENTER", row.mark, "CENTER")
      row.name = UI.Text(content, "body", 14, C.text)
      row.name:SetPoint("TOPLEFT", 30, -4)
      row.name:SetPoint("TOPRIGHT", content, "TOPRIGHT", -10, -4)
      row.name:SetWordWrap(false)
      row.meta = UI.Text(content, "body", 12, C.muted)
      row.meta:SetPoint("TOPLEFT", row.name, "BOTTOMLEFT", 0, -2)
      row.meta:SetPoint("TOPRIGHT", row.name, "BOTTOMRIGHT", 0, -2)
      row.meta:SetWordWrap(false)
    end,
    updateRow = function(row, r)
      local name, meta, mark, now
      if r.step then
        name, meta = R.StepLines(r.step)
        local s = r.step.state.s
        now = r.step.now
        mark = s == "done" and "done" or (now and "now" or (s == "log" and "log" or "later"))
      else
        name, meta = R.Lines(r)
        mark = r.bucket == "done" and "done" or (r.bucket == "log" and "log" or "later")
      end
      row.name:SetText(name)
      row.meta:SetText(meta)
      -- the other faction's and other classes' quests: greyed
      local grey = r.greyed or r.bucket == "nfy" or (r.step and r.step.state.s == "nfy")
      row.name:SetAlpha(grey and .45 or 1)
      row.meta:SetAlpha(grey and .45 or 1)
      local a = UI.Accent("clairvoyance")
      row.nowBand:SetColorTexture(a[1], a[2], a[3], .14)
      row.nowStripe:SetColorTexture(a[1], a[2], a[3], 1)
      row.nowBand:SetShown(now == true)
      row.nowStripe:SetShown(now == true)
      row.check:SetShown(mark == "done")
      row.mark:SetShown(mark ~= "done")
      local c = mark == "now" and a or (mark == "log" and C.info or C.faint)
      row.mark:SetVertexColor(c[1], c[2], c[3])
    end,
    onClick = function(r, _, button)
      local id = r.step and r.step.id or (r.entry and r.entry.id)
      if not id then return end
      if button == "RightButton" then
        local card = O.Quests.Card(id)
        if card then O.Quests.Track(card) end
        return
      end
      O.Inspector:Show("quest", id)
    end,
    onGroupClick = function(g)
      if g.foldable then fold[g.foldable] = not fold[g.foldable] or nil R:Fill(R.key) end
    end,
    onEnter = function(row, r)
      GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
      if r.step and r.step.inside then GameTooltip:AddLine("Done inside the dungeon", ORANGE[1], ORANGE[2], ORANGE[3]) end
      GameTooltip:AddLine("Click: the quest · right-click: Track (its giver, or its first step's, on your map)", .66, .63, .54)
      GameTooltip:Show()
    end,
    onLeave = function() GameTooltip:Hide() end,
  })
  f.list:SetPoint("TOPLEFT", 1, -4)
  f.list:SetPoint("BOTTOMRIGHT", -1, 4)
  f.list:ApplyAccent(UI.Accent("oracle"))
  f.empty = UI.Text(pane, "body", 13, C.faint)
  f.empty:SetPoint("TOPLEFT", 14, -14)
  f.empty:SetPoint("TOPRIGHT", -14, -14)
  f.empty:SetWordWrap(true)
  f.empty:SetText("NorgannonDB knows no quests for this instance yet.")
  self.frame = f
  f:Hide()
  return f
end

function R:Fill(key)
  if not (self.frame and key) then return end
  if key ~= self.key then
    for k in pairs(fold) do if k:find("^line:") then fold[k] = nil end end
  end
  self.key = key
  local f = self.frame
  local mode = O.db.readyMode or "lines"
  f.mode:Select(mode, true)
  local ready = QB().Ready(key)
  self.ready = ready
  local rows
  if mode == "lines" then
    rows, self.lines = R.LineRows(key)
  else
    rows = R.Rows(key)
  end
  self.rows = rows
  f.list:SetData(rows, true)
  local c = ready.counts
  f.empty:SetShown(#rows == 0)
  f.big:SetText(string.format("%d of %d quests ready", c.log, c.total))
  f.stats:SetText(string.format("%s%d|r to pick up in %s%d|r %s · %s%d|r partway · %d not yet · %d done",
    UI.Code(C.text), c.pick, UI.Code(C.text), c.places, c.places == 1 and "place" or "places",
    UI.Code(C.text), c.part, c.later, c.done))
  local tracking = O.Quests.TrackingAll and O.Quests.TrackingAll(key)
  f.track:SetLabel(tracking and "Tracked" or "Track pickups")
  f.track:SetShown(c.pick + c.part > 0 or tracking)
end

-- your log or level changed: everything moves
Core:Listen("ORACLE_QUESTBOOK_CHANGED", "oracle.readycheck", function()
  if R.frame and R.frame:IsVisible() and R.key then R:Fill(R.key) end
end)
