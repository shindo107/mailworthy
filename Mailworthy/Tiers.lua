-- Material tiers (operator, 2026-11-06: "I just got my first aid to 80, which is a
-- threshold to where I shouldn't be using linen cloth anymore ... I want this same
-- methodology applied to all crafting materials"). The skill at which a crafting
-- profession is done with a material. From that skill on:
--   - this character's own profession no longer keeps it (Valuation.NeededBy), so it
--     is valued like anything else, or goes to a binding whose player still needs it;
--   - a binding no longer takes it once the bound player's skill (their Mailworthy's
--     "S2" message, the guild roster, or this account's own character) is past it
--     (Routes.Matches): it goes to the bank alt on the normal rule.
--
-- Which skill (research 2026-11-06, every Forever recipe of every crafting profession:
-- zockify's Forever tables from client 1.60.1.70790, Tailoring and Blacksmithing also against
-- the client's DB2 tables; item IDs on Wowhead's Forever tooltips; tools/tiers/data.py):
--   - First Aid cloth: where the next bandage is learnable (the operator's rule: Linen 80).
--   - everything else: where the last non-holiday recipe using the material, directly or through
--     a part the profession makes (bolts, cured hides, grinding stones, blasting powders, tubes),
--     turns grey. One-off gear-into-gear chains (Engineering's goggles) don't count.
--   - leather up-conversions (4 Light Leather -> 1 Medium): the leather's own recipes, then kept
--     while converting pays more than selling (WorthConverting, auction prices).
-- No row = never outgrown: a grey of 300 or more (used at the cap). Materials outside a
-- profession's subclasses are kept only while levelling (KEEP, rows below 300; operator
-- 2026-11-06), and Alchemy herbs that still make level-60 potions have no row (operator).
-- All of it only while "Keep my professions' materials" is on. Switch: /mw feature tiers off.
local _, ns = ...

local Tiers = {}
ns.Tiers = Tiers

-- The data (generated from the research: tools/tiers/build.py) is in TierData.lua:
-- DONE[skill line] = { { itemID, skill, name }, ... }, KEEP[skill line] = { [itemID] = true }
-- (kept beyond the profession's subclasses), CONVERT[skill line][itemID] = { into, count, name }.
Tiers.DONE, Tiers.KEEP, Tiers.CONVERT = {}, {}, {}

local byItem -- profession -> itemID -> { at, name }
local function index()
    if byItem then return byItem end
    byItem = {}
    for profession, rows in pairs(Tiers.DONE) do
        byItem[profession] = {}
        for _, row in ipairs(rows) do byItem[profession][row[1]] = { at = row[2], name = row[3] } end
    end
    return byItem
end

--- Pure: the skill at which `profession` is done with `itemID`, or nil (never).
function Tiers.Threshold(profession, itemID)
    local rows = index()[tonumber(profession) or -1]
    local row = rows and rows[tonumber(itemID) or -1]
    return row and row.at or nil
end

--- Pure: true when a `skill` in `profession` is past the item (nil skill: unknown, not past).
function Tiers.Outgrown(profession, itemID, skill)
    local at = Tiers.Threshold(profession, itemID)
    return at ~= nil and tonumber(skill) ~= nil and tonumber(skill) >= at
end

--- Pure: the names of the materials a `skill` in `profession` is past, in tier order.
function Tiers.OutgrownNames(profession, skill)
    local names = {}
    for _, row in ipairs(Tiers.DONE[tonumber(profession) or -1] or {}) do
        if tonumber(skill) and tonumber(skill) >= row[2] then names[#names + 1] = row[3] end
    end
    return names
end

--- Pure: "Linen Cloth, Peacebloom, Briarthorn and 4 more" (the latest outgrown first), or "".
function Tiers.PastText(profession, skill, max)
    local names, out = Tiers.OutgrownNames(profession, skill), {}
    max = max or 3
    for i = #names, math.max(1, #names - max + 1), -1 do out[#out + 1] = names[i] end
    local text = table.concat(out, ", ")
    if #names > max then text = text .. " and " .. (#names - max) .. " more" end
    return text
end

--- Pure: how many thresholds in `profession` a `skill` has crossed (a "tier step").
function Tiers.Step(profession, skill)
    return #Tiers.OutgrownNames(profession, skill)
end

--- Pure: past its own recipes, a material the profession can convert up (4 Light Leather make a
--- Medium Leather) is kept while converting pays more at the auction house than selling
--- (operator, 2026-11-06: "if the price is right we sell it, otherwise convert"). `priceOf(itemID)`
--- gives a unit auction price or nil. Returns the conversion { into, count, name } when it pays,
--- or when a price is missing (can't tell: kept, as before); nil when selling pays at least as much
--- or there is no conversion.
function Tiers.WorthConverting(profession, itemID, priceOf)
    local c = (Tiers.CONVERT[tonumber(profession) or -1] or {})[tonumber(itemID) or -1]
    if not c then return nil end
    local raw = type(priceOf) == "function" and tonumber(priceOf(itemID)) or nil
    local product = type(priceOf) == "function" and tonumber(priceOf(c.into)) or nil
    if raw == nil or product == nil then return c end
    if raw * c.count >= product then return nil end
    return c
end

function Tiers.On() return ns.Features.On("tiers") end

