-- Tier check (2026-11-06): the material tiers (Tiers.lua, TierData.lua) come from a beta-client
-- snapshot of Forever's recipes (1.60.1.70790) and were never checked in game. The player's own
-- profession window colours every recipe for the player's own skill (orange / yellow / green /
-- grey), which is ground truth for the tier rule "done when every recipe using it, directly or
-- through a part the profession makes, is grey". So when the player opens one of their own
-- crafting professions, Mailworthy reads each learned recipe's difficulty and reagents and records,
-- per character and skill line (MailworthyDB.tierCheck), the skill rank and, for each reagent,
-- the hardest non-grey recipe still using it (false: only grey ones).
--
-- `/mw report` then lists every material the table calls done that a non-grey recipe still uses
-- ("tier check: Wool Cloth still used by Gray Woolen Shirt (yellow) at skill 110, table says done
-- at 105"), and while the latest read says so the material stays in the bags ("your Tailoring
-- needs it": Valuation.NeededBy, the entry's `stillUsed`) until the window says otherwise.
--
-- Read only: no frames, no writes into Blizzard's UI, no hooks; the events only.
-- API (Forever's source, Ketho/wow-ui-source-forever): the Professions window is the retail one,
-- fed by C_TradeSkillUI: GetBaseProfessionInfo / GetChildProfessionInfo (ProfessionInfo:
-- professionID, parentProfessionID, skillLevel), GetRecipeInfo (TradeSkillRecipeInfo: learned,
-- relativeDifficulty = Enum.TradeskillRelativeDifficulty Optimal 0 / Medium 1 / Easy 2 / Trivial 3),
-- GetRecipeSchematic (reagentSlotSchematics[].reagents[].itemID, outputItemID), GetFilteredRecipeIDs,
-- IsTradeSkillLinked / IsTradeSkillGuild / IsTradeSkillGuildMember / IsNPCCrafting (Blizzard's
-- profession frame calls them). GetAllRecipeIDs is not in Forever's Lua (retail has it): tried
-- first. The Classic globals (GetTradeSkillInfo, GetCraftInfo, ...) aren't in Forever's source at
-- all; they are a fallback for a client without C_TradeSkillUI. Everything is pcall'd (README
-- "Beta unknowns"). Switch: /mw feature tierCheck off.
local _, ns = ...

local TierCheck = {}
ns.TierCheck = TierCheck

TierCheck.COLORS = { [0] = "orange", [1] = "yellow", [2] = "green", [3] = "grey" }
TierCheck.GREY = 3
local CLASSIC_DIFFICULTY = { optimal = 0, medium = 1, easy = 2, trivial = 3 }
local TRADE_GOODS = 7

-- First Aid's cloth is done where the next bandage is learnable (the operator's rule), not
-- where its bandages turn grey, so a still-yellow bandage is no evidence against it.
TierCheck.EXEMPT = { [129] = { [2589] = true, [2592] = true, [4306] = true, [4338] = true } }

local function call(fn, ...)
    if type(fn) ~= "function" then return nil end
    local results = { pcall(fn, ...) }
    if not results[1] then return nil end
    return unpack(results, 2, table.maxn(results))
end

local function itemIDFromLink(link)
    return tonumber(type(link) == "string" and link:match("item:(%d+)") or nil)
end

function TierCheck.On() return ns.Features.On("tierCheck") end

--- Pure: from a recipe list { { name, difficulty (0-3), reagents = { itemID, ... }, output = itemID }, ... }
--- the map reagent itemID -> { recipe, difficulty, via } (the hardest non-grey recipe using it, `via`
--- the name of the profession's own part it goes through) or false (only grey recipes use it).
--- A part is the output of another recipe in the list; with `classOf(itemID)` given, only trade
--- goods count as parts (bolts, grinding stones, blasting powders; not gear made from gear).
--- A recipe making the item a material converts into (Tiers.CONVERT: 4 Light Leather -> 1 Medium)
--- doesn't count for that material: past its own recipes it is kept while converting pays.
function TierCheck.Summarize(recipes, profession, classOf)
    local reagents, makers = {}, {}
    local converts = ns.Tiers.CONVERT[tonumber(profession) or -1] or {}
    local function isConversion(r, out)
        for _, id in ipairs(r.reagents or {}) do
            if converts[id] and converts[id].into == out then return true end
        end
        return false
    end
    for _, r in ipairs(recipes or {}) do
        local out = tonumber(r.output)
        local class = out and type(classOf) == "function" and classOf(out) or nil
        if out and (class == nil or class == TRADE_GOODS) and not isConversion(r, out) then
            makers[out] = makers[out] or {}
            table.insert(makers[out], r)
        end
        for _, id in ipairs(r.reagents or {}) do
            if reagents[id] == nil then reagents[id] = false end
        end
    end
    local function mark(id, recipe, via, depth, seen)
        local c = converts[id]
        if c and tonumber(recipe.output) == c.into and not via then return end
        local old = reagents[id]
        if not old or recipe.difficulty < old.difficulty then
            reagents[id] = { recipe = recipe.name, difficulty = recipe.difficulty, via = via }
        end
        if depth >= 4 or seen[id] then return end
        seen[id] = true
        for _, maker in ipairs(makers[id] or {}) do
            for _, sub in ipairs(maker.reagents or {}) do mark(sub, recipe, via or maker.name, depth + 1, seen) end
        end
    end
    for _, r in ipairs(recipes or {}) do
        if tonumber(r.difficulty) and r.difficulty < TierCheck.GREY then
            for _, id in ipairs(r.reagents or {}) do mark(id, r, nil, 0, {}) end
        end
    end
    return reagents
end

--- Pure: the materials the table calls done at `record.rank` that a non-grey recipe still uses:
--- { { itemID, name, at, recipe, difficulty, via }, ... } by threshold.
function TierCheck.Findings(profession, record)
    local out = {}
    if type(record) ~= "table" or type(record.reagents) ~= "table" then return out end
    local exempt = TierCheck.EXEMPT[tonumber(profession) or -1] or {}
    for id, used in pairs(record.reagents) do
        local at = ns.Tiers.Threshold(profession, id)
        if used and at and not exempt[id] and tonumber(record.rank) and record.rank >= at then
            out[#out + 1] = { itemID = id, name = ns.Tiers.Name(profession, id), at = at, recipe = used.recipe,
                difficulty = used.difficulty, via = used.via }
        end
    end
    table.sort(out, function(a, b)
        if a.at ~= b.at then return a.at < b.at end
        return a.itemID < b.itemID
    end)
    return out
end

--- Pure: "tier check: Linen Cloth still used by Soft-soled Linen Boots (yellow) at skill 120, table says
--- done at 115 (via Bolt of Linen Cloth)".
function TierCheck.FindingText(f, rank)
    return string.format("tier check: %s still used by %s (%s) at skill %s, table says done at %d%s",
        tostring(f.name or f.itemID), tostring(f.recipe), TierCheck.COLORS[f.difficulty] or "?", tostring(rank),
        f.at, f.via and (" (via " .. f.via .. ")") or "")
end

-- Reading the window -------------------------------------------------------------------------

local function professionName(id)
    local p = ns.Valuation.PROFESSION_MATS[tonumber(id) or -1]
    return p and p.name
end

-- This character's crafting profession by skill line, or by name: { skillLine, rank }.
local function ownProfession(ids, name)
    for _, p in ipairs(ns.Characters.Professions()) do
        for _, id in ipairs(ids) do
            if tonumber(p.skillLine) == tonumber(id) and professionName(id) then return p end
        end
    end
    for _, p in ipairs(ns.Characters.Professions()) do
        if name and p.name == name and professionName(p.skillLine) then return p end
    end
end

local function modernRecipes()
    local T = C_TradeSkillUI
    if type(T) ~= "table" then return nil end
    if call(T.IsTradeSkillLinked) or call(T.IsTradeSkillGuild) or call(T.IsTradeSkillGuildMember)
        or call(T.IsNPCCrafting) then
        return nil, "not your own profession window"
    end
    if type(T.IsTradeSkillReady) == "function" and call(T.IsTradeSkillReady) == false then return nil, "not ready" end
    local base, child = call(T.GetBaseProfessionInfo), call(T.GetChildProfessionInfo)
    base, child = type(base) == "table" and base or {}, type(child) == "table" and child or {}
    local own = ownProfession({ base.professionID, child.parentProfessionID, child.professionID },
        base.professionName or child.parentProfessionName)
    if not own then return nil, "not a crafting profession Mailworthy keeps materials for" end
    local ids, source = call(T.GetAllRecipeIDs), "C_TradeSkillUI"
    if type(ids) ~= "table" then
        ids, source = call(T.GetFilteredRecipeIDs), "C_TradeSkillUI (filtered list)"
    end
    if type(ids) ~= "table" then return nil, "no recipe list" end
    local recipes = {}
    for _, id in ipairs(ids) do
        local info = call(T.GetRecipeInfo, id)
        if type(info) == "table" and info.learned and tonumber(info.relativeDifficulty) and not info.isRecraft
            and not info.isDummyRecipe and not info.isSalvageRecipe and not info.isGatheringRecipe then
            local schematic = call(T.GetRecipeSchematic, id, false)
            local reagents = {}
            for _, slot in ipairs(type(schematic) == "table" and schematic.reagentSlotSchematics or {}) do
                for _, reagent in ipairs(type(slot) == "table" and slot.reagents or {}) do
                    if tonumber(reagent.itemID) then reagents[#reagents + 1] = tonumber(reagent.itemID) end
                end
            end
            recipes[#recipes + 1] = { name = info.name, difficulty = tonumber(info.relativeDifficulty),
                reagents = reagents, output = type(schematic) == "table" and tonumber(schematic.outputItemID) or nil }
        end
    end
    local rank = tonumber(own.rank) or tonumber(child.skillLevel) or tonumber(base.skillLevel)
    return { skillLine = tonumber(own.skillLine), rank = rank, recipes = recipes, source = source }
end

-- Classic globals (not in Forever's source): GetTradeSkillLine / GetNumTradeSkills / GetTradeSkillInfo,
-- or for Enchanting's craft window GetCraftDisplaySkillLine / GetNumCrafts / GetCraftInfo.
local function classicRecipes(craft)
    local G = _G
    local lineFn = craft and G.GetCraftDisplaySkillLine or G.GetTradeSkillLine
    local name, rank = call(lineFn)
    local own = ownProfession({}, name)
    if not own then return nil, "not a crafting profession Mailworthy keeps materials for" end
    local count = tonumber(call(craft and G.GetNumCrafts or G.GetNumTradeSkills)) or 0
    local recipes = {}
    for i = 1, count do
        local recipeName, kind
        if craft then
            local craftName, _, craftType = call(G.GetCraftInfo, i)
            recipeName, kind = craftName, craftType
        else
            recipeName, kind = call(G.GetTradeSkillInfo, i)
        end
        local difficulty = CLASSIC_DIFFICULTY[kind or ""]
        if recipeName and difficulty then
            local reagents = {}
            local n = tonumber(call(craft and G.GetCraftNumReagents or G.GetTradeSkillNumReagents, i)) or 0
            for j = 1, n do
                local id = itemIDFromLink(call(craft and G.GetCraftReagentItemLink or G.GetTradeSkillReagentItemLink, i, j))
                if id then reagents[#reagents + 1] = id end
            end
            recipes[#recipes + 1] = { name = recipeName, difficulty = difficulty, reagents = reagents,
                output = itemIDFromLink(call(craft and G.GetCraftItemLink or G.GetTradeSkillItemLink, i)) }
        end
    end
    return { skillLine = tonumber(own.skillLine), rank = tonumber(own.rank) or tonumber(rank), recipes = recipes,
        source = craft and "classic craft window" or "classic trade skill window" }
end

local function classOf(itemID)
    local class = select(6, call(GetItemInfoInstant, itemID))
    return tonumber(class)
end

local function charKey() return ns.Characters.Key(ns.Characters.Current()) end

--- The saved reads: MailworthyDB.tierCheck[character key][skill line] = { rank, at, recipes, source, reagents,
--- profession, skillLine, version, findings = { { itemID, name, doneAt, recipe, difficulty, color, via, text }, ... } }
--- (findings: what the table, as of `version`, calls done that a non-grey recipe still uses; /mw report's lines).
function TierCheck.Records()
    MailworthyDB.tierCheck = type(MailworthyDB.tierCheck) == "table" and MailworthyDB.tierCheck or {}
    return MailworthyDB.tierCheck
end

--- This character's latest read of `skillLine`, or nil.
function TierCheck.Latest(skillLine)
    local mine = TierCheck.Records()[charKey()]
    return type(mine) == "table" and mine[tonumber(skillLine) or -1] or nil
end

local lastLogged = {}

--- Read the open profession window (`craft`: Classic's craft window) and save it. Returns the record or nil, why.
function TierCheck.Scan(craft)
    if not TierCheck.On() then return nil, "off" end
    if call(InCombatLockdown) then return nil, "in combat" end
    local read, why
    if not craft and type(C_TradeSkillUI) == "table" then
        read, why = modernRecipes()
    else
        read, why = classicRecipes(craft)
    end
    if not read then return nil, why end
    if not read.rank or #read.recipes == 0 then return nil, "no learned recipes read" end
    local record = { rank = read.rank, at = call(GetServerTime) or time(), recipes = #read.recipes, source = read.source,
        reagents = TierCheck.Summarize(read.recipes, read.skillLine, classOf) }
    local records = TierCheck.Records()
    local key = charKey()
    records[key] = type(records[key]) == "table" and records[key] or {}
    records[key][read.skillLine] = record
    local findings = TierCheck.Findings(read.skillLine, record)
    -- The comparison is saved with the read, so the SavedVariables file holds the answer for a reader
    -- outside the game (rl-companion) without the tier table or /mw report.
    record.profession, record.skillLine, record.version = professionName(read.skillLine), read.skillLine, ns.VERSION
    record.findings = {}
    for _, f in ipairs(findings) do
        record.findings[#record.findings + 1] = { itemID = f.itemID, name = f.name, doneAt = f.at, recipe = f.recipe,
            difficulty = f.difficulty, color = TierCheck.COLORS[f.difficulty], via = f.via,
            text = TierCheck.FindingText(f, record.rank) }
    end
    local sig = string.format("%d:%d:%d", record.rank, record.recipes, #findings)
    if lastLogged[read.skillLine] ~= sig then
        lastLogged[read.skillLine] = sig
        ns.Log.Add("tiercheck", "%s %d: %d learned recipes read (%s), %d material(s) still used past the table",
            tostring(professionName(read.skillLine)), record.rank, record.recipes, record.source, #findings)
    end
    return record
end

--- Mark this character's crafting professions (Characters.Professions entries) with `stillUsed`:
--- itemID -> { recipe, difficulty, via } for each material the table calls done that the latest window
--- read says a non-grey recipe still uses (Valuation.NeededBy keeps those). Nothing while switched off.
function TierCheck.Annotate(professions)
    if not TierCheck.On() then return professions end
    for _, p in ipairs(type(professions) == "table" and professions or {}) do
        if type(p) == "table" and p.skillLine and p.stillUsed == nil then
            local record = TierCheck.Latest(p.skillLine)
            if record then
                local used = {}
                for _, f in ipairs(TierCheck.Findings(p.skillLine, record)) do
                    used[f.itemID] = { recipe = f.recipe, difficulty = f.difficulty, via = f.via }
                end
                p.stillUsed = used
            end
        end
    end
    return professions
end

--- The /mw report lines: one per read (character, profession), then one per finding.
function TierCheck.ReportLines()
    if not TierCheck.On() then return { "tier check: off (/mw feature tierCheck on, then /reload)" } end
    local lines = {}
    local keys = {}
    for key in pairs(TierCheck.Records()) do keys[#keys + 1] = key end
    table.sort(keys)
    for _, key in ipairs(keys) do
        local ids = {}
        for id in pairs(TierCheck.Records()[key]) do ids[#ids + 1] = id end
        table.sort(ids)
        for _, id in ipairs(ids) do
            local record = TierCheck.Records()[key][id]
            local findings = TierCheck.Findings(id, record)
            lines[#lines + 1] = string.format("tier check: %s %s %s read %s (%s learned recipes, %s): %s",
                tostring(key:match("^[^|]*")), tostring(professionName(id) or id), tostring(record.rank),
                date("%Y-%m-%d %H:%M", tonumber(record.at) or 0), tostring(record.recipes), tostring(record.source),
                #findings == 0 and "matches the table" or (#findings .. " material(s) still used past the table"))
            for _, f in ipairs(findings) do lines[#lines + 1] = TierCheck.FindingText(f, record.rank) end
        end
    end
    if #lines == 0 then
        lines[1] = "tier check: no profession window read yet (open one of your crafting professions)"
    end
    return lines
end

-- Events: the window opening, its list changing (skill-ups, new recipes), and Classic's craft window
-- (Enchanting). Event names a client doesn't know fail to register quietly (ns.On's pcall).
-- Bursts (a list update per craft) are read once, half a second after the last one.
local pending = {}
local function schedule(craft)
    if not TierCheck.On() or pending[craft] then return end
    pending[craft] = true
    C_Timer.After(0.5, function()
        pending[craft] = nil
        TierCheck.Scan(craft)
    end)
end
for _, event in ipairs({ "TRADE_SKILL_SHOW", "TRADE_SKILL_LIST_UPDATE", "TRADE_SKILL_DATA_SOURCE_CHANGED",
    "TRADE_SKILL_UPDATE" }) do
    ns.On(event, function() schedule(false) end)
end
for _, event in ipairs({ "CRAFT_SHOW", "CRAFT_UPDATE" }) do
    ns.On(event, function() schedule(true) end)
end
