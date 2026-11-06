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
-- Which skill (research 2026-11-06, Forever client data 1.60.1 via zockify's recipe
-- tables and the wow-professions.com Forever guides; Forever's recipes are NOT Classic
-- 1.15's: bolts, leathers and bars come 20-35 points earlier, and new recipe sets reuse
-- older materials at higher skill):
--   - First Aid: where the next cloth's bandage is learnable, the operator's rule (Wool
--     Bandage at 80, so Linen Cloth is done at 80); First Aid's cloth path is Classic's.
--   - every other profession: where the last normal recipe using the material turns grey
--     (Forever reuses older materials well past the levelling switch: Copper Bar in the
--     Sterling Silver Breastplate to 185). Holiday recipes are left out.
-- No row = never outgrown (kept as before): each line's last tier (Runecloth, Rugged
-- Leather, Thorium, Mithril, Dense / Solid Stone, Dream Dust and up), Alchemy (herbs stay
-- in use into Artisan) and Cooking (no tiers). Rows marked "est." rest on the guides
-- (the client tables cut off below ~60-125) and are rounded up. Pure data and functions.
-- Switch: /mw feature tiers off.
local _, ns = ...

local Tiers = {}
ns.Tiers = Tiers

-- profession skill line -> { { itemID, skill at which it's done, name }, ... } in tier order.
Tiers.DONE = {
    [129] = { -- First Aid: the next bandage's learn skill
        { 2589, 80, "Linen Cloth" },        -- Wool Bandage learn 80
        { 2592, 150, "Wool Cloth" },        -- Silk Bandage learn 150
        { 4306, 210, "Silk Cloth" },        -- Mageweave Bandage learn 210
        { 4338, 260, "Mageweave Cloth" },   -- Runecloth Bandage learn 260
    },
    [197] = { -- Tailoring: cloth and its bolt together (a tailor bolts cloth as needed)
        { 2589, 125, "Linen Cloth" },       -- est.: every route is on wool by 75-87
        { 2996, 125, "Bolt of Linen Cloth" },
        { 2592, 160, "Wool Cloth" },        -- Phoenix Gloves / Pants grey 160
        { 2997, 160, "Bolt of Woolen Cloth" },
        { 4306, 220, "Silk Cloth" },        -- Crimson Silk Gloves grey 220
        { 4305, 220, "Bolt of Silk Cloth" },
        { 4338, 250, "Mageweave Cloth" },   -- Nether Cuffs, Stormcloth Boots grey 250
        { 4339, 250, "Bolt of Mageweave" },
    },
    [165] = { -- Leatherworking
        { 2934, 175, "Ruined Leather Scraps" }, -- est.: nothing learnable at 125+ uses them
        { 2318, 175, "Light Leather" },
        { 783, 175, "Light Hide" },
        { 4231, 175, "Cured Light Hide" },
        { 2319, 175, "Medium Leather" },    -- Wisdom's / Totemic Leggings grey 170
        { 4232, 205, "Medium Hide" },       -- Mender's Mail Boots and others grey 205
        { 4233, 205, "Cured Medium Hide" },
        { 4234, 215, "Heavy Leather" },     -- Barbaric Belt, Mender's Leather Gloves grey 215
        { 4304, 255, "Thick Leather" },     -- Mender's Mail Gauntlets grey 255
        { 4235, 265, "Heavy Hide" },        -- Mender's Leather Bracers grey 265
        { 4236, 265, "Cured Heavy Hide" },
        { 8169, 290, "Thick Hide" },        -- Mender's Mail Belt grey 290
        { 8172, 290, "Cured Thick Hide" },
    },
    [164] = { -- Blacksmithing: an ore with its bar (Copper and Tin go into Bronze)
        { 2835, 155, "Rough Stone" },       -- Ironforge Breastplate (Rough Grinding Stone) grey 155
        { 2840, 185, "Copper Bar" },        -- Sterling Silver Breastplate grey 185
        { 2770, 185, "Copper Ore" },
        { 3576, 185, "Tin Bar" },
        { 2771, 185, "Tin Ore" },
        { 2841, 185, "Bronze Bar" },        -- Bronze Warhammer grey 185
        { 2836, 185, "Coarse Stone" },      -- Veteran's Silvered Chain Leggings grey 185
        { 3575, 230, "Iron Bar" },          -- into Steel: Steel Plate Helm grey 230
        { 2772, 230, "Iron Ore" },
        { 3859, 230, "Steel Bar" },
        { 2838, 260, "Heavy Stone" },       -- Shining Mithril Pants (Heavy Grinding Stone) grey 260
    },
    [202] = { -- Engineering: its parts keep older bars in use, so late
        { 2835, 125, "Rough Stone" },       -- est.: Rough Blasting Powder users grey by ~65-110
        { 2840, 185, "Copper Bar" },        -- Clanking Cord (Copper Modulator) grey 185
        { 2836, 195, "Coarse Stone" },      -- SAF-T Bronze Bomb grey 195
        { 3859, 215, "Steel Bar" },         -- Gyromatic Micro-Adjustor grey 215
        { 2770, 240, "Copper Ore" },        -- smelts into Bronze
        { 3576, 240, "Tin Bar" },
        { 2771, 240, "Tin Ore" },
        { 2841, 240, "Bronze Bar" },        -- Mechanical Dragonling (Bronze Framework) grey 240
        { 2838, 245, "Heavy Stone" },       -- SAF-T Bomb grey 245
        { 3575, 265, "Iron Bar" },          -- SAF-T Bomb grey 245; 265 in case Gyrochronatom uses it
        { 2772, 265, "Iron Ore" },
    },
    [333] = { -- Enchanting: lesser and greater essences convert, so each pair together
        { 10978, 180, "Small Glimmering Shard" }, -- Cloak Lesser Protection grey 180
        { 10938, 180, "Lesser Magic Essence" },   -- Mystic Mushroom grey 180
        { 10939, 180, "Greater Magic Essence" },
        { 10940, 205, "Strange Dust" },           -- Chest Lesser Absorption grey 205
        { 10998, 215, "Lesser Astral Essence" },  -- Chest Minor Stats, Runed Golden Rod grey 215
        { 11082, 215, "Greater Astral Essence" },
        { 11084, 215, "Large Glimmering Shard" },
        { 11083, 230, "Soul Dust" },              -- Bracer Stamina and others grey 230
        { 11138, 235, "Small Glowing Shard" },    -- Lesser Beastslayer grey 235
        { 11134, 265, "Lesser Mystic Essence" },  -- Bracer Lesser Healing Power grey 265
        { 11135, 265, "Greater Mystic Essence" },
        { 11139, 280, "Large Glowing Shard" },    -- 2H Lesser Strength grey 280
        { 11137, 285, "Vision Dust" },            -- Gloves Strength grey 285
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

