-- Material tiers (operator, 2026-11-06: "I just got my first aid to 80, which is a
-- threshold to where I shouldn't be using linen cloth anymore ... I want this same
-- methodology applied to all crafting materials"). A crafting profession stops
-- needing a material at the skill where the next tier's recipe becomes learnable,
-- the point Classic levelling guides switch materials (First Aid: Wool Bandage at 80,
-- so Linen Cloth is done at 80). From that skill on:
--   - this character's own profession no longer keeps it (Valuation.NeededBy), so it
--     is valued like anything else, or goes to a binding whose player still needs it;
--   - a binding no longer takes it once the bound player's skill (their Mailworthy's
--     "S2" message, the guild roster, or this account's own character) is past it
--     (Routes.Matches): it goes to the bank alt on the normal rule.
-- A material with no row here is never outgrown (kept as before): the last tier, and
-- anything still used in recipes made past the switch (docs/HANDOFF.md, research
-- 2026-11-06). Pure data and functions. Switch: /mw feature tiers off.
local _, ns = ...

local Tiers = {}
ns.Tiers = Tiers

-- profession skill line -> { { itemID, skill at which it's done, name }, ... } in tier order.
Tiers.DONE = {
    [129] = { -- First Aid
        { 2589, 80, "Linen Cloth" },        -- Wool Bandage requires 80
        { 2592, 150, "Wool Cloth" },        -- Silk Bandage requires 150
        { 4306, 210, "Silk Cloth" },        -- Mageweave Bandage requires 210
        { 4338, 260, "Mageweave Cloth" },   -- Runecloth Bandage requires 260
    },
}

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

--- Pure: how many thresholds in `profession` a `skill` has crossed (a "tier step").
function Tiers.Step(profession, skill)
    return #Tiers.OutgrownNames(profession, skill)
end

function Tiers.On() return ns.Features.On("tiers") end

