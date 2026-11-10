-- "Worth a mailbox trip" (Trip.lua): one chat line a session when the bags are nearly full away
-- from a mailbox and something would be mailed, and the same result in the minimap button's
-- tooltip. Display only: nothing is attached or sent.
local loadAddon = require("spec.support.load_addon")

describe("worth a mailbox trip", function()
    local ns, prices, scans
    local BANK_ALT = "Roknua Themicrulah"
    local BOB = "Bob Surname"
    local ENCHANTING = 333
    local SLOTS = 30 -- the stub's backpack (20) and bags 1 (4) and 2 (6)

    local function useAuctionator()
        _G.Auctionator = { API = { v1 = {
            GetAuctionPriceByItemLink = function(_, l) return prices[l] end,
            GetAuctionAgeByItemLink = function() return 0 end,
        } } }
    end
    local function slotAt(n) -- the n-th of the 30 slots as bag, slot
        if n <= 20 then return 0, n end
        if n <= 24 then return 1, n - 20 end
        return 2, n - 24
    end
    --- Grey junk in slots `from`..`to` (never mailed).
    local function junk(from, to)
        for n = from, to do
            local bag, slot = slotAt(n)
            WowStub.setBag(bag, slot, WowStub.item(4865, "Ruined Pelt", { quality = 0, sell = 12, class = 15 }))
        end
    end
    --- Copper Ore x14 worth 2g 24s 60c more than vendoring (after the cut, deposit and postage) in slot 1, junk up to `free` free slots.
    local function nearlyFull(free)
        local ore = WowStub.item(2770, "Copper Ore", { count = 14, sell = 5, class = 7, subclass = 7 })
        WowStub.setBag(0, 1, ore)
        prices[ore.hyperlink] = 1700
        junk(2, SLOTS - free)
    end
    local function printed() return table.concat(WowStub.printed, "\n") end
    local function tripLines()
        local n = 0
        for _, line in ipairs(WowStub.printed) do
            if line:find("bag slot", 1, true) then n = n + 1 end
        end
        return n
    end
    local function bagsChanged() ns.Fire("BAG_UPDATE_DELAYED") end

    before_each(function()
        ns = loadAddon()
        prices = {}
        useAuctionator()
        ns.Fire("PLAYER_LOGIN")
        ns.Config.SetBankAlt(BANK_ALT)
        MailFrame:Hide()
        scans = 0
        local evaluate = ns.Bags.Evaluate
        ns.Bags.Evaluate = function(...)
            scans = scans + 1
            return evaluate(...)
        end
        for i = #WowStub.printed, 1, -1 do WowStub.printed[i] = nil end
    end)
    after_each(function()
        _G.Auctionator = nil
        _G.Minimap = nil
        for _, line in ipairs(ns.Log.Lines()) do assert.is_nil(line:find("error", 1, true), line) end
        assert.same({}, WowStub.state.sent, "display only: nothing is ever mailed from here")
        assert.same({}, WowStub.state.attached)
    end)

    describe("free slots", function()
        it("counts the backpack and bags 1-4, general-purpose bags only", function()
            junk(1, 27)
            assert.equal(3, ns.Trip.FreeSlots())
            WowStub.state.numSlots[5] = 8 -- an empty reagent bag holds no loot
            assert.equal(3, ns.Trip.FreeSlots())
            WowStub.state.numSlots[3] = 12 -- an empty herb bag neither
            WowStub.state.bagFamily = { [3] = 32 }
            assert.equal(3, ns.Trip.FreeSlots())
            WowStub.state.bagFamily = nil
            assert.equal(15, ns.Trip.FreeSlots())
        end)

        it("no answer when the game's call is missing or fails: nothing is scanned or said", function()
            nearlyFull(2)
            local real = C_Container.GetContainerNumFreeSlots
            C_Container.GetContainerNumFreeSlots = nil
            assert.is_nil(ns.Trip.FreeSlots())
            C_Container.GetContainerNumFreeSlots = function() error("secret") end
            assert.is_nil(ns.Trip.FreeSlots())
            bagsChanged()
            C_Container.GetContainerNumFreeSlots = real
            assert.equal(0, scans)
            assert.equal("", printed())
        end)
    end)

    describe("the threshold", function()
        it("above 4 free slots the bags are never valued, whatever is in them", function()
            assert.equal(4, ns.Trip.THRESHOLD)
            nearlyFull(5)
            bagsChanged()
            bagsChanged()
            assert.equal(0, scans)
            assert.equal("", printed())
            assert.is_nil(ns.Trip.TooltipText())
        end)

        it("at 4 free slots: one scan and the line", function()
            nearlyFull(4)
            bagsChanged()
            assert.equal(1, scans)
            assert.truthy(printed():find(
                "Mailworthy|r: 4 bag slots left. 14 items are worth mailing: +2g 24s 60c more than vendoring.", 1, true), printed())
            assert.equal("Worth mailing now: 14 items, +2g 24s 60c", ns.Trip.TooltipText())
        end)

        it("scans again only when the free-slot count changed; room again clears the tooltip line", function()
            nearlyFull(4)
            bagsChanged()
            bagsChanged()
            bagsChanged()
            assert.equal(1, scans)
            junk(27, 28) -- 2 slots left
            bagsChanged()
            assert.equal(2, scans)
            for n = 20, 28 do -- sold at a vendor: plenty of room
                local bag, slot = slotAt(n)
                WowStub.state.bags[bag][slot] = nil
            end
            bagsChanged()
            assert.equal(2, scans)
            assert.is_nil(ns.Trip.TooltipText())
        end)
    end)

    describe("once per session", function()
        it("the line is printed once, however the bags change afterwards", function()
            nearlyFull(4)
            bagsChanged()
            junk(27, 28)
            bagsChanged()
            junk(29, 30)
            bagsChanged()
            assert.equal(3, scans)
            assert.equal(1, tripLines(), printed())
            assert.equal("Worth mailing now: 14 items, +2g 24s 60c", ns.Trip.TooltipText(), "the tooltip still follows the bags")
        end)

        it("nearly full with nothing worth mailing says nothing; the line comes when something is", function()
            junk(1, 27)
            bagsChanged()
            assert.equal(1, scans)
            assert.equal("", printed())
            assert.is_nil(ns.Trip.TooltipText())
            local ore = WowStub.item(2770, "Copper Ore", { count = 14, sell = 5, class = 7, subclass = 7 })
            prices[ore.hyperlink] = 1700
            WowStub.setBag(2, 4, ore) -- slot 28
            bagsChanged()
            assert.truthy(printed():find("2 bag slots left. 14 items are worth mailing: +2g 24s 60c more than vendoring.", 1, true),
                printed())
        end)
    end)

    describe("at a mailbox", function()
        it("nothing is scanned or said while the mailbox is open; the next bag change after it is", function()
            nearlyFull(3)
            ns.Fire("MAIL_SHOW")
            bagsChanged()
            assert.equal(0, scans)
            assert.equal("", printed())
            assert.is_nil(ns.Trip.TooltipText())
            ns.Fire("MAIL_CLOSED")
            bagsChanged()
            assert.equal(1, scans)
            assert.equal(1, tripLines())
        end)

        it("a mailbox visit drops the cached result (the bags were just mailed)", function()
            nearlyFull(3)
            bagsChanged()
            assert.is_not_nil(ns.Trip.TooltipText())
            ns.Fire("MAIL_SHOW")
            assert.is_nil(ns.Trip.TooltipText())
            ns.Fire("MAIL_CLOSED")
            assert.is_nil(ns.Trip.TooltipText())
        end)

        it("the mail window open without the event (a /reload at the mailbox) counts too", function()
            nearlyFull(3)
            MailFrame:Show()
            bagsChanged()
            assert.equal(0, scans)
            assert.equal("", printed())
        end)
    end)

    describe("without a bank alt", function()
        it("says nothing: its share would stay in the bags", function()
            MailworthyDB.bankAlts = {}
            assert.is_nil(ns.Config.BankAlt())
            nearlyFull(2)
            bagsChanged()
            assert.equal("", printed())
            assert.is_nil(ns.Trip.TooltipText())
        end)

        it("unless a binding would mail", function()
            MailworthyDB.bankAlts = {}
            nearlyFull(3)
            local dust = WowStub.item(10940, "Strange Dust", { count = 20, sell = 2, class = 7, subclass = 12 })
            prices[dust.hyperlink] = 3
            WowStub.setBag(2, 4, dust) -- slot 28: 2 left
            assert.truthy(ns.Routes.Add(BOB, ENCHANTING))
            bagsChanged()
            assert.truthy(printed():find("Mailworthy|r: 2 bag slots left. 20 items are ready to mail.", 1, true), printed())
            assert.equal("Worth mailing now: 20 items", ns.Trip.TooltipText())
        end)

        it("on the bank alt itself: nothing, its share is what it sells", function()
            ns.Config.SetBankAltHere()
            nearlyFull(2)
            bagsChanged()
            assert.equal("", printed())
            assert.is_nil(ns.Trip.TooltipText())
        end)
    end)

    it("without Auctionator: white items go, with no gain to name", function()
        _G.Auctionator = nil
        nearlyFull(1)
        bagsChanged()
        assert.truthy(printed():find("Mailworthy|r: 1 bag slot left. 14 items are ready to mail.", 1, true), printed())
        assert.equal("Worth mailing now: 14 items", ns.Trip.TooltipText())
    end)

    it("in combat nothing is scanned; leaving combat checks again", function()
        nearlyFull(3)
        WowStub.state.inCombat = true
        bagsChanged()
        assert.equal(0, scans)
        assert.equal("", printed())
        WowStub.state.inCombat = false
        ns.Fire("PLAYER_REGEN_ENABLED")
        assert.equal(1, scans)
        assert.equal(1, tripLines())
    end)

    describe("the texts (pure)", function()
        it("slots and items in the singular, the plural and none", function()
            local T = ns.Trip.ChatText
            assert.equal("2 bag slots left. 14 items are worth mailing: +2g 10s more than vendoring.",
                T(2, { items = 14, gain = 21000 }))
            assert.equal("1 bag slot left. 1 item is worth mailing: +45c more than vendoring.", T(1, { items = 1, gain = 45 }))
            assert.equal("No bag slots left. 3 items are ready to mail.", T(0, { items = 3, gain = 0 }))
            assert.equal("4 bag slots left. 1 item is ready to mail.", T(4, { items = 1, gain = 0 }))
        end)

        it("a scan with nothing to mail has no summary", function()
            assert.is_nil(ns.Trip.Summary(nil))
            assert.is_nil(ns.Trip.Summary({ mail = {}, totals = { items = 0, gain = 0 }, priced = true }))
            assert.same({ items = 5, gain = 120 },
                ns.Trip.Summary({ mail = { {} }, totals = { items = 5, gain = 120 }, priced = true }))
            assert.same({ items = 5, gain = 0 },
                ns.Trip.Summary({ mail = { {} }, totals = { items = 5, gain = 0 }, priced = false }))
        end)
    end)

    describe("/mw feature tripNudge", function()
        it("is on by default and listed in /mw help", function()
            assert.is_true(ns.Features.DEFAULTS.tripNudge)
            assert.is_true(ns.Trip.On())
            SlashCmdList.MAILWORTHY("help")
            assert.truthy(printed():find("|tripNudge", 1, true))
            assert.truthy(printed():find("/mw feature tripNudge off", 1, true))
        end)

        it("off: no scan, no line, no tooltip line", function()
            nearlyFull(2)
            bagsChanged()
            assert.is_not_nil(ns.Trip.TooltipText())
            SlashCmdList.MAILWORTHY("feature tripNudge off")
            assert.is_false(ns.Trip.On())
            assert.is_nil(ns.Trip.TooltipText())
            junk(29, 29)
            bagsChanged()
            assert.equal(1, scans)
            assert.equal(1, tripLines())
        end)

        it("off from the start: nothing at all", function()
            MailworthyDB.features.tripNudge = false
            nearlyFull(2)
            bagsChanged()
            assert.equal(0, scans)
            assert.equal(0, tripLines())
        end)
    end)

    describe("the minimap button's tooltip", function()
        local lines
        local function hover()
            lines = {}
            rawset(GameTooltip, "AddLine", function(_, t) lines[#lines + 1] = t end)
            local button = ns.MinimapButton.Button()
            button.scripts.OnEnter(button)
            rawset(GameTooltip, "AddLine", nil)
            return table.concat(lines, "\n")
        end
        before_each(function()
            _G.Minimap = WowStub.newWidget("Frame", "Minimap")
            ns.MinimapButton.Create()
        end)

        it("carries the line while the bags are nearly full and something would be mailed", function()
            assert.is_nil(hover():find("Worth mailing", 1, true))
            assert.equal(0, scans, "hovering never scans")
            nearlyFull(2)
            bagsChanged()
            local text = hover()
            assert.truthy(text:find("Bank alt: " .. BANK_ALT, 1, true), text)
            assert.equal("Worth mailing now: 14 items, +2g 24s 60c", lines[#lines])
            assert.equal(1, scans, "from the cached result")
        end)

        it("not with the switch off", function()
            nearlyFull(2)
            bagsChanged()
            MailworthyDB.features.tripNudge = false
            assert.is_nil(hover():find("Worth mailing", 1, true))
        end)
    end)
end)
