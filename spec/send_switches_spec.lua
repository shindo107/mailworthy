-- Send switches: what Send takes of the bank alt's share, by the item's verdict (the bag tag):
-- Auction (AH), Disenchant (DE), Bank (B) on by default, Vendor (V) off. A switch that is off
-- keeps its items in the bags; Vendor on mails what a vendor pays more for too. The tags never
-- change: the switches are about mailing only.
local loadAddon = require("spec.support.load_addon")

local BANK_ALT = "Roknua Themicrulah"

describe("send switches", function()
    local ns, prices

    local function put(bag, slot, it, price)
        WowStub.setBag(bag, slot, it)
        if price then prices[it.hyperlink] = price end
    end

    --- itemID -> "mail:<route>" or "keep:<held or reason>".
    local function scan(settings)
        local out = {}
        local result = ns.Bags.Evaluate(settings)
        for _, it in ipairs(result.mail) do out[it.itemID] = "mail:" .. tostring(it.result.route) end
        for _, it in ipairs(result.keep) do out[it.itemID] = "keep:" .. tostring(it.result.held or it.result.reason) end
        for _, it in ipairs(result.unmailable) do out[it.itemID] = "unmailable" end
        return out, result
    end

    before_each(function()
        ns = loadAddon()
        ns.Fire("PLAYER_LOGIN")
        ns.Config.SetBankAlt(BANK_ALT)
        ns.Config.Set("disenchant", true)
        prices = {}
        local item = WowStub.item
        put(0, 1, item(2770, "Copper Ore", { count = 20, sell = 5, class = 7, subclass = 7 }), 174)        -- AH
        put(0, 2, item(2589, "Linen Cloth", { count = 20, sell = 13, class = 7, subclass = 5 }), 14)        -- V: not worth it
        put(0, 3, item(4865, "Ruined Pelt", { quality = 0, sell = 12, class = 15 }))                        -- V: grey junk
        put(0, 4, item(6125, "Brawler's Pants", { bound = true, quality = 2, sell = 300, class = 4 }))      -- soulbound
        put(0, 5, item(2775, "Silver Ore", { count = 5, sell = 75, class = 7, subclass = 7 }), 9000)        -- locked below
        put(0, 6, item(858, "Lesser Healing Potion", { count = 5, sell = 5, class = 0 }))                   -- no price
        ns.Locks.ToggleItem(2775, WowStub.link(2775, "Silver Ore"), "spec")
        _G.Auctionator = { API = { v1 = {
            GetAuctionPriceByItemLink = function(_, l) return prices[l] end,
            GetAuctionAgeByItemLink = function() return 0 end,
        } } }
    end)
    after_each(function() _G.Auctionator = nil end)

    it("by default nothing changes: the auction item goes, vendor items and junk stay", function()
        local got = scan()
        assert.equal("mail:ah", got[2770])
        assert.equal("keep:not worth it", got[2589])
        assert.truthy(got[4865]:find("^keep:"))
        assert.equal("mail:noprice", got[858], "an unpriced item: no verdict, no switch")
        assert.equal("keep:locked", got[2775])
        assert.equal("unmailable", got[6125])
    end)

    it("a switch that is off keeps its items in the bags and says why", function()
        ns.Config.Set("sendAuction", false)
        local got, result = scan()
        assert.equal("keep:sending Auction items is off", got[2770])
        assert.equal("mail:noprice", got[858], "the rest of the share still goes")
        for _, it in ipairs(result.keep) do
            if it.itemID == 2770 then
                assert.equal("ah", it.result.route, "what it would have been")
                assert.equal("ah", ns.BankAlt.Verdict({ result = { action = "mail", route = "ah" } }))
            end
        end
    end)

    it("Vendor on: vendor items and junk go to the bank alt too, with their postage counted", function()
        ns.Config.Set("sendVendor", true)
        local got, result = scan()
        assert.equal("mail:vendor", got[2589])
        assert.equal("mail:vendor", got[4865])
        assert.equal("mail:ah", got[2770])
        local postage = 0
        for _, it in ipairs(result.mail) do
            assert.is_number(it.result.postage, tostring(it.itemID))
            postage = postage + it.result.postage
        end
        assert.equal(postage, result.totals.postage)
    end)

    it("Vendor on never mails a hard keep or a soulbound item", function()
        ns.Config.Set("sendVendor", true)
        local got = scan()
        assert.equal("keep:locked", got[2775])
        assert.equal("unmailable", got[6125])
    end)

    it("Vendor on needs a price source: without one junk and non-white items stay (the safety rule)", function()
        _G.Auctionator = nil
        ns.Config.Set("sendVendor", true)
        local got = scan()
        assert.truthy(got[4865]:find("^keep:"), got[4865])
        assert.equal("mail:common", got[2589], "a white item goes as before")
    end)

    it("without a bank alt, or with it skipped, the switches mail nothing", function()
        ns.Config.Set("sendVendor", true)
        ns.Bags.SkipBankAlt(true)
        local got = scan()
        for itemID, where in pairs(got) do assert.is_nil(where:find("^mail:"), itemID .. " " .. where) end
        ns.Bags.SkipBankAlt(false)
    end)

    it("a binding's share is not the bank alt's: its switch doesn't hold it back", function()
        put(0, 7, WowStub.item(10940, "Strange Dust", { count = 20, sell = 2, class = 7, subclass = 12 }), 500)
        ns.Routes.Add("Bob Surname", 333)
        ns.Config.Set("sendAuction", false)
        local _, result = scan()
        local to
        for _, it in ipairs(result.mail) do
            if it.itemID == 10940 then to = it.result.to end
        end
        assert.equal("Bob Surname", to)
    end)

    it("the tags never change: a switch is about mailing, not about what an item is worth", function()
        ns.Config.Set("sendAuction", false)
        ns.Config.Set("sendVendor", true)
        local tags = {}
        local result = ns.Bags.Evaluate(ns.BankAlt.Settings())
        for _, list in ipairs({ result.mail, result.keep }) do
            for _, it in ipairs(list) do tags[it.itemID] = ns.BankAlt.Verdict(it) end
        end
        assert.equal("ah", tags[2770])
        assert.equal("v", tags[2589])
        assert.equal("v", tags[4865])
    end)

    it("/mw scan and /mw report say which switches are on", function()
        ns.Config.Set("sendVendor", true)
        assert.equal("Auction on, Disenchant on, Bank on, Vendor on", ns.Bags.SendText(ns.Config.Values()))
        assert.truthy(ns.Bags.Report(ns.Bags.Evaluate()):find("send: Auction on, Disenchant on, Bank on, Vendor on", 1, true))
    end)
end)
