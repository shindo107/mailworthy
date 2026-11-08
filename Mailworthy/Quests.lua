-- Items the player's active quests ask for (operator, 2026-11-08: "if the player has an active
-- quest for an item (not always "quest items") it shouldn't recommend vendoring or
-- auctioning"). Crisp Spider Meat for Redridge Goulash is a plain trade good, not a quest
-- item, so the bag's quest flag never sees it: the quest log does. An item an objective
-- names stays in the bags (Valuation: "a quest needs it", a hard keep no binding overrides).
--
-- API (Forever's source, Ketho/wow-ui-source-forever): C_QuestLog.GetNumQuestLogEntries,
-- C_QuestLog.GetInfo(index) -> { title, questID, isHeader }, C_QuestLog.GetQuestObjectives(questID)
-- -> { { text, type = "item", ... } } (QuestLogDocumentation.lua); the Vanilla quest log's own
-- GetNumQuestLogEntries / GetQuestLogTitle / GetNumQuestLeaderBoards / GetQuestLogLeaderBoard
-- (Blizzard_UIPanels_Game/Vanilla/QuestLogFrame.lua) as the fallback. Objectives name the item,
-- not its ID ("Crisp Spider Meat: 3/5"), so items are matched by name. Every call is pcall'd;
-- a quest under a collapsed header may not be listed (Beta unknowns, README).
local _, ns = ...

local Quests = {}
ns.Quests = Quests

local needs -- lower-case item name -> quest title; nil = read the log again
local MAX_ENTRIES = 100

local function call(fn, ...)
    if type(fn) ~= "function" then return nil end
    local results = { pcall(fn, ...) }
    if not results[1] then return nil end
    return unpack(results, 2, table.maxn(results))
end

--- Pure: the item an objective's text names: "Crisp Spider Meat: 3/5" (Classic), "3/5 Crisp
--- Spider Meat" (the modern client), or the text itself. nil for an empty text.
function Quests.ItemName(text)
    if type(text) ~= "string" then return nil end
    local name = text:match("^(.-)%s*:%s*%d+%s*/%s*%d+") or text:match("^%d+%s*/%s*%d+%s+(.+)$") or text
    name = name:gsub("%s*%(.-%)%s*$", ""):match("^%s*(.-)%s*$") -- "(Complete)" and spaces
    return name ~= "" and name or nil
end

--- Pure: name -> quest title from { { title, objectives = { { text, type } } } }; item objectives only.
function Quests.Index(quests)
    local out = {}
    for _, q in ipairs(quests or {}) do
        for _, o in ipairs(q.objectives or {}) do
            local name = o.type == "item" and Quests.ItemName(o.text)
            if name and not out[name:lower()] then out[name:lower()] = tostring(q.title or "a quest") end
        end
    end
    return out
end

-- The quest log as { { title, objectives } }.
local function readModern(log)
    local count = tonumber((call(log.GetNumQuestLogEntries))) or 0
    local quests = {}
    for i = 1, math.min(count, MAX_ENTRIES) do
        local info = call(log.GetInfo, i)
        if type(info) == "table" and not info.isHeader and info.questID then
            local objectives = call(log.GetQuestObjectives, info.questID)
            quests[#quests + 1] = { title = info.title, objectives = type(objectives) == "table" and objectives or {} }
        end
    end
    return quests
end

local function readLegacy()
    local count = tonumber((call(rawget(_G, "GetNumQuestLogEntries")))) or 0
    local quests = {}
    for i = 1, math.min(count, MAX_ENTRIES) do
        local title, _, _, isHeader = call(rawget(_G, "GetQuestLogTitle"), i)
        if title and not isHeader then
            local q = { title = title, objectives = {} }
            for j = 1, tonumber((call(rawget(_G, "GetNumQuestLeaderBoards"), i))) or 0 do
                local text, kind = call(rawget(_G, "GetQuestLogLeaderBoard"), j, i)
                q.objectives[#q.objectives + 1] = { text = text, type = kind }
            end
            quests[#quests + 1] = q
        end
    end
    return quests
end

--- The quests in the log, with their objectives.
function Quests.Read()
    local log = rawget(_G, "C_QuestLog")
    if type(log) == "table" and type(log.GetInfo) == "function" and type(log.GetQuestObjectives) == "function" then
        local quests = readModern(log)
        if #quests > 0 then return quests end
    end
    return readLegacy()
end

--- The quest that needs this item (by link or name), or nil.
function Quests.For(link)
    if not ns.Features.On("questNeeds") then return nil end
    if not needs then
        local ok, quests = pcall(Quests.Read)
        needs = Quests.Index(ok and quests or {})
    end
    local name = tostring(link or ""):match("%[(.-)%]") or link
    return type(name) == "string" and needs[name:lower()] or nil
end

function Quests.Invalidate() needs = nil end

--- Pure: do two indexes name the same items for the same quests?
function Quests.Same(a, b)
    for k, v in pairs(a or {}) do if (b or {})[k] ~= v then return false end end
    for k in pairs(b or {}) do if (a or {})[k] == nil then return false end end
    return true
end

--- QUEST_LOG_UPDATE fires often: read the log again, and only when what it asks for changed,
--- redraw what depends on it (the bag tags and tooltips, the Mailworthy window), so a quest
--- accepted or turned in with the item already in the bags shows at once (Codex review).
function Quests.Update()
    local before = needs
    local ok, quests = pcall(Quests.Read)
    needs = Quests.Index(ok and quests or {})
    if before == nil or Quests.Same(before, needs) then return false end
    if ns.BankAlt then ns.BankAlt.Redraw() end
    if ns.MailWindow and not ns.Mailer.Busy() then ns.MailWindow.RefreshIfShown() end
    return true
end

ns.On("QUEST_LOG_UPDATE", function()
    if ns.Features.On("questNeeds") then Quests.Update() end
end)
ns.On("PLAYER_LOGIN", function() Quests.Invalidate() end)
