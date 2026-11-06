-- The decision rule (docs/PLAN.md "Decision rule"): mail an item to the bank
-- alt when the auction house (after cut, deposit and postage) or disenchanting
-- beats the vendor by at least the minimum gain; otherwise it stays in the bags.
-- Pure: no WoW API calls, so every case is a busted spec.
--
-- An item is every stack of one item link in the bags (so one item never
-- splits into "mail 20, keep 3"). Measured on Forever (2026-10-13):
--   deposit = floor(vendor value of the listing x 5%) x 1 / 4 / 12 for 2h / 8h / 24h
--   postage = 30c per attached stack
local _, ns = ...

local Valuation = {}
ns.Valuation = Valuation

Valuation.DEPOSIT_RATE = 0.05
Valuation.MEDIAN_DAYS = 3        -- the smoothed price: median of the last 3 scanned days
Valuation.LAUNCH_EPOCH = 1793833200 -- Forever launch: 2026-11-04 15:00 PST (docs/ALGORITHM-RESEARCH.md)
Valuation.FRESH_REALM_DAYS = 14  -- launch days 0-13: unpriced white trade goods are mailed
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
    minGain = 500,        -- 5s ...
    minGainPct = 0.25,    -- ... and 25% of the vendor value, both
    maxAgeDays = 7,       -- older Auctionator prices don't count
    disenchant = false,   -- Valuation.Settings switches it on when a disenchant addon is installed
    keepProfessionMats = true, -- materials this character's crafting professions use stay (operator, 2026-10-22)
    sellGathered = false,      -- ... except what its gathering professions gather (operator, 2026-11-06: off by default)
}

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
    [129] = { name = "First Aid", subclasses = { [5] = true }, mats = "cloth" },
    [171] = { name = "Alchemy", subclasses = { [9] = true }, mats = "herbs" },
    [333] = { name = "Enchanting", subclasses = { [12] = true }, mats = "dust, essences and shards" },
    [185] = { name = "Cooking", subclasses = { [8] = true }, mats = "meat and fish" },
}

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

--- Pure: the name of this character's crafting profession that uses the item, or nil.
--- A profession whose skill (`rank` in a { skillLine, rank } entry) is past the item
--- (Tiers: Linen Cloth is done for First Aid at 80) doesn't count, unless `tiers` is
--- false. Second return: { name, skill } of the first profession past it, when none
--- needs it; third: the skill at which the needing profession will be done with it.
function Valuation.NeededBy(item, professions, tiers)
    if item.classID ~= Valuation.TRADE_GOODS then return nil end
    local outgrown
    for _, p in ipairs(type(professions) == "table" and professions or {}) do
        local id = tonumber(type(p) == "table" and p.skillLine or p)
        local known = Valuation.PROFESSION_MATS[id or -1]
        if known and known.subclasses[item.subclassID] then
            local rank = type(p) == "table" and tonumber(p.rank) or nil
            if tiers ~= false and ns.Tiers.Outgrown(id, item.itemID, rank) then
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

--- Pure: research 4.2. With Auctionator installed but no price for this item yet, a white
--- trade good is mailed during the first FRESH_REALM_DAYS launch days: cloth, ore, herbs and
--- leather always sell on a fresh realm, and in launch week almost nothing has a price.
--- The exception to AGENTS "an item without a price stays" (operator, 2026-10-20); never
--- when the price call itself failed.
function Valuation.FreshRealmDefault(item, price, settings)
    return type(price) == "table" and price.ah == nil and not price.failed
        and item.quality == 1 and item.classID == Valuation.TRADE_GOODS
        and tonumber(settings.serverDay) ~= nil and settings.serverDay < Valuation.FRESH_REALM_DAYS
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

function Valuation.Deposit(vendorUnit, count, duration)
    local mult = Valuation.DEPOSIT_MULTIPLIER[duration] or Valuation.DEPOSIT_MULTIPLIER[Valuation.DEFAULTS.duration]
    return math.floor((vendorUnit or 0) * (count or 0) * Valuation.DEPOSIT_RATE) * mult
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

--- Soulbound and quest items can never be mailed: the window doesn't list them.
function Valuation.Unmailable(result)
    return result.action == "keep" and (result.reason == "soulbound" or result.reason == "quest item")
end

--- Armor (class 4) or weapon (class 2), uncommon or better.
function Valuation.CanDisenchant(item)
    return (item.classID == 2 or item.classID == 4) and (item.quality or 0) >= 2
end

--- The unit price an item is valued at (docs/ALGORITHM-RESEARCH.md 4.1 / 4.7): the median
--- of the highest minimum buyout over the last MEDIAN_DAYS scanned days, so one 1c undercut
--- in the latest scan can't flip a verdict; the last scan's price when there are fewer than
--- two days of history. An inexact price loses INEXACT_HAIRCUT. Returns copper (nil without
--- a price) and the number of scanned days behind it (1 = the last scan alone).
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
function Valuation.SmoothedPrice(price, field)
    if type(price) ~= "table" or price.ah == nil then return nil, 0 end
    local recent = {}
    for i, row in ipairs(scannedDays(price)) do
        if i > Valuation.MEDIAN_DAYS then break end
        recent[#recent + 1] = row[field or "maxSeen"] or row.maxSeen
    end
    local unit, scans = price.ah, 1
    if #recent >= 2 then unit, scans = median(recent), #recent end
    if price.exact == false then unit = math.floor(unit * (1 - Valuation.INEXACT_HAIRCUT)) end
    return unit, scans
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

local evaluate

--- item: { link, itemID, count, stacks, quality, classID, vendor (copper per unit; nil = not
---   loaded yet), bound, quest, inUse (locked by the game), locked (Mailworthy lock) }
--- price: nil when there's no price source at all (no Auctionator); else
---   { ah = copper per unit or nil, age = days or nil, de = copper per item or nil }
---   history = Prices.History rows (optional), exact = true / false / nil }
--- Returns { action = "mail" | "keep", route = "ah" | "de" | "common" | "bank" (mail only; bank =
---   mail it and hold it, listRoute = the route it would have had), reason,
---   vendor, deposit, depositCounted, postage, ahUnit (the smoothed unit price), scans (days
---   behind it), liquidity (Valuation.Liquidity), ahNet, deNet, gain, threshold } (copper, totals).
function Valuation.Evaluate(item, price, settings)
    settings = settings or Valuation.DEFAULTS
    if item.locked then return keep("locked") end
    if item.bound then return keep("soulbound") end
    if item.quest then return keep("quest item") end
    if item.inUse then return keep("in use") end
    if Valuation.IsTool(item) then return keep("profession tool") end
    if settings.keepProfessionMats then
        local profession, _, untilSkill = Valuation.NeededBy(item, settings.professions, settings.tiers)
        -- "Sell what I gather": what a gathering profession brought in is valued like anything else.
        if profession and not (settings.sellGathered and Valuation.GatheredBy(item, settings.professions)) then
            return keep("your " .. profession .. " needs it", { untilSkill = untilSkill })
        end
    end
    local r = evaluate(item, price, settings)
    if settings.keepProfessionMats and r.reason ~= "item info not loaded yet" then
        local _, outgrown = Valuation.NeededBy(item, settings.professions, settings.tiers)
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
        -- No price source: mail plain white (common) items, keep the rest (operator, 2026-10-13).
        if item.quality == 1 then
            return mail("common", "common item (no price data)", { vendor = vendor, postage = postage }, item, settings)
        end
        return keep(item.quality == 0 and "junk (no price data)" or "uncommon or better (no price data)",
            { vendor = vendor })
    end

    local r = { vendor = vendor, postage = postage }
    local stale = price.ah ~= nil and price.age ~= nil and price.age > settings.maxAgeDays
    if price.ah ~= nil and not stale then
        r.liquidity = Valuation.Liquidity(price, n)
        r.ahUnit, r.scans = Valuation.SmoothedPrice(price, r.liquidity.glut and "minSeen" or nil)
        r.deposit = Valuation.Deposit(item.vendor, n, settings.duration)
        r.depositCounted = math.floor(r.deposit * (r.liquidity.glut and 1 or settings.relistFactor))
        r.ahNet = math.floor(r.ahUnit * n * (1 - settings.cut)) - r.depositCounted - postage
    end
    if settings.disenchant and price.de ~= nil and Valuation.CanDisenchant(item) then
        r.deNet = math.floor(price.de * n) - postage
    end
    if r.ahNet == nil and r.deNet == nil then
        if stale then return keep(string.format("price too old (%d days)", price.age), r) end
        if Valuation.FreshRealmDefault(item, price, settings) then
            return mail("common", "common trade good (fresh realm, no price yet)", { vendor = vendor, postage = postage },
                item, settings)
        end
        return keep("no price", r)
    end

    local best, route = r.ahNet, "ah"
    if r.deNet ~= nil and (best == nil or r.deNet > best) then best, route = r.deNet, "de" end
    r.gain = best - vendor
    r.threshold = Valuation.Threshold(vendor, settings)
    if r.gain >= r.threshold then
        return mail(route, route == "ah" and "auction house" or "disenchant", r, item, settings)
    end
    return keep("not worth it", r)
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
