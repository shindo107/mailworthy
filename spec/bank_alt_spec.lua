-- The bank alt view: AH / DE / V tags on bag slots recomputed with this
-- character's own prices (no postage: nothing is mailed from here), tooltip
-- lines with today's verdict and why it was mailed, and the summary window.
-- Tags are textures / font strings only: the stub errors on any field written
-- on Blizzard's bag buttons.
local loadAddon = require("spec.support.load_addon")

describe("bank alt view", function()
    local ns, combined, prices, postCalls, tooltipLines, displayed

    local function tagOf(button)
        for _, f in ipairs(button.fontStrings) do
            if f:IsShown() then return f.text end
        end
        return nil
    end

    local function hover(link, itemID)
        tooltipLines, displayed = {}, link
        postCalls[0](GameTooltip, { id = itemID })
        return table.concat(tooltipLines, "\n")
    end

    before_each(function()
        ns = loadAddon()
        ns.Valuation.DEFAULTS.minGain = 500 -- these fixtures were built on the old 5s default (1s since 2026-11-07)
        prices, postCalls, tooltipLines = {}, {}, {}
        _G.Auctionator = { API = { v1 = {
            GetAuctionPriceByItemLink = function(_, l) return prices[l] and prices[l].ah end,
            GetAuctionAgeByItemLink = function() return 0 end,
            IsAuctionDataExactByItemLink = function() return true end,
            GetDisenchantPriceByItemLink = function(_, l) return prices[l] and prices[l].de end,
        } } }
        _G.DisenchantryDB = {}
        _G.Enum = { TooltipDataType = { Item = 0 } }
        _G.TooltipDataProcessor = { AddTooltipPostCall = function(t, fn) postCalls[t] = fn end }
        _G.TooltipUtil = { GetDisplayedItem = function() return "name", displayed end }
        rawset(GameTooltip, "AddLine", function(_, text) table.insert(tooltipLines, text) end)

        WowStub.setBag(0, 1, WowStub.item(2770, "Copper Ore", { count = 5, sell = 5 }))
        prices[WowStub.link(2770, "Copper Ore")] = { ah = 174 }
        WowStub.setBag(0, 2, WowStub.item(2589, "Linen Cloth", { count = 20, sell = 10 }))
        prices[WowStub.link(2589, "Linen Cloth")] = { ah = 38 } -- 722 - 60 (half deposit) - 200 = 4s 62c: under 5s
        WowStub.setBag(0, 3, WowStub.item(6360, "Green Ring", { quality = 2, class = 4, sell = 50 }))
        prices[WowStub.link(6360, "Green Ring")] = { de = 1000 }
        WowStub.setBag(0, 4, WowStub.item(6948, "Hearthstone", { bound = true, sell = 0 }))
        combined = ContainerFrameCombinedBags
        combined.Items = { WowStub.itemButton(0, 1), WowStub.itemButton(0, 2), WowStub.itemButton(0, 3),
            WowStub.itemButton(0, 4) }
        ns.Fire("PLAYER_LOGIN")
        ns.Config.SetBankAlt("Rettana Quilwrit") -- this character is the bank alt
        MailworthyDB.bankAlts["Classic Beta PvP|Alliance"] = "Rettana Quilwrit"
        ns.BankAlt.Redraw()
    end)

    after_each(function()
        _G.Auctionator, _G.DisenchantryDB, _G.Enum, _G.TooltipDataProcessor, _G.TooltipUtil = nil, nil, nil, nil, nil
        rawset(GameTooltip, "AddLine", nil)
        for _, line in ipairs(ns.Log.Lines()) do assert.is_nil(line:find("error", 1, true), line) end
    end)

    it("tags each slot with today's verdict: AH, DE, V; nothing on soulbound items", function()
        combined:UpdateItems()
        assert.equal("AH", tagOf(combined.Items[1]), "Copper Ore: 826 - 6 (half the 12c deposit), no postage, vs 25c")
        assert.equal("V", tagOf(combined.Items[2]), "Linen Cloth: gain 4s 62c, under 5s")
        assert.equal("DE", tagOf(combined.Items[3]))
        assert.is_nil(tagOf(combined.Items[4]))
    end)

    it("counts no postage on the bank alt", function()
        local item
        for _, i in ipairs(ns.BankAlt.Refresh().mail) do if i.itemID == 2770 then item = i end end
        assert.equal(0, item.result.postage)
        assert.equal(826 - 50 - 25, item.result.gain, "half of the 1s minimum deposit")
    end)

    it("B: bank it for a later phase, with the tooltip and a summary row", function()
        WowStub.setBag(0, 5, WowStub.item(10940, "Strange Dust", { count = 10, sell = 2, subclass = 12 }))
        prices[WowStub.link(10940, "Strange Dust")] = { ah = 100 }
        combined.Items[5] = WowStub.itemButton(0, 5)
        ns.BankAlt.Redraw()
        combined:UpdateItems()
        assert.equal("B", tagOf(combined.Items[5]))
        local text = hover(WowStub.link(10940, "Strange Dust"), 10940)
        assert.truthy(text:find("Mailworthy  |cffffffff[Bank]|r", 1, true), text)
        -- no postage here: 950 - 50 (half the 1s minimum deposit) - 20 vendor = 8s 80c
        assert.truthy(text:find("Bank it, don't list it yet: enchanting materials sell once raids open (launch day 35). "
            .. "Listed today it would bring 1s each, 8s 80c more than a vendor.", 1, true), text)
        assert.same({ stacks = 1, items = 10, gain = 880 }, ns.BankAlt.Summary(ns.BankAlt.Refresh()).b)
        ns.HandleSlash("summary")
        assert.is_true(MailworthySummaryFrame:IsShown())
    end)

    it("B without Auctionator: the tag stays, the tooltip says the gain is unknown", function()
        _G.Auctionator = nil
        WowStub.setBag(0, 5, WowStub.item(10940, "Strange Dust", { count = 10, sell = 2, subclass = 12 }))
        combined.Items[5] = WowStub.itemButton(0, 5)
        ns.BankAlt.Redraw()
        combined:UpdateItems()
        assert.equal("B", tagOf(combined.Items[5]))
        local text = hover(WowStub.link(10940, "Strange Dust"), 10940)
        assert.truthy(text:find("Bank it, don't list it yet: enchanting materials sell once raids open (launch day 35). "
            .. "No auction price yet, so the gain is unknown.", 1, true), text)
        assert.same({ stacks = 1, items = 10, gain = 0 }, ns.BankAlt.Summary(ns.BankAlt.Refresh()).b)
    end)

    it("follows a lock at once (a locked item has no tag)", function()
        ns.Locks.ToggleItem(2770, "link", "spec")
        assert.is_nil(tagOf(combined.Items[1]))
    end)

    it("not on other characters unless the setting says every character", function()
        MailworthyDB.bankAlts["Classic Beta PvP|Alliance"] = "Roknua Themicrulah"
        ns.BankAlt.Redraw()
        assert.is_nil(tagOf(combined.Items[1]))
        assert.equal("", hover(WowStub.link(2770, "Copper Ore"), 2770))
        ns.Config.Set("tagsEverywhere", true)
        ns.BankAlt.Redraw()
        assert.equal("AH", tagOf(combined.Items[1]))
    end)

    it("tooltip: today's verdict with the numbers, and why it was mailed", function()
        MailworthyDB.mailed = { [2589] = { route = "ah", gain = 821, at = WowStub.state.serverTime,
            from = "Tilda Quickfoot", to = "Rettana Quilwrit" } }
        local text = hover(WowStub.link(2589, "Linen Cloth"), 2589)
        assert.truthy(text:find("Mailworthy  |cffffffff[Vendor now]|r", 1, true), text)
        assert.truthy(text:find("Auction price today: 38c each (scanned today). After the 5% cut and the deposit "
            .. "that's under your 5s minimum gain, so sell it to a vendor (2s).", 1, true), text)
        assert.truthy(text:find("Mailed for: Auction +8s 21c, " .. date("%b %d", WowStub.state.serverTime)
            .. ", from Tilda Quickfoot", 1, true), text)
        text = hover(WowStub.link(2770, "Copper Ore"), 2770)
        assert.truthy(text:find("Auction price today: 1s 74c each (scanned today). After the 5% cut and the 24h deposit: "
            .. "7s 51c more than a vendor.", 1, true), text)
        assert.is_nil(text:find("Mailed for", 1, true), "never mailed: no such line")
    end)

    it("tooltip: a kept item says why (operator, 2026-11-08: Sharp Claw and Jade said nothing)", function()
        WowStub.state.professions = { { index = 1, name = "Blacksmithing", rank = 60, maxRank = 150, skillLine = 164 } }
        WowStub.setBag(0, 5, WowStub.item(5635, "Sharp Claw", { count = 4, sell = 45, class = 7, subclass = 6 }))
        prices[WowStub.link(5635, "Sharp Claw")] = { ah = 900 }
        WowStub.setBag(0, 6, WowStub.item(1529, "Jade", { quality = 2, count = 2, sell = 700, class = 7, subclass = 7 }))
        prices[WowStub.link(1529, "Jade")] = { ah = 2150 }
        ns.BankAlt.Redraw()
        local text = hover(WowStub.link(5635, "Sharp Claw"), 5635)
        assert.truthy(text:find("Mailworthy  |cffffffff[Keep]|r", 1, true), text)
        assert.truthy(text:find("Stays in your bags: your Blacksmithing needs it (until skill 200).", 1, true), text)
        text = hover(WowStub.link(1529, "Jade"), 1529)
        assert.truthy(text:find("Stays in your bags: your Blacksmithing needs it (until skill 290).", 1, true), text)
        assert.equal("", hover(WowStub.link(6948, "Hearthstone"), 6948), "soulbound: the game already says so")
    end)

    it("tooltip lines are pure: where the window mails it, or why it stays", function()
        local other = ns.BankAlt.OtherLine
        assert.same({ "Mail", "Goes to Bob Surname at the mailbox: Enchanting materials binding." },
            { other({ result = { action = "mail", route = "friend", to = "Bob Surname", what = "Enchanting materials" } }) })
        assert.same({ "Mail", "Goes to your bank alt at the mailbox: common item (no price data)." },
            { other({ result = { action = "mail", route = "common", reason = "common item (no price data)" } }) })
        assert.same({ "Keep", "Stays in your bags: Auction +5s: bank alt skipped." },
            { other({ result = { action = "keep", route = "ah", gain = 500, held = "bank alt skipped" } }) })
        assert.same({ "Keep", "Stays in your bags: no auction price yet." },
            { other({ result = { action = "keep", reason = "no price" } }) })
        -- The screenshot's Plans: Iridescent Hammer said "[Keep] Stays in your bags: no auction price yet." (operator,
        -- 2026-11-08: "going to the bank alt on no data is better than holding on the main")
        assert.same({ "Mail", "Goes to your bank alt at the mailbox: no auction price yet." },
            { other({ result = { action = "mail", route = "noprice", reason = "no auction price yet" } }) })
        assert.same({ "Keep", "Stays in your bags: the price lookup failed." },
            { other({ result = { action = "keep", reason = "no price", failed = true } }) })
        for reason in pairs(ns.BankAlt.QUIET_KEEPS) do
            assert.is_nil(other({ result = { action = "keep", reason = reason } }), reason)
        end
        assert.is_nil(other(nil))
        -- No bank alt: nothing goes to one, so the tooltip never says it does (Codex review).
        assert.same({ "Keep", "Stays in your bags: no bank alt (common item (no price data))." },
            { other({ result = { action = "mail", route = "common", reason = "common item (no price data)" } }, true) })
        -- On the bank alt itself (or skipped): never "goes to your bank alt" (Codex review, 2026-11-08).
        assert.same({ "Keep", "Stays in your bags: this is your bank alt (no auction price yet)." },
            { other({ result = { action = "mail", route = "noprice", reason = "no auction price yet" } }, "this is your bank alt") })
    end)

    it("without Auctionator: no tags, only why it was mailed", function()
        _G.Auctionator = nil
        MailworthyDB.mailed = { [2589] = { route = "common", at = WowStub.state.serverTime, from = "Tilda Quickfoot" } }
        ns.BankAlt.Redraw()
        assert.is_nil(tagOf(combined.Items[2]))
        local text = hover(WowStub.link(2589, "Linen Cloth"), 2589)
        assert.truthy(text:find("Mailed for: Common item, ", 1, true), text)
        assert.is_nil(text:find("price today", 1, true))
    end)

    it("summary: stacks to list, items to disenchant, what's now better at a vendor", function()
        MailworthyDB.mailed = { [2589] = { route = "ah", at = WowStub.state.serverTime } }
        local s = ns.BankAlt.Summary(ns.BankAlt.Refresh())
        assert.same({ stacks = 1, items = 5, gain = 751 }, s.ah)
        assert.same({ stacks = 1, items = 1, gain = 950 }, s.de)
        assert.same({ stacks = 1, items = 20, vendor = 200, wasAuction = 1 }, s.v)
        MailworthyDB.mailed = { [2589] = { route = "bank", listRoute = "ah", at = WowStub.state.serverTime } }
        assert.equal(1, ns.BankAlt.Summary(ns.BankAlt.Refresh()).v.wasAuction, "banked for the auction house counts too")
        ns.HandleSlash("summary")
        assert.is_true(MailworthySummaryFrame:IsShown())
    end)

    it("the Mailworthy button on the bank alt opens the window, its Summary the summary; the controller drives it", function()
        -- operator, 2026-11-08: "mailworthy bank alt view should still allow mail automation"
        MailFrame:Show()
        SendMailFrame:Show()
        _G.MailworthyMailButton:Click()
        assert.is_true(ns.MailWindow.Frame():IsShown())
        assert.is_false(MailworthySummaryFrame:IsShown())
        assert.truthy(ns.MailWindow.Texts().to[1]:find("This is your bank alt", 1, true))
        assert.is_true(_G.MailworthyMailSummary:IsShown())
        assert.is_false(_G.MailworthyMailSkipBankAlt:IsShown(), "no Skip once on the bank alt itself")
        for _, item in ipairs(ns.MailWindow.Result().mail) do
            assert.truthy(item.result.to, "nothing goes to the bank alt from the bank alt")
        end
        _G.MailworthyMailSummary:Click()
        assert.is_true(MailworthySummaryFrame:IsShown())
        ns.MailWindow.Frame():Hide()
        WowStub.state.gamepadUI = true
        WowStub.state.activeFrame = nil
        MailworthyPadWatcher.scripts.OnUpdate(MailworthyPadWatcher, 0.2)
        assert.equal("CLICK MailworthyPadCircle:LeftButton", WowStub.state.bindings.PAD2)
        _G.MailworthyPadCircle:Click()
        assert.is_false(MailworthySummaryFrame:IsShown())
    end)

    it("bankAltMail off: the Mailworthy button on the bank alt opens only the summary, as before", function()
        ns.HandleSlash("feature bankAltMail off")
        MailFrame:Show()
        SendMailFrame:Show()
        _G.MailworthyMailButton:Click()
        assert.is_true(MailworthySummaryFrame:IsShown())
        assert.is_false(ns.MailWindow.Frame():IsShown())
    end)

    it("switches: no tags and no tooltip hook when off", function()
        local ns2 = loadAddon() -- a fresh client: new bags and bag frames
        ns2.Valuation.DEFAULTS.minGain = 500
        WowStub.setBag(0, 1, WowStub.item(2770, "Copper Ore", { count = 5, sell = 5 }))
        local button = WowStub.itemButton(0, 1)
        ContainerFrameCombinedBags.Items = { button }
        ns2.HandleSlash("feature bankAltTags off")
        ns2.HandleSlash("feature tooltipLines off")
        postCalls = {}
        ns2.Fire("PLAYER_LOGIN")
        ns2.Config.SetBankAlt("Rettana Quilwrit")
        ns2.BankAlt.Redraw()
        ContainerFrameCombinedBags:UpdateItems()
        assert.is_nil(tagOf(button))
        -- The only item-tooltip hook left is the lock glow's (its own switch, slotBorder: border_spec),
        -- and it adds nothing for an unlocked item.
        if postCalls[0] then assert.equal("", hover(WowStub.link(2770, "Copper Ore"), 2770)) end
        ns = ns2 -- after_each reads this one's log
    end)
end)

describe("vendor tags on a main after sending", function()
    local ns, combined, prices

    local function tagOf(button)
        for _, f in ipairs(button.fontStrings) do
            if f:IsShown() then return f.text end
        end
        return nil
    end

    before_each(function()
        ns = loadAddon()
        ns.Valuation.DEFAULTS.minGain = 500 -- these fixtures were built on the old 5s default (1s since 2026-11-07)
        prices = {}
        _G.Auctionator = { API = { v1 = {
            GetAuctionPriceByItemLink = function(_, l) return prices[l] end,
            GetAuctionAgeByItemLink = function() return 0 end,
        } } }
        WowStub.setBag(0, 1, WowStub.item(2770, "Copper Ore", { count = 5, sell = 5 }))
        prices[WowStub.link(2770, "Copper Ore")] = 174
        WowStub.setBag(0, 2, WowStub.item(2589, "Linen Cloth", { count = 20, sell = 10 }))
        prices[WowStub.link(2589, "Linen Cloth")] = 40
        WowStub.setBag(0, 3, WowStub.item(4865, "Ruined Pelt", { quality = 0, count = 2, sell = 5 }))
        WowStub.setBag(0, 4, WowStub.item(6948, "Hearthstone", { bound = true, sell = 0 }))
        combined = ContainerFrameCombinedBags
        combined.Items = { WowStub.itemButton(0, 1), WowStub.itemButton(0, 2), WowStub.itemButton(0, 3),
            WowStub.itemButton(0, 4) }
        ns.Fire("PLAYER_LOGIN")
        ns.Config.SetBankAlt("Roknua Themicrulah") -- this character is a main
        MailFrame:Show()
        SendMailFrame:Show()
    end)

    after_each(function() _G.Auctionator = nil end)

    local function send()
        _G.MailworthyMailButton:Click()
        _G.MailworthyMailSend:Click()
        WowStub.runTimers()
        ns.Fire("MAIL_SEND_SUCCESS")
        WowStub.runTimers()
        combined:UpdateItems()
    end

    it("no tags before sending", function()
        combined:UpdateItems()
        for _, b in ipairs(combined.Items) do assert.is_nil(tagOf(b)) end
    end)

    it("after Send: V on what a vendor pays more for, grey junk included; nothing else", function()
        send()
        assert.equal(1, #WowStub.state.sent, "the Copper Ore went")
        assert.is_nil(tagOf(combined.Items[1]), "its slot is empty now")
        assert.equal("V", tagOf(combined.Items[2]), "Linen Cloth: the window kept it for the vendor")
        assert.equal("V", tagOf(combined.Items[3]), "grey junk: no auction price, a vendor buys it")
        assert.is_nil(tagOf(combined.Items[4]), "soulbound: nothing to say")
        assert.equal("vendor", ns.BankAlt.Mode())
    end)

    it("uses the window's settings (postage included), so the tags match what it showed", function()
        send()
        local linen = ns.BankAlt.Refresh().keep[1]
        for _, item in ipairs(ns.BankAlt.Refresh().keep) do if item.itemID == 2589 then linen = item end end
        assert.equal(30, linen.result.postage)
    end)

    it("locking an item after the send removes its V at once; unlocking brings it back", function()
        send()
        assert.equal("V", tagOf(combined.Items[2]))
        ns.Locks.ToggleItem(2589, "[Linen Cloth]", "Alt+click") -- "wait, I want to keep that"
        assert.is_nil(tagOf(combined.Items[2]), "no bag update needed")
        ns.Locks.ToggleItem(2589, "[Linen Cloth]", "Alt+click")
        assert.equal("V", tagOf(combined.Items[2]))
        WowStub.state.navButton = WowStub.itemButton(0, 3)
        ns.Locks.ToggleSelectedBagSlot() -- L3 on the grey junk
        assert.is_nil(tagOf(combined.Items[3]))
    end)

    it("a send that fails turns nothing on", function()
        _G.MailworthyMailButton:Click()
        _G.MailworthyMailSend:Click()
        WowStub.runTimers()
        ns.Fire("MAIL_FAILED")
        combined:UpdateItems()
        assert.is_nil(tagOf(combined.Items[2]))
        assert.is_nil(ns.BankAlt.Mode())
    end)

    it("while the Mailworthy window is open, the tooltip says what the window does with the item", function()
        -- operator, 2026-11-08: Sharp Claw hovered at the mailbox, before sending, said nothing.
        local postCall, lines, displayed = nil, {}, nil
        _G.Enum = { TooltipDataType = { Item = 0 } }
        _G.TooltipDataProcessor = { AddTooltipPostCall = function(_, fn) postCall = fn end }
        _G.TooltipUtil = { GetDisplayedItem = function() return "name", displayed end }
        ns.BankAlt.InstallTooltip()
        rawset(GameTooltip, "AddLine", function(_, text) table.insert(lines, text) end)
        local function hover(id, name)
            lines, displayed = {}, WowStub.link(id, name)
            postCall(GameTooltip, { id = id })
            return table.concat(lines, "\n")
        end
        assert.equal("", hover(2770, "Copper Ore"), "window closed, no tags here: nothing")
        _G.MailworthyMailButton:Click()
        MailworthyDB.mailed = { [2770] = { route = "ah", at = WowStub.state.serverTime, from = "Tilda Quickfoot" } }
        local text = hover(2770, "Copper Ore")
        assert.truthy(text:find("[Auction]", 1, true), text)
        assert.is_nil(text:find("Mailed for", 1, true), "'Mailed for' is the bank alt's line")
        assert.truthy(hover(2589, "Linen Cloth"):find("[Vendor now]", 1, true))
        rawset(GameTooltip, "AddLine", nil)
        _G.Enum, _G.TooltipDataProcessor, _G.TooltipUtil = nil, nil, nil
    end)

    it("the tooltip says to vendor it, without 'Mailed for' (that's for the bank alt)", function()
        local postCall, lines = nil, {}
        _G.Enum = { TooltipDataType = { Item = 0 } }
        _G.TooltipDataProcessor = { AddTooltipPostCall = function(_, fn) postCall = fn end }
        _G.TooltipUtil = { GetDisplayedItem = function() return "name", WowStub.link(2589, "Linen Cloth") end }
        ns.BankAlt.InstallTooltip()
        rawset(GameTooltip, "AddLine", function(_, text) table.insert(lines, text) end)
        send()
        MailworthyDB.mailed[2589] = { route = "ah", at = WowStub.state.serverTime, from = "Rettana Quilwrit" }
        postCall(GameTooltip, { id = 2589 })
        local text = table.concat(lines, "\n")
        assert.truthy(text:find("[Vendor now]", 1, true), text)
        assert.is_nil(text:find("Mailed for", 1, true))
        rawset(GameTooltip, "AddLine", nil)
        _G.Enum, _G.TooltipDataProcessor, _G.TooltipUtil = nil, nil, nil
    end)
end)

-- A bank alt on a second WoW account: its SavedVariables never saw the main's
-- pick or a single send, so it declares itself the bank alt in the settings window
-- and MailworthyDB.mailed is nil there.
describe("bank alt on a second account (never sent, no pick from a main)", function()
    local ns, combined, prices, postCalls, tooltipLines, displayed

    local function tagOf(button)
        for _, f in ipairs(button.fontStrings) do
            if f:IsShown() then return f.text end
        end
        return nil
    end

    local function hover(link, itemID)
        tooltipLines, displayed = {}, link
        postCalls[0](GameTooltip, { id = itemID })
        return table.concat(tooltipLines, "\n")
    end

    before_each(function()
        ns = loadAddon()
        ns.Valuation.DEFAULTS.minGain = 500 -- these fixtures were built on the old 5s default (1s since 2026-11-07)
        prices, postCalls, tooltipLines = {}, {}, {}
        _G.Auctionator = { API = { v1 = {
            GetAuctionPriceByItemLink = function(_, l) return prices[l] and prices[l].ah end,
            GetAuctionAgeByItemLink = function() return 0 end,
            IsAuctionDataExactByItemLink = function() return true end,
        } } }
        _G.Enum = { TooltipDataType = { Item = 0 } }
        _G.TooltipDataProcessor = { AddTooltipPostCall = function(t, fn) postCalls[t] = fn end }
        _G.TooltipUtil = { GetDisplayedItem = function() return "name", displayed end }
        rawset(GameTooltip, "AddLine", function(_, text) table.insert(tooltipLines, text) end)
        WowStub.setBag(0, 1, WowStub.item(2770, "Copper Ore", { count = 5, sell = 5 }))
        prices[WowStub.link(2770, "Copper Ore")] = { ah = 174 }
        WowStub.setBag(0, 2, WowStub.item(2589, "Linen Cloth", { count = 20, sell = 10 }))
        prices[WowStub.link(2589, "Linen Cloth")] = { ah = 38 }
        combined = ContainerFrameCombinedBags
        combined.Items = { WowStub.itemButton(0, 1), WowStub.itemButton(0, 2) }
        ns.Fire("PLAYER_LOGIN")
        assert.is_nil(MailworthyDB.mailed, "nothing was ever sent from this account")
        assert.equal(0, #ns.Characters.Mailable(), "the main is on the other account: unknown here")
    end)

    after_each(function()
        _G.Auctionator, _G.Enum, _G.TooltipDataProcessor, _G.TooltipUtil = nil, nil, nil, nil
        rawset(GameTooltip, "AddLine", nil)
        for _, line in ipairs(ns.Log.Lines()) do assert.is_nil(line:find("error", 1, true), line) end
    end)

    it("is not the bank alt until it says so; then the tags come on without 'tags everywhere'", function()
        combined:UpdateItems()
        assert.is_false(ns.BankAlt.IsBankAlt())
        -- No bank alt on this realm and faction: this character sells its own, so its tags show
        -- (the bank alt is optional, operator 2026-11-08).
        assert.equal("self", ns.BankAlt.Mode())
        assert.equal("AH", tagOf(combined.Items[1]))
        ns.SettingsUI.Show()
        _G.MailworthySettingsHere:Click()
        assert.is_true(ns.BankAlt.IsBankAlt())
        assert.equal("bankalt", ns.BankAlt.Mode())
        assert.is_false(ns.Config.Flag("tagsEverywhere"))
        combined:UpdateItems()
        assert.equal("AH", tagOf(combined.Items[1]))
        assert.equal("V", tagOf(combined.Items[2]))
    end)

    it("tooltips and the summary work with no mailed-for history at all", function()
        ns.SettingsUI.Show()
        _G.MailworthySettingsHere:Click()
        local text = hover(WowStub.link(2770, "Copper Ore"), 2770)
        assert.truthy(text:find("Mailworthy  |cffffffff[Auction]|r", 1, true), text)
        assert.truthy(text:find("7s 51c more than a vendor.", 1, true), text)
        assert.is_nil(text:find("Mailed for", 1, true), "no record: no such line")
        assert.is_nil(MailworthyDB.mailed, "hovering writes nothing")
        local s = ns.BankAlt.Summary(ns.BankAlt.Refresh())
        assert.same({ stacks = 1, items = 5, gain = 751 }, s.ah)
        assert.same({ stacks = 1, items = 20, vendor = 200, wasAuction = 0 }, s.v)
        ns.HandleSlash("summary")
        assert.is_true(MailworthySummaryFrame:IsShown())
    end)

    it("a damaged or partial mailed record never errors", function()
        ns.SettingsUI.Show()
        _G.MailworthySettingsHere:Click()
        MailworthyDB.mailed = { [2770] = true, [2589] = {} }
        local text = hover(WowStub.link(2770, "Copper Ore"), 2770)
        assert.is_nil(text:find("Mailed for", 1, true), text)
        text = hover(WowStub.link(2589, "Linen Cloth"), 2589)
        assert.truthy(text:find("Mailed for: nil, ", 1, true), text)
        assert.equal(0, ns.BankAlt.Summary(ns.BankAlt.Refresh()).v.wasAuction)
    end)

    it("at a mailbox the Mailworthy button opens the window, its share stays, and sending to itself is refused", function()
        ns.SettingsUI.Show()
        _G.MailworthySettingsHere:Click()
        MailworthySettingsFrame:Hide()
        MailFrame:Show()
        SendMailFrame:Show()
        _G.MailworthyMailButton:Click()
        assert.is_true(ns.MailWindow.Frame():IsShown())
        assert.equal(0, #ns.MailWindow.Result().mail, "no binding, no returns: nothing to mail")
        assert.equal("this is your bank alt", ns.MailWindow.Result().keep[1].result.held)
        assert.equal("this character is the bank alt", ns.Mailer.Blocker(ns.Config.BankAlt(), { {} }))
        ns.MailWindow.Show("send")
        ns.MailWindow.Send()
        assert.equal(0, #WowStub.state.sent, "nothing sent")
    end)
end)
