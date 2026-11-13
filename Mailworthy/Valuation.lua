-- The decision rule (docs/PLAN.md "Decision rule"): mail an item to the bank
-- alt when the auction house (after cut, deposit and postage) or disenchanting
-- beats the vendor by at least the minimum gain, or when there's no auction price yet
-- (Valuation.Unpriced); otherwise it stays in the bags.
-- Pure: no WoW API calls, so every case is a busted spec.
--
-- An item is every stack of one item link in the bags (so one item never
-- splits into "mail 20, keep 3"). Measured on Forever (2026-10-13):
--   deposit = floor(vendor value of the listing x 5%) x 1 / 4 / 12 for 2h / 8h / 24h,
--             at least 1s per listing (Forever's minimum: player report, 2026-11-07)
--   postage = 30c per attached stack
local _, ns = ...

local Valuation = {}
ns.Valuation = Valuation

Valuation.DEPOSIT_RATE = 0.05
-- Forever's minimum auction deposit (a player on CurseForge, 2026-11-07: "I didn't expect them to
-- make the minimum deposit 1 silver"). Counted per stack in the bags, each stack a listing: the
-- cautious reading while it's unverified whether it is per auction and the same for every
-- duration (README "Beta unknowns").
Valuation.MIN_DEPOSIT = 100
Valuation.MEDIAN_DAYS = 3        -- the smoothed price: median of the last 3 scanned days
Valuation.LAUNCH_EPOCH = 1793833200 -- Forever launch: 2026-11-04 15:00 PST (docs/ALGORITHM-RESEARCH.md)
Valuation.TRADE_GOODS = 7        -- item class: cloth, ore, herbs, leather, enchanting materials...
Valuation.RAID_DAY = 35          -- Dec 9, 2026: the first raids; enchanting mats, herbs, elementals sell from here
Valuation.BANK_UNTIL_DAY = 60    -- no Bank verdicts from this launch day on (research 4.4)
Valuation.BANK_RECOVERY = 1.5    -- a glut is banked when last week's median was 1.5x today's floor price
Valuation.INFLATION_DAYS = 180   -- after RAID_DAY the minimum gain grows by 1/180 per launch day (research 4.5) ...
Valuation.INFLATION_CAP = 2      -- ... up to twice the setting: vendor prices are fixed copper, gold inflates
Valuation.INEXACT_HAIRCUT = 0.10 -- off an inexact price (Auctionator matched a similar name)
Valuation.TREND_DAYS = 10        -- liquidity: the 3-day median against the median of scanned days 4-10
Valuation.GLUT_SUPPLY = 10       -- a glut: at least 10x our count listed ...
Valuation.GLUT_DROP = 0.25       -- ... and the recent median 25% or more under the older one
Valuation.DEPOSIT_MULTIPLIER = { 1, 4, 12 } -- AH durations 1 / 2 / 3 = 2h / 8h / 24h
Valuation.DURATION_HOURS = { 2, 8, 24 }

Valuation.DEFAULTS = {
    duration = 3,         -- 24h listing (operator, 2026-10-13)
    relistFactor = 0.5,   -- half the deposit counted: the game refunds it on a sale, and raw materials sell
                          -- (research 4.3); a glut counts it in full
    cut = 0.05,           -- AH cut, until a sale mail confirms it
    postage = 30,         -- copper per attached stack
    minGain = 100,        -- 1s (operator, 2026-11-07; was 5s) ...
    minGainPct = 0.25,    -- ... and 25% of the vendor value, both
    maxAgeDays = 7,       -- older Auctionator prices don't count
    disenchant = false,   -- Valuation.Settings switches it on when a disenchant addon is installed
    keepProfessionMats = true, -- materials this character's crafting professions use stay (operator, 2026-10-22)
    -- With keepProfessionMats: those materials wait on the bank alt instead of in this character's
    -- bank (the B tag, mailed like the other banked items; the Bank send switch gates them too).
    matsToBankAlt = false,
    sellGathered = false,      -- ... except what its gathering professions gather (operator, 2026-11-06: off by default)
    -- What Send takes of the bank alt's share, by verdict (Valuation.SEND; applied by Bags.ApplySendSwitches):
    sendAuction = true,    -- items for the auction house (the AH tag)
    sendDisenchant = true, -- items to disenchant (DE)
    sendBank = true,       -- items to bank for a later phase (B)
    sendVendor = false,    -- items a vendor pays more for (V): they stay unless the player wants them sent too
}

-- The setting behind each verdict tag (BankAlt.Verdict), in the order the settings window shows them.
Valuation.SEND = { ah = "sendAuction", de = "sendDisenchant", b = "sendBank", v = "sendVendor" }
Valuation.SEND_ORDER = { "ah", "de", "b", "v" }
Valuation.SEND_LABEL = { ah = "Auction", de = "Disenchant", b = "Bank", v = "Vendor" }
Valuation.SEND_TAG = { ah = "AH", de = "DE", b = "B", v = "V" } -- as the bag tags read (BankAlt.TAGS)
Valuation.VENDOR = "vendor" -- the route of a vendor (V) item mailed because sendVendor is on

-- What each crafting profession needs from the trade goods (class 7) in the bags, by
-- the profession's skill line ID (GetProfessionInfo's 7th return) and the item's
-- subclass (modern numbering, as Valuation.SUBCLASS: 1 parts, 2 explosives, 3 devices,
-- 5 cloth, 6 leather, 7 metal & stone, 8 meat and fish, 9 herbs, 12 enchanting).
-- Gathering professions (Mining, Herbalism, Skinning, Fishing) need nothing: what they
-- gather is what gets sold. Elemental materials are used by several professions in
-- small amounts and stay mailable (lock them to keep them).
Valuation.PROFESSION_MATS = {
    [164] = { name = "Blacksmithing", subclasses = { [7] = true }, mats = "metal and stone" },
    [202] = { name = "Engineering", subclasses = { [7] = true, [1] = true, [2] = true, [3] = true },
        mats = "metal and stone, parts, explosives, devices" },
    [165] = { name = "Leatherworking", subclasses = { [6] = true }, mats = "leather and hides" },
    [197] = { name = "Tailoring", subclasses = { [5] = true }, mats = "cloth" },
    [129] = { name = "First Aid", subclasses = { [5] = true },
        mats = "cloth, healing-potion herbs, venom sacs, leather, poultice reagents" },
    [171] = { name = "Alchemy", subclasses = { [9] = true }, mats = "herbs" },
    [333] = { name = "Enchanting", subclasses = { [12] = true }, mats = "dust, essences and shards" },
    [185] = { name = "Cooking", subclasses = { [8] = true }, mats = "meat and fish" },
}

-- Beyond the subclasses, the exact items each profession keeps (Tiers.KEEP, TierData.lua): on
-- Forever First Aid also makes potions, Anti-Venoms and Tourniquets; a blacksmith's gems, an
-- engineer's cloth, a cook's tea herbs ... while levelling (research and operator, 2026-11-06).
for id, p in pairs(Valuation.PROFESSION_MATS) do p.items = ns.Tiers.KEEP[id] end

-- What each gathering profession brings in, by skill line ID and trade-goods subclass. Used
-- only by the "Sell what I gather" setting (sellGathered, off by default): a miner who is
-- also a blacksmith, an herbalist who is also an alchemist, ... mails what they gather to
-- be sold instead of keeping it for the crafting profession (operator, 2026-11-06: "some
-- players use gathering professions simply to gather materials to send to the ah").
-- Mining covers all of metal & stone (ore, stone, and the bars its own smelting makes).
Valuation.GATHERED_MATS = {
    [186] = { name = "Mining", subclasses = { [7] = true }, mats = "metal and stone" },
    [182] = { name = "Herbalism", subclasses = { [9] = true }, mats = "herbs" },
    [393] = { name = "Skinning", subclasses = { [6] = true }, mats = "leather and hides" },
    [356] = { name = "Fishing", subclasses = { [8] = true }, mats = "fish" },
}

--- Pure: the gathering professions among `professions` (ids or { skillLine = } entries).
function Valuation.GatheringProfessions(professions)
    local list = {}
    for _, p in ipairs(type(professions) == "table" and professions or {}) do
        local id = type(p) == "table" and p.skillLine or p
        local known = Valuation.GATHERED_MATS[tonumber(id) or -1]
        if known then list[#list + 1] = known end
    end
    return list
end

--- Pure: the name of this character's gathering profession that brings in the item, or nil.
function Valuation.GatheredBy(item, professions)
    if item.classID ~= Valuation.TRADE_GOODS then return nil end
    for _, p in ipairs(Valuation.GatheringProfessions(professions)) do
        if p.subclasses[item.subclassID] then return p.name end
    end
    return nil
end

--- Pure: the crafting professions among `professions` (a list of skill line IDs, or of
--- { skillLine = ... } entries) that Mailworthy keeps materials for: { { name, mats }, ... }.
function Valuation.CraftingProfessions(professions)
    local list = {}
    for _, p in ipairs(type(professions) == "table" and professions or {}) do
        local id = type(p) == "table" and p.skillLine or p
        local known = Valuation.PROFESSION_MATS[tonumber(id) or -1]
        if known then list[#list + 1] = known end
    end
    return list
end

--- Pure: a crafting profession (a PROFESSION_MATS entry) uses the item: a trade good of one
--- of its subclasses, or one of its listed `items` (by item ID, whatever its class).
function Valuation.Uses(p, item)
    if type(p) ~= "table" then return false end
    if p.items and p.items[tonumber(item.itemID) or -1] then return true end
    return item.classID == Valuation.TRADE_GOODS and p.subclasses[item.subclassID] == true
end

--- Pure: the name of this character's crafting profession that uses the item, or nil.
--- A profession whose skill (`rank` in a { skillLine, rank } entry) is past the item
--- (Tiers: Linen Cloth is done for First Aid at 80) doesn't count, unless `tiers` is
--- false. Second return: { name, skill } of the first profession past it, when none
--- needs it; third: the skill at which the needing profession will be done with it; fourth:
--- the conversion ({ into, count, name }) when it's past its own recipes but converting it pays
--- (Tiers.WorthConverting with `priceOf`, an itemID -> unit auction price function); fifth: the
--- non-grey recipe ({ recipe, difficulty, via }) the profession window last showed still using a
--- material the table calls done (the entry's `stillUsed`, TierCheck.Annotate): it stays.
function Valuation.NeededBy(item, professions, tiers, priceOf)
    local outgrown
    for _, p in ipairs(type(professions) == "table" and professions or {}) do
        local id = tonumber(type(p) == "table" and p.skillLine or p)
        local known = Valuation.PROFESSION_MATS[id or -1]
        if Valuation.Uses(known, item) then
            local rank = type(p) == "table" and tonumber(p.rank) or nil
            local outgrownHere = tiers ~= false and ns.Tiers.Outgrown(id, item.itemID, rank)
            local window = outgrownHere and type(p.stillUsed) == "table" and p.stillUsed[tonumber(item.itemID) or -1] or nil
            local convert = outgrownHere and not window and ns.Tiers.WorthConverting(id, item.itemID, priceOf) or nil
            if window then
                return known.name, nil, nil, nil, window
            elseif convert then
                return known.name, nil, nil, convert
            elseif outgrownHere then
                outgrown = outgrown or { name = known.name, skill = rank }
            else
                return known.name, nil, tiers ~= false and ns.Tiers.Threshold(id, item.itemID) or nil
            end
        end
    end
    return nil, outgrown
end

--- Pure: days since the realm launched (0 before launch and on launch day). `now` is
--- the server time; `firstSeen` the first server time Mailworthy saw this realm, which
--- stands in for the launch of any realm that opens later than Forever's first wave.
function Valuation.ServerDay(now, firstSeen)
    now = tonumber(now)
    if not now then return nil end
    local launch = Valuation.LAUNCH_EPOCH
    if tonumber(firstSeen) and firstSeen < launch then launch = firstSeen end
    return math.max(0, math.floor((now - launch) / 86400))
end

-- Unpriced items (operator, 2026-11-08: "going to the bank alt on no data is better than holding
-- on the main"): with an auction price source installed but no auction price for an item, it is
-- mailed to the bank alt (route NO_PRICE, chip "No price") to wait there for one, instead of
-- staying in the bags. Grey junk stays for the vendor; a failed price call is never "no price
-- yet" (AGENTS safety): that item stays. The hard keeps (locked, soulbound, quest, conjured, a
-- quest needs it, in use, tools) and the profession keep come first, as for everything.
Valuation.NO_PRICE = "noprice"
Valuation.UNPRICED_GEAR = true -- unpriced green / blue weapons and armor go too (see the PR's questions)

-- Staple trade goods ("flat rules for certain common tradegoods", operator, 2026-11-08): what
-- always sells above a vendor on any realm, at any level. Used only when there's no auction
-- price: then the item is mailed as a common item ("always mail", never an invented copper
-- value), with the Bank verdict (BankReason: late-demand goods before the first raids) on top.
-- Without any price source too, whatever its quality (the green and blue essences, shards and
-- elemental essences, which the white-items rule would keep). Replaces the launch-days 0-13
-- exception for white trade goods (2026-10-20). Classic item IDs (cross-checked with TierData.lua,
-- Disenchant.lua and Stale.lua where they appear there).
Valuation.STAPLES = {
    -- cloth
    [2589] = "Linen Cloth", [2592] = "Wool Cloth", [4306] = "Silk Cloth", [4338] = "Mageweave Cloth",
    [14047] = "Runecloth", [14256] = "Felcloth",
    -- leather and hides
    [2934] = "Ruined Leather Scraps", [2318] = "Light Leather", [2319] = "Medium Leather", [4234] = "Heavy Leather",
    [4304] = "Thick Leather", [8170] = "Rugged Leather", [783] = "Light Hide", [4232] = "Medium Hide",
    [4235] = "Heavy Hide", [8169] = "Thick Hide", [8171] = "Rugged Hide",
    -- ore, bars and stone
    [2770] = "Copper Ore", [2771] = "Tin Ore", [2772] = "Iron Ore", [2775] = "Silver Ore", [2776] = "Gold Ore",
    [3858] = "Mithril Ore", [7911] = "Truesilver Ore", [10620] = "Thorium Ore", [11370] = "Dark Iron Ore",
    [2840] = "Copper Bar", [3576] = "Tin Bar", [2841] = "Bronze Bar", [2842] = "Silver Bar", [3575] = "Iron Bar",
    [3577] = "Gold Bar", [3859] = "Steel Bar", [3860] = "Mithril Bar", [6037] = "Truesilver Bar", [12359] = "Thorium Bar",
    [2835] = "Rough Stone", [2836] = "Coarse Stone", [2838] = "Heavy Stone", [7912] = "Solid Stone", [12365] = "Dense Stone",
    -- herbs
    [2447] = "Peacebloom", [765] = "Silverleaf", [2449] = "Earthroot", [785] = "Mageroyal", [2450] = "Briarthorn",
    [3820] = "Stranglekelp", [2453] = "Bruiseweed", [3355] = "Wild Steelbloom", [3369] = "Grave Moss",
    [3356] = "Kingsblood", [3357] = "Liferoot", [3818] = "Fadeleaf", [3821] = "Goldthorn", [3358] = "Khadgar's Whisker",
    [3819] = "Wintersbite", [4625] = "Firebloom", [8831] = "Purple Lotus", [8836] = "Arthas' Tears", [8838] = "Sungrass",
    [8839] = "Blindweed", [8845] = "Ghost Mushroom", [8846] = "Gromsblood", [13464] = "Golden Sansam",
    [13463] = "Dreamfoil", [13465] = "Mountain Silversage", [13466] = "Plaguebloom", [13467] = "Icecap",
    [13468] = "Black Lotus",
    -- elemental
    [7067] = "Elemental Earth", [7068] = "Elemental Fire", [7069] = "Elemental Air", [7070] = "Elemental Water",
    [7075] = "Core of Earth", [7076] = "Essence of Earth", [7077] = "Heart of Fire", [7078] = "Essence of Fire",
    [7079] = "Globe of Water", [7080] = "Essence of Water", [7081] = "Breath of Wind", [7082] = "Essence of Air",
    [7972] = "Ichor of Undeath", [12803] = "Living Essence", [12808] = "Essence of Undeath",
    -- enchanting
    [10940] = "Strange Dust", [11083] = "Soul Dust", [11137] = "Vision Dust", [11176] = "Dream Dust",
    [16204] = "Illusion Dust", [10938] = "Lesser Magic Essence", [10939] = "Greater Magic Essence",
    [10998] = "Lesser Astral Essence", [11082] = "Greater Astral Essence", [11134] = "Lesser Mystic Essence",
    [11135] = "Greater Mystic Essence", [11174] = "Lesser Nether Essence", [11175] = "Greater Nether Essence",
    [16202] = "Lesser Eternal Essence", [16203] = "Greater Eternal Essence", [10978] = "Small Glimmering Shard",
    [11084] = "Large Glimmering Shard", [11138] = "Small Glowing Shard", [11139] = "Large Glowing Shard",
    [11177] = "Small Radiant Shard", [11178] = "Large Radiant Shard", [14343] = "Small Brilliant Shard",
    [14344] = "Large Brilliant Shard",
}

function Valuation.IsStaple(item)
    return Valuation.STAPLES[tonumber(item.itemID) or -1] ~= nil
end

-- Recipes (item class 9) by subclass (Enum.ItemRecipeSubclass, Blizzard_APIDocumentationGenerated/
-- ItemConstantsDocumentation.lua on Forever): the crafting profession (skill line ID, as
-- PROFESSION_MATS) that learns it. Books (0) and Fishing (9) have no crafting profession: they
-- follow the normal rule. A profession binding takes its recipes (Routes.Matches).
Valuation.RECIPE = 9
Valuation.RECIPE_PROFESSION = {
    [1] = 165, [2] = 197, [3] = 202, [4] = 164, [5] = 185, [6] = 171, [7] = 129, [8] = 333,
}

--- Pure: the crafting profession (skill line ID) that learns a recipe, or nil.
function Valuation.RecipeProfession(item)
    if item.classID ~= Valuation.RECIPE then return nil end
    return Valuation.RECIPE_PROFESSION[tonumber(item.subclassID) or -1]
end

-- Research 4.4: trade goods whose demand comes with the level-60 crowd and the first
-- raids, not while everyone levels. Subclasses use the modern client's numbering.
Valuation.SUBCLASS = { METAL = 7, HERB = 9, ELEMENTAL = 10, ENCHANTING = 12 }
Valuation.STARTER_HERBS = { -- sold now: levelling alchemists want them, and the player needs the gold
    [2447] = "Peacebloom", [765] = "Silverleaf", [2449] = "Earthroot", [785] = "Mageroyal",
    [2450] = "Briarthorn", [3820] = "Stranglekelp",
}
Valuation.LATE_METALS = {
    [3858] = "Mithril Ore", [3860] = "Mithril Bar", [7911] = "Truesilver Ore", [6037] = "Truesilver Bar",
    [10620] = "Thorium Ore", [12359] = "Thorium Bar", [11370] = "Dark Iron Ore", [11371] = "Dark Iron Bar",
    [12360] = "Arcanite Bar",
}

--- Pure: what kind of late-demand item this is ("enchanting materials", "herbs", "elemental
--- materials", "high-level metal"), or nil for everything that sells now.
function Valuation.LateDemand(item)
    if item.classID ~= Valuation.TRADE_GOODS then return nil end
    local sub = item.subclassID
    if sub == Valuation.SUBCLASS.ENCHANTING then return "enchanting materials" end
    if sub == Valuation.SUBCLASS.ELEMENTAL then return "elemental materials" end
    if sub == Valuation.SUBCLASS.HERB and not Valuation.STARTER_HERBS[item.itemID] then return "herbs" end
    if Valuation.LATE_METALS[item.itemID] then return "high-level metal" end
    return nil
end

--- Pure: for an item that is being mailed for the auction house (or as a common item):
--- the reason to bank it on the alt instead of listing it now, or nil. Before the first
--- raids, late-demand trade goods; until BANK_UNTIL_DAY, a glut that was worth 1.5x more
--- last week. Never without a known server day, never for disenchanting.
function Valuation.BankReason(item, r, settings)
    local day = tonumber(settings and settings.serverDay)
    if day == nil or day >= Valuation.BANK_UNTIL_DAY then return nil end
    if day < Valuation.RAID_DAY then
        local what = Valuation.LateDemand(item)
        if what then return string.format("bank: %s sell once raids open (launch day %d)", what, Valuation.RAID_DAY) end
    end
    local L = r and r.liquidity
    if item.classID == Valuation.TRADE_GOODS and L and L.glut and L.older and r.ahUnit
        and L.older >= Valuation.BANK_RECOVERY * r.ahUnit then
        return string.format("bank: the market is flooded (%d listed, %+d%% vs last week)", L.available,
            math.floor(L.trend * 100 + 0.5))
    end
    return nil
end

--- Settings for a scan: saved values over the defaults. The disenchant default
--- follows the disenchant addon (Siz DisenchantValue or Disenchantry installed)
--- until the player sets it (then their choice sticks).
function Valuation.Settings(saved, disenchantAddonInstalled)
    local s = {}
    for k, v in pairs(Valuation.DEFAULTS) do s[k] = v end
    s.disenchant = disenchantAddonInstalled == true
    for k, v in pairs(type(saved) == "table" and saved or {}) do
        if Valuation.DEFAULTS[k] ~= nil and type(v) == type(Valuation.DEFAULTS[k]) then s[k] = v end
    end
    if not Valuation.DEPOSIT_MULTIPLIER[s.duration] then s.duration = Valuation.DEFAULTS.duration end
    return s
end

--- Pure: the deposit for `count` items listed in `listings` auctions (default 1): the
--- vendor-based deposit, and never under Forever's minimum per listing.
function Valuation.Deposit(vendorUnit, count, duration, listings)
    local mult = Valuation.DEPOSIT_MULTIPLIER[duration] or Valuation.DEPOSIT_MULTIPLIER[Valuation.DEFAULTS.duration]
    local deposit = math.floor((vendorUnit or 0) * (count or 0) * Valuation.DEPOSIT_RATE) * mult
    return math.max(deposit, Valuation.MIN_DEPOSIT * math.max(1, tonumber(listings) or 1))
end

-- Profession tools stay in the bags whatever they'd sell for (the v0.2.0 scan
-- listed a Fishing Pole to mail). Classic item IDs; fishing poles also by class
-- (weapon, subclass 20).
Valuation.TOOLS = {
    [2901] = "Mining Pick", [5956] = "Blacksmith Hammer", [7005] = "Skinning Knife",
    [4471] = "Flint and Tinder", [6219] = "Arclight Spanner", [10498] = "Gyromatic Micro-Adjustor",
    [6218] = "Runed Copper Rod", [6339] = "Runed Silver Rod", [11130] = "Runed Golden Rod",
    [11145] = "Runed Truesilver Rod", [16207] = "Runed Arcanite Rod", [6256] = "Fishing Pole",
}
Valuation.FISHING_POLE_SUBCLASS = 20

function Valuation.IsTool(item)
    return Valuation.TOOLS[item.itemID] ~= nil
        or (item.classID == 2 and item.subclassID == Valuation.FISHING_POLE_SUBCLASS)
end

--- Conjured items (Conjured.lua: healthstones, mana gems, a mage's food and water) never leave
--- the bags: `item.conjured` (the bag scan's answer, which reads the tooltip too) or a known ID.
function Valuation.IsConjured(item)
    return item.conjured == true or ns.Conjured.Known(item.itemID)
end

--- Soulbound, quest and conjured items can never be mailed: the window doesn't list them.
function Valuation.Unmailable(result)
    return result.action == "keep" and (result.reason == "soulbound" or result.reason == "quest item"
        or result.reason == ns.Conjured.REASON)
end

--- Armor (class 4) or weapon (class 2), uncommon or better.
function Valuation.CanDisenchant(item)
    return (item.classID == 2 or item.classID == 4) and (item.quality or 0) >= 2
end

--- The unit price an item is valued at (docs/ALGORITHM-RESEARCH.md 4.1 / 4.7): the last
--- scan's price, or the median of the highest minimum buyout over the last MEDIAN_DAYS
--- scanned days when that is lower, so one empty-market spike in the latest scan can't make
--- a dud mailworthy. An inexact price loses INEXACT_HAIRCUT. Returns copper (nil without a
--- price) and the number of scanned days behind it (1 = the last scan alone).
local function median(list)
    local n = #list
    if n == 0 then return nil end
    table.sort(list)
    return n % 2 == 1 and list[(n + 1) / 2] or math.floor((list[n / 2] + list[n / 2 + 1]) / 2)
end

--- The scanned days of a price history (rows with a maxSeen), newest first.
local function scannedDays(price)
    local days = {}
    for _, row in ipairs(type(price) == "table" and type(price.history) == "table" and price.history or {}) do
        if type(row) == "table" and row.maxSeen then days[#days + 1] = row end
    end
    return days
end

--- `field` = "maxSeen" (default) or "minSeen" (a glut: the floor of the market).
--- The median only ever lowers the price: when the last scan is under it, the last scan wins
--- (a CurseForge report, 2026-11-07: "says silk cloth 5s30 while its 2s70"). Auctionator's
--- maxSeen is the day's HIGHEST minimum buyout, so on a falling market (a fresh realm) the
--- median of the last days' highs trails the market and over-values everything; the last
--- scan is what a listing competes with today, and it's the price Auctionator itself shows.
--- Third and fourth returns, when the last scan won: the median it beat and its days.
function Valuation.SmoothedPrice(price, field)
    if type(price) ~= "table" or price.ah == nil then return nil, 0 end
    local recent = {}
    for i, row in ipairs(scannedDays(price)) do
        if i > Valuation.MEDIAN_DAYS then break end
        recent[#recent + 1] = row[field or "maxSeen"] or row.maxSeen
    end
    local unit, scans, over, overDays = price.ah, 1, nil, nil
    if #recent >= 2 then
        local m = median(recent)
        if m <= price.ah then unit, scans = m, #recent else over, overDays = m, #recent end
    end
    if price.exact == false then unit = math.floor(unit * (1 - Valuation.INEXACT_HAIRCUT)) end
    return unit, scans, over, overDays
end

--- Pure (research 4.3): how the market for an item looks, from Auctionator's history.
--- { available = units listed at the last scan, recent / older = medians of the last 3 and
--- the previous 7 scanned days, trend = recent / older - 1 (nil with fewer than 2 + 2 days),
--- glut = at least GLUT_SUPPLY x `count` listed and the trend down GLUT_DROP or more }.
--- A glut is valued at the floor of the market with the deposit counted as lost.
function Valuation.Liquidity(price, count)
    local L = { available = type(price) == "table" and tonumber(price.available) or nil, glut = false }
    local recent, older = {}, {}
    for i, row in ipairs(scannedDays(price)) do
        if i <= Valuation.MEDIAN_DAYS then recent[#recent + 1] = row.maxSeen
        elseif i <= Valuation.TREND_DAYS then older[#older + 1] = row.maxSeen end
    end
    if #recent >= 2 and #older >= 2 then
        L.recent, L.older = median(recent), median(older)
        if L.older > 0 then L.trend = L.recent / L.older - 1 end
    end
    L.glut = L.available ~= nil and tonumber(count) ~= nil and L.available >= Valuation.GLUT_SUPPLY * count
        and L.trend ~= nil and L.trend <= -Valuation.GLUT_DROP
    return L
end

--- The minimum gain in force: the setting, grown with the server's age from RAID_DAY on
--- so the preview doesn't fill with 5s items the player no longer cares about.
function Valuation.MinGain(settings)
    local day = tonumber(settings.serverDay)
    local extraDays = math.max(0, (day or 0) - Valuation.RAID_DAY)
    local grown = settings.minGain + math.floor(settings.minGain * extraDays / Valuation.INFLATION_DAYS)
    return math.min(grown, settings.minGain * Valuation.INFLATION_CAP)
end

function Valuation.Threshold(vendorTotal, settings)
    return math.max(Valuation.MinGain(settings), math.ceil(vendorTotal * settings.minGainPct))
end

local function keep(reason, extra)
    local r = extra or {}
    r.action, r.reason = "keep", reason
    return r
end

--- A mail verdict; an auction / common route may turn into "bank" (listRoute keeps the original).
local function mail(route, reason, r, item, settings)
    r.action, r.route, r.reason = "mail", route, reason
    if route == "ah" or route == "common" then
        local why = Valuation.BankReason(item, r, settings)
        if why then r.listRoute, r.route, r.reason = route, "bank", why end
    end
    return r
end

--- Pure: a verdict that keeps an item for this character's own crafting, which the bank holds as
--- well as the bags (operator, 2026-11-11: "if the recommendation is to keep in my bag because some
--- profession needs it, it should recommend Banking"). Not one to convert: that's crafted now.
function Valuation.BankForCraft(r)
    return type(r) == "table" and r.action == "keep" and r.neededBy ~= nil and not r.convert
end

local evaluate

-- item.pin: Pins.BANK / Pins.VENDOR (Pins.lua loads before this file; kept apart so this stays pure)
Valuation.PIN_BANK = "bank"
Valuation.PIN_VENDOR = "vendor"
Valuation.VENDOR_PIN_REASON = "vendor: you pinned it" -- a hard keep (Routes.HARD_KEEPS)

--- item: { link, itemID, count, stacks, quality, classID, vendor (copper per unit; nil = not
---   loaded yet), bound, quest, conjured (Conjured.Is), questFor (the title of an active quest
---   that needs it), inUse (locked by the game), locked (Mailworthy lock), pin ("bank" / "vendor": Pins.lua) }
--- price: nil when there's no price source at all (no Auctionator); else
---   { ah = copper per unit or nil, age = days or nil, de = copper per item or nil }
---   history = Prices.History rows (optional), exact = true / false / nil }
--- Returns { action = "mail" | "keep", route = "ah" | "de" | "common" | "bank" | "noprice" (mail only;
---   Bags.ApplySendSwitches may add "vendor";
---   bank = mail it and hold it, listRoute = the route it would have had; noprice = no auction price
---   yet, the bank alt holds it), reason, failed (a "no price" keep: the price call failed),
---   vendor, deposit, depositCounted, postage, ahUnit (the smoothed unit price), median / medianDays
---   (the higher median the last scan beat, if it did), scans (days
---   behind it), liquidity (Valuation.Liquidity), ahNet, deNet, gain, threshold } (copper, totals).
function Valuation.Evaluate(item, price, settings)
    settings = settings or Valuation.DEFAULTS
    if item.locked then return keep("locked") end
    -- A vendor pin (Pins.lua): the player asked for this item to stay for the vendor and show V,
    -- soulbound or not (an outgrown quest reward: before the soulbound keep, so it gets the tag).
    -- It only ever keeps an item; a quest item, a quest's objective, a conjured item and an item
    -- in use keep their own reason, and without a vendor price there is nothing to vendor.
    if item.pin == Valuation.PIN_VENDOR and not item.quest and not item.questFor and not item.inUse
        and not Valuation.IsConjured(item) and (item.vendor or 0) > 0 then
        return keep(Valuation.VENDOR_PIN_REASON, { vendor = item.vendor * (item.count or 1), vendorPin = true })
    end
    if item.bound then return keep("soulbound") end
    if item.quest then return keep("quest item") end
    -- Conjured (a Healthstone, operator 2026-11-10): gone 15 minutes after logout, never mailed.
    if Valuation.IsConjured(item) then return keep(ns.Conjured.REASON) end
    -- An item an active quest's objective names (Quests.lua), quest item or not: never sold.
    if item.questFor then return keep("a quest needs it", { quest = item.questFor }) end
    if item.inUse then return keep("in use") end
    if Valuation.IsTool(item) then return keep("profession tool") end
    -- A bank pin (Pins.lua): the player asked for this item to always go to the bank alt and be
    -- banked there, whatever the market or a profession of this character says. Past every hard
    -- keep above, so a pin never mails what the rule wouldn't touch. It overrides the no-price-source
    -- rule and the grey junk rule (operator, 2026-11-13: "Pins override them"), not the item data
    -- hard keep or a failed price call.
    if item.pin == Valuation.PIN_BANK then
        if item.vendor == nil then return keep("item info not loaded yet") end
        if type(price) == "table" and price.failed then
            return keep("no price", { vendor = item.vendor * (item.count or 1), failed = true })
        end
        return { action = "mail", route = "bank", listRoute = "common", reason = "bank: you pinned it", pinned = true,
            vendor = (item.vendor or 0) * (item.count or 1), postage = (settings.postage or 0) * (item.stacks or 1) }
    end
    if settings.keepProfessionMats then
        local profession, _, untilSkill, convert, window = Valuation.NeededBy(item, settings.professions,
            settings.tiers, settings.priceOf)
        -- "Sell what I gather": what a gathering profession brought in is valued like anything else.
        if profession and not (settings.sellGathered and Valuation.GatheredBy(item, settings.professions)) then
            -- "On my bank alt": mailed there and banked, not kept here. Never one to convert (that
            -- is crafted now, here), never before the item's data or with a failed price call, and
            -- without a price source only what the rule mails then: white items and staples.
            if settings.matsToBankAlt and not convert and item.vendor ~= nil
                and not (type(price) == "table" and price.failed)
                and (price ~= nil or item.quality == 1 or ((item.quality or 0) >= 1 and Valuation.IsStaple(item))) then
                return { action = "mail", route = "bank", listRoute = "common", craftBank = true,
                    reason = "bank: your " .. profession .. " needs it", untilSkill = untilSkill, window = window,
                    neededBy = profession, vendor = item.vendor * (item.count or 1),
                    postage = (settings.postage or 0) * (item.stacks or 1) }
            end
            return keep("your " .. profession .. " needs it", { untilSkill = untilSkill, convert = convert,
                window = window, neededBy = profession })
        end
    end
    local r = evaluate(item, price, settings)
    if settings.keepProfessionMats and r.reason ~= "item info not loaded yet" then
        local _, outgrown = Valuation.NeededBy(item, settings.professions, settings.tiers, settings.priceOf)
        r.outgrown = outgrown -- "your First Aid (80) is past it", in the workings
    end
    return r
end

-- Evaluate past the hard keeps and the profession keep: price against vendor.
evaluate = function(item, price, settings)
    if item.vendor == nil then return keep("item info not loaded yet") end

    local n = item.count or 1
    local vendor = item.vendor * n
    local postage = settings.postage * (item.stacks or 1)

    if price == nil then
        -- No price source: mail plain white (common) items, keep the rest (operator, 2026-10-13),
        -- except the staple trade goods, whatever their quality (operator, 2026-11-08).
        if item.quality == 1 then
            return mail("common", "common item (no price data)", { vendor = vendor, postage = postage }, item, settings)
        end
        if (item.quality or 0) >= 1 and Valuation.IsStaple(item) then
            return mail("common", "staple trade good (no price data)", { vendor = vendor, postage = postage }, item, settings)
        end
        return keep(item.quality == 0 and "junk (no price data)" or "uncommon or better (no price data)",
            { vendor = vendor })
    end

    -- The auction price call failed: nothing is mailed on it, not even for a disenchant value
    -- (AGENTS safety: never when the price call failed; Codex review, 2026-11-08).
    if price.failed then return keep("no price", { vendor = vendor, failed = true }) end
    local r = { vendor = vendor, postage = postage }
    local stale = price.ah ~= nil and price.age ~= nil and price.age > settings.maxAgeDays
    if price.ah ~= nil and not stale then
        r.liquidity = Valuation.Liquidity(price, n)
        r.ahUnit, r.scans, r.median, r.medianDays = Valuation.SmoothedPrice(price,
            r.liquidity.glut and "minSeen" or nil)
        r.deposit = Valuation.Deposit(item.vendor, n, settings.duration, item.stacks)
        r.depositCounted = math.floor(r.deposit * (r.liquidity.glut and 1 or settings.relistFactor))
        r.ahNet = math.floor(r.ahUnit * n * (1 - settings.cut)) - r.depositCounted - postage
    end
    if settings.disenchant and price.de ~= nil and Valuation.CanDisenchant(item) then
        r.deNet = math.floor(price.de * n) - postage
    end
    if r.ahNet == nil and r.deNet == nil then
        return Valuation.Unpriced(item, price, vendor, postage, settings, stale and price.age or nil)
    end

    local best, route = r.ahNet, "ah"
    if r.deNet ~= nil and (best == nil or r.deNet > best) then best, route = r.deNet, "de" end
    r.gain = best - vendor
    r.threshold = Valuation.Threshold(vendor, settings)
    if r.gain >= r.threshold then
        return mail(route, route == "ah" and "auction house" or "disenchant", r, item, settings)
    end
    -- Disenchanting alone doesn't pay, and the auction house has no (current) price: it may still
    -- sell there, so it goes like any unpriced item.
    if price.ah == nil or stale then
        return Valuation.Unpriced(item, price, vendor, postage, settings, stale and price.age or nil)
    end
    return keep("not worth it", r)
end

--- Pure: the verdict for an item the price source has no auction price for, or only one older
--- than the age limit (`staleDays`: its age; operator, 2026-11-08: "Stale prices go too"): a
--- failed price call keeps it (never "no price yet"), grey junk stays for the vendor, a staple
--- trade good is mailed as a common item (Bank on top, BankReason), anything else goes to the bank
--- alt to wait for a price (route NO_PRICE). Unpriced gear only while UNPRICED_GEAR is on.
function Valuation.Unpriced(item, price, vendor, postage, settings, staleDays)
    if type(price) == "table" and price.failed then return keep("no price", { vendor = vendor, failed = true }) end
    if (item.quality or 0) == 0 then return keep("junk (no price data)", { vendor = vendor }) end
    local old = staleDays and string.format("auction price too old (%d days)", staleDays) or nil
    if Valuation.IsStaple(item) then
        return mail("common", staleDays and string.format("staple trade good (price %d days old)", staleDays)
            or "staple trade good (no price yet)", { vendor = vendor, postage = postage }, item, settings)
    end
    if not Valuation.UNPRICED_GEAR and Valuation.CanDisenchant(item) then return keep("no price", { vendor = vendor }) end
    return mail(Valuation.NO_PRICE, old or "no auction price yet", { vendor = vendor, postage = postage }, item, settings)
end

--- "1g 2s 3c", "-45c", "0c".
function Valuation.Money(copper)
    copper = math.floor((copper or 0) + 0.5)
    local sign = copper < 0 and "-" or ""
    copper = math.abs(copper)
    local g, s, c = math.floor(copper / 10000), math.floor(copper / 100) % 100, copper % 100
    local parts = {}
    if g > 0 then parts[#parts + 1] = g .. "g" end
    if s > 0 then parts[#parts + 1] = s .. "s" end
    if c > 0 or #parts == 0 then parts[#parts + 1] = c .. "c" end
    return sign .. table.concat(parts, " ")
end
