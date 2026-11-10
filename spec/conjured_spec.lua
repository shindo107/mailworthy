-- Conjured items (operator, 2026-11-10: "mailworthy tried to send a healthstone in my inventory
-- to my bank alt to ah yesterday ... should always be keep as they are ephemeral items"): a
-- Healthstone, a mana gem, a mage's food and water never leave the bags and aren't listed.
local loadAddon = require("spec.support.load_addon")

local HEALTHSTONE = 5512 -- Minor Healthstone: white, sells for nothing, no auction price
local BISCUIT = 211999   -- not in Conjured.ITEMS: only its tooltip says "Conjured Item"
local BOB = "Bob Surname"

describe("conjured items", function()
    local ns, prices

    local function find(list, itemID)
        for _, it in ipairs(list) do if it.itemID == itemID then return it end end
    end

    local function useAuctionator()
        _G.Auctionator = { API = { v1 = {
            GetAuctionPriceByItemLink = function(_, l) return prices[l] end,
            GetAuctionAgeByItemLink = function() return 0 end,
        } } }
    end

    before_each(function()
        ns = loadAddon()
        WowStub.state.serverTime = ns.Valuation.LAUNCH_EPOCH + 20 * 86400
        prices = {}
        ns.Fire("PLAYER_LOGIN")
        ns.Config.SetBankAlt("Roknua Themicrulah")
        WowStub.setBag(0, 1, WowStub.item(HEALTHSTONE, "Minor Healthstone", { sell = 0, class = 0 }))
        WowStub.setBag(0, 2, WowStub.item(2770, "Copper Ore", { count = 20, sell = 5, class = 7, subclass = 7 }))
        prices[WowStub.link(2770, "Copper Ore")] = 174
    end)
    after_each(function()
        _G.Auctionator = nil
        for _, line in ipairs(ns.Log.Lines()) do assert.is_nil(line:find("error", 1, true), line) end
    end)

    it("knows Classic's conjured items by ID, every healthstone among them", function()
        local C = ns.Conjured
        for _, id in ipairs({ 5512, 19004, 19005, 5511, 19006, 19007, 5509, 19008, 19009, 5510, 19010, 19011,
            9421, 19012, 19013 }) do
            assert.is_true(C.Known(id), "healthstone " .. id)
            assert.truthy(C.ITEMS[id]:find("Healthstone", 1, true))
        end
        assert.is_true(C.Known(8008), "Mana Ruby")
        assert.is_true(C.Known(8079), "Conjured Crystal Water")
        assert.is_true(C.Known("22895"), "Conjured Cinnamon Roll, as a string")
        assert.is_false(C.Known(2770), "Copper Ore")
        assert.is_false(C.Known(6948), "Hearthstone: soulbound, not conjured")
        assert.is_false(C.Known(nil))
    end)

    it("reads the tooltip's own line, in the client's words", function()
        local C = ns.Conjured
        assert.is_true(C.IsLine("Conjured Item", "Conjured Item"))
        assert.is_true(C.IsLine("  |cffffffffConjured Item|r ", "Conjured Item"), "colour codes and spaces don't count")
        assert.is_true(C.IsLine("|cnWHITE_FONT_COLOR:Conjured Item|r", "Conjured Item"), "a named colour neither")
        assert.is_true(C.IsLine("Herbeigezauberter Gegenstand", "Herbeigezauberter Gegenstand"))
        assert.is_true(C.IsLine("Conjured Item"), "no global string: the English text")
        assert.is_true(C.IsLine("Conjured Item", ""))
        assert.is_false(C.IsLine("Conjured Items disappear if logged out for more than 15 minutes.", "Conjured Item"))
        assert.is_false(C.IsLine("Minor Healthstone", "Conjured Item"))
        assert.is_false(C.IsLine(nil, "Conjured Item"))
    end)

    it("a Healthstone with no auction price stays, and the window doesn't list it", function()
        useAuctionator()
        local result = ns.Bags.Evaluate()
        assert.is_nil(find(result.mail, HEALTHSTONE), "the report's bug: mailed to the bank alt as 'no auction price yet'")
        assert.is_nil(find(result.keep, HEALTHSTONE), "not under Staying either")
        local stone = find(result.unmailable, HEALTHSTONE)
        assert.equal("keep", stone.result.action)
        assert.equal("conjured item", stone.result.reason)
        assert.truthy(find(result.mail, 2770), "the rest mails as before")
        assert.equal(1, #result.mail)
        assert.truthy(ns.Bags.Report(result):find(
            "NOT MAILABLE (soulbound, quest or conjured, not listed in the window): [Minor Healthstone] x1", 1, true))
    end)

    it("stays whatever the auction house says it is worth", function()
        useAuctionator()
        prices[WowStub.link(HEALTHSTONE, "Minor Healthstone")] = 500000
        local result = ns.Bags.Evaluate()
        assert.is_nil(find(result.mail, HEALTHSTONE))
        assert.equal("conjured item", find(result.unmailable, HEALTHSTONE).result.reason)
    end)

    it("stays without a price source too: not a 'common item'", function()
        local result = ns.Bags.Evaluate()
        assert.is_false(result.priced)
        assert.is_nil(find(result.mail, HEALTHSTONE), "white items mail without Auctionator; this one doesn't")
        assert.equal("conjured item", find(result.unmailable, HEALTHSTONE).result.reason)
        assert.equal("common", find(result.mail, 2770).result.route)
    end)

    it("an item only the tooltip calls conjured stays; without the line it mails", function()
        useAuctionator()
        WowStub.setBag(0, 3, WowStub.item(BISCUIT, "Forever Mana Biscuit", { count = 20, sell = 0, class = 0 }))
        assert.is_false(ns.Conjured.Is(BISCUIT))
        assert.truthy(find(ns.Bags.Evaluate().mail, BISCUIT), "an unpriced white item: to the bank alt")
        WowStub.state.conjured[BISCUIT] = true
        ns.Conjured.Forget(true)
        assert.is_true(ns.Conjured.Is(BISCUIT))
        local result = ns.Bags.Evaluate()
        assert.is_nil(find(result.mail, BISCUIT))
        assert.equal("conjured item", find(result.unmailable, BISCUIT).result.reason)
    end)

    it("a tooltip that raises or has nothing yet answers 'not conjured' without an error; the IDs still hold", function()
        local real = _G.C_TooltipInfo
        _G.C_TooltipInfo = { GetItemByID = function() error("boom") end }
        assert.is_false(ns.Conjured.Is(BISCUIT))
        assert.is_true(ns.Conjured.Is(HEALTHSTONE))
        _G.C_TooltipInfo = { GetItemByID = function() return nil end }
        assert.is_false(ns.Conjured.Is(BISCUIT))
        _G.C_TooltipInfo = nil
        assert.is_false(ns.Conjured.Is(BISCUIT))
        assert.is_true(ns.Conjured.Is(HEALTHSTONE))
        useAuctionator()
        assert.equal("conjured item", find(ns.Bags.Evaluate().unmailable, HEALTHSTONE).result.reason)
        _G.C_TooltipInfo = real
    end)

    it("without the ITEM_CONJURED global string the English line still counts", function()
        local label = _G.ITEM_CONJURED
        _G.ITEM_CONJURED = nil
        WowStub.state.conjured[BISCUIT] = true
        local ok, is = pcall(ns.Conjured.Is, BISCUIT)
        _G.ITEM_CONJURED = label
        assert.is_true(ok)
        assert.is_true(is)
    end)

    it("the pure rule: a hard keep, after soulbound and quest, before any price", function()
        local V, S = ns.Valuation, ns.Valuation.DEFAULTS
        local stone = { itemID = HEALTHSTONE, count = 1, stacks = 1, quality = 1, classID = 0, vendor = 0 }
        assert.same({ action = "keep", reason = "conjured item" }, V.Evaluate(stone, { ah = 90000, age = 0 }, S))
        assert.same({ action = "keep", reason = "conjured item" }, V.Evaluate(stone, nil, S))
        assert.same({ action = "keep", reason = "conjured item" },
            V.Evaluate({ itemID = BISCUIT, conjured = true, count = 1, quality = 1, vendor = 0 }, { ah = nil }, S))
        assert.is_true(V.Unmailable({ action = "keep", reason = "conjured item" }))
        assert.is_true(ns.Routes.HARD_KEEPS["conjured item"])
        assert.is_true(ns.BankAlt.QUIET_KEEPS["conjured item"], "the game's tooltip already says so")
    end)

    it("no binding takes one: a warlock-only item goes to the warlock friend, a conjured one doesn't", function()
        useAuctionator()
        WowStub.setBag(0, 3, WowStub.item(BISCUIT, "Forever Soul Biscuit", { sell = 15, class = 0 }))
        prices[WowStub.link(BISCUIT, "Forever Soul Biscuit")] = 100
        prices[WowStub.link(HEALTHSTONE, "Minor Healthstone")] = 100
        WowStub.state.itemClasses[BISCUIT], WowStub.state.itemClasses[HEALTHSTONE] = "Warlock", "Warlock"
        assert(ns.Routes.Add(BOB, "WARLOCK"))
        local result = ns.Bags.Evaluate()
        assert.equal(BOB, find(result.mail, BISCUIT).result.to, "the binding works for a plain warlock-only item")
        assert.is_nil(find(result.mail, HEALTHSTONE))
        assert.equal("conjured item", find(result.unmailable, HEALTHSTONE).result.reason)
        WowStub.state.conjured[BISCUIT] = true
        ns.Conjured.Forget(true)
        result = ns.Bags.Evaluate()
        assert.is_nil(find(result.mail, BISCUIT), "conjured now: the binding leaves it")
        assert.same({ "" }, result.totals.recipients, "only the bank alt gets mail")
    end)

    it("Return to sender leaves one alone, whoever mailed it", function()
        useAuctionator()
        local settings = ns.Bags.CurrentSettings()
        settings.returns = { [HEALTHSTONE] = { { to = BOB, count = 1, at = 100 } } }
        local result = ns.Bags.Evaluate(settings)
        assert.is_nil(find(result.mail, HEALTHSTONE))
        assert.equal("conjured item", find(result.unmailable, HEALTHSTONE).result.reason)
    end)

    it("the mailer's last check before attaching refuses a conjured stack", function()
        local stack = { bag = 0, slot = 1, count = 1, itemID = HEALTHSTONE, link = WowStub.link(HEALTHSTONE, "Minor Healthstone") }
        assert.same({ false, "conjured" }, { ns.Mailer.StillThere(stack) })
        local ore = { bag = 0, slot = 2, count = 20, itemID = 2770, link = WowStub.link(2770, "Copper Ore") }
        assert.is_true(ns.Mailer.StillThere(ore))
    end)

    --- Open the mailbox and the Mailworthy window; returns what it lists.
    local function atMailbox()
        ns.Fire("MAIL_SHOW")
        MailFrame:Show()
        SendMailFrame:Show()
        _G.MailworthyMailButton:Click()
        return ns.MailWindow.Result()
    end

    --- Press Send and answer every mail as the server does; returns the item IDs that left.
    local function send()
        _G.MailworthyMailSend:Click()
        for _ = 1, 20 do
            WowStub.runTimers()
            if not ns.Mailer.Busy() then break end
            ns.Fire("MAIL_SEND_SUCCESS")
        end
        assert.is_false(ns.Mailer.Busy())
        local went = {}
        for _, carried in ipairs(WowStub.state.sentItems) do
            for _, it in ipairs(carried) do went[it.itemID] = true end
        end
        return went
    end

    it("at the mailbox: the window lists the ore and not the Healthstone, and Send mails only the ore", function()
        useAuctionator()
        local shown = atMailbox()
        assert.is_nil(find(shown.mail, HEALTHSTONE))
        assert.is_nil(find(shown.keep, HEALTHSTONE))
        assert.truthy(find(shown.mail, 2770))
        assert.same({ [2770] = true }, send())
        assert.equal(HEALTHSTONE, WowStub.state.bags[0][1].itemID, "the Healthstone is still in its slot")
    end)

    it("a tooltip that loads after the preview: Send skips the stack and mails the rest", function()
        useAuctionator()
        WowStub.setBag(0, 3, WowStub.item(BISCUIT, "Forever Mana Biscuit", { count = 20, sell = 0, class = 0 }))
        WowStub.state.conjured[BISCUIT] = true
        WowStub.state.uncached[BISCUIT] = true -- its data hasn't arrived: a name line alone
        local shown = atMailbox()
        assert.truthy(find(shown.mail, BISCUIT), "not known to be conjured yet: listed like any unpriced white item")
        WowStub.state.uncached[BISCUIT] = nil -- the item's data arrives while the window is open
        assert.same({ [2770] = true }, send())
        assert.equal(BISCUIT, WowStub.state.bags[0][3].itemID, "the biscuit never left")
        ns.Fire("BAG_UPDATE_DELAYED")
        assert.is_nil(find(ns.MailWindow.Result().mail, BISCUIT), "and the next list leaves it out")
    end)

    it("a tooltip that loads after the run was planned: the last check before attaching refuses the stack", function()
        WowStub.setBag(0, 3, WowStub.item(BISCUIT, "Forever Mana Biscuit", { count = 20, sell = 0, class = 0 }))
        WowStub.state.conjured[BISCUIT] = true
        WowStub.state.uncached[BISCUIT] = true
        local stack = { bag = 0, slot = 3, count = 20, itemID = BISCUIT, link = WowStub.link(BISCUIT, "Forever Mana Biscuit") }
        assert.is_true(ns.Mailer.StillThere(stack), "nothing says it is conjured yet")
        WowStub.state.uncached[BISCUIT] = nil
        assert.same({ false, "conjured" }, { ns.Mailer.StillThere(stack) })
    end)

    it("asks each item's tooltip once, not every scan; again at the next mailbox visit", function()
        useAuctionator()
        ns.Bags.Evaluate()
        local reads = WowStub.state.tooltipReads
        assert.is_true(reads >= 1, "Copper Ore isn't a known ID: its tooltip is read")
        ns.Bags.Evaluate()
        ns.Bags.Evaluate()
        assert.equal(reads, WowStub.state.tooltipReads, "'not conjured' is remembered once the item's data is loaded")
        ns.Fire("MAIL_SHOW")
        ns.Bags.Evaluate()
        assert.equal(reads * 2, WowStub.state.tooltipReads, "a mailbox visit asks again, once")
        -- an item whose data hasn't loaded is asked every time, and a found line is never forgotten
        WowStub.setBag(0, 3, WowStub.item(BISCUIT, "Forever Mana Biscuit", { sell = 0, class = 0 }))
        WowStub.state.uncached[BISCUIT] = true
        assert.is_false(ns.Conjured.Is(BISCUIT))
        local before = WowStub.state.tooltipReads
        assert.is_false(ns.Conjured.Is(BISCUIT))
        assert.equal(before + 1, WowStub.state.tooltipReads)
        WowStub.state.uncached[BISCUIT], WowStub.state.conjured[BISCUIT] = nil, true
        assert.is_true(ns.Conjured.Is(BISCUIT))
        ns.Fire("MAIL_SHOW")
        WowStub.state.conjured[BISCUIT] = nil
        assert.is_true(ns.Conjured.Is(BISCUIT), "found once, conjured for the session")
    end)

    it("without C_Item.IsItemDataCachedByID nothing is remembered as 'not conjured'", function()
        local real = _G.C_Item
        _G.C_Item = nil
        ns.Conjured.Is(2770)
        local reads = WowStub.state.tooltipReads
        ns.Conjured.Is(2770)
        _G.C_Item = real
        assert.equal(reads + 1, WowStub.state.tooltipReads)
    end)

    it("/mw report says what the client calls it and what in the bags counts, and how it was known", function()
        WowStub.setBag(0, 3, WowStub.item(BISCUIT, "Forever Mana Biscuit", { sell = 0, class = 0 }))
        WowStub.state.conjured[BISCUIT] = true
        local report = ns.Report.Build()
        assert.truthy(report:find('conjured items (never mailed): ITEM_CONJURED = "Conjured Item"; in your bags: ', 1, true), report)
        assert.truthy(report:find("[Minor Healthstone]|h|r (item ID)", 1, true)
            or report:find("Minor Healthstone%]%S* %(item ID%)"), report)
        assert.truthy(report:find("Forever Mana Biscuit%]%S* %(tooltip%)"), report)
        assert.is_nil(report:find("Copper Ore%]%S* %("), "the ore isn't conjured")
        local label = _G.ITEM_CONJURED
        _G.ITEM_CONJURED = nil
        WowStub.setBag(0, 1, nil)
        WowStub.setBag(0, 3, nil)
        local lines = ns.Conjured.ReportLines()
        _G.ITEM_CONJURED = label
        assert.same({ 'conjured items (never mailed): no ITEM_CONJURED text, comparing with "Conjured Item"; '
            .. "in your bags: none" }, lines)
    end)
end)
