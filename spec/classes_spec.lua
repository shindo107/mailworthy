-- Class bindings (operator, 2026-11-08: "this is a mage only item, id like to be able to friend
-- mail these types of items too"): a "Classes: Mage" item goes to a mage friend.
local loadAddon = require("spec.support.load_addon")

local SCROLL = 211234 -- a mage-only scroll ("Scroll: VOCE WELL" in the operator's bags)
local BOB = "Bob Surname"

describe("class-only items", function()
    local ns, prices

    before_each(function()
        ns = loadAddon()
        WowStub.state.serverTime = ns.Valuation.LAUNCH_EPOCH + 20 * 86400
        prices = {}
        _G.Auctionator = { API = { v1 = {
            GetAuctionPriceByItemLink = function(_, l) return prices[l] end,
            GetAuctionAgeByItemLink = function() return 0 end,
        } } }
        ns.Fire("PLAYER_LOGIN")
        ns.Config.SetBankAlt("Roknua Themicrulah")
        WowStub.setBag(0, 1, WowStub.item(SCROLL, "Scroll: VOCE WELL", { sell = 15, class = 0 }))
        prices[WowStub.link(SCROLL, "Scroll: VOCE WELL")] = 100 -- 1s: the vendor's 15c wins on the normal rule
        WowStub.state.itemClasses[SCROLL] = "Mage"
        WowStub.setBag(0, 2, WowStub.item(2770, "Copper Ore", { count = 20, sell = 5, class = 7, subclass = 7 }))
        prices[WowStub.link(2770, "Copper Ore")] = 174
    end)
    after_each(function()
        _G.Auctionator = nil
        for _, line in ipairs(ns.Log.Lines()) do assert.is_nil(line:find("error", 1, true), line) end
    end)

    local function find(list, itemID)
        for _, it in ipairs(list) do if it.itemID == itemID then return it end end
    end

    it("reads the tooltip's class line, in the client's words", function()
        local C = ns.Classes
        assert.same({ MAGE = true }, C.Parse("Classes: Mage", "Classes: %s"))
        assert.same({ MAGE = true, WARLOCK = true }, C.Parse("Classes: Mage, Warlock", "Classes: %s"))
        assert.is_nil(C.Parse("Requires Comprehension (15)", "Classes: %s"))
        assert.is_nil(C.Parse("Classes: Nobody", "Classes: %s"))
        _G.LOCALIZED_CLASS_NAMES_MALE = { MAGE = "Magier" }
        assert.same({ MAGE = true }, C.Parse("Klassen: Magier", "Klassen: %s"))
        assert.equal("Magier", C.Name("MAGE"))
        _G.LOCALIZED_CLASS_NAMES_MALE = nil
        assert.equal("MAGE", C.Token(8), "C_Club's classID")
        assert.equal("MAGE", C.Token("mage"))
        assert.is_nil(C.Token(6), "no death knights in Classic")
    end)

    it("asks the item's tooltip data once: a class set, false for anyone, nil before it's loaded", function()
        assert.same({ MAGE = true }, ns.Classes.Of(SCROLL))
        assert.is_false(ns.Classes.Of(2770))
        local real = _G.C_TooltipInfo
        _G.C_TooltipInfo = { GetItemByID = function() return { lines = {} } end }
        assert.is_nil(ns.Classes.Of(4242), "not loaded yet: no answer, asked again later")
        _G.C_TooltipInfo = { GetItemByID = function() return { lines = { { args = {
            { field = "leftText", stringVal = "Classes: Mage" } } } } } end }
        assert.same({ MAGE = true }, ns.Classes.Of(4242), "an older client's args")
        _G.C_TooltipInfo = real
    end)

    it("a class binding takes what only that class can use: the scroll to the mage, the ore stays the bank alt's", function()
        local before = find(ns.Bags.Evaluate().keep, SCROLL)
        assert.equal("not worth it", before.result.reason, "without the binding: sell it to a vendor")
        local route = assert(ns.Routes.Add(BOB, "MAGE"))
        assert.equal("Mage items", ns.Routes.What(route))
        assert.equal("class:MAGE|bob surname", route.key)
        local result = ns.Bags.Evaluate()
        local scroll = find(result.mail, SCROLL)
        assert.equal(BOB, scroll.result.to)
        assert.equal("Mage items", scroll.result.what)
        assert.is_nil(find(result.mail, 2770).result.to)
        assert.is_nil(ns.Routes.Skill(route))
        assert.truthy(table.concat(ns.Routes.ReportLines(), "\n"):find("binding: Mage items to Bob Surname", 1, true))
        assert.is_true(ns.Routes.Remove(route.key))
    end)

    it("not what this character can use itself, and never a hard keep", function()
        ns.Routes.Add(BOB, "MAGE")
        WowStub.state.itemClasses[SCROLL] = "Mage, Paladin" -- this character is a paladin
        ns.Classes.Forget()
        assert.is_nil(find(ns.Bags.Evaluate().mail, SCROLL))
        WowStub.state.itemClasses[SCROLL] = "Mage"
        ns.Classes.Forget()
        ns.Locks.ToggleItem(SCROLL, "link", "spec")
        assert.equal("locked", find(ns.Bags.Evaluate().keep, SCROLL).result.reason)
    end)

    it("never over the price rules: unpriced with Auctionator, or a green without it, stays (Codex review)", function()
        ns.Routes.Add(BOB, "MAGE")
        prices[WowStub.link(SCROLL, "Scroll: VOCE WELL")] = nil
        assert.equal("no price", find(ns.Bags.Evaluate().keep, SCROLL).result.reason)
        _G.Auctionator = nil
        WowStub.setBag(0, 1, WowStub.item(SCROLL, "Scroll: VOCE WELL", { quality = 2, sell = 15, class = 0 }))
        assert.equal("uncommon or better (no price data)", find(ns.Bags.Evaluate().keep, SCROLL).result.reason)
        WowStub.setBag(0, 1, WowStub.item(SCROLL, "Scroll: VOCE WELL", { sell = 15, class = 0 }))
        assert.equal(BOB, find(ns.Bags.Evaluate().mail, SCROLL).result.to, "a white one goes, as without a binding")
    end)

    it("a tooltip that loads in parts: no class line yet is asked again, not cached (Codex review)", function()
        local real, full = _G.C_TooltipInfo, false
        _G.C_TooltipInfo = { GetItemByID = function()
            local lines = { { leftText = "Scroll: VOCE WELL" } }
            if full then lines[2] = { leftText = "Classes: Mage" } end
            return { lines = lines }
        end }
        assert.is_false(ns.Classes.Of(4243))
        full = true
        assert.same({ MAGE = true }, ns.Classes.Of(4243))
        _G.C_TooltipInfo = real
    end)

    it("refuses a class that isn't one", function()
        assert.same({ nil, "not a crafting profession or a class" }, { ns.Routes.Add(BOB, "DEATHKNIGHT") })
    end)

    it("the friends window offers the picked player's class first; guild rules stay per profession", function()
        WowStub.state.guild = { clubId = 3, members = {
            { name = BOB, level = 30, online = true, classID = 8, professions = { 333 } } } }
        ns.RoutesUI.Show()
        _G.MailworthyFriendsPick1:Click()
        assert.truthy(_G.MailworthyFriendsProfession1:GetText():find("> Mage items (only a mage can use them) <", 1, true))
        assert.is_true(_G.MailworthyFriendsProfession9:IsShown(), "and every profession after it")
        _G.MailworthyFriendsProfession1:Click()
        local r = ns.Routes.List()[1]
        assert.equal("MAGE", r.class)
        assert.equal(BOB, r.to)
        assert.truthy(table.concat(WowStub.printed, "\n"):find("Mage items now go to Bob Surname", 1, true))
        assert.is_nil(ns.RoutesUI.Options({ name = BOB, class = "MAGE", professions = {} }, true)[1].class,
            "a guild rule: professions only")
        assert.equal(8, #ns.RoutesUI.Options({ name = BOB, professions = {} }), "class unknown: professions only")
    end)
end)
