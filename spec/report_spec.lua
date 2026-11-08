-- /mw report (one copyable report for bug reports), the end of the discovery
-- self-test, quiet blocked-action messages, and the AH sale-mail reader that
-- measures the house cut.
local loadAddon = require("spec.support.load_addon")

describe("report", function()
    local ns
    local function has(text, s) assert.truthy(text:find(s, 1, true), "missing: " .. s .. "\n" .. text) end

    before_each(function()
        ns = loadAddon()
        ns.Fire("PLAYER_LOGIN")
    end)

    it("/mw report shows everything a bug report needs in the copy box", function()
        ns.Config.SetBankAlt("Roknua Themicrulah")
        ns.Locks.ToggleItem(2770, "[Copper Ore]", "spec")
        ns.HandleSlash("report")
        local text = ns.Report.Text()
        assert.is_true(MailworthyReportFrame:IsShown())
        has(text, "Mailworthy " .. ns.VERSION .. " report at ")
        has(text, "build: 1.60.1, 70338")
        has(text, "character: Rettana Quilwrit (Classic Beta PvP, Alliance)")
        has(text, "bank alt: Roknua Themicrulah")
        has(text, "settings: 24h listing, min gain 1s and 25%, disenchant off, max price age 7 days, tags bank alt only")
        has(text, "server: launch day 0 (realm first seen 2026-10-13)")
        has(text, "prices: none")
        has(text, "features: altClickLock=on, arkInventoryTags=on, autoOpen=on, baganatorTags=on, bagnonTags=on, "
            .. "bankAltMail=on, bankAltTags=on")
        has(text, "bag addon: Baganator not loaded")
        has(text, "bag addon: Bagnon not loaded")
        has(text, "bag addon: ArkInventory not loaded")
        has(text, "controller bindings: sets none")
        has(text, "locked items (this character): 2770 [Copper Ore]")
        has(text, "last send: none this session")
        has(text, "known character: Rettana Quilwrit")
        has(text, "[lock] locked [Copper Ore]")
        assert.equal(0, WowStub.focusCalls)
    end)

    it("/mw report and the settings' Prices line name the auction source in use (TSM: 2026-11-08)", function()
        finally(function() _G.TSM_API, _G.Auctionator = nil, nil end)
        local function tsm() _G.TSM_API = { GetCustomPriceValue = function() end } end
        local function atr() _G.Auctionator = { API = { v1 = { GetAuctionPriceByItemLink = function() end } } } end
        assert.equal("Prices: none (install Auctionator or TSM; only white items are mailed)", ns.SettingsUI.PricesText())
        tsm()
        ns.HandleSlash("report")
        has(ns.Report.Text(), "prices: TradeSkillMaster")
        assert.equal("Prices: TradeSkillMaster", ns.SettingsUI.PricesText())
        atr()
        ns.HandleSlash("report")
        has(ns.Report.Text(), "prices: Auctionator (TSM installed, not used)")
        assert.equal("Prices: Auctionator (TSM installed, not used)", ns.SettingsUI.PricesText())
        _G.TSM_API = nil
        assert.equal("Prices: Auctionator", ns.SettingsUI.PricesText())
    end)

    it("the discovery self-test is gone, and its saved data with it", function()
        local saved = { selftest = { answers = { icon = { value = "yes" } }, log = { "old" } }, characters = {} }
        local ns2 = loadAddon()
        _G.MailworthyDB = saved
        ns2.Init()
        assert.is_nil(MailworthyDB.selftest)
        assert.same({}, MailworthyDB.log)
        ns2.HandleSlash("selftest")
        assert.truthy(table.concat(WowStub.printed, "\n"):find("commands (/mw or /mailworthy)", 1, true),
            "an unknown command shows the help")
        assert.is_nil(ns2.SelfTest)
    end)

    it("a blocked action prints one chat line per session; all of them are in the report", function()
        local before = #WowStub.printed
        ns.Blocked.OnEvent("ADDON_ACTION_BLOCKED", "Mailworthy", "A()")
        ns.Blocked.OnEvent("ADDON_ACTION_BLOCKED", "Mailworthy", "B()")
        assert.equal(before + 1, #WowStub.printed)
        assert.truthy(WowStub.printed[#WowStub.printed]:find("/mw report", 1, true))
        local text = ns.Report.Build()
        has(text, "blocked: ADDON_ACTION_BLOCKED A()")
        has(text, "blocked: ADDON_ACTION_BLOCKED B()")
    end)

    it("logs AH sale mails with the house cut, once per mailbox visit", function()
        WowStub.state.inbox = { {} }
        WowStub.state.invoices = { { type = "seller", item = "Copper Ore", player = "Someone", bid = 0, buyout = 2000,
            deposit = 100, cut = 100, count = 10 } }
        ns.Fire("MAIL_SHOW")
        ns.Fire("MAIL_INBOX_UPDATE")
        ns.Fire("MAIL_INBOX_UPDATE")
        local log = table.concat(ns.Log.Lines(), "\n")
        has(log, '[invoice] seller "Copper Ore" x10: bid 0, buyout 2000, deposit 100, house cut 100 (5.00%)')
        assert.is_nil(log:find("Someone", 1, true), "never the other player's name")
        local _, n = log:gsub("%[invoice%]", "")
        assert.equal(1, n)
    end)
end)
