-- Class-only items (operator, 2026-11-08: "this is a mage only item, id like to be able to
-- friend mail these types of items too"): a "Scroll: VOCE WELL" says "Classes: Mage" in its
-- tooltip, so a Warrior can't use it but a mage friend can. A class binding (Routes, "Mage
-- items to Bob") mails such items to a player of that class.
--
-- API (Forever's source, Ketho/wow-ui-source-forever): C_TooltipInfo.GetItemByID(itemID) ->
-- { lines = { { type, leftText, ... } } } (TooltipInfoDocumentation.lua); the class line is
-- TooltipDataLineType.UsageRequirement with requirement type RaceClass
-- (TooltipInfoSharedDocumentation.lua, read the same way in Blizzard_PerksProgramElements.lua),
-- its text ITEM_CLASSES_ALLOWED ("Classes: %s", as the wardrobe formats it). Class names map to
-- tokens through LOCALIZED_CLASS_NAMES_MALE / _FEMALE, else the English names. Every call is
-- pcall'd; an item whose tooltip data isn't loaded yet has no answer and is asked again later.
local _, ns = ...

local Classes = {}
ns.Classes = Classes

-- Classic's classes: token -> English name, and the class IDs (fixed since 1.x) C_Club gives.
Classes.NAMES = {
    WARRIOR = "Warrior", PALADIN = "Paladin", HUNTER = "Hunter", ROGUE = "Rogue", PRIEST = "Priest",
    SHAMAN = "Shaman", MAGE = "Mage", WARLOCK = "Warlock", DRUID = "Druid",
}
Classes.BY_ID = { [1] = "WARRIOR", [2] = "PALADIN", [3] = "HUNTER", [4] = "ROGUE", [5] = "PRIEST",
    [7] = "SHAMAN", [8] = "MAGE", [9] = "WARLOCK", [11] = "DRUID" }
Classes.ORDER = { "DRUID", "HUNTER", "MAGE", "PALADIN", "PRIEST", "ROGUE", "SHAMAN", "WARLOCK", "WARRIOR" }

local cache = {} -- itemID -> set of tokens (only a class line found is kept: see Classes.Of)

local function call(fn, ...)
    if type(fn) ~= "function" then return nil end
    local results = { pcall(fn, ...) }
    if not results[1] then return nil end
    return unpack(results, 2, table.maxn(results))
end

--- The class name the player sees ("Mage") for a token, or nil.
function Classes.Name(token)
    token = type(token) == "string" and token:upper() or nil
    if not token or not Classes.NAMES[token] then return nil end
    local localized = rawget(_G, "LOCALIZED_CLASS_NAMES_MALE")
    return type(localized) == "table" and localized[token] or Classes.NAMES[token]
end

--- A class token from a token, an English or localized name, or a C_Club class ID; nil otherwise.
function Classes.Token(value)
    if type(value) == "number" then return Classes.BY_ID[value] end
    if type(value) ~= "string" then return nil end
    local trimmed = value:match("^%s*(.-)%s*$")
    local upper = trimmed:upper()
    if Classes.NAMES[upper] then return upper end
    for _, tableName in ipairs({ "LOCALIZED_CLASS_NAMES_MALE", "LOCALIZED_CLASS_NAMES_FEMALE" }) do
        local names = rawget(_G, tableName)
        for token, name in pairs(type(names) == "table" and names or {}) do
            if type(name) == "string" and name:lower() == trimmed:lower() and Classes.NAMES[token] then return token end
        end
    end
    for token, name in pairs(Classes.NAMES) do
        if name:lower() == trimmed:lower() then return token end
    end
    return nil
end

--- Pure: the class tokens a tooltip line names ("Classes: Mage, Warlock" -> { MAGE = true, WARLOCK = true }),
--- or nil when it isn't the class line. `format` is ITEM_CLASSES_ALLOWED ("Classes: %s").
function Classes.Parse(text, format)
    if type(text) ~= "string" then return nil end
    format = type(format) == "string" and format or "Classes: %s"
    local prefix = format:gsub("%%s.*$", "")
    if prefix == "" or text:sub(1, #prefix) ~= prefix then return nil end
    local set, any = {}, false
    for part in text:sub(#prefix + 1):gmatch("[^,]+") do
        local token = Classes.Token(part)
        if token then set[token], any = true, true end
    end
    return any and set or nil
end

-- The texts of a tooltip data line (surfaced fields, or the args of an older client).
local function lineText(line)
    if type(line) ~= "table" then return nil end
    if type(line.leftText) == "string" then return line.leftText end
    for _, arg in ipairs(type(line.args) == "table" and line.args or {}) do
        if type(arg) == "table" and arg.field == "leftText" then return arg.stringVal end
    end
    return nil
end

--- The classes that may use an item ({ MAGE = true }), false when anyone can, nil when the
--- game hasn't loaded its tooltip yet. Only a found class line is cached: tooltip data can
--- arrive in parts (a name line first), so "anyone" is asked again next scan (Codex review).
function Classes.Of(itemID)
    itemID = tonumber(itemID)
    if not itemID then return nil end
    if cache[itemID] ~= nil then return cache[itemID] end
    local info = rawget(_G, "C_TooltipInfo")
    local data = type(info) == "table" and call(info.GetItemByID, itemID) or nil
    if type(data) ~= "table" or type(data.lines) ~= "table" or #data.lines == 0 then return nil end
    local format = rawget(_G, "ITEM_CLASSES_ALLOWED")
    local found = false
    for _, line in ipairs(data.lines) do
        local set = Classes.Parse(lineText(line), format)
        if set then found = set break end
    end
    if found then cache[itemID] = found end
    return found
end

--- This character's class token ("WARRIOR"), or nil.
function Classes.Mine()
    local _, token = call(rawget(_G, "UnitClass"), "player")
    return Classes.Token(token)
end

--- Pure: an item restricted to `token`'s class that this character (`mine`) can't use. `classes`
--- is Classes.Of's answer.
function Classes.ForOther(classes, token, mine)
    return type(classes) == "table" and token ~= nil and classes[token] == true and not (mine and classes[mine])
end

function Classes.Forget() cache = {} end
