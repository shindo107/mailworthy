-- Items an active quest asks for stay in the bags (operator, 2026-11-08: "if the player has an
-- active quest for an item (not always "quest items") it shouldn't recommend vendoring or
-- auctioning"): Crisp Spider Meat for Redridge Goulash, a plain trade good.
local loadAddon = require("spec.support.load_addon")

local MEAT = 1081

describe("quests", function()
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
        WowStub.setBag(0, 1, WowStub.item(MEAT, "Crisp Spider Meat", { count = 5, sell = 250, class = 7, subclass = 8 }))
        prices[WowStub.link(MEAT, "Crisp Spider Meat")] = 900 -- the auction house would pay well (under a binding's 10s cap)
        WowStub.state.quests = {
            { title = "Redridge", header = true },
            { title = "Redridge Goulash", objectives = {
                { text = "Great Goretusk Snout: 5/5", type = "item" },
                { text = "Crisp Spider Meat: 3/5", type = "item" },
                { text = "Tough Condor Meat: 5/5", type = "item" } } },
            { title = "Blackrock Menace", objectives = { { text = "Blackrock Grunt slain: 4/15", type = "monster" } } },
        }
    end)
    after_each(function()
        _G.Auctionator = nil
        for _, line in ipairs(ns.Log.Lines()) do assert.is_nil(line:find("error", 1, true), line) end
    end)

    local function find(list, itemID)
        for _, it in ipairs(list) do if it.itemID == itemID then return it end end
    end

    it("reads the item an objective names, in either client's format", function()
        local name = ns.Quests.ItemName
        assert.equal("Crisp Spider Meat", name("Crisp Spider Meat: 3/5"))
        assert.equal("Crisp Spider Meat", name("3/5 Crisp Spider Meat"))
        assert.equal("Crisp Spider Meat", name("Crisp Spider Meat: 5/5 (Complete)"))
        assert.equal("Bundle of Letters", name("Bundle of Letters"))
        assert.is_nil(name(""))
        assert.is_nil(name(nil))
    end)

    it("indexes item objectives only, skipping headers and kill objectives", function()
        local needs = ns.Quests.Index(ns.Quests.Read())
        assert.equal("Redridge Goulash", needs["crisp spider meat"])
        assert.equal("Redridge Goulash", needs["great goretusk snout"])
        assert.is_nil(needs["blackrock grunt slain"])
        assert.is_nil(needs["redridge"])
    end)

    it("falls back to the Vanilla quest log calls", function()
        local modern = _G.C_QuestLog
        _G.C_QuestLog = nil
        _G.GetNumQuestLogEntries = function() return 2 end
        _G.GetQuestLogTitle = function(i)
            if i == 1 then return "Redridge", 0, nil, true end
            return "Redridge Goulash", 18, nil, false
        end
        _G.GetNumQuestLeaderBoards = function(i) return i == 2 and 1 or 0 end
        _G.GetQuestLogLeaderBoard = function() return "Crisp Spider Meat: 3/5", "item", false end
        local ok, quests = pcall(ns.Quests.Read)
        _G.C_QuestLog, _G.GetNumQuestLogEntries, _G.GetQuestLogTitle = modern, nil, nil
        _G.GetNumQuestLeaderBoards, _G.GetQuestLogLeaderBoard = nil, nil
        assert.is_true(ok, tostring(quests))
        assert.equal("Redridge Goulash", ns.Quests.Index(quests)["crisp spider meat"])
    end)

    it("an item a quest needs stays, however much it's worth, and says which quest", function()
        local result = ns.Bags.Evaluate()
        assert.is_nil(find(result.mail, MEAT))
        local meat = find(result.keep, MEAT)
        assert.equal("a quest needs it", meat.result.reason)
        assert.equal("Redridge Goulash needs it", ns.MailWindow.StayReason(meat.result))
        assert.truthy(ns.Bags.Report(result):find("KEEP [Crisp Spider Meat] x5: a quest needs it (Redridge Goulash)", 1, true))
    end)

    it("a hard keep: a Cooking binding doesn't take it either", function()
        ns.Routes.Add("Bob Surname", 185)
        assert.is_nil(find(ns.Bags.Evaluate().mail, MEAT))
        MailworthyDB.features = { questNeeds = false } -- without the quest, the binding would take it
        assert.equal("Bob Surname", find(ns.Bags.Evaluate().mail, MEAT).result.to)
    end)

    it("once the quest is gone from the log (turned in), it's valued like anything else", function()
        WowStub.state.quests = {}
        ns.Fire("QUEST_LOG_UPDATE")
        assert.truthy(find(ns.Bags.Evaluate().mail, MEAT))
    end)

    it("never a vendor tag: the tooltip names the quest instead", function()
        local lines, postCall = {}, nil
        _G.Enum = { TooltipDataType = { Item = 0 } }
        _G.TooltipDataProcessor = { AddTooltipPostCall = function(_, fn) postCall = fn end }
        _G.TooltipUtil = { GetDisplayedItem = function() return "name", WowStub.link(MEAT, "Crisp Spider Meat") end }
        rawset(GameTooltip, "AddLine", function(_, text) table.insert(lines, text) end)
        prices[WowStub.link(MEAT, "Crisp Spider Meat")] = 49 -- under the vendor's 2s 50c, as in game
        ns.Config.Set("tagsEverywhere", true)
        ns.BankAlt.InstallTooltip()
        ns.BankAlt.Invalidate()
        postCall(GameTooltip, { id = MEAT })
        local text = table.concat(lines, "\n")
        rawset(GameTooltip, "AddLine", nil)
        _G.Enum, _G.TooltipDataProcessor, _G.TooltipUtil = nil, nil, nil
        assert.is_nil(text:find("Vendor now", 1, true), text)
        assert.truthy(text:find("Mailworthy  |cffffffff[Keep]|r", 1, true), text)
        assert.truthy(text:find("Stays in your bags: Redridge Goulash needs it.", 1, true), text)
    end)

    it("a quest accepted mid-run: the slot is re-checked before attaching and skipped (Codex review)", function()
        local quests = WowStub.state.quests
        WowStub.state.quests = {}
        ns.Fire("QUEST_LOG_UPDATE")
        local stack = { bag = 0, slot = 1, count = 5, itemID = MEAT, link = WowStub.link(MEAT, "Crisp Spider Meat") }
        assert.is_true(ns.Mailer.StillThere(stack))
        WowStub.state.quests = quests
        ns.Fire("QUEST_LOG_UPDATE")
        assert.same({ false, "an active quest needs it" }, { ns.Mailer.StillThere(stack) })
    end)

    it("a quest abandoned after the preview: Send holds, the list shows the item going (Codex review)", function()
        MailFrame:Show()
        SendMailFrame:Show()
        -- Something else to mail, so Send can be pressed (an empty list greys it out: "Nothing to send").
        WowStub.setBag(0, 2, WowStub.item(2770, "Copper Ore", { count = 20, sell = 5, class = 7 }))
        prices[WowStub.link(2770, "Copper Ore")] = 5000
        _G.MailworthyMailButton:Click()
        assert.is_nil(find(ns.MailWindow.Result().mail, MEAT), "under Staying")
        assert.truthy(find(ns.MailWindow.Result().mail, 2770))
        WowStub.state.quests = {}
        ns.Quests.Invalidate() -- the log changed; the window hasn't redrawn yet
        _G.MailworthyMailSend:Click()
        assert.is_false(ns.Mailer.Busy(), "an item the list showed staying never goes unseen")
        WowStub.runTimers()
        assert.equal(0, #WowStub.state.sent)
        assert.truthy(table.concat(WowStub.printed, "\n"):find(
            "Not sent: Crisp Spider Meat now goes to Roknua instead of staying in your bags", 1, true))
        assert.truthy(find(ns.MailWindow.Result().mail, MEAT), "the list now shows it going")
    end)

    it("a quest accepted with the item already in the bags redraws the window and the tags (Codex review)", function()
        local quests = WowStub.state.quests
        WowStub.state.quests = {}
        ns.Fire("QUEST_LOG_UPDATE")
        MailFrame:Show()
        SendMailFrame:Show()
        _G.MailworthyMailButton:Click()
        assert.truthy(find(ns.MailWindow.Result().mail, MEAT))
        ns.Fire("QUEST_LOG_UPDATE")
        assert.truthy(find(ns.MailWindow.Result().mail, MEAT), "nothing changed: no redraw needed")
        WowStub.state.quests = quests
        ns.Fire("QUEST_LOG_UPDATE")
        assert.is_nil(find(ns.MailWindow.Result().mail, MEAT), "the window redrew on its own")
        assert.equal("a quest needs it", find(ns.BankAlt.Refresh().keep, MEAT).result.reason)
    end)

    it("the questNeeds switch turns it off", function()
        MailworthyDB.features = { questNeeds = false }
        assert.truthy(find(ns.Bags.Evaluate().mail, MEAT))
    end)
end)
