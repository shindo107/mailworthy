-- Price sources. Auctionator (optional) gives auction prices from its own scans;
-- Mailworthy never scans the AH itself. Disenchant values, in this order: Siz
-- DisenchantValue (optional; its documented API for other addons,
-- DisenchantValueAPI.GetValue(link) = copper per item or nil, learned from the
-- player's own disenchants), then the era disenchant tables priced with
-- Auctionator's material prices (Disenchant.lua: the same number Disenchantry's
-- tooltip shows, since Disenchantry has no API; labelled "Disenchantry" when it
-- is installed), then Auctionator's own disenchant call (never seen returning a
-- value on Forever). Vendor prices come from the item info. Confirmed on Forever
-- (Auctionator 340/341, 2026-10-13): the API.v1 calls below exist and return
-- prices after a scan (age 0, exact). Every call is guarded: a missing or failing
-- call is "no price", never a guess.
--
-- TradeSkillMaster (optional, 2026-11-08, a CurseForge request) is the other auction price
-- source: its public TSM_API (TSM 4.x Core/API.lua; TSM 4.15 ships a Forever build):
-- TSM_API.ToItemString(link) -> "i:12345", TSM_API.GetCustomPriceValue(source, itemString)
-- -> copper or nil, errorMessage (nil + message both for "no data" and for an invalid
-- source, so TSM_API.IsCustomPriceValid(source) tells them apart). Sources read: this realm's
-- AuctionDB "DBMinBuyout" (lowest buyout at TSM's last data) and "DBMarket" (its market
-- value). Never region sources: the item sells on this realm's AH. Auctionator wins when both
-- are installed (Prices.Source): its scans carry an age, exactness and a daily history that the
-- decision rule uses, and TSM's public API has none of those.
local _, ns = ...

local Prices = {}
ns.Prices = Prices

Prices.CALLER = "Mailworthy"

local function call(fn, ...)
    if type(fn) ~= "function" then return nil end
    local results = { pcall(fn, ...) }
    if not results[1] then return nil end
    return unpack(results, 2, table.maxn(results))
end

--- Like call, but says whether the call happened: ok, results...
local function try(fn, ...)
    if type(fn) ~= "function" then return false end
    return pcall(fn, ...)
end

local function copper(value)
    value = tonumber(value)
    return value and value >= 0 and value or nil
end

function Prices.Auctionator()
    local api = rawget(_G, "Auctionator")
    api = type(api) == "table" and type(api.API) == "table" and api.API.v1
    return type(api) == "table" and type(api.GetAuctionPriceByItemLink) == "function" and api or nil
end

--- TradeSkillMaster's public API table (TSM_API with GetCustomPriceValue), or nil.
function Prices.TSM()
    local api = rawget(_G, "TSM_API")
    return type(api) == "table" and type(api.GetCustomPriceValue) == "function" and api or nil
end

Prices.SOURCE_NAME = { Auctionator = "Auctionator", TSM = "TradeSkillMaster" }

--- The auction price source in use: "Auctionator" (wins when both are installed), "TSM", or nil.
--- Any source counts as "with Auctionator" in the AGENTS.md Safety rules: an item it has no
--- price for goes to the bank alt (2026-11-08); with none, only unlocked, tradeable white items
--- and the staple trade goods are mailed.
function Prices.Source()
    if Prices.Auctionator() then return "Auctionator" end
    if Prices.TSM() then return "TSM" end
    return nil
end

--- What to call the source in the settings, `/mw scan` and `/mw report`: "Auctionator",
--- "TradeSkillMaster", "Auctionator (TSM installed, not used)", or nil.
function Prices.SourceText()
    local source = Prices.Source()
    if not source then return nil end
    local text = Prices.SOURCE_NAME[source]
    if source == "Auctionator" and Prices.TSM() then text = text .. " (TSM installed, not used)" end
    return text
end

--- TSM's item string for a link ("i:12345", with its bonus / random parts when TSM keeps
--- them); falls back to "i:<item ID>" read from the link when ToItemString can't say.
function Prices.TSMItemString(link)
    local api = Prices.TSM()
    if not api or type(link) ~= "string" then return nil end
    local s = call(api.ToItemString, link)
    if type(s) == "string" and s:find("^[ip]:%d+") then return s end
    local id = link:match("item:(%d+)") or link:match("^i:(%d+)")
    return id and ("i:" .. id) or nil
end

local tsmValid = {} -- source -> true once IsCustomPriceValid said so (a "no" is asked again)

--- One TSM price source for an item string: copper, or nil; second return true when the call
--- failed (it raised, or TSM doesn't know the source), which is never "no price yet".
local function tsmValue(api, source, itemString)
    local ok, value = pcall(api.GetCustomPriceValue, source, itemString)
    if not ok then return nil, true end
    value = copper(value)
    if value ~= nil then return math.floor(value + 0.5), false end
    -- nil comes with a message both for "no data for this item" and for an unknown source:
    -- only a source TSM calls valid makes it "no price yet"; anything else is a failed call.
    if not tsmValid[source] then
        local okValid, valid = try(api.IsCustomPriceValid, source)
        tsmValid[source] = okValid and valid == true or nil
    end
    return nil, not tsmValid[source]
end

--- TSM's unit price for an item string: the lower of DBMinBuyout and DBMarket (the last data's
--- lowest buyout, capped by the market value as Auctionator's last scan is capped by its median),
--- or whichever one there is. Returns unit, failed, minBuyout, market.
function Prices.TSMUnit(itemString)
    local api = Prices.TSM()
    if not api or not itemString then return nil, true end
    local minBuyout, failedMin = tsmValue(api, "DBMinBuyout", itemString)
    local market, failedMarket = tsmValue(api, "DBMarket", itemString)
    local unit = minBuyout
    if market ~= nil and (unit == nil or market < unit) then unit = market end
    return unit, (unit == nil and (failedMin or failedMarket)) or false, minBuyout, market
end

--- Forget what IsCustomPriceValid said (specs; TSM loaded or changed later).
function Prices.ResetTSM() tsmValid = {} end

--- Siz DisenchantValue's API table (DisenchantValueAPI with GetValue), or nil.
--- Detected by the API, not the addon folder name (unverified; README "Beta unknowns").
function Prices.DisenchantValue()
    local api = rawget(_G, "DisenchantValueAPI")
    return type(api) == "table" and type(api.GetValue) == "function" and api or nil
end

--- Disenchant value per item (copper) from Siz DisenchantValue, or nil when it isn't
--- installed, can't value the item, or errors.
function Prices.DisenchantValueOf(link)
    local api = Prices.DisenchantValue()
    if not api then return nil end
    return copper(call(api.GetValue, link))
end

--- Disenchantry (CurseForge project 1704637, back since 2026-10-22): no API, so its
--- values are recomputed by Disenchant.lua; its presence switches the disenchant
--- comparison on by default and names the source.
function Prices.DisenchantryInstalled()
    local addons = rawget(_G, "C_AddOns")
    if type(addons) == "table" and call(addons.IsAddOnLoaded, "Disenchantry") then return true end
    return rawget(_G, "DisenchantryDB") ~= nil
end

--- The disenchant addon that switches the disenchant comparison on by default:
--- "Siz DisenchantValue", "Disenchantry", or nil.
function Prices.DisenchantAddon()
    if Prices.DisenchantValue() then return "Siz DisenchantValue" end
    if Prices.DisenchantryInstalled() then return "Disenchantry" end
    return nil
end

function Prices.DisenchantAddonInstalled()
    return Prices.DisenchantAddon() ~= nil
end

Prices.HISTORY_DAYS = 21 -- Auctionator's default PRICE_HISTORY_DAYS

--- Auctionator's per-day history for one link: { { day, minSeen, maxSeen, available }, ... },
--- newest first, at most HISTORY_DAYS entries; nil when there is none. minSeen / maxSeen
--- are the lowest and highest "minimum buyout" its scans saw that day, available the units
--- listed at the day's biggest scan. This is NOT Auctionator's stable API
--- (Database:GetPriceHistory, Utilities.BasicDBKeyFromLink; README "Beta unknowns"), so
--- every step is guarded and anything odd means "no history".
function Prices.History(link)
    local a = rawget(_G, "Auctionator")
    if type(a) ~= "table" or type(a.Database) ~= "table" or type(a.Utilities) ~= "table" then return nil end
    local key = call(a.Utilities.BasicDBKeyFromLink, link)
    if type(key) ~= "string" and type(key) ~= "number" then return nil end
    local rows = call(a.Database.GetPriceHistory, a.Database, key)
    if type(rows) ~= "table" then return nil end
    local history = {}
    for _, row in ipairs(rows) do
        local day = type(row) == "table" and tonumber(row.rawDay)
        if day then
            history[#history + 1] = { day = day, minSeen = copper(row.minSeen), maxSeen = copper(row.maxSeen),
                available = tonumber(row.available) }
        end
    end
    if #history == 0 then return nil end
    table.sort(history, function(x, y) return x.day > y.day end)
    while #history > Prices.HISTORY_DAYS do history[#history] = nil end
    return history
end

--- The auction price for a material by item ID (copper per unit): Auctionator's, the call
--- Disenchantry uses for its material prices (GetAuctionPriceByItemID, else the link form);
--- TradeSkillMaster's (Prices.TSMUnit) when it is the source.
function Prices.MaterialPrice(itemID)
    if not tonumber(itemID) then return nil end
    if Prices.Source() == "TSM" then return (Prices.TSMUnit("i:" .. math.floor(tonumber(itemID)))) end
    local api = Prices.Auctionator()
    if not api then return nil end
    if type(api.GetAuctionPriceByItemID) == "function" then
        return copper(call(api.GetAuctionPriceByItemID, Prices.CALLER, tonumber(itemID)))
    end
    return copper(call(api.GetAuctionPriceByItemLink, Prices.CALLER, "item:" .. tonumber(itemID)))
end

--- Quality, item level and class of an item from its info (nil while not loaded).
function Prices.ItemFacts(link)
    local getInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo
    local name, _, quality, level, _, _, _, _, _, _, _, classID = call(getInfo, link)
    if name == nil then return nil end
    return { quality = tonumber(quality), level = tonumber(level), classID = tonumber(classID) }
end

--- The disenchant value of an item (copper per item) and its source: "DisenchantValue"
--- (Siz DisenchantValue's API), "Disenchantry" (the era tables priced with Auctionator,
--- Disenchantry installed), "tables" (the same without it), "Auctionator" (its own call).
function Prices.DisenchantValueFor(link)
    local de = Prices.DisenchantValueOf(link)
    if de ~= nil then return de, "DisenchantValue" end
    de = ns.Disenchant and ns.Disenchant.Value(Prices.ItemFacts(link))
    if de ~= nil then return de, Prices.DisenchantryInstalled() and "Disenchantry" or "tables" end
    local api = Prices.Auctionator()
    de = api and copper(call(api.GetDisenchantPriceByItemLink, Prices.CALLER, link)) or nil
    if de ~= nil then return de, "Auctionator" end
    return nil, nil
end

--- Auction data for one item link, or nil when there's no price source at all.
--- { ah = copper per unit (last scan's minimum buyout), failed = true when that call errored, age = days since seen, exact = true / false /
---   nil (unknown), de = copper per item, deSource = "DisenchantValue" / "Disenchantry" / "tables" / "Auctionator"
---   (Prices.DisenchantValueFor), history = Prices.History(link),
---   available = units listed at the last scanned day, source = "Auctionator" / "TSM" }; any may be nil.
--- With TradeSkillMaster as the source: ah = Prices.TSMUnit, with minBuyout and market beside
--- it; age, exact and history are nil (its public API doesn't give them).
function Prices.Lookup(link)
    local source = Prices.Source()
    if source == "TSM" then return Prices.LookupTSM(link) end
    local api = Prices.Auctionator()
    if not api then return nil end
    local exact = call(api.IsAuctionDataExactByItemLink, Prices.CALLER, link)
    if exact ~= nil then exact = exact == true end
    local history = Prices.History(link)
    local ok, ah = try(api.GetAuctionPriceByItemLink, Prices.CALLER, link)
    local de, deSource = Prices.DisenchantValueFor(link)
    return {
        ah = ok and copper(ah) or nil,
        failed = not ok or nil, -- the price call itself failed: never "no price yet" (AGENTS safety)
        age = tonumber((call(api.GetAuctionAgeByItemLink, Prices.CALLER, link))),
        exact = exact,
        de = de,
        deSource = de ~= nil and deSource or nil,
        history = history,
        available = history and history[1].available or nil,
        source = "Auctionator",
    }
end

--- Prices.Lookup with TradeSkillMaster as the source (nil without TSM).
function Prices.LookupTSM(link)
    if not Prices.TSM() then return nil end
    local unit, failed, minBuyout, market = Prices.TSMUnit(Prices.TSMItemString(link))
    local de, deSource = Prices.DisenchantValueFor(link)
    return {
        ah = unit,
        failed = failed or nil, -- the price call itself failed: never "no price yet" (AGENTS safety)
        minBuyout = minBuyout,
        market = market,
        de = de,
        deSource = de ~= nil and deSource or nil,
        source = "TSM",
    }
end

--- Vendor sell price per unit (copper), or nil while the item info isn't loaded.
function Prices.Vendor(link)
    local getInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo
    local name, _, _, _, _, _, _, _, _, _, sell = call(getInfo, link)
    if name == nil then return nil end
    return copper(sell) or 0
end

--- Item class (2 = weapon, 4 = armor) and subclass, without needing the item cached.
function Prices.ClassID(link)
    local instant = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
    local _, _, _, _, _, classID, subclassID = call(instant, link)
    return tonumber(classID), tonumber(subclassID)
end
