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
        prices[WowStub.link(MEAT, "Crisp Spider Meat")] = 5000 -- the auction house would pay well
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

    it("the questNeeds switch turns it off", function()
        MailworthyDB.features = { questNeeds = false }
        assert.truthy(find(ns.Bags.Evaluate().mail, MEAT))
    end)
end)
