-- Selling the V items at a vendor (Vendor.lua): the button under the merchant window lists what
-- the bag tags call V, and Sell sells exactly that list, 12 stacks a press (the buyback list's
-- size), after re-reading each slot. Nothing else is ever sold: no hard keep, nothing the
-- auction house or disenchanting pays more for, nothing without a V verdict.
local loadAddon = require("spec.support.load_addon")

local BANK_ALT = "Roknua Themicrulah"

describe("selling V items at a vendor", function()
    local ns, prices

    local function put(bag, slot, it, price)
        WowStub.setBag(bag, slot, it)
        if price then prices[it.hyperlink] = price end
    end

    local function soldIDs()
        local ids = {}
        for _, s in ipairs(WowStub.state.sold or {}) do ids[#ids + 1] = s.itemID end
        table.sort(ids)
        return ids
    end

    local function merchant()
        MerchantFrame:Show()
        ns.Fire("MERCHANT_SHOW")
    end

    before_each(function()
        ns = loadAddon()
        ns.Fire("PLAYER_LOGIN")
        ns.Config.SetBankAlt(BANK_ALT)
        prices = {}
        local item = WowStub.item
        put(0, 1, item(6948, "Hearthstone", { bound = true, sell = 0, class = 15 }))
        put(0, 2, item(2770, "Copper Ore", { count = 20, sell = 5, class = 7, subclass = 7 }), 174)      -- AH
        put(0, 3, item(2589, "Linen Cloth", { count = 20, sell = 13, class = 7, subclass = 5 }), 14)      -- V
        put(0, 4, item(4865, "Ruined Pelt", { quality = 0, sell = 12, class = 15 }))                      -- V (junk)
        put(0, 5, item(6125, "Brawler's Pants", { bound = true, quality = 2, sell = 300, class = 4 }))    -- soulbound
        put(0, 6, item(5022, "Bundle of Letters", { quest = true, class = 12 }))                          -- quest
        put(0, 7, item(2775, "Silver Ore", { count = 5, sell = 75, class = 7, subclass = 7 }), 76)        -- V, but locked
        put(0, 8, item(2901, "Mining Pick", { sell = 16, class = 2, subclass = 14 }), 17)                 -- tool
        put(0, 9, item(858, "Lesser Healing Potion", { count = 5, sell = 5, class = 0 }))                 -- no price
        put(1, 1, item(2589, "Linen Cloth", { count = 7, sell = 13, class = 7, subclass = 5 }))           -- V: a second stack
        ns.Locks.ToggleItem(2775, WowStub.link(2775, "Silver Ore"), "spec")
        _G.Auctionator = { API = { v1 = {
            GetAuctionPriceByItemLink = function(_, l) return prices[l] end,
            GetAuctionAgeByItemLink = function() return 0 end,
        } } }
    end)
    after_each(function()
        _G.Auctionator = nil
        MerchantFrame:Hide()
        for _, line in ipairs(ns.Log.Lines()) do assert.is_nil(line:find("error", 1, true), line) end
    end)

    it("lists exactly the V stacks, in bag order, with what the vendor pays", function()
        local stacks = ns.Vendor.Stacks()
        local got = {}
        for i, s in ipairs(stacks) do got[i] = { s.bag, s.slot, s.itemID, s.count, s.price } end
        assert.same({ { 0, 3, 2589, 20, 260 }, { 0, 4, 4865, 1, 12 }, { 1, 1, 2589, 7, 91 } }, got)
    end)

    it("the button under the merchant window counts them and opens the window; nothing is sold yet", function()
        merchant()
        assert.equal("Mailworthy: sell V (3)", _G.MailworthyVendorButton:GetText())
        _G.MailworthyVendorButton:Click()
        assert.is_true(ns.Vendor.Frame():IsShown())
        assert.equal("Sell 3 for 3s 63c", _G.MailworthyVendorSell:GetText())
        WowStub.runTimers()
        assert.same({}, soldIDs())
    end)

    it("Sell sells what was listed and nothing else: no hard keep, nothing worth more elsewhere", function()
        merchant()
        _G.MailworthyVendorButton:Click()
        local listed = {}
        for _, s in ipairs(ns.Vendor.Batch()) do listed[#listed + 1] = s.itemID end
        table.sort(listed)
        _G.MailworthyVendorSell:Click()
        WowStub.runTimers()
        assert.same(listed, soldIDs(), "sold exactly the list")
        assert.same({ 2589, 2589, 4865 }, soldIDs())
        for _, s in ipairs(WowStub.state.sold) do
            assert.is_false(s.bound, "sold a soulbound item")
            assert.is_false(s.quest, "sold a quest item")
            assert.is_false(ns.Locks.IsItemLocked(s.itemID), "sold a locked item")
        end
        for _, at in ipairs({ { 0, 1 }, { 0, 2 }, { 0, 5 }, { 0, 6 }, { 0, 7 }, { 0, 8 }, { 0, 9 } }) do
            assert.truthy(WowStub.state.bags[at[1]][at[2]], "bag " .. at[1] .. " slot " .. at[2] .. " is still there")
        end
        assert.truthy(WowStub.printed[#WowStub.printed]:find("Sold 3 stacks for 3s 63c", 1, true))
        assert.is_false(ns.Vendor.Busy())
    end)

    it("sells at most 12 stacks a press, and says how many are left", function()
        WowStub.state.numSlots[2] = 16
        for i = 1, 15 do put(2, i, WowStub.item(5000 + i, "Junk " .. i, { quality = 0, sell = 10, class = 15 })) end
        merchant()
        _G.MailworthyVendorButton:Click()
        assert.equal(12, #ns.Vendor.Batch())
        assert.truthy(_G.MailworthyVendorSell:GetText():find("^Sell 12 for "))
        _G.MailworthyVendorSell:Click()
        WowStub.runTimers()
        assert.equal(12, #WowStub.state.sold)
        ns.Fire("BAG_UPDATE_DELAYED")
        assert.equal(6, #ns.Vendor.Batch(), "the rest, for the next press")
        _G.MailworthyVendorSell:Click()
        WowStub.runTimers()
        assert.equal(18, #WowStub.state.sold)
    end)

    it("re-reads each slot right before selling it: a slot that changed is skipped", function()
        merchant()
        _G.MailworthyVendorButton:Click()
        WowStub.setBag(0, 4, WowStub.item(6515, "Spellbinder Robes", { quality = 2, sell = 300, class = 4 })) -- swapped in
        WowStub.state.bags[1][1].stackCount = 6 -- one cloth used
        _G.MailworthyVendorSell:Click()
        WowStub.runTimers()
        assert.same({ 2589 }, soldIDs(), "only the stack that is still what was listed")
        assert.truthy(WowStub.printed[#WowStub.printed]:find("Skipped 2 that changed", 1, true))
    end)

    it("stops when the merchant closes, and at combat", function()
        merchant()
        _G.MailworthyVendorButton:Click()
        _G.MailworthyVendorSell:Click() -- the first stack goes at once
        MerchantFrame:Hide()
        ns.Fire("MERCHANT_CLOSED")
        WowStub.runTimers()
        assert.equal(1, #WowStub.state.sold)
        assert.truthy(WowStub.printed[#WowStub.printed]:find("Stopped: the merchant closed", 1, true))

        merchant()
        ns.Vendor.Toggle("spec")
        if not ns.Vendor.Frame():IsShown() then ns.Vendor.Toggle("spec") end
        WowStub.state.inCombat = true
        _G.MailworthyVendorSell:Click()
        WowStub.runTimers()
        assert.equal(1, #WowStub.state.sold, "nothing more in combat")
        WowStub.state.inCombat = false
    end)

    it("away from a merchant nothing is sold, by the window or by Sell itself", function()
        ns.HandleSlash("vendor")
        assert.is_true(ns.Vendor.Frame():IsShown())
        assert.equal("Nothing to sell", _G.MailworthyVendorSell:GetText())
        _G.MailworthyVendorSell:Click()
        ns.Vendor.Sell(ns.Vendor.Stacks())
        WowStub.runTimers()
        assert.same({}, soldIDs())
        assert.same({}, WowStub.state.used, "no item was used either")
    end)

    it("a lock takes an item off the list", function()
        merchant()
        ns.Locks.ToggleItem(2589, WowStub.link(2589, "Linen Cloth"), "spec")
        _G.MailworthyVendorButton:Click()
        _G.MailworthyVendorSell:Click()
        WowStub.runTimers()
        assert.same({ 4865 }, soldIDs())
    end)

    it("/mw feature vendorButton off: no button under the merchant window", function()
        local ns2 = loadAddon()
        MailworthyDB.features = { vendorButton = false }
        ns2.Fire("PLAYER_LOGIN")
        assert.is_nil(ns2.Vendor.Button())
    end)
end)
