-- The decision rule (docs/PLAN.md): AH net (cut, 24h deposit, postage) or
-- disenchant vs vendor, minimum gain 5s and 25%; the no-Auctionator rule; and
-- every reason an item stays in the bags.
local loadAddon = require("spec.support.load_addon")

describe("valuation", function()
    local V, S

    -- 20 Linen Cloth at 10c vendor each, unless overridden.
    local function item(o)
        local t = { link = "[Linen Cloth]", itemID = 2589, count = 20, stacks = 1, quality = 1, classID = 7, vendor = 10 }
        for k, v in pairs(o or {}) do t[k] = v end
        return t
    end

    before_each(function()
        V = loadAddon().Valuation
        V.DEFAULTS.minGain = 500 -- these fixtures were built on the old 5s default (1s since 2026-11-07)
        S = V.Settings(nil, false)
    end)

    it("defaults to a 1s minimum gain (operator, 2026-11-07; was 5s)", function()
        assert.equal(100, loadAddon().Valuation.Settings(nil, false).minGain)
    end)

    describe("deposit", function()
        it("is floor(vendor value x 5%) x 1 / 4 / 12 for 2h / 8h / 24h (measured on the beta, 2026-10-13)", function()
            assert.equal(250, V.Deposit(250, 20, 1))
            assert.equal(1000, V.Deposit(250, 20, 2))
            assert.equal(3000, V.Deposit(250, 20, 3))
        end)

        it("rounds down before multiplying", function()
            assert.equal(1236, V.Deposit(103, 20, 3), "floor(103) x 12")
            assert.equal(1200, V.Deposit(100, 20, 3))
        end)

        it("is at least 1s per listing (Forever's minimum), so cheap items pay 1s", function()
            assert.equal(100, V.Deposit(10, 20, 1), "Linen Bandage x20 on 2h: 10c, raised to 1s")
            assert.equal(120, V.Deposit(10, 20, 3), "already over the minimum")
            assert.equal(100, V.Deposit(0, 20, 3), "no vendor value")
            assert.equal(300, V.Deposit(10, 3, 3, 3), "three stacks, three listings")
            assert.equal(100, V.Deposit(10, 3, 3, 0))
        end)

        it("defaults to the 24h listing", function()
            assert.equal(3, S.duration)
            assert.equal(3000, V.Deposit(250, 20, nil))
        end)
    end)

    describe("auction house", function()
        it("PLAN's example: gain 4s 70c is under the 5s minimum, so it stays", function()
            local r = V.Evaluate(item(), { ah = 40, age = 0 }, S)
            assert.equal("keep", r.action)
            assert.equal("not worth it", r.reason)
            assert.equal(200, r.vendor)
            assert.equal(120, r.deposit)
            assert.equal(60, r.depositCounted, "half: the game refunds it on a sale")
            assert.equal(30, r.postage)
            assert.equal(760 - 60 - 30, r.ahNet)
            assert.equal(470, r.gain)
            assert.equal(500, r.threshold)
        end)

        it("mails when the gain reaches 5s", function()
            local r = V.Evaluate(item(), { ah = 60, age = 0 }, S)
            assert.equal("mail", r.action)
            assert.equal("ah", r.route)
            assert.equal(1140 - 60 - 30 - 200, r.gain)
        end)

        it("the deposit counts in full with a relist factor of 1 (the old default)", function()
            local full = V.Settings({ relistFactor = 1 }, false)
            local r = V.Evaluate(item(), { ah = 40, age = 0 }, full)
            assert.equal(120, r.depositCounted)
            assert.equal(760 - 120 - 30, r.ahNet)
        end)

        it("needs 25% of the vendor value too, when that's more than 5s", function()
            local sword = item({ count = 1, vendor = 10000 })
            assert.equal(2500, V.Threshold(10000, S))
            -- 1g 50s: 14250 - 3000 (half of the 6000 deposit) - 30 postage = 11220, gain 12s 20c < 25s
            assert.equal("keep", V.Evaluate(sword, { ah = 15000 }, S).action)
            -- 1g 65s: 15675 - 3000 - 30 = 12645, gain 26s 45c
            assert.equal("mail", V.Evaluate(sword, { ah = 16500 }, S).action)
        end)

        it("the 24h deposit (x12) can decide it: the same item mails with a 2h listing", function()
            local sword = item({ count = 1, vendor = 10000 })
            assert.equal("keep", V.Evaluate(sword, { ah = 15000 }, S).action)
            local short = V.Settings({ duration = 1 }, false)
            local r = V.Evaluate(sword, { ah = 15000 }, short)
            assert.equal("mail", r.action)
            assert.equal(500, r.deposit)
        end)

        it("postage is 30c per stack", function()
            assert.equal(90, V.Evaluate(item({ stacks = 3 }), { ah = 60 }, S).postage)
        end)

        it("items without a vendor value mail on their AH price alone", function()
            local r = V.Evaluate(item({ count = 1, vendor = 0 }), { ah = 700 }, S)
            assert.equal(100, r.deposit, "Forever's 1s minimum")
            assert.equal(665 - 50 - 30, r.gain)
            assert.equal("mail", r.action)
        end)

        it("ignores prices older than 7 days (then it goes as unpriced, 2026-11-08); an unknown age counts", function()
            local r = V.Evaluate(item(), { ah = 60, age = 8 }, S)
            assert.equal("mail", r.action)
            assert.equal("common", r.route, "Linen Cloth is a staple: mailed as a common item, not for its old price")
            assert.equal("staple trade good (price 8 days old)", r.reason)
            assert.is_nil(r.ahNet)
            assert.equal("ah", V.Evaluate(item(), { ah = 60, age = 7 }, S).route)
            assert.equal("ah", V.Evaluate(item(), { ah = 60 }, S).route)
        end)

        it("an item Auctionator has no price for goes to the bank alt (operator, 2026-11-08)", function()
            local r = V.Evaluate(item({ itemID = 858, link = "[Lesser Healing Potion]", classID = 0 }), { ah = nil }, S)
            assert.equal("mail", r.action)
            assert.equal(V.NO_PRICE, r.route)
            assert.equal("no auction price yet", r.reason)
        end)
    end)

    describe("smoothed price (ALGORITHM-RESEARCH 4.1 / 4.7)", function()
        -- Prices.History rows: newest first, maxSeen = the day's highest minimum buyout.
        local function hist(...)
            local rows, day = {}, 100
            for _, v in ipairs({ ... }) do
                rows[#rows + 1] = { day = day, minSeen = v, maxSeen = v, available = 500 }
                day = day - 1
            end
            return rows
        end

        it("is the last scan's price without history, or with a single day", function()
            assert.same({ 60, 1 }, { V.SmoothedPrice({ ah = 60 }) })
            assert.same({ 60, 1 }, { V.SmoothedPrice({ ah = 60, history = hist(55) }) })
            assert.same({ nil, 0 }, { V.SmoothedPrice({ ah = nil, history = hist(55, 56) }) })
            assert.same({ nil, 0 }, { V.SmoothedPrice(nil) })
        end)

        it("is the median of the last three scanned days when the last scan is above it (two days: their mean)", function()
            assert.same({ 65, 3 }, { V.SmoothedPrice({ ah = 70, history = hist(70, 60, 65) }) })
            assert.same({ 65, 3 }, { V.SmoothedPrice({ ah = 70, history = hist(70, 60, 65, 5, 5) }) }, "older days don't count")
            assert.same({ 65, 2 }, { V.SmoothedPrice({ ah = 70, history = hist(70, 61) }) })
            assert.same({ 60, 3 }, { V.SmoothedPrice({ ah = 60, history = hist(60, 60, 65) }) }, "equal: the median")
        end)

        it("is the last scan when that is under the median, and names the median it beat", function()
            assert.same({ 40, 1, 60, 3 }, { V.SmoothedPrice({ ah = 40, history = hist(40, 60, 65) }) })
            assert.same({ 40, 1, 50, 2 }, { V.SmoothedPrice({ ah = 40, history = hist(40, 61) }) })
        end)

        it("skips days without a price and tolerates odd rows", function()
            local rows = hist(70, 60, 65)
            rows[2].maxSeen = nil
            assert.same({ 67, 2 }, { V.SmoothedPrice({ ah = 70, history = rows }) })
            assert.same({ 40, 1 }, { V.SmoothedPrice({ ah = 40, history = "junk" }) })
        end)

        it("takes 10% off an inexact price; an unknown exactness is left alone", function()
            assert.same({ 54, 1 }, { V.SmoothedPrice({ ah = 60, exact = false }) })
            assert.same({ 60, 1 }, { V.SmoothedPrice({ ah = 60, exact = true }) })
            assert.same({ 60, 1 }, { V.SmoothedPrice({ ah = 60 }) })
            assert.same({ 58, 3 }, { V.SmoothedPrice({ ah = 70, exact = false, history = hist(70, 60, 65) }) })
            assert.same({ 36, 1, 60, 3 }, { V.SmoothedPrice({ ah = 40, exact = false, history = hist(40, 60, 65) }) })
        end)

        it("one spike in the latest scan doesn't make a dud mailworthy; a drop is believed", function()
            -- 20 Linen Cloth: 40c each is "not worth it" (PLAN's example), 60c mails.
            assert.equal("keep", V.Evaluate(item(), { ah = 40, age = 0 }, S).action)
            assert.equal("keep", V.Evaluate(item(), { ah = 60, age = 0, history = hist(60, 40, 40) }, S).action)
            local r = V.Evaluate(item(), { ah = 70, age = 0, history = hist(70, 60, 65) }, S)
            assert.equal("mail", r.action)
            assert.equal(65, r.ahUnit)
            assert.equal(3, r.scans)
            assert.equal(1235 - 60 - 30, r.ahNet)
            -- the market fell to 40c: the item stays, whatever the last days' highs were
            r = V.Evaluate(item(), { ah = 40, age = 0, history = hist(40, 60, 65) }, S)
            assert.equal("keep", r.action)
            assert.equal(40, r.ahUnit)
            assert.equal(1, r.scans)
            assert.equal(60, r.median)
        end)

        it("a fresh scan under the median wins: Silk Cloth at 2s 70c, not 5s 30c (vdb1, CurseForge)", function()
            -- "AH data seems off from auctionator ... says silk cloth 5s30 while its 2s70": Auctionator's
            -- last scan (its tooltip, API.v1) says 2s 70c; its daily highs of the minimum buyout over the
            -- last three days were 5s 30c (an earlier scan today), 6s and 5s, median 5s 30c.
            local unit, scans, median, days = V.SmoothedPrice({ ah = 270, age = 0, history = hist(530, 600, 500) })
            assert.same({ 270, 1, 530, 3 }, { unit, scans, median, days })
            local r = V.Evaluate(item({ link = "[Silk Cloth]", itemID = 4306, vendor = 150 }),
                { ah = 270, age = 0, history = hist(530, 600, 500) }, S)
            assert.equal(270, r.ahUnit)
            assert.equal(530, r.median)
        end)

        it("the age gate still uses the last scan's age", function()
            assert.equal("staple trade good (price 8 days old)",
                V.Evaluate(item(), { ah = 40, age = 8, history = hist(40, 60, 65) }, S).reason)
        end)
    end)

    describe("server day", function()
        local LAUNCH = V.LAUNCH_EPOCH

        it("counts days since Forever's launch, 0 before it", function()
            assert.equal(1793833200, LAUNCH, "2026-11-04 15:00 PST")
            assert.equal(0, V.ServerDay(LAUNCH - 15 * 86400))
            assert.equal(0, V.ServerDay(LAUNCH))
            assert.equal(0, V.ServerDay(LAUNCH + 86399))
            assert.equal(1, V.ServerDay(LAUNCH + 86400))
            assert.equal(35, V.ServerDay(LAUNCH + 35 * 86400 + 100), "Dec 9, first raids")
            assert.is_nil(V.ServerDay(nil))
        end)

        it("a realm first seen before the launch date counts from when it was first seen", function()
            assert.equal(10, V.ServerDay(LAUNCH, LAUNCH - 10 * 86400))
            assert.equal(2, V.ServerDay(LAUNCH + 2 * 86400, LAUNCH + 86400), "a later first sight changes nothing")
            assert.equal(2, V.ServerDay(LAUNCH + 2 * 86400, "junk"))
        end)
    end)

    describe("liquidity (ALGORITHM-RESEARCH 4.3)", function()
        -- rows newest first: { maxSeen, minSeen }
        local function rows(...)
            local list, day = {}, 100
            for _, pair in ipairs({ ... }) do
                list[#list + 1] = { day = day, maxSeen = pair[1], minSeen = pair[2] or pair[1], available = 1 }
                day = day - 1
            end
            return list
        end

        it("needs two recent and two older scanned days for a trend", function()
            local L = V.Liquidity({ available = 500, history = rows({ 40 }, { 40 }, { 40 }) }, 20)
            assert.same({ available = 500, glut = false }, L)
            L = V.Liquidity({ available = 500, history = rows({ 40 }, { 40 }, { 40 }, { 60 }) }, 20)
            assert.is_nil(L.trend, "one older day isn't enough")
            L = V.Liquidity({ available = 500, history = rows({ 45 }, { 40 }, { 44 }, { 60 }, { 62 }, { 58 }) }, 20)
            assert.equal(44, L.recent)
            assert.equal(60, L.older)
            assert.is_true(math.abs(L.trend - (44 / 60 - 1)) < 1e-9)
            assert.same({ available = nil, glut = false }, V.Liquidity(nil, 20))
        end)

        it("a glut is 10x our count listed and the recent median down 25% or more", function()
            local falling = rows({ 45 }, { 40 }, { 44 }, { 60 }, { 62 }, { 58 }) -- -26.7%
            assert.is_true(V.Liquidity({ available = 200, history = falling }, 20).glut)
            assert.is_false(V.Liquidity({ available = 199, history = falling }, 20).glut, "not enough listed")
            assert.is_false(V.Liquidity({ available = 200, history = falling }, 21).glut)
            assert.is_false(V.Liquidity({ history = falling }, 20).glut, "no quantity known")
            local flat = rows({ 60 }, { 58 }, { 62 }, { 60 }, { 60 })
            assert.is_false(V.Liquidity({ available = 9999, history = flat }, 20).glut, "busy but stable: liquid")
            local gentle = rows({ 50 }, { 50 }, { 50 }, { 60 }, { 60 }) -- -16.7%
            assert.is_false(V.Liquidity({ available = 9999, history = gentle }, 20).glut)
        end)

        it("a glut is valued at the floor of the market with the deposit counted lost", function()
            local history = rows({ 44, 30 }, { 40, 30 }, { 45, 30 }, { 60 }, { 62 }, { 58 })
            -- liquid: 20 x 44c median = 8s 80c x 0.95 = 8s 36c - 60c (half deposit) - 30c = 7s 46c, gain 5s 46c
            local r = V.Evaluate(item(), { ah = 44, available = 100, history = history }, S)
            assert.equal("mail", r.action)
            assert.equal(44, r.ahUnit)
            assert.equal(60, r.depositCounted)
            assert.equal(546, r.gain)
            -- glut: the 30c floor, 6s x 0.95 = 5s 70c - 1s 20c - 30c = 4s 20c, gain 2s 20c: stays
            r = V.Evaluate(item(), { ah = 44, available = 500, history = history }, S)
            assert.equal("keep", r.action)
            assert.is_true(r.liquidity.glut)
            assert.equal(30, r.ahUnit)
            assert.equal(120, r.depositCounted)
            assert.equal(220, r.gain)
        end)
    end)

    describe("no auction price yet (operator, 2026-11-08)", function()
        -- "going to the bank alt on no data is better than holding on the main"
        local potion = function(o)
            local t = item({ itemID = 858, link = "[Lesser Healing Potion]", classID = 0, count = 5, vendor = 5 })
            for k, v in pairs(o or {}) do t[k] = v end
            return t
        end
        local recipe = item({ itemID = 7975, link = "[Plans: Iridescent Hammer]", count = 1, quality = 2, classID = 9,
            subclassID = 4, vendor = 450 })

        it("goes to the bank alt on any launch day, with no gain made up", function()
            for _, day in ipairs({ 0, 13, 14, 90 }) do
                S.serverDay = day
                local r = V.Evaluate(potion(), { ah = nil }, S)
                assert.equal("mail", r.action)
                assert.equal(V.NO_PRICE, r.route)
                assert.is_nil(r.gain)
                assert.is_nil(r.listRoute, "never turned into Bank: it goes to the bank alt as it is")
                assert.equal(25, r.vendor)
                assert.equal(30, r.postage)
            end
            S.serverDay = nil
            assert.equal(V.NO_PRICE, V.Evaluate(potion(), { ah = nil }, S).route, "unknown server day too")
        end)

        it("recipes and green or blue gear too; grey junk stays for the vendor", function()
            assert.equal(V.NO_PRICE, V.Evaluate(recipe, { ah = nil }, S).route, "the screenshot's Plans: Iridescent Hammer")
            assert.equal(V.NO_PRICE, V.Evaluate(potion({ quality = 2, classID = 4 }), { ah = nil }, S).route, "green armor")
            assert.equal(V.NO_PRICE, V.Evaluate(potion({ quality = 3, classID = 2 }), { ah = nil }, S).route, "blue weapon")
            assert.equal(V.NO_PRICE, V.Evaluate(potion({ classID = 4 }), { ah = nil }, S).route, "white armor")
            local junk = V.Evaluate(potion({ quality = 0, classID = 15 }), { ah = nil }, S)
            assert.equal("keep", junk.action)
            assert.equal("junk (no price data)", junk.reason)
            V.UNPRICED_GEAR = false
            assert.equal("no price", V.Evaluate(potion({ quality = 2, classID = 4 }), { ah = nil }, S).reason,
                "the switch keeps unpriced gear")
            assert.equal(V.NO_PRICE, V.Evaluate(recipe, { ah = nil }, S).route, "recipes aren't gear")
            V.UNPRICED_GEAR = true
        end)

        it("never when the price call failed or over a current price; a stale price goes too (operator, 2026-11-08)", function()
            local failed = V.Evaluate(potion(), { ah = nil, failed = true }, S)
            assert.equal("keep", failed.action)
            assert.equal("no price", failed.reason)
            assert.is_true(failed.failed)
            assert.equal("keep", V.Evaluate(item(), { ah = nil, failed = true }, S).action, "a staple neither (AGENTS safety)")
            local deOn = V.Settings(nil, true)
            local robe = potion({ count = 1, quality = 2, classID = 4, vendor = 300 })
            assert.equal("de", V.Evaluate(robe, { ah = nil, de = 5000 }, deOn).route)
            local failedDE = V.Evaluate(robe, { ah = nil, failed = true, de = 5000 }, deOn)
            assert.equal("keep", failedDE.action, "a failed auction call keeps it even when disenchanting pays (Codex review)")
            assert.is_true(failedDE.failed)
            local stale = V.Evaluate(potion(), { ah = 40, age = 8 }, S)
            assert.equal(V.NO_PRICE, stale.route, "\"Stale prices go too\"")
            assert.equal("auction price too old (8 days)", stale.reason)
            assert.is_nil(stale.gain, "the old price isn't used")
            assert.equal("ah", V.Evaluate(potion(), { ah = 4000, age = 7 }, S).route, "7 days still counts")
            assert.equal("keep", V.Evaluate(potion({ quality = 0, classID = 15 }), { ah = 40, age = 8 }, S).action,
                "stale junk stays for the vendor")
            S = V.Settings(nil, true)
            local green = potion({ count = 1, quality = 2, classID = 4, vendor = 500 })
            assert.equal(V.NO_PRICE, V.Evaluate(green, { ah = 90000, age = 8, de = 100 }, S).route,
                "stale AH, disenchanting doesn't pay: to the bank alt")
            assert.equal("not worth it", V.Evaluate(item(), { ah = 40 }, S).reason, "priced: the numbers decide")
        end)

        it("the hard keeps and the profession keep come first", function()
            for _, o in ipairs({ { locked = true }, { bound = true }, { quest = true }, { questFor = "Goulash" },
                { inUse = true }, { conjured = true }, { itemID = 5512 } }) do
                assert.equal("keep", V.Evaluate(potion(o), { ah = nil }, S).action)
            end
            assert.equal("profession tool", V.Evaluate(potion({ itemID = 2901 }), { ah = nil }, S).reason)
            S.professions = { 197 }
            assert.equal("your Tailoring needs it", V.Evaluate(item({ subclassID = 5 }), { ah = nil }, S).reason)
        end)

        it("disenchanting that doesn't pay leaves the auction house open: to the bank alt", function()
            S = V.Settings(nil, true)
            local green = potion({ count = 1, quality = 2, classID = 4, vendor = 500 })
            local r = V.Evaluate(green, { ah = nil, de = 100 }, S)
            assert.equal(V.NO_PRICE, r.route)
            assert.is_nil(r.gain, "the loss on disenchanting isn't counted as its gain")
            assert.equal("de", V.Evaluate(green, { ah = nil, de = 5000 }, S).route, "disenchanting that pays still wins")
            assert.equal("not worth it", V.Evaluate(green, { ah = 400, de = 100 }, S).reason, "priced: the numbers decide")
        end)

        it("a staple trade good is mailed as a common item, whatever the launch day or quality", function()
            for _, day in ipairs({ 0, 13, 14, 90 }) do
                S.serverDay = day
                local r = V.Evaluate(item({ itemID = 2835, link = "[Rough Stone]", count = 10, vendor = 2 }), { ah = nil }, S)
                assert.equal("common", r.route)
                assert.equal("staple trade good (no price yet)", r.reason)
            end
            local essence = item({ itemID = 10938, link = "[Lesser Magic Essence]", quality = 2, subclassID = 12, count = 2 })
            S.serverDay = 40
            assert.equal("common", V.Evaluate(essence, { ah = nil }, S).route)
            S.serverDay = 10
            assert.equal("bank", V.Evaluate(essence, { ah = nil }, S).route, "late demand before the raids: Bank on top")
        end)
    end)

    describe("staple trade goods (the flat rules, operator, 2026-11-08)", function()
        it("is one table of item IDs to names: cloth, leather, ore, bars, stone, herbs, elemental, enchanting", function()
            local n = 0
            for id, name in pairs(V.STAPLES) do
                n = n + 1
                assert.equal("number", type(id))
                assert.equal("string", type(name))
            end
            assert.is_true(n >= 100, "the list in the PR")
            for _, id in ipairs({ 2589, 14047, 2318, 2770, 3860, 2835, 2447, 13468, 7068, 10940, 14344 }) do
                assert.truthy(V.STAPLES[id], id)
            end
            assert.is_true(V.IsStaple({ itemID = 4306 }))
            assert.is_false(V.IsStaple({ itemID = 858 }))
            assert.is_false(V.IsStaple({}))
        end)

        it("agrees with the names the addon's other tables give the same IDs", function()
            local ns = loadAddon()
            local others = {}
            for _, list in pairs(ns.Tiers.DONE) do
                for _, row in ipairs(list) do others[row[1]] = row[3] end
            end
            for id, name in pairs(V.LATE_METALS) do others[id] = name end
            for id, name in pairs(V.STARTER_HERBS) do others[id] = name end
            local checked = 0
            for id, name in pairs(V.STAPLES) do
                if others[id] then
                    assert.equal(others[id], name, "item " .. id)
                    checked = checked + 1
                end
            end
            assert.is_true(checked >= 40, "cross-checked " .. checked)
        end)

        it("without any price source, a non-white staple is mailed too; other greens stay", function()
            local essence = item({ itemID = 10938, link = "[Lesser Magic Essence]", quality = 2, subclassID = 12, count = 2 })
            local r = V.Evaluate(essence, nil, S)
            assert.equal("mail", r.action)
            assert.equal("staple trade good (no price data)", r.reason)
            assert.equal("uncommon or better (no price data)",
                V.Evaluate(item({ itemID = 5000, quality = 2, classID = 4 }), nil, S).reason)
            assert.equal("junk (no price data)", V.Evaluate(item({ quality = 0 }), nil, S).reason, "a grey never")
        end)
    end)

    describe("recipes (operator, 2026-11-08)", function()
        it("knows each recipe's crafting profession from its subclass (Enum.ItemRecipeSubclass)", function()
            local function of(sub) return V.RecipeProfession({ classID = 9, subclassID = sub }) end
            assert.equal(165, of(1), "Leatherworking")
            assert.equal(197, of(2), "Tailoring")
            assert.equal(202, of(3), "Engineering")
            assert.equal(164, of(4), "Blacksmithing")
            assert.equal(185, of(5), "Cooking")
            assert.equal(171, of(6), "Alchemy")
            assert.equal(129, of(7), "First Aid")
            assert.equal(333, of(8), "Enchanting")
            assert.is_nil(of(0), "a book")
            assert.is_nil(of(9), "Fishing: not a crafting profession")
            assert.is_nil(V.RecipeProfession({ classID = 7, subclassID = 4 }), "not a recipe")
            for _, id in pairs(V.RECIPE_PROFESSION) do assert.truthy(V.PROFESSION_MATS[id], "bindable: " .. id) end
        end)
    end)

    describe("bank (ALGORITHM-RESEARCH 4.4)", function()
        local function dust(o)
            local t = item({ itemID = 10940, link = "[Strange Dust]", subclassID = 12, count = 10, vendor = 2 })
            for k, v in pairs(o or {}) do t[k] = v end
            return t
        end

        it("knows which trade goods sell later: enchanting, herbs past the starters, elementals, high metals", function()
            assert.equal("enchanting materials", V.LateDemand(dust()))
            assert.equal("herbs", V.LateDemand(item({ itemID = 2453, subclassID = 9 })), "Bruiseweed")
            assert.is_nil(V.LateDemand(item({ itemID = 2447, subclassID = 9 })), "Peacebloom sells now")
            assert.equal("elemental materials", V.LateDemand(item({ itemID = 7067, subclassID = 10 })))
            assert.equal("high-level metal", V.LateDemand(item({ itemID = 3858, subclassID = 7 })), "Mithril Ore")
            assert.is_nil(V.LateDemand(item({ itemID = 2770, subclassID = 7 })), "Copper Ore")
            assert.is_nil(V.LateDemand(item({ subclassID = 5 })), "cloth")
            assert.is_nil(V.LateDemand(item({ classID = 4, subclassID = 12 })), "armor")
        end)

        it("banks a late-demand item that would be mailed for the auction house, until the raids open", function()
            S.serverDay = 10
            local r = V.Evaluate(dust(), { ah = 100 }, S)
            assert.equal("mail", r.action)
            assert.equal("bank", r.route)
            assert.equal("ah", r.listRoute)
            assert.equal("bank: enchanting materials sell once raids open (launch day 35)", r.reason)
            assert.equal(950 - 50 - 30 - 20, r.gain, "the gain it would bring listed today (1s minimum deposit, half)")
            S.serverDay = 34
            assert.equal("bank", V.Evaluate(dust(), { ah = 100 }, S).route)
            S.serverDay = 35
            assert.equal("ah", V.Evaluate(dust(), { ah = 100 }, S).route)
            S.serverDay = nil
            assert.equal("ah", V.Evaluate(dust(), { ah = 100 }, S).route, "unknown server day: never")
        end)

        it("only what would be mailed anyway: a dud stays, disenchanting is never banked", function()
            S.serverDay = 10
            assert.equal("not worth it", V.Evaluate(dust(), { ah = 5 }, S).reason)
            assert.equal("locked", V.Evaluate(dust({ locked = true }), { ah = 100 }, S).reason)
            S = V.Settings(nil, true)
            S.serverDay = 10
            local green = item({ count = 1, quality = 2, classID = 4, subclassID = 12, vendor = 50 })
            assert.equal("de", V.Evaluate(green, { ah = 100, de = 1000 }, S).route)
        end)

        it("banks common items too (no Auctionator, or an unpriced staple)", function()
            S.serverDay = 10
            local r = V.Evaluate(dust(), nil, S)
            assert.equal("bank", r.route)
            assert.equal("common", r.listRoute)
            assert.equal("bank", V.Evaluate(dust(), { ah = nil }, S).route, "a staple, no price yet")
            S.serverDay = 40
            assert.equal("common", V.Evaluate(dust(), nil, S).route)
            assert.equal("staple trade good (no price yet)", V.Evaluate(dust(), { ah = nil }, S).reason)
        end)

        it("banks a flooded market that was worth 1.5x more last week, until launch day 60", function()
            local function rows(...)
                local list, day = {}, 100
                for _, pair in ipairs({ ... }) do
                    list[#list + 1] = { day = day, maxSeen = pair[1], minSeen = pair[2] or pair[1] }
                    day = day - 1
                end
                return list
            end
            local history = rows({ 88, 60 }, { 80, 60 }, { 90, 60 }, { 120 }, { 124 }, { 116 })
            S.serverDay = 20
            -- glut: floor 60c x 20 = 12s x 0.95 = 11s 40c - 1s 20c - 30c = 9s 90c, gain 7s 90c: mails; 120c >= 1.5 x 60c
            local r = V.Evaluate(item(), { ah = 88, available = 1000, history = history }, S)
            assert.equal("bank", r.route)
            assert.equal("bank: the market is flooded (1000 listed, -27% vs last week)", r.reason)
            assert.equal(790, r.gain)
            S.serverDay = 60
            assert.equal("ah", V.Evaluate(item(), { ah = 88, available = 1000, history = history }, S).route)
            S.serverDay = 20
            assert.equal("ah", V.Evaluate(item(), { ah = 88, available = 100, history = history }, S).route, "no glut")
            local shallow = rows({ 88, 85 }, { 80, 85 }, { 90, 85 }, { 120 }, { 124 }, { 116 }) -- 120 < 1.5 x 85
            assert.equal("ah", V.Evaluate(item(), { ah = 88, available = 1000, history = shallow }, S).route)
            local sword = item({ classID = 2, subclassID = 7, quality = 1, count = 1, vendor = 0 })
            local price = { ah = 8800, available = 50, history = rows({ 8800, 6000 }, { 8000, 6000 }, { 9000, 6000 },
                { 12000 }, { 12400 }, { 11600 }) }
            assert.equal("ah", V.Evaluate(sword, price, S).route, "a glut of gear is listed, never banked (trade goods only)")
            assert.is_true(V.Evaluate(sword, price, S).liquidity.glut)
        end)
    end)

    describe("minimum gain over the server's life (ALGORITHM-RESEARCH 4.5)", function()
        it("is the setting until the raids open, then grows by 1/180 a day, at most to twice", function()
            assert.equal(500, V.MinGain(S))
            S.serverDay = 34
            assert.equal(500, V.MinGain(S))
            S.serverDay = 35
            assert.equal(500, V.MinGain(S))
            S.serverDay = 90
            assert.equal(652, V.MinGain(S), "500 x (1 + 55 / 180)")
            assert.equal(652, V.Threshold(200, S))
            assert.equal(2500, V.Threshold(10000, S), "the percentage still wins when it's more")
            S.serverDay = 1000
            assert.equal(1000, V.MinGain(S))
            S.minGain = 0
            assert.equal(0, V.MinGain(S))
            S.minGain, S.serverDay = 100, 62
            assert.equal(115, V.MinGain(S), "integer arithmetic: 100 + floor(100 x 27 / 180), not floor(114.99...)")
        end)

        it("changes the verdict: 20 Linen at 49c mails at launch, not at launch day 90", function()
            -- 980 x 0.95 = 931 - 60 - 30 - 200 = 6s 41c
            assert.equal("mail", V.Evaluate(item(), { ah = 49 }, S).action)
            S.serverDay = 90
            local r = V.Evaluate(item(), { ah = 49 }, S)
            assert.equal("keep", r.action)
            assert.equal(641, r.gain)
            assert.equal(652, r.threshold)
            assert.equal("mail", V.Evaluate(item(), { ah = 60 }, S).action, "8s 50c still clears it")
        end)
    end)

    describe("disenchant", function()
        local green
        before_each(function()
            green = item({ itemID = 5000, link = "[Green Gloves]", count = 1, quality = 2, classID = 4, vendor = 50 })
            S = V.Settings(nil, true)
        end)

        it("is compared only when on, for uncommon+ armor and weapons", function()
            assert.is_true(V.CanDisenchant(green))
            assert.is_true(V.CanDisenchant(item({ quality = 3, classID = 2 })))
            assert.is_false(V.CanDisenchant(item({ quality = 1, classID = 4 })), "white gear")
            assert.is_false(V.CanDisenchant(item({ quality = 2, classID = 7 })), "trade goods")
            local r = V.Evaluate(green, { de = 1000 }, S)
            assert.equal("mail", r.action)
            assert.equal("de", r.route)
            assert.equal(1000 - 30, r.deNet)
            assert.equal(920, r.gain)
            S.disenchant = false
            assert.equal(V.NO_PRICE, V.Evaluate(green, { de = 1000 }, S).route, "no auction price: to the bank alt")
        end)

        it("the better of AH and disenchant wins", function()
            -- AH: 950 - floor(2.5) x 12 - 30 = 896; DE: 1970
            assert.equal("de", V.Evaluate(green, { ah = 1000, de = 2000 }, S).route)
            -- AH: 2850 - 24 - 30 = 2796; DE: 970
            assert.equal("ah", V.Evaluate(green, { ah = 3000, de = 1000 }, S).route)
        end)
    end)

    describe("without Auctionator", function()
        it("mails plain white items and keeps grey junk and uncommon or better", function()
            local r = V.Evaluate(item(), nil, S)
            assert.equal("mail", r.action)
            assert.equal("common", r.route)
            assert.equal("junk (no price data)", V.Evaluate(item({ quality = 0 }), nil, S).reason)
            assert.equal("uncommon or better (no price data)", V.Evaluate(item({ itemID = 5000, quality = 2 }), nil, S).reason)
        end)
    end)

    it("keeps locked, soulbound, quest, in-use and not-yet-loaded items before looking at prices", function()
        local rich = { ah = 100000 }
        assert.equal("locked", V.Evaluate(item({ locked = true, bound = true }), rich, S).reason)
        assert.equal("soulbound", V.Evaluate(item({ bound = true }), rich, S).reason)
        assert.equal("quest item", V.Evaluate(item({ quest = true }), rich, S).reason)
        assert.equal("in use", V.Evaluate(item({ inUse = true }), rich, S).reason)
        local unloaded = item()
        unloaded.vendor = nil
        assert.equal("item info not loaded yet", V.Evaluate(unloaded, rich, S).reason)
        assert.equal("locked", V.Evaluate(item({ locked = true }), nil, S).reason, "also without Auctionator")
    end)

    describe("profession materials", function()
        local cloth = { link = "[Linen Cloth]", itemID = 2589, count = 20, stacks = 1, quality = 1, classID = 7,
            subclassID = 5, vendor = 10 }

        it("knows the crafting professions by skill line, and ignores gathering ones", function()
            local list = V.CraftingProfessions({ 186, { skillLine = 197 }, 333, 999, "junk" })
            assert.equal(2, #list)
            assert.equal("Tailoring", list[1].name)
            assert.equal("cloth", list[1].mats)
            assert.equal("Enchanting", list[2].name)
            assert.same({}, V.CraftingProfessions(nil))
        end)

        it("names the profession that needs a trade good, by its subclass", function()
            assert.equal("Tailoring", V.NeededBy(cloth, { 197 }))
            assert.equal("First Aid", V.NeededBy(cloth, { 129 }))
            assert.is_nil(V.NeededBy({ itemID = 4306, classID = 7, subclassID = 5 }, { 164, 186 }),
                "a blacksmith miner doesn't need Silk Cloth (Linen it levels with, to 105)")
            assert.equal("Blacksmithing", V.NeededBy({ classID = 7, subclassID = 7 }, { 164 }))
            assert.equal("Engineering", V.NeededBy({ classID = 7, subclassID = 1 }, { 202 }))
            assert.equal("Enchanting", V.NeededBy({ classID = 7, subclassID = 12 }, { 333 }))
            assert.equal("Alchemy", V.NeededBy({ classID = 7, subclassID = 9 }, { 171 }))
            assert.is_nil(V.NeededBy({ classID = 7, subclassID = 10 }, { 164, 171, 202 }), "elementals stay mailable")
            assert.is_nil(V.NeededBy({ classID = 4, subclassID = 5 }, { 197 }), "cloth armour isn't a material")
            assert.is_nil(V.NeededBy(cloth, nil))
        end)

        it("on my bank alt: the materials are mailed to be banked, behind every hard keep and the no-price rule", function()
            S.professions = { 197 }
            S.matsToBankAlt = true
            local rich = { ah = 1000, exact = true, age = 0 }
            local white = { classID = 7, subclassID = 5, quality = 1, vendor = 13, count = 20, stacks = 1 }
            local r = V.Evaluate(white, rich, S)
            assert.same({ "mail", "bank", "bank: your Tailoring needs it", "Tailoring", true, 260, 30 },
                { r.action, r.route, r.reason, r.neededBy, r.craftBank, r.vendor, r.postage })
            assert.equal("mail", V.Evaluate(white, nil, S).action, "no price source: a white item still goes")
            local green = { classID = 7, subclassID = 5, quality = 2, vendor = 13, count = 1, stacks = 1 }
            assert.equal("keep", V.Evaluate(green, nil, S).action, "no price source: only white items and staples go")
            assert.equal("your Tailoring needs it", V.Evaluate(green, nil, S).reason)
            assert.equal("keep", V.Evaluate(white, { failed = true }, S).action, "a failed price call mails nothing")
            local unloaded = { classID = 7, subclassID = 5, quality = 1, count = 1, stacks = 1 }
            assert.equal("keep", V.Evaluate(unloaded, rich, S).action, "item data not loaded: stays")
            for _, hard in ipairs({ "locked", "bound", "quest", "inUse" }) do
                local it = { classID = 7, subclassID = 5, quality = 1, vendor = 13, count = 1, stacks = 1, [hard] = true }
                assert.equal("keep", V.Evaluate(it, rich, S).action, hard)
            end
            S.keepProfessionMats = false
            assert.is_nil(V.Evaluate(white, rich, S).craftBank, "keep off: valued like anything else")
            S.keepProfessionMats, S.matsToBankAlt = true, false
        end)

        it("keeps the materials before any pricing, unless the setting is off", function()
            S.professions = { 197 }
            local rich = { ah = 1000, exact = true, age = 0 }
            local r = V.Evaluate(cloth, rich, S)
            assert.equal("keep", r.action)
            assert.equal("your Tailoring needs it", r.reason)
            S.keepProfessionMats = false
            assert.equal("mail", V.Evaluate(cloth, rich, S).action)
            S.keepProfessionMats = true
            S.professions = { 186 }
            assert.equal("mail", V.Evaluate(cloth, rich, S).action, "a miner mails cloth")
            assert.equal("locked", V.Evaluate({ locked = true, classID = 7, subclassID = 5 }, rich, S).reason,
                "a lock is still the first reason")
        end)

        it("knows the gathering professions and what they bring in", function()
            local list = V.GatheringProfessions({ 186, { skillLine = 182 }, 197, 393, 356, "junk" })
            assert.equal(4, #list)
            assert.same({ "Mining", "Herbalism", "Skinning", "Fishing" },
                { list[1].name, list[2].name, list[3].name, list[4].name })
            assert.equal("Mining", V.GatheredBy({ classID = 7, subclassID = 7 }, { 164, 186 }))
            assert.equal("Herbalism", V.GatheredBy({ classID = 7, subclassID = 9 }, { 182 }))
            assert.equal("Skinning", V.GatheredBy({ classID = 7, subclassID = 6 }, { 393 }))
            assert.equal("Fishing", V.GatheredBy({ classID = 7, subclassID = 8 }, { 356 }))
            assert.is_nil(V.GatheredBy(cloth, { 186, 182, 393, 356 }), "nobody gathers cloth")
            assert.is_nil(V.GatheredBy({ classID = 4, subclassID = 7 }, { 186 }), "trade goods only")
        end)

        it("'Sell what I gather' (off by default): a gatherer-crafter mails what they gather", function()
            local ore = { classID = 7, subclassID = 7, quality = 1, vendor = 5, count = 20 }
            local herb = { classID = 7, subclassID = 9, quality = 1, vendor = 5, count = 20 }
            local rich = { ah = 1000, exact = true, age = 0 }
            S.professions = { 164, 186 } -- Blacksmithing and Mining
            assert.is_false(S.sellGathered)
            assert.equal("your Blacksmithing needs it", V.Evaluate(ore, rich, S).reason, "off: kept for the craft")
            S.sellGathered = true
            assert.equal("mail", V.Evaluate(ore, rich, S).action, "on: the ore goes to the bank alt to be sold")
            S.professions = { 164, 171, 186 } -- Blacksmithing, Alchemy, Mining: herbs aren't gathered here
            assert.equal("your Alchemy needs it", V.Evaluate(herb, rich, S).reason)
            S.professions = { 197 }
            assert.equal("your Tailoring needs it", V.Evaluate(cloth, rich, S).reason, "no gathering profession: no change")
            assert.equal("locked", V.Evaluate({ locked = true, classID = 7, subclassID = 7 }, rich, S).reason)
            S.sellGathered = false
        end)
    end)

    describe("settings", function()
        it("defaults: 24h, 5% cut, 30c postage, 5s and 25%, 7 days", function()
            assert.same({ duration = 3, relistFactor = 0.5, cut = 0.05, postage = 30, minGain = 500, minGainPct = 0.25,
                maxAgeDays = 7, disenchant = false, keepProfessionMats = true, matsToBankAlt = false, sellGathered = false,
                sendAuction = true, sendDisenchant = true, sendBank = true, sendVendor = false }, S)
        end)

        it("disenchant follows Disenchantry until the player sets it", function()
            assert.is_true(V.Settings(nil, true).disenchant)
            assert.is_false(V.Settings({ disenchant = false }, true).disenchant)
            assert.is_true(V.Settings({ disenchant = true }, false).disenchant)
        end)

        it("ignores unknown keys, wrong types and durations that don't exist", function()
            local s = V.Settings({ duration = 9, minGain = "lots", other = 1 }, false)
            assert.equal(3, s.duration)
            assert.equal(500, s.minGain)
            assert.is_nil(s.other)
        end)
    end)

    it("formats money", function()
        assert.equal("0c", V.Money(0))
        assert.equal("45c", V.Money(45))
        assert.equal("4s 10c", V.Money(410))
        assert.equal("1g 5c", V.Money(10005))
        assert.equal("-1s 20c", V.Money(-120))
        assert.equal("3g 20s", V.Money(32000))
    end)
end)
