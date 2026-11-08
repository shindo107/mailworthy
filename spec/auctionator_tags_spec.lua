-- The bag tags on Auctionator's own buttons (operator, 2026-11-08: "can the item badges we show on
-- the bag also be shown in the Auctionator ah menus too?"). Auctionator is stubbed the way its
-- 340 source behaves (Source/Groups/View.lua, ViewItem.lua/.xml; Source/Tabs/Selling/Mixins/
-- BagItemSelected.lua): the item buttons get the mixin's functions copied in when the pool
-- creates them (after login: the auction house builds its frames on first open), the view
-- releases every button and calls SetItemInfo(info) again on each refresh, and the posting
-- panel's icon calls the global mixin's SetItemInfo. Writing any Lua field on Auctionator's
-- buttons from Mailworthy is an error here.
local loadAddon = require("spec.support.load_addon")

local function location(bag, slot)
    return { GetBagAndSlot = function() return bag, slot end }
end

-- An Auctionator item button: textures may be created on it; only Auctionator's own code
-- (rawset below) may write fields on it.
local function atrButton(mixin)
    local b = { textures = {}, fontStrings = {}, shown = true }
    function b.Hide(self) rawset(self, "shown", false) end -- the pool's release (Auctionator's own)
    function b.IsShown(self) return self.shown end
    function b.IsVisible(self) return self.shown end
    function b.Show(self) rawset(self, "shown", true) end -- the group's AddButton (SetShown)
    function b.CreateTexture()
        local t = WowStub.newWidget("Texture")
        table.insert(b.textures, t)
        return t
    end
    function b.CreateFontString()
        local f = WowStub.newWidget("FontString")
        table.insert(b.fontStrings, f)
        return f
    end
    for k, v in pairs(mixin) do b[k] = v end -- the XML mixin: copied when the frame is created
    return setmetatable(b, { __newindex = function(_, k) error("wrote field " .. tostring(k) .. " on an Auctionator button") end })
end

local function tagOf(button)
    for _, f in ipairs(button.fontStrings) do
        if f:IsShown() then return f.text end
    end
    return nil
end

-- AuctionatorGroupsViewMixin's frame pool: ReleaseAll hides every button, Acquire hands one back
-- (the same buttons, in order), and each gets SetItemInfo(info).
local function newView()
    local view = { buttons = {}, active = 0 }
    function view.Show(_, infos)
        for i = 1, view.active do view.buttons[i]:Hide() end
        view.active = 0
        for _, info in ipairs(infos) do
            view.active = view.active + 1
            local b = view.buttons[view.active]
            if not b then
                b = atrButton(_G.AuctionatorGroupsViewItemMixin)
                view.buttons[view.active] = b
            end
            b:SetItemInfo(info)
            b:Show()
        end
        return view.buttons
    end
    return view
end

local function info(link, bag, slot, count)
    return { itemLink = link, itemCount = count or 1, locations = bag and { location(bag, slot) } or {} }
end

local function setupAuctionator(prices)
    _G.Auctionator = { API = { v1 = {
        GetAuctionPriceByItemLink = function(_, l) return prices[l] and prices[l].ah end,
        GetAuctionAgeByItemLink = function() return 0 end,
        IsAuctionDataExactByItemLink = function() return true end,
        GetDisenchantPriceByItemLink = function(_, l) return prices[l] and prices[l].de end,
    } } }
    _G.AuctionatorGroupsViewItemMixin = {
        SetItemInfo = function(self, i) rawset(self, "itemInfo", i) end, -- Auctionator's own write
    }
end

describe("Mailworthy tags on Auctionator's Selling tab", function()
    local ns, prices
    local ore, linen, ring

    before_each(function()
        ns = loadAddon()
        ns.Valuation.DEFAULTS.minGain = 500 -- bank_alt_spec's fixtures: Linen Cloth's 4s 62c gain is a V
        prices = {}
        setupAuctionator(prices)
        _G.DisenchantryDB = {}
        ore, linen, ring = WowStub.link(2770, "Copper Ore"), WowStub.link(2589, "Linen Cloth"), WowStub.link(6360, "Green Ring")
        WowStub.setBag(0, 1, WowStub.item(2770, "Copper Ore", { count = 5, sell = 5 }))
        prices[ore] = { ah = 174 }
        WowStub.setBag(0, 2, WowStub.item(2589, "Linen Cloth", { count = 20, sell = 10 }))
        prices[linen] = { ah = 38 }
        WowStub.setBag(0, 3, WowStub.item(6360, "Green Ring", { quality = 2, class = 4, sell = 50 }))
        prices[ring] = { de = 1000 }
        ns.Fire("PLAYER_LOGIN")
        ns.Config.SetBankAlt("Rettana Quilwrit") -- this character is the bank alt: tags show
        MailworthyDB.bankAlts["Classic Beta PvP|Alliance"] = "Rettana Quilwrit"
        ns.BankAlt.Redraw()
    end)

    after_each(function()
        _G.Auctionator, _G.AuctionatorGroupsViewItemMixin, _G.DisenchantryDB = nil, nil, nil
        for _, line in ipairs(ns.Log.Lines()) do assert.is_nil(line:find("error", 1, true), line) end
    end)

    it("shows the bag tags on the bag list's buttons: AH, V, DE", function()
        local buttons = newView():Show({ info(ore, 0, 1, 5), info(linen, 0, 2, 20), info(ring, 0, 3) })
        assert.equal("AH", tagOf(buttons[1]))
        assert.equal("V", tagOf(buttons[2]))
        assert.equal("DE", tagOf(buttons[3]))
        assert.equal(3, ns.AuctionatorTags.Shown())
        assert.equal(ore, rawget(buttons[1], "itemInfo").itemLink, "Auctionator's own SetItemInfo still ran")
    end)

    it("follows a recycled button to its new item, and clears it for none", function()
        local view = newView()
        local buttons = view:Show({ info(ore, 0, 1, 5), info(linen, 0, 2, 20) })
        local first = buttons[1]
        view:Show({ info(ring, 0, 3), info(ore, 0, 1, 5) }) -- the same two buttons, other items
        assert.equal(first, view.buttons[1])
        assert.equal("DE", tagOf(first))
        assert.equal("AH", tagOf(view.buttons[2]))
        first:SetItemInfo(nil)
        assert.is_nil(tagOf(first), "a cleared button has no tag")
        first:SetItemInfo(info(ore, nil, nil, 0)) -- a favourite that isn't in the bags
        assert.is_nil(tagOf(first))
        -- no readable location: drawn by its link (Border.RefreshButton's link fallback)
        local calls = {}
        local refresh = ns.Border.RefreshButton
        ns.Border.RefreshButton = function(...) calls[#calls + 1] = { ... } return refresh(...) end
        first:SetItemInfo({ itemLink = linen, itemCount = 20 })
        first:SetItemInfo(info(ore, nil, nil, 0))
        ns.Border.RefreshButton = refresh
        assert.same({ first, nil, nil, nil, nil, linen }, calls[1])
        first:SetItemInfo({ itemLink = linen, itemCount = 20 })
        assert.equal("V", tagOf(first), "BankAlt.Decorate finds it by link")
        assert.same({ first, nil, nil, nil, nil, nil }, calls[2], "a favourite not in the bags: no link either")
    end)

    it("never shows another item's tag when stacks swap before Auctionator redraws (Codex review)", function()
        local buttons = newView():Show({ info(ore, 0, 1, 5), info(linen, 0, 2, 20) })
        assert.equal("AH", tagOf(buttons[1]))
        assert.equal("V", tagOf(buttons[2]))
        WowStub.setBag(0, 1, WowStub.item(2589, "Linen Cloth", { count = 20, sell = 10 }))
        WowStub.setBag(0, 2, WowStub.item(2770, "Copper Ore", { count = 5, sell = 5 }))
        ns.Fire("BAG_UPDATE_DELAYED") -- Mailworthy redraws first; Auctionator's buttons still point at the old slots
        assert.not_equal("V", tagOf(buttons[1]), "the Copper Ore button never shows Linen Cloth's V")
        assert.not_equal("AH", tagOf(buttons[2]), "the Linen Cloth button never shows Copper Ore's AH")
    end)

    it("tells random-suffix variants of one item ID apart (Codex review)", function()
        local bear = "|cff1eff00|Hitem:15210:0:0:0:0:0:1191:0:8|h[Raider's Shortsword of the Bear]|h|r"
        local whale = "|cff1eff00|Hitem:15210:0:0:0:0:0:1192:0:8|h[Raider's Shortsword of the Whale]|h|r"
        local function sword(link)
            local it = WowStub.item(15210, "Raider's Shortsword", { quality = 2, class = 2, sell = 50 })
            it.hyperlink = link
            return it
        end
        assert.equal("15210:1191", ns.AuctionatorTags.Variant(bear))
        assert.equal("2770:0", ns.AuctionatorTags.Variant(ore))
        assert.is_nil(ns.AuctionatorTags.Variant("|Hbattlepet:261:1:3|h[Pet]|h"))
        WowStub.setBag(0, 4, sword(bear))
        prices[bear] = { ah = 5000 }
        WowStub.setBag(0, 5, sword(whale))
        prices[whale] = { ah = 60 }
        ns.Fire("BAG_UPDATE_DELAYED")
        local buttons = newView():Show({ info(bear, 0, 4), info(whale, 0, 5) })
        local bearTag, whaleTag = tagOf(buttons[1]), tagOf(buttons[2])
        assert.equal("AH", bearTag)
        assert.not_equal(bearTag, whaleTag)
        WowStub.setBag(0, 4, sword(whale))
        WowStub.setBag(0, 5, sword(bear))
        ns.Fire("BAG_UPDATE_DELAYED") -- before Auctionator redraws
        assert.equal(bearTag, tagOf(buttons[1]), "the Bear icon keeps the Bear's tag")
        assert.equal(whaleTag, tagOf(buttons[2]))
        -- Auctionator's GetItemInfo link may differ in other fields (the level): still the same item
        local atrOre = "|cffffffff|Hitem:2770::::::::60:::::|h[Copper Ore]|h|r"
        buttons[1]:SetItemInfo(info(atrOre, 0, 1, 5))
        assert.equal("AH", tagOf(buttons[1]))
    end)

    it("never trusts a slot it can't match: no link, or a link without an item ID (Codex review)", function()
        local view = newView()
        local buttons = view:Show({ { itemCount = 1, locations = { location(0, 1) } }, -- no link
            info("|cff0070dd|Hbattlepet:261:1:3:152:13:10:0x0|h[Personal World Destroyer]|h|r", 0, 1),
            info("|cffa335ee|Hkeystone:180653:375:2|h[Keystone]|h|r", 0, 1) })
        for i = 1, 3 do assert.is_nil(tagOf(buttons[i]), "button " .. i .. ": Copper Ore sits in that slot") end
    end)

    it("a fresh lock's glow on Auctionator's icon ends with its flash (Codex review)", function()
        local buttons = newView():Show({ info(ore, 0, 1, 5) })
        local function glowing()
            for _, t in ipairs(ns.Border.Glow(buttons[1])) do if not t:IsShown() then return false end end
            return true
        end
        ns.Locks.ToggleItem(2770, ore, "spec") -- away from the mailbox: a 3 s flash
        assert.is_true(glowing())
        assert.is_nil(tagOf(buttons[1]), "a locked item has no tag")
        WowStub.state.now = WowStub.state.now + ns.Border.FLASH + 1
        WowStub.runTimers(ns.Border.FLASH)
        assert.is_false(glowing(), "Border.RefreshAll ran the Auctionator refresher")
    end)

    it("counts only tags on screen: a released button or a closed auction house shows none", function()
        local view = newView()
        view:Show({ info(ore, 0, 1, 5), info(linen, 0, 2, 20) })
        assert.equal(2, ns.AuctionatorTags.Shown())
        view:Show({ info(ore, 0, 1, 5) }) -- one released, hidden by the pool
        assert.equal(1, ns.AuctionatorTags.Shown())
        view.buttons[1]:Hide()
        assert.equal(0, ns.AuctionatorTags.Shown())
    end)

    it("redraws its tags when the bags change, even after Auctionator drew first", function()
        local buttons = newView():Show({ info(linen, 0, 2, 20) })
        assert.equal("V", tagOf(buttons[1]))
        prices[linen] = { ah = 200 } -- a new scan
        WowStub.setBag(0, 2, WowStub.item(2589, "Linen Cloth", { count = 20, sell = 10 }))
        ns.Fire("BAG_UPDATE_DELAYED")
        assert.equal("AH", tagOf(buttons[1]), "no new SetItemInfo needed")
        WowStub.setBag(0, 2, nil) -- sold: the slot is empty, Auctionator hasn't redrawn yet
        ns.Fire("BAG_UPDATE_DELAYED")
        assert.is_nil(tagOf(buttons[1]))
    end)

    it("tags the posting panel's icon, which calls the global mixin's SetItemInfo", function()
        local selectedMixin = {}
        function selectedMixin.SetItemInfo(self, i) _G.AuctionatorGroupsViewItemMixin.SetItemInfo(self, i) end
        local icon = atrButton(selectedMixin)
        icon:SetItemInfo({ itemLink = ore, count = 5, location = location(0, 1) })
        assert.equal("AH", tagOf(icon))
        icon:SetItemInfo(nil)
        assert.is_nil(tagOf(icon))
    end)

    it("shows nothing where the bag tags don't show (a main with a bank alt elsewhere)", function()
        MailworthyDB.bankAlts["Classic Beta PvP|Alliance"] = "Roknua Themicrulah"
        ns.BankAlt.Redraw()
        local buttons = newView():Show({ info(ore, 0, 1, 5) })
        assert.is_nil(tagOf(buttons[1]))
        assert.equal(0, #buttons[1].textures, "nothing created on a button that never needed a tag")
    end)

    it("says what it saw in /mw report", function()
        newView():Show({ info(ore, 0, 1, 5), info(linen, 0, 2, 20) })
        local line = ns.AuctionatorTags.ReportLines()[1]
        assert.truthy(line:find("auctionator tags: hooked; 2 Auctionator button(s) seen, 2 tagged now", 1, true), line)
        ns.HandleSlash("report")
        assert.truthy(ns.Report.Text():find("auctionator tags: hooked", 1, true))
    end)
end)

describe("Auctionator tags switched off or missing", function()
    after_each(function() _G.Auctionator, _G.AuctionatorGroupsViewItemMixin = nil, nil end)

    it("/mw feature auctionatorTags off: no hook, nothing drawn", function()
        local ns = loadAddon()
        setupAuctionator({})
        local original = _G.AuctionatorGroupsViewItemMixin.SetItemInfo
        MailworthyDB.features.auctionatorTags = false
        ns.Fire("PLAYER_LOGIN")
        assert.equal(original, _G.AuctionatorGroupsViewItemMixin.SetItemInfo, "Auctionator's mixin untouched")
        assert.truthy(ns.AuctionatorTags.ReportLines()[1]:find("off (/mw feature auctionatorTags on", 1, true))
    end)

    it("without Auctionator: nothing hooked, nothing breaks", function()
        local ns = loadAddon()
        ns.Fire("PLAYER_LOGIN")
        assert.is_false(ns.AuctionatorTags.Install())
        ns.BankAlt.Redraw()
        assert.truthy(ns.AuctionatorTags.ReportLines()[1]:find("Auctionator not loaded", 1, true))
        ns.HandleSlash("report")
    end)
end)
