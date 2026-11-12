-- Bag scan and /mw scan: stacks grouped per item, locks and game state applied,
-- prices from Auctionator (or the common-items rule without it), a report a
-- player can check by hand, and nothing attached or sent.
local loadAddon = require("spec.support.load_addon")

describe("bag scan", function()
    local ns, prices

    local function byName(list, name)
        for _, item in ipairs(list) do
            if item.link:find("[" .. name .. "]", 1, true) then return item end
        end
    end

    before_each(function()
        ns = loadAddon()
        ns.Valuation.DEFAULTS.minGain = 500 -- these fixtures were built on the old 5s default (1s since 2026-11-07)
        -- launch day 20 (the Bank verdicts' window has its own tests)
        WowStub.state.serverTime = ns.Valuation.LAUNCH_EPOCH + 20 * 86400
        ns.Fire("PLAYER_LOGIN")
        ns.Config.SetBankAlt("Roknua Themicrulah") -- without one, its share stays (its own test below)
        prices = {}
        _G.Auctionator = { API = { v1 = {
            GetAuctionPriceByItemLink = function(caller, l)
                assert.equal("Mailworthy", caller)
                return prices[l]
            end,
            GetAuctionAgeByItemLink = function() return 0 end,
            IsAuctionDataExactByItemLink = function() return true end,
            GetDisenchantPriceByItemLink = function() return nil end,
        } } }
        -- Copper Ore in two stacks, vendor 5c; AH 50c each
        WowStub.setBag(0, 1, WowStub.item(2770, "Copper Ore", { count = 20, sell = 5 }))
        WowStub.setBag(1, 2, WowStub.item(2770, "Copper Ore", { count = 5, sell = 5 }))
        prices[WowStub.link(2770, "Copper Ore")] = 50
        -- Linen Cloth: PLAN's example, not worth it
        WowStub.setBag(0, 2, WowStub.item(2589, "Linen Cloth", { count = 20, sell = 10 }))
        prices[WowStub.link(2589, "Linen Cloth")] = 40
        -- soulbound, quest, unpriced (a staple trade good: mailed as a common item, 2026-11-08)
        WowStub.setBag(0, 3, WowStub.item(6948, "Hearthstone", { bound = true, sell = 0 }))
        WowStub.setBag(0, 4, WowStub.item(1234, "Quest Thing", { quest = true }))
        WowStub.setBag(2, 1, WowStub.item(2835, "Rough Stone", { count = 10, sell = 2 }))
    end)

    after_each(function()
        _G.Auctionator = nil
        _G.DisenchantryDB = nil
        _G.DisenchantValueAPI = nil
    end)

    it("scans the reagent bag (bag 5) like the others, and never a bank tab", function()
        WowStub.state.numSlots[5] = 16
        WowStub.state.numSlots[6] = 98
        WowStub.setBag(5, 3, WowStub.item(2770, "Copper Ore", { count = 10, sell = 5 }))
        WowStub.setBag(6, 1, WowStub.item(2770, "Copper Ore", { count = 20, sell = 5 })) -- a bank tab
        local result = ns.Bags.Evaluate()
        local ore = byName(result.mail, "Copper Ore")
        assert.equal(35, ore.count)
        assert.equal(3, ore.stacks)
        assert.same({ bag = 5, slot = 3, count = 10 }, ore.slots[3])
        assert.equal(5, ns.Bags.LastBag())
        assert.is_true(ns.Bags.IsBag(5))
        assert.is_false(ns.Bags.IsBag(6))
        assert.is_false(ns.Bags.IsBag(-1), "the keyring isn't a bag here")
    end)

    it("falls back to NUM_BAG_SLOTS + NUM_REAGENTBAG_SLOTS without the total constant", function()
        local total, reagent = NUM_TOTAL_EQUIPPED_BAG_SLOTS, NUM_REAGENTBAG_SLOTS
        _G.NUM_TOTAL_EQUIPPED_BAG_SLOTS = nil
        assert.equal(5, ns.Bags.LastBag())
        _G.NUM_REAGENTBAG_SLOTS = nil
        assert.equal(5, ns.Bags.LastBag(), "Forever has one reagent bag slot")
        _G.NUM_TOTAL_EQUIPPED_BAG_SLOTS, _G.NUM_REAGENTBAG_SLOTS = total, reagent
    end)

    it("groups every stack of an item, and values each item once", function()
        local result = ns.Bags.Evaluate()
        local ore = byName(result.mail, "Copper Ore")
        assert.equal(25, ore.count)
        assert.equal(2, ore.stacks)
        -- 1250 x 0.95 = 1187; deposit floor(125 x 5%) x 12 = 72, raised to 1s per stack (Forever's
        -- minimum) = 200, half counted; postage 2 x 30
        assert.equal(1187 - 100 - 60, ore.result.ahNet)
        assert.equal(1187 - 100 - 60 - 125, ore.result.gain)
        assert.equal(2, #result.mail)
        assert.equal("not worth it", byName(result.keep, "Linen Cloth").result.reason)
        assert.equal("soulbound", byName(result.unmailable, "Hearthstone").result.reason)
        assert.equal("quest item", byName(result.unmailable, "Quest Thing").result.reason)
        assert.is_nil(byName(result.keep, "Hearthstone"), "never-mailable items aren't in the keep list")
        assert.equal("staple trade good (no price yet)", byName(result.mail, "Rough Stone").result.reason)
        assert.same({ items = 35, stacks = 3, mails = 1, gain = 902, postage = 90, routed = 0, unpriced = 1, recipients = { "" },
            byRecipient = { [""] = { items = 35, stacks = 3, mails = 1, what = {} } } },
            result.totals)
    end)

    it("keeps locked items (every stack) and stacks the game has locked", function()
        ns.Locks.ToggleItem(2770, "link", "spec")
        local result = ns.Bags.Evaluate()
        assert.is_nil(byName(result.mail, "Copper Ore"))
        assert.equal("locked", byName(result.keep, "Copper Ore").result.reason)
        ns.Locks.ToggleItem(2770, "link", "spec")
        WowStub.state.bags[1][2].isLocked = true -- e.g. being moved
        result = ns.Bags.Evaluate()
        assert.equal(20, byName(result.mail, "Copper Ore").count, "the free stack still goes")
        assert.equal("in use", byName(result.keep, "Copper Ore").result.reason)
    end)

    it("values at the last scan, or the 3-day median when lower, and says which in the workings", function()
        local rows = { { rawDay = 9, maxSeen = 60, available = 400 }, { rawDay = 8, maxSeen = 65, available = 300 },
            { rawDay = 7, maxSeen = 58 } }
        Auctionator.Database = { GetPriceHistory = function(_, key) return key == "2589" and rows or nil end }
        Auctionator.Utilities = { BasicDBKeyFromLink = function(l) return l:match("item:(%d+)") end }
        -- the market fell: 40c last scan (Auctionator's own price) under a 60c median of the daily highs
        local result = ns.Bags.Evaluate()
        local linen = byName(result.keep, "Linen Cloth")
        assert.is_not_nil(linen, "40c last scan: still not worth it, whatever the last days' highs were")
        assert.equal(40, linen.result.ahUnit)
        assert.equal(400, linen.price.available)
        local report = ns.Bags.Report(result)
        assert.truthy(report:find("AH 40c each (last scan; 3-day median 60c), 0 days old", 1, true), report)
        assert.truthy(report:find("AH 50c each, 0 days old", 1, true), "Copper Ore: no history, last scan")
        -- a spike: 40c last scan over a 30c median of the daily highs
        rows = { { rawDay = 9, maxSeen = 30 }, { rawDay = 8, maxSeen = 35 }, { rawDay = 7, maxSeen = 28 } }
        result = ns.Bags.Evaluate()
        linen = byName(result.keep, "Linen Cloth")
        assert.equal(30, linen.result.ahUnit)
        report = ns.Bags.Report(result)
        assert.truthy(report:find("AH 30c each (3-day median; last scan 40c), 0 days old", 1, true), report)
    end)

    it("no auction price yet: to the bank alt (operator, 2026-11-08), a staple trade good as a common item", function()
        -- "going to the bank alt on no data is better than holding on the main"
        WowStub.setBag(2, 2, WowStub.item(858, "Lesser Healing Potion", { count = 5, sell = 5, class = 0 }))
        WowStub.setBag(2, 3, WowStub.item(7975, "Plans: Iridescent Hammer", { quality = 2, sell = 450, class = 9, subclass = 4 }))
        WowStub.setBag(2, 4, WowStub.item(1000, "Grey Junk", { quality = 0, sell = 3, class = 15 }))
        for _, day in ipairs({ 3, 20, 90 }) do -- no launch-days window any more
            WowStub.state.serverTime = ns.Valuation.LAUNCH_EPOCH + day * 86400
            local result = ns.Bags.Evaluate()
            local stone = byName(result.mail, "Rough Stone")
            assert.equal("common", stone.result.route)
            assert.equal("staple trade good (no price yet)", stone.result.reason)
            for _, name in ipairs({ "Lesser Healing Potion", "Plans: Iridescent Hammer" }) do
                local it = byName(result.mail, name)
                assert.equal("noprice", it.result.route, name .. " on day " .. day)
                assert.equal("no auction price yet", it.result.reason)
                assert.is_nil(it.result.to, "to the bank alt")
                assert.is_nil(it.result.gain, "no made-up gain")
            end
            assert.equal("junk (no price data)", byName(result.keep, "Grey Junk").result.reason, "junk stays for the vendor")
            assert.equal("not worth it", byName(result.keep, "Linen Cloth").result.reason, "priced items follow the numbers")
            assert.equal(902, result.totals.gain)
        end
        local report = ns.Bags.Report(ns.Bags.Evaluate())
        assert.truthy(report:find("prices: Auctionator (no auction price yet: to the bank alt)", 1, true), report)
        assert.truthy(report:find("MAIL NO PRICE [Lesser Healing Potion] x5: no auction price yet - vendor 5c each", 1, true), report)
        MailworthyDB.bankAlts = {}
        local held = byName(ns.Bags.Evaluate().keep, "Lesser Healing Potion")
        assert.equal("no bank alt", held.result.held, "without a bank alt it stays, as the rest of its share")
        assert.equal("No price: no bank alt", ns.MailWindow.StayReason(held.result))
    end)

    it("shows the grown minimum gain once the server is old enough", function()
        WowStub.state.serverTime = ns.Valuation.LAUNCH_EPOCH + 90 * 86400
        local report = ns.Bags.Report(ns.Bags.Evaluate())
        assert.truthy(report:find("min gain 5s (6s 52c at launch day 90) and 25%", 1, true), report)
        assert.truthy(report:find("gain 9s 2c (needs 6s 52c)", 1, true), report)
    end)

    it("a late-demand item before the raids goes in the mail as BANK", function()
        WowStub.setBag(2, 2, WowStub.item(10940, "Strange Dust", { count = 10, sell = 2, subclass = 12 }))
        prices[WowStub.link(10940, "Strange Dust")] = 100
        local result = ns.Bags.Evaluate()
        local dust = byName(result.mail, "Strange Dust")
        assert.equal("bank", dust.result.route)
        assert.equal(4, result.totals.stacks, "banked items are mailed like the rest")
        assert.truthy(ns.Bags.Report(result):find(
            "MAIL BANK [Strange Dust] x10: bank: enchanting materials sell once raids open (launch day 35) - vendor 2c each",
            1, true))
    end)

    it("without Auctionator: mails white items, keeps the rest", function()
        _G.Auctionator = nil
        WowStub.setBag(2, 2, WowStub.item(1000, "Grey Junk", { quality = 0 }))
        WowStub.setBag(2, 3, WowStub.item(1001, "Green Ring", { quality = 2, class = 4 }))
        local result = ns.Bags.Evaluate()
        assert.is_false(result.priced)
        assert.equal("common", byName(result.mail, "Copper Ore").result.route)
        assert.truthy(byName(result.mail, "Linen Cloth"))
        assert.truthy(byName(result.mail, "Rough Stone"))
        assert.equal("junk (no price data)", byName(result.keep, "Grey Junk").result.reason)
        assert.equal("uncommon or better (no price data)", byName(result.keep, "Green Ring").result.reason)
        assert.equal("soulbound", byName(result.unmailable, "Hearthstone").result.reason)
    end)

    it("a green weapon goes for disenchanting on Siz DisenchantValue's value, end to end", function()
        -- Vendor 1s; no auction price; Siz says 10s of materials: DE net 10s - 30c = 9s 70c, gain 8s 70c
        WowStub.setBag(1, 1, WowStub.item(2011, "Green Sword", { quality = 2, class = 2, sell = 100 }))
        local result = ns.Bags.Evaluate()
        assert.equal("noprice", byName(result.mail, "Green Sword").result.route, "no auction price: to the bank alt")
        _G.DisenchantValueAPI = { GetValue = function(l) return l:find("Green Sword", 1, true) and 1000 or nil end }
        result = ns.Bags.Evaluate()
        assert.is_true(result.settings.disenchant, "the comparison switches on with the addon")
        local sword = byName(result.mail, "Green Sword")
        assert.equal("de", sword.result.route)
        assert.equal(970, sword.result.deNet)
        assert.equal(870, sword.result.gain)
        assert.equal(1000, sword.price.de)
        assert.equal("DisenchantValue", sword.price.deSource)
        local report = ns.Bags.Report(result)
        assert.truthy(report:find("MAIL DE [Green Sword] x1: disenchant - vendor 1s each = 1s; disenchant 10s each (DisenchantValue); "
            .. "DE net 9s 70c;", 1, true), report)
        assert.truthy(ns.Report.Build():find(", Siz DisenchantValue installed", 1, true))
    end)

    it("uses saved settings and switches disenchant on when a disenchant addon is installed", function()
        assert.is_false(ns.Bags.CurrentSettings().disenchant)
        _G.DisenchantValueAPI = { GetValue = function() return nil end }
        assert.is_true(ns.Bags.CurrentSettings().disenchant, "Siz DisenchantValue")
        _G.DisenchantValueAPI = nil
        _G.DisenchantryDB = {}
        assert.is_true(ns.Bags.CurrentSettings().disenchant, "Disenchantry (still honoured)")
        MailworthyDB.settings = { duration = 1, disenchant = false }
        local s = ns.Bags.CurrentSettings()
        assert.equal(1, s.duration)
        assert.is_false(s.disenchant)
        -- the 2h deposit is floor(125 x 5%) = 6, under the 1s minimum for each of the 2 stacks
        assert.equal(200, byName(ns.Bags.Evaluate().mail, "Copper Ore").result.deposit)
    end)

    it("keeps the materials this character's professions use; the setting lets them go", function()
        WowStub.state.bags[0][2].subclass = 5 -- Linen Cloth: trade goods, cloth
        WowStub.state.bags[0][1].subclass = 7 -- Copper Ore: metal & stone
        prices[WowStub.link(2589, "Linen Cloth")] = 1000
        local result = ns.Bags.Evaluate()
        assert.truthy(byName(result.mail, "Linen Cloth"), "a miner mails cloth")
        assert.truthy(byName(result.mail, "Copper Ore"), "and ore: Mining gathers, it doesn't need it")
        WowStub.state.professions = { { index = 6, name = "Mining", rank = 12, maxRank = 75, skillLine = 186 },
            { index = 7, name = "Tailoring", rank = 40, maxRank = 75, skillLine = 197 } }
        result = ns.Bags.Evaluate()
        assert.equal("your Tailoring needs it", byName(result.keep, "Linen Cloth").result.reason)
        assert.truthy(byName(result.mail, "Copper Ore"))
        local report = ns.Bags.Report(result)
        assert.truthy(report:find("profession materials kept for Tailoring", 1, true), report)
        assert.truthy(report:find("KEEP [Linen Cloth] x20: your Tailoring needs it - vendor 10c each = 2s", 1, true), report)
        assert.truthy(ns.Report.Build():find(", profession materials kept for Tailoring", 1, true))
        ns.Config.Set("keepProfessionMats", false)
        result = ns.Bags.Evaluate()
        assert.truthy(byName(result.mail, "Linen Cloth"))
        assert.truthy(ns.Bags.Report(result):find("profession materials mailed", 1, true))
    end)

    it("keeps profession tools whatever they'd sell for (v0.2.0 listed a Fishing Pole)", function()
        WowStub.setBag(2, 2, WowStub.item(2901, "Mining Pick", { sell = 2 }))
        WowStub.setBag(2, 3, WowStub.item(6365, "Strong Fishing Pole", { sell = 50, class = 2 }))
        WowStub.state.bags[2][3].subclass = 20
        prices[WowStub.link(2901, "Mining Pick")] = 100000
        prices[WowStub.link(6365, "Strong Fishing Pole")] = 100000
        local result = ns.Bags.Evaluate()
        assert.equal("profession tool", byName(result.keep, "Mining Pick").result.reason)
        assert.equal("profession tool", byName(result.keep, "Strong Fishing Pole").result.reason)
    end)

    it("shows the vendor total for items kept before pricing (v0.2.0 printed '= 0c')", function()
        ns.Locks.ToggleItem(2589, "link", "spec")
        ns.HandleSlash("scan")
        local text = ns.Report.Text()
        assert.truthy(text:find("KEEP [Linen Cloth] x20: locked - vendor 10c each = 2s", 1, true), text)
    end)

    it("a failing price call is no price, never a crash, never 'no price yet' and never a staple", function()
        Auctionator.API.v1.GetAuctionPriceByItemLink = function() error("boom") end
        local result = ns.Bags.Evaluate()
        assert.equal(0, #result.mail)
        assert.equal("no price", byName(result.keep, "Copper Ore").result.reason)
        WowStub.state.serverTime = ns.Valuation.LAUNCH_EPOCH + 3 * 86400
        result = ns.Bags.Evaluate()
        assert.equal(0, #result.mail, "launch day 3: still nothing, the price call failed")
        assert.equal("no price", byName(result.keep, "Rough Stone").result.reason)
        assert.is_true(byName(result.keep, "Rough Stone").result.failed)
        assert.equal("the price lookup failed", ns.MailWindow.StayReason(byName(result.keep, "Rough Stone").result))
    end)

    it("/mw scan shows the workings in the copy box and sends nothing", function()
        ns.HandleSlash("scan")
        local text = ns.Report.Text()
        local function has(s) assert.truthy(text:find(s, 1, true), "missing: " .. s .. "\n" .. text) end
        has("prices: Auctionator")
        has("settings: 24h listing (deposit x12), AH cut 5%, postage 30c per stack, min gain 5s and 25%, "
            .. "disenchant off, max price age 7 days, launch day 20")
        has("total: 35 items (3 stacks) in 1 mail(s), 9s 2c more than vendoring, postage 90c")
        has("MAIL AH [Copper Ore] x25 (2 stacks): auction house - vendor 5c each = 1s 25c; AH 50c each, 0 days old; "
            .. "AH net 10s 27c (cut 5%, deposit 2s counted 1s, postage 60c); gain 9s 2c (needs 5s)")
        has("KEEP [Linen Cloth] x20: not worth it - vendor 10c each = 2s; AH 40c each, 0 days old; "
            .. "AH net 6s 70c (cut 5%, deposit 1s 20c counted 60c, postage 30c); gain 4s 70c (needs 5s)")
        has("NOT MAILABLE (soulbound, quest or conjured, not listed in the window): [Hearthstone] x1, [Quest Thing] x1")
        assert.same({}, WowStub.state.attached)
        assert.same({}, WowStub.state.sent)
        assert.same({}, WowStub.state.used)
        local log = table.concat(ns.Log.Lines(), "\n")
        assert.truthy(log:find("[scan] 2 to mail (3 stacks, 1 mails, gain 9s 2c), 1 kept", 1, true), log)
    end)

    it("/mw scan says what 'Sell what I gather' does", function()
        local text = ns.Bags.ProfessionMatsText
        assert.equal("kept for Blacksmithing", text({ keepProfessionMats = true, professions = { 164, 186 } }))
        assert.equal("banked on your bank alt for Blacksmithing",
            text({ keepProfessionMats = true, matsToBankAlt = true, professions = { 164, 186 } }))
        assert.equal("kept for Blacksmithing; what Mining gathers is mailed",
            text({ keepProfessionMats = true, sellGathered = true, professions = { 164, 186 } }))
        assert.equal("kept for Blacksmithing; sell what I gather: on (no gathering profession here)",
            text({ keepProfessionMats = true, sellGathered = true, professions = { 164 } }))
        assert.equal("mailed", text({ keepProfessionMats = false, sellGathered = true, professions = { 164, 186 } }))
    end)
end)

describe("bag scan without a bank alt, or with it skipped this visit", function()
    -- operator, 2026-11-08: "dont require a bank alt to use mailworthy", "Players should be able to
    -- click skip once for their bank alt sends too". Its share stays in the bags; bindings still go.
    local ns, prices
    local BOB = "Bob Surname"

    before_each(function()
        ns = loadAddon()
        WowStub.state.serverTime = ns.Valuation.LAUNCH_EPOCH + 20 * 86400
        ns.Fire("PLAYER_LOGIN")
        prices = {}
        _G.Auctionator = { API = { v1 = {
            GetAuctionPriceByItemLink = function(_, l) return prices[l] end,
            GetAuctionAgeByItemLink = function() return 0 end,
        } } }
        WowStub.setBag(0, 1, WowStub.item(2770, "Copper Ore", { count = 20, sell = 5, class = 7, subclass = 7 }))
        prices[WowStub.link(2770, "Copper Ore")] = 174
        WowStub.setBag(0, 2, WowStub.item(10940, "Strange Dust", { count = 20, sell = 2, class = 7, subclass = 12 }))
        prices[WowStub.link(10940, "Strange Dust")] = 3
        ns.Routes.Add(BOB, 333)
    end)
    after_each(function() _G.Auctionator = nil end)

    local function find(list, itemID)
        for _, it in ipairs(list) do if it.itemID == itemID then return it end end
    end

    it("no bank alt: the auction share stays with its route and gain; the binding still mails", function()
        assert.equal("no bank alt", ns.Bags.HoldReason())
        local result = ns.Bags.Evaluate()
        assert.equal(1, #result.mail)
        assert.equal(BOB, result.mail[1].result.to)
        local ore = find(result.keep, 2770)
        assert.equal("no bank alt", ore.result.held)
        assert.equal("ah", ore.result.route)
        assert.equal("Auction +" .. ns.Valuation.Money(ore.result.gain) .. ": no bank alt", ns.MailWindow.StayReason(ore.result))
        assert.same({ BOB }, result.totals.recipients)
        assert.equal(0, result.totals.gain, "held items add nothing to the gain line")
        local report = ns.Bags.Report(result)
        assert.truthy(report:find("bank alt: none (its share stays in the bags", 1, true), report)
        assert.truthy(report:find("KEEP [Copper Ore] x20: no bank alt (AH auction house)", 1, true), report)
    end)

    it("the bank alt view's own scan never holds: its tags say what the market says", function()
        local result = ns.Bags.Evaluate(ns.BankAlt.Settings())
        assert.truthy(find(result.mail, 2770))
    end)

    it("skip once: held for this mailbox visit only", function()
        ns.Config.SetBankAlt("Roknua Themicrulah")
        assert.is_nil(ns.Bags.HoldReason())
        assert.truthy(find(ns.Bags.Evaluate().mail, 2770))
        ns.Bags.SkipBankAlt(true)
        local result = ns.Bags.Evaluate()
        assert.equal("bank alt skipped", find(result.keep, 2770).result.held)
        assert.equal(BOB, result.mail[1].result.to)
        assert.truthy(ns.Bags.Report(result):find("Roknua Themicrulah, skipped this visit", 1, true))
        ns.Fire("MAIL_CLOSED")
        assert.is_false(ns.Bags.BankAltSkipped())
        assert.truthy(find(ns.Bags.Evaluate().mail, 2770))
    end)
end)
