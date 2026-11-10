-- Conjured items (operator, 2026-11-10: "mailworthy tried to send a healthstone in my inventory
-- to my bank alt to ah ... should always be keep as they are ephemeral items"): a Healthstone is
-- a white item with no auction price, so the scan mailed it like any unpriced item. What a
-- warlock or a mage conjures disappears after 15 minutes logged out and can't be auctioned: it
-- stays in the bags, a hard keep (Valuation: "conjured item"), and like soulbound and quest
-- items the window doesn't list it.
--
-- Two ways to know one, either is enough:
-- 1. Classic's conjured items by ID (ITEMS; each checked against Wowhead Classic's tooltip,
--    2026-11-10: all say "Conjured Item"). No API involved, so it holds before item data loads.
-- 2. The tooltip's own "Conjured Item" line, for anything Forever adds: C_TooltipInfo.GetItemByID
--    (TooltipInfoDocumentation.lua on Forever, as Classes.lua reads it), a line whose text is
--    ITEM_CONJURED. Forever's source has no line type for it and its global strings aren't in
--    the source mirror, so the text is compared, with the English text as the fallback
--    (README "Beta unknowns"; /mw report says what was found). Every call is pcall'd.
--    A "not conjured" answer is remembered only once the item's data is loaded
--    (C_Item.IsItemDataCachedByID, ItemDocumentation.lua on Forever: until then the tooltip can
--    be a name line alone), and forgotten at each mailbox visit, so a scan doesn't build every
--    bag item's tooltip again (the window reads the bags every 2 seconds while its list is empty).
local _, ns = ...

local Conjured = {}
ns.Conjured = Conjured

Conjured.REASON = "conjured item" -- the verdict's reason (Valuation.Evaluate)
Conjured.LABEL = "Conjured Item"  -- ITEM_CONJURED in English

Conjured.ITEMS = {
    -- healthstones (three item IDs each: plain, and with Improved Healthstone 1 / 2)
    [5512] = "Minor Healthstone", [19004] = "Minor Healthstone", [19005] = "Minor Healthstone",
    [5511] = "Lesser Healthstone", [19006] = "Lesser Healthstone", [19007] = "Lesser Healthstone",
    [5509] = "Healthstone", [19008] = "Healthstone", [19009] = "Healthstone",
    [5510] = "Greater Healthstone", [19010] = "Greater Healthstone", [19011] = "Greater Healthstone",
    [9421] = "Major Healthstone", [19012] = "Major Healthstone", [19013] = "Major Healthstone",
    -- soulstones, spellstones, firestones
    [5232] = "Minor Soulstone", [16892] = "Lesser Soulstone", [16893] = "Soulstone",
    [16895] = "Greater Soulstone", [16896] = "Major Soulstone",
    [5522] = "Spellstone", [13602] = "Greater Spellstone", [13603] = "Major Spellstone",
    [1254] = "Lesser Firestone", [13699] = "Firestone", [13700] = "Greater Firestone", [13701] = "Major Firestone",
    -- mana gems
    [5514] = "Mana Agate", [5513] = "Mana Jade", [8007] = "Mana Citrine", [8008] = "Mana Ruby",
    -- conjured water
    [5350] = "Conjured Water", [2288] = "Conjured Fresh Water", [2136] = "Conjured Purified Water",
    [3772] = "Conjured Spring Water", [8077] = "Conjured Mineral Water", [8078] = "Conjured Sparkling Water",
    [8079] = "Conjured Crystal Water",
    -- conjured food
    [5349] = "Conjured Muffin", [1113] = "Conjured Bread", [1114] = "Conjured Rye", [1487] = "Conjured Pumpernickel",
    [8075] = "Conjured Sourdough", [8076] = "Conjured Sweet Roll", [22895] = "Conjured Cinnamon Roll",
}

-- itemID -> true (the tooltip has the line) / false (it doesn't, and the item's data was loaded)
local cache = {}

local function call(fn, ...)
    if type(fn) ~= "function" then return nil end
    local results = { pcall(fn, ...) }
    if not results[1] then return nil end
    return unpack(results, 2, table.maxn(results))
end

-- The text of a tooltip data line (surfaced field, or the args of an older client).
local function lineText(line)
    if type(line) ~= "table" then return nil end
    if type(line.leftText) == "string" then return line.leftText end
    for _, arg in ipairs(type(line.args) == "table" and line.args or {}) do
        if type(arg) == "table" and arg.field == "leftText" then return arg.stringVal end
    end
    return nil
end

--- Pure: is this tooltip line the "Conjured Item" line? `label` is ITEM_CONJURED (the client's
--- own text); colour codes (|cAARRGGBB, |cnNAME:) and spaces around it don't count.
function Conjured.IsLine(text, label)
    if type(text) ~= "string" then return false end
    label = type(label) == "string" and label ~= "" and label or Conjured.LABEL
    local plain = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|cn[^:|]+:", ""):gsub("|r", ""):match("^%s*(.-)%s*$")
    return plain == label
end

--- Pure: is this item ID one of Classic's conjured items?
function Conjured.Known(itemID)
    return Conjured.ITEMS[tonumber(itemID) or -1] ~= nil
end

-- Is the item's data loaded, so its tooltip is whole? Unknown (no such call) counts as no.
local function loaded(itemID)
    local items = rawget(_G, "C_Item")
    return type(items) == "table" and call(items.IsItemDataCachedByID, itemID) == true
end

--- Is this item conjured: a known ID, or its tooltip says so. false when neither; that answer
--- is asked again next time until the item's data is loaded.
function Conjured.Is(itemID)
    itemID = tonumber(itemID)
    if not itemID then return false end
    if Conjured.Known(itemID) then return true end
    if cache[itemID] ~= nil then return cache[itemID] end
    local info = rawget(_G, "C_TooltipInfo")
    local data = type(info) == "table" and call(info.GetItemByID, itemID) or nil
    if type(data) ~= "table" or type(data.lines) ~= "table" then return false end
    local label = rawget(_G, "ITEM_CONJURED")
    for _, line in ipairs(data.lines) do
        if Conjured.IsLine(lineText(line), label) then
            cache[itemID] = true
            return true
        end
    end
    if #data.lines > 0 and loaded(itemID) then cache[itemID] = false end
    return false
end

--- How an item is known to be conjured: "item ID", "tooltip", or nil when it isn't.
function Conjured.How(itemID)
    if Conjured.Known(itemID) then return "item ID" end
    return Conjured.Is(itemID) and "tooltip" or nil
end

--- /mw report: whether the client has the tooltip's text, and what in the bags counts as conjured.
function Conjured.ReportLines()
    local label = rawget(_G, "ITEM_CONJURED")
    local names, seen = {}, {}
    for _, s in ipairs(ns.Bags.Slots()) do
        local how = not seen[s.itemID] and Conjured.How(s.itemID) or nil
        seen[s.itemID] = true
        if how then names[#names + 1] = string.format("%s (%s)", tostring(s.link), how) end
    end
    return { string.format("conjured items (never mailed): %s; in your bags: %s",
        type(label) == "string" and ("ITEM_CONJURED = \"" .. label .. "\"")
            or "no ITEM_CONJURED text, comparing with \"" .. Conjured.LABEL .. "\"",
        #names > 0 and table.concat(names, ", ") or "none") }
end

--- Forget what the tooltips said ("not conjured" only, by default: a found line stays found).
function Conjured.Forget(all)
    if all then cache = {} return end
    for itemID, is in pairs(cache) do
        if is == false then cache[itemID] = nil end
    end
end

-- Each mailbox visit asks the tooltips again, once.
ns.On("MAIL_SHOW", function() Conjured.Forget() end)
