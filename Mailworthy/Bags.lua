-- Bag scan: every stack in the backpack, bags 1-4 and the reagent bag (bag 5)
-- becomes item facts, grouped per item link (all stacks of an item go or stay
-- together), then valued by Valuation. `/mw scan` shows the result and sends
-- nothing. Profession bags (herb, enchanting, soul, quiver...) sit in bag slots
-- 1-4, so they are covered; the keyring (-1) and the bank are not bags here.
local _, ns = ...

local Bags = {}
ns.Bags = Bags

Bags.ATTACHMENTS = 12 -- per mail (ATTACHMENTS_MAX_SEND, measured)

local function call(fn, ...)
    if type(fn) ~= "function" then return nil end
    local results = { pcall(fn, ...) }
    if not results[1] then return nil end
    return unpack(results, 2, table.maxn(results))
end

--- The last equipped bag ID: the reagent bag (Enum.BagIndex.ReagentBag = 5 on
--- Forever, Blizzard_FrameXMLBase/Constants.lua: NUM_TOTAL_EQUIPPED_BAG_SLOTS =
--- NUM_BAG_SLOTS + NUM_REAGENTBAG_SLOTS). Bag IDs above it are bank tabs.
function Bags.LastBag()
    local total = tonumber(NUM_TOTAL_EQUIPPED_BAG_SLOTS)
    if total then return total end
    return (tonumber(NUM_BAG_SLOTS) or 4) + (tonumber(NUM_REAGENTBAG_SLOTS) or 1)
end

--- Is this a bag the player carries (backpack, bags 1-4, reagent bag)?
function Bags.IsBag(bag)
    return type(bag) == "number" and bag >= 0 and bag <= Bags.LastBag()
end

--- One entry per occupied bag slot.
function Bags.Slots()
    local slots = {}
    local container = C_Container or {}
    for bag = 0, Bags.LastBag() do
        for slot = 1, tonumber((call(container.GetContainerNumSlots, bag))) or 0 do
            local info = call(container.GetContainerItemInfo, bag, slot)
            if type(info) == "table" and info.hyperlink then
                local quest = call(container.GetContainerItemQuestInfo, bag, slot)
                slots[#slots + 1] = {
                    bag = bag, slot = slot, itemID = info.itemID, link = info.hyperlink,
                    count = tonumber(info.stackCount) or 1, quality = tonumber(info.quality),
                    bound = info.isBound == true, inUse = info.isLocked == true, noValue = info.hasNoValue == true,
                    quest = type(quest) == "table" and quest.isQuestItem == true, icon = info.iconFileID,
                }
            end
        end
    end
    return slots
end

--- Stacks of the same link (and same bound / in-use state) become one item.
function Bags.Group(slots)
    local items, byKey = {}, {}
    for _, s in ipairs(slots) do
        local key = table.concat({ s.link, tostring(s.bound), tostring(s.inUse) }, "|")
        local item = byKey[key]
        if not item then
            item = { link = s.link, itemID = s.itemID, quality = s.quality, bound = s.bound, inUse = s.inUse,
                quest = s.quest, noValue = s.noValue, icon = s.icon, count = 0, stacks = 0, slots = {} }
            byKey[key] = item
            items[#items + 1] = item
        end
        item.count = item.count + s.count
        item.stacks = item.stacks + 1
        item.quest = item.quest or s.quest
        item.slots[#item.slots + 1] = { bag = s.bag, slot = s.slot, count = s.count }
    end
    return items
end

-- The bank alt is optional (operator, 2026-11-08: "dont require a bank alt to use mailworthy"),
-- and the player can skip it for one mailbox visit ("Skip once for their bank alt sends too"):
-- then what would have gone to the bank alt stays in the bags, listed under Staying with the
-- route it would have had, and only bindings mail.
local bankAltSkipped = false

function Bags.SkipBankAlt(on)
    bankAltSkipped = on == true
    ns.Log.Add("scan", "bank alt %s this visit", bankAltSkipped and "skipped" or "back")
end
function Bags.BankAltSkipped() return bankAltSkipped end

--- Why the bank alt's share stays in the bags at this mailbox, or nil when it goes.
function Bags.HoldReason()
    if not ns.Config.BankAlt() then return "no bank alt" end
    if bankAltSkipped then return "bank alt skipped" end
    return nil
end

--- The window's settings (and /mw scan's): the saved ones, and whether the bank alt's share is held.
function Bags.CurrentSettings()
    local s = ns.Config.Values()
    s.hold = Bags.HoldReason()
    return s
end

--- Scan and value the bags. `settings.hold` (Bags.HoldReason): the bank alt's share is kept, with
--- result.held saying why and result.route what it would have been. Returns { settings, priced,
--- mail = {items}, keep = {items},
--- unmailable = {items} (soulbound / quest: never listed in the window), totals }.
function Bags.Evaluate(settings)
    settings = settings or Bags.CurrentSettings()
    if settings.serverDay == nil then settings.serverDay = ns.Config.ServerDay() end
    if settings.professions == nil then settings.professions = ns.Characters.Professions() end
    if settings.tiers == nil then settings.tiers = ns.Tiers.On() end
    -- What the profession window last showed still in use past the table (TierCheck): kept.
    if settings.tiers then ns.TierCheck.Annotate(settings.professions) end
    -- Auction unit prices by item ID, for the leather conversions (Tiers.WorthConverting).
    -- Priced = an auction price source (Auctionator, else TradeSkillMaster: Prices.Source); without
    -- one only white items go (AGENTS.md Safety "without Auctionator").
    local source = ns.Prices.Source()
    if settings.priceOf == nil and source then settings.priceOf = ns.Prices.MaterialPrice end
    local priced = source ~= nil
    local routes = settings.routes or ns.Routes.Active()
    local result = { settings = settings, priced = priced, source = source, routes = routes, mail = {}, keep = {}, unmailable = {},
        totals = { items = 0, stacks = 0, mails = 0, gain = 0, postage = 0, routed = 0, recipients = {}, byRecipient = {} } }
    local stacksTo = {}
    -- Class bindings (Routes, Classes.lua) need each item's class line: read only when there's one.
    local classRoutes = false
    for _, r in ipairs(routes) do classRoutes = classRoutes or r.class ~= nil end
    local mine = classRoutes and ns.Classes.Mine() or nil
    for _, item in ipairs(Bags.Group(Bags.Slots())) do
        item.locked = ns.Locks.IsItemLocked(item.itemID)
        if classRoutes then item.classes, item.myClass = ns.Classes.Of(item.itemID), mine end
        item.questFor = ns.Quests.For(item.link)
        item.classID, item.subclassID = ns.Prices.ClassID(item.link)
        item.vendor = item.noValue and 0 or ns.Prices.Vendor(item.link)
        item.price = priced and ns.Prices.Lookup(item.link) or nil
        item.result = ns.Valuation.Evaluate(item, item.price, settings)
        local diverted, capped, past = ns.Routes.Divert(item, item.result, item.price, settings, routes)
        if diverted then item.result = diverted elseif capped then item.result.capped = capped end
        if not diverted and past then item.result.pastFor = past end
        -- No bank alt, or skipped this visit: its share stays (bindings still go).
        if settings.hold and item.result.action == "mail" and not item.result.to then
            item.result.action, item.result.held = "keep", settings.hold
        end
        if item.result.action == "mail" then
            table.insert(result.mail, item)
            local t = result.totals
            t.items, t.stacks = t.items + item.count, t.stacks + item.stacks
            t.postage = t.postage + item.result.postage
            local to = item.result.to or "" -- "" = the bank alt
            if item.result.to then t.routed = t.routed + item.stacks else t.gain = t.gain + (item.result.gain or 0) end
            if not stacksTo[to] then
                stacksTo[to] = 0
                t.recipients[#t.recipients + 1] = to
                t.byRecipient[to] = { items = 0, stacks = 0, mails = 0, what = {}, crafter = item.result.crafter }
            end
            stacksTo[to] = stacksTo[to] + item.stacks
            local each = t.byRecipient[to]
            each.items, each.stacks = each.items + item.count, each.stacks + item.stacks
            if item.result.what and not each.what[item.result.what] then
                each.what[item.result.what] = true
                each.what[#each.what + 1] = item.result.what
            end
        elseif ns.Valuation.Unmailable(item.result) then
            table.insert(result.unmailable, item)
        else
            table.insert(result.keep, item)
        end
    end
    for to, n in pairs(stacksTo) do
        local mails = math.ceil(n / Bags.ATTACHMENTS)
        result.totals.mails = result.totals.mails + mails
        result.totals.byRecipient[to].mails = mails
    end
    for i, to in ipairs(result.totals.recipients) do -- the bank alt first
        if to == "" and i > 1 then
            table.remove(result.totals.recipients, i)
            table.insert(result.totals.recipients, 1, "")
        end
    end
    local function byGain(a, b)
        local ga, gb = a.result.gain or -math.huge, b.result.gain or -math.huge
        if ga ~= gb then return ga > gb end
        return a.link < b.link
    end
    -- The Mailing list in recipient groups (the bank alt's first), so who gets what is plain.
    local order = {}
    for i, to in ipairs(result.totals.recipients) do order[to] = i end
    table.sort(result.mail, function(a, b)
        local oa, ob = order[a.result.to or ""] or 0, order[b.result.to or ""] or 0
        if oa ~= ob then return oa < ob end
        return byGain(a, b)
    end)
    -- Locked items first (operator, 2026-11-07: "I click them, they disappear off the menu and
    -- then there's not a quick way to see what's been locked"): one press on the row unlocks.
    table.sort(result.keep, function(a, b)
        local la, lb = a.result.reason == "locked", b.result.reason == "locked"
        if la ~= lb then return la end
        return byGain(a, b)
    end)
    result.locked = 0
    for _, item in ipairs(result.keep) do
        if item.result.reason == "locked" then result.locked = result.locked + 1 end
    end
    return result
end

-- Report ---------------------------------------------------------------------

local money = function(c) return ns.Valuation.Money(c) end

local ROUTE = { ah = "AH", de = "DE", common = "COMMON", bank = "BANK", friend = "FRIEND" }

local function itemName(item)
    local name = item.link:match("%[(.-)%]") or item.link
    return string.format("[%s] x%d%s", name, item.count, item.stacks > 1 and (" (" .. item.stacks .. " stacks)") or "")
end

--- "5s", or "5s (6s 52c at launch day 90)" once the server's age has grown it.
function Bags.MinGainText(settings)
    local effective = ns.Valuation.MinGain(settings)
    if effective == settings.minGain then return money(settings.minGain) end
    return string.format("%s (%s at launch day %d)", money(settings.minGain), money(effective), settings.serverDay)
end

-- The numbers behind a verdict, so it can be checked by hand.
local function workings(item, settings)
    local r, p, parts = item.result, item.price, {}
    if item.vendor ~= nil then
        parts[#parts + 1] = "vendor " .. money(item.vendor) .. " each = " .. money(r.vendor or item.vendor * item.count)
    end
    if p and p.ah then
        local text = "AH " .. money(r.ahUnit or p.ah) .. " each"
        if (r.scans or 1) > 1 then
            text = text .. string.format(" (%d-day median; last scan %s)", r.scans, money(p.ah))
        elseif r.median then
            text = text .. string.format(" (last scan; %d-day median %s)", r.medianDays or 0, money(r.median))
        end
        if p.age then text = text .. ", " .. p.age .. " days old" end
        if p.exact == false then text = text .. " (not exact, -10%)" end
        parts[#parts + 1] = text
    end
    local L = r.liquidity
    if L and (L.available or L.trend) then
        local text = "market: " .. (L.available and (L.available .. " listed") or "listed ?")
        if L.trend then text = text .. string.format(", %+d%% vs last week", math.floor(L.trend * 100 + 0.5)) end
        if L.glut then text = text .. " (glut: floor price, deposit counted lost)" end
        parts[#parts + 1] = text
    end
    if r.ahNet then
        local deposit = money(r.deposit)
        if r.depositCounted ~= r.deposit then deposit = deposit .. " counted " .. money(r.depositCounted) end
        parts[#parts + 1] = string.format("AH net %s (cut %d%%, deposit %s, postage %s)", money(r.ahNet),
            math.floor(settings.cut * 100 + 0.5), deposit, money(r.postage))
    end
    if p and p.de then parts[#parts + 1] = "disenchant " .. money(p.de) .. " each (" .. tostring(p.deSource or "?") .. ")" end
    if r.deNet then parts[#parts + 1] = "DE net " .. money(r.deNet) end
    if r.gain then parts[#parts + 1] = string.format("gain %s (needs %s)", money(r.gain), money(r.threshold)) end
    if r.to then
        parts[#parts + 1] = "binding" .. (r.crafter and " (their character with the profession)" or "")
            .. (r.ahUnit and (", under the cap at " .. money(r.ahUnit) .. " each") or "")
    elseif r.capped then
        parts[#parts + 1] = string.format("not to %s: at or above the %s cap", tostring(r.capped.to),
            money(r.capped.cap or 0))
    end
    if r.pastFor then
        parts[#parts + 1] = string.format("not to %s: their %s (%s) is past it", tostring(r.pastFor.to),
            tostring(ns.Routes.ProfessionName(r.pastFor.profession)), tostring(r.pastFor.skill))
    end
    if r.outgrown then
        parts[#parts + 1] = string.format("your %s (%s) is past it", r.outgrown.name, tostring(r.outgrown.skill))
    end
    if r.untilSkill then parts[#parts + 1] = "kept until skill " .. r.untilSkill end
    if r.window then
        parts[#parts + 1] = string.format("past the table, but your profession window still shows %s (%s)%s",
            tostring(r.window.recipe), ns.TierCheck.COLORS[r.window.difficulty] or "?",
            r.window.via and (" via " .. r.window.via) or "")
    end
    if r.convert then
        parts[#parts + 1] = string.format("past its recipes; %d make a %s, worth more than selling them",
            r.convert.count, r.convert.name)
    end
    return table.concat(parts, "; ")
end

--- Pure: "First Aid 80, Tailoring 130" (each crafting profession with its skill, when known).
function Bags.CraftingText(professions)
    local names = {}
    for _, p in ipairs(type(professions) == "table" and professions or {}) do
        local id = tonumber(type(p) == "table" and p.skillLine or p)
        local known = ns.Valuation.PROFESSION_MATS[id or -1]
        if known then
            local rank = type(p) == "table" and tonumber(p.rank) or nil
            names[#names + 1] = known.name .. (rank and (" " .. rank) or "")
        end
    end
    return table.concat(names, ", ")
end

--- Pure: "First Aid 80 is past Linen Cloth; Tailoring 180 is past Linen Cloth, Wool Cloth" or "".
function Bags.OutgrownText(professions)
    local parts = {}
    for _, p in ipairs(type(professions) == "table" and professions or {}) do
        local id = tonumber(type(p) == "table" and p.skillLine)
        local known = ns.Valuation.PROFESSION_MATS[id or -1]
        local past = known and ns.Tiers.PastText(id, p.rank, nil, p.stillUsed) or ""
        if past ~= "" then parts[#parts + 1] = string.format("%s %d is past %s", known.name, p.rank, past) end
    end
    return table.concat(parts, "; ")
end

--- "kept for Tailoring 130, Enchanting 90" / "kept (no crafting profession here)" / "mailed".
function Bags.ProfessionMatsText(settings)
    if not settings.keepProfessionMats then return "mailed" end
    local crafting = Bags.CraftingText(settings.professions)
    local text = crafting ~= "" and ("kept for " .. crafting) or "kept (no crafting profession here)"
    local past = settings.tiers ~= false and Bags.OutgrownText(settings.professions) or ""
    if past ~= "" then text = text .. "; " .. past .. " (mailed)" end
    local names = ns.Valuation.CraftingProfessions(settings.professions)
    if settings.sellGathered and #names > 0 then
        local gathered = {}
        for _, p in ipairs(ns.Valuation.GatheringProfessions(settings.professions)) do gathered[#gathered + 1] = p.name end
        text = text .. (#gathered > 0 and ("; what " .. table.concat(gathered, ", ") .. " gathers is mailed")
            or "; sell what I gather: on (no gathering profession here)")
    end
    return text
end

function Bags.Report(result)
    local s, t = result.settings, result.totals
    local lines = {
        string.format("Mailworthy %s scan at %s (sends nothing)", ns.VERSION, date("%Y-%m-%d %H:%M")),
        "bank alt: " .. tostring(ns.Config.BankAlt() or "none (its share stays in the bags; /mw settings)")
            .. (bankAltSkipped and ", skipped this visit" or ""),
        "prices: " .. (result.priced and (ns.Prices.SOURCE_NAME[result.source] or "Auctionator")
            or "none (no Auctionator or TradeSkillMaster: mailing common items)")
            .. ((result.priced and (s.serverDay or math.huge) < ns.Valuation.FRESH_REALM_DAYS)
                and " (fresh realm: unpriced white trade goods are mailed)" or ""),
        string.format("settings: %dh listing (deposit x%d), AH cut %d%%, postage %s per stack, "
            .. "min gain %s and %d%%, disenchant %s, max price age %d days, launch day %s, profession materials %s",
            ns.Valuation.DURATION_HOURS[s.duration], ns.Valuation.DEPOSIT_MULTIPLIER[s.duration],
            math.floor(s.cut * 100 + 0.5), money(s.postage), Bags.MinGainText(s), math.floor(s.minGainPct * 100 + 0.5),
            s.disenchant and "on" or "off", s.maxAgeDays, tostring(s.serverDay), Bags.ProfessionMatsText(s)),
        string.format("total: %d items (%d stacks) in %d mail(s), %s more than vendoring, postage %s%s",
            t.items, t.stacks, t.mails, money(t.gain), money(t.postage),
            t.routed > 0 and string.format(" (%d stacks to friends)", t.routed) or ""),
    }
    for _, r in ipairs(result.routes or {}) do
        local to, crafter = ns.Routes.Recipient(r)
        lines[#lines + 1] = string.format("binding: %s (%s%s)", ns.Routes.Describe(r), ns.Routes.CapText(r),
            crafter and (", delivered to their crafter " .. to) or "")
    end
    for _, item in ipairs(result.mail) do
        local w = workings(item, s)
        lines[#lines + 1] = string.format("MAIL %s %s: %s%s", ROUTE[item.result.route] or "?", itemName(item),
            item.result.reason, w ~= "" and (" - " .. w) or "")
    end
    for _, item in ipairs(result.keep) do
        local w = workings(item, s)
        local r = item.result
        local why = r.held and string.format("%s (%s %s)", r.held, ROUTE[r.route] or "?", r.reason) or r.reason
        if r.quest then why = why .. " (" .. r.quest .. ")" end
        lines[#lines + 1] = string.format("KEEP %s: %s%s", itemName(item), why, w ~= "" and (" - " .. w) or "")
    end
    if #result.unmailable > 0 then
        local names = {}
        for _, item in ipairs(result.unmailable) do names[#names + 1] = itemName(item) end
        lines[#lines + 1] = "NOT MAILABLE (soulbound or quest, not listed in the window): " .. table.concat(names, ", ")
    end
    return table.concat(lines, "\n")
end

function Bags.Scan()
    local result = Bags.Evaluate()
    local t = result.totals
    ns.Log.Add("scan", "%d to mail (%d stacks, %d mails, gain %s), %d kept, prices %s", #result.mail, t.stacks,
        t.mails, money(t.gain), #result.keep, result.priced and tostring(result.source) or "none")
    ns.Print(string.format("would mail %d items (%d stacks, %d mail(s)), %s more than vendoring; keeps %d. Details in the window.",
        t.items, t.stacks, t.mails, money(t.gain), #result.keep))
    ns.Report.Show(Bags.Report(result), "Mailworthy scan (sends nothing)")
    return result
end

ns.On("MAIL_CLOSED", function() bankAltSkipped = false end)
