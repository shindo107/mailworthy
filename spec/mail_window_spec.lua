-- The Mailworthy window at the mailbox: recipient, what goes and why, what
-- stays and why (soulbound / quest items not listed), totals, Send / Settings /
-- Close; rows lock and unlock items; works with the mouse and the controller.
local loadAddon = require("spec.support.load_addon")

describe("mail window", function()
    local ns, prices

    local function text(name) return tostring(_G[name] and _G[name].text) end
    local function rowNames(prefix, n)
        local out = {}
        for i = 1, n do
            local row = _G[prefix .. i]
            if row and row:IsShown() then out[#out + 1] = row end
        end
        return out
    end

    before_each(function()
        ns = loadAddon()
        ns.Fire("PLAYER_LOGIN")
        ns.Config.SetBankAlt("Roknua Themicrulah")
        prices = {}
        _G.Auctionator = { API = { v1 = {
            GetAuctionPriceByItemLink = function(_, l) return prices[l] end,
            GetAuctionAgeByItemLink = function() return 0 end,
        } } }
        WowStub.setBag(0, 1, WowStub.item(2770, "Copper Ore", { count = 20, sell = 5 }))
        prices[WowStub.link(2770, "Copper Ore")] = 174
        WowStub.setBag(0, 2, WowStub.item(2589, "Linen Cloth", { count = 20, sell = 10 }))
        prices[WowStub.link(2589, "Linen Cloth")] = 40
        WowStub.setBag(0, 3, WowStub.item(6948, "Hearthstone", { bound = true, sell = 0 }))
        MailFrame:Show()
        SendMailFrame:Show()
    end)
    after_each(function()
        _G.Auctionator = nil
        assert.equal(0, WowStub.focusCalls)
    end)

    it("shows the recipient, what goes and why, what stays and why, and the total", function()
        _G.MailworthyMailButton:Click()
        assert.is_true(ns.MailWindow.Frame():IsShown())
        local result = ns.MailWindow.Result()
        assert.equal(1, #result.mail)
        assert.equal(1, #result.keep, "the Hearthstone isn't listed: it can never be mailed")
        assert.equal(1, #rowNames("MailworthyMailRow", ns.MailWindow.MAIL_ROWS))
        assert.equal(1, #rowNames("MailworthyStayRow", ns.MailWindow.STAY_ROWS))
        assert.equal("Send to Roknua", text("MailworthyMailSend"))
    end)

    it("formats item names and reasons for people", function()
        assert.equal("|cffffffffCopper Ore|r |cffaaaaaax20|r", ns.MailWindow.ItemText(WowStub.link(2770, "Copper Ore"), 20))
        assert.equal("sells better at a vendor", ns.MailWindow.StayReason({ reason = "not worth it", gain = -10 }))
        assert.equal("only 4s 10c more than a vendor (needs 5s)",
            ns.MailWindow.StayReason({ reason = "not worth it", gain = 410, threshold = 500 }))
        assert.equal("no auction price yet", ns.MailWindow.StayReason({ reason = "no price" }))
        assert.equal("profession tool", ns.MailWindow.StayReason({ reason = "profession tool" }))
    end)

    it("pressing a row locks the item (it moves to staying); pressing it again unlocks it", function()
        _G.MailworthyMailButton:Click()
        _G.MailworthyMailRow1:Click()
        assert.is_true(ns.Locks.IsItemLocked(2770))
        assert.equal(0, #ns.MailWindow.Result().mail)
        assert.equal(2, #ns.MailWindow.Result().keep)
        -- staying is sorted by gain: Linen Cloth (+4s 10c) first, the locked Copper Ore (no gain) last
        _G.MailworthyStayRow2:Click()
        assert.is_false(ns.Locks.IsItemLocked(2770), "unlocked again")
        assert.is_false(ns.Locks.IsItemLocked(2589), "nothing else locked")
        assert.equal(1, #ns.MailWindow.Result().mail)
    end)

    it("Send mails the list to the bank alt; Settings opens the settings", function()
        _G.MailworthyMailButton:Click()
        _G.MailworthyMailSend:Click()
        WowStub.runTimers()
        assert.equal(1, #WowStub.state.sent)
        assert.equal("Roknua Themicrulah", WowStub.state.sent[1].name)
        assert.equal(1, WowStub.state.sent[1].count, "only the Copper Ore: not the Linen Cloth or the Hearthstone")
        ns.Fire("MAIL_SEND_SUCCESS")
        WowStub.runTimers()
        ns.Fire("BAG_UPDATE_DELAYED")
        assert.equal(0, #ns.MailWindow.Result().mail, "re-scanned after sending")
        _G.MailworthyMailSettings:Click()
        assert.is_true(ns.SettingsUI.Frame():IsShown())
    end)

    it("updates itself after sending, even when the bags updated mid-send (v0.4.0 kept the sent item)", function()
        _G.MailworthyMailButton:Click()
        assert.is_true(_G.MailworthyMailRow1:IsShown())
        _G.MailworthyMailSend:Click()
        WowStub.runTimers()
        ns.Fire("MAIL_SEND_SUCCESS")
        ns.Fire("BAG_UPDATE_DELAYED") -- the item left the bags while the mailer was still busy
        WowStub.runTimers()           -- the mailer finishes; no further bag update comes
        assert.is_false(ns.Mailer.Busy())
        assert.equal(0, #ns.MailWindow.Result().mail)
        assert.is_false(_G.MailworthyMailRow1:IsShown())
        assert.truthy(ns.Mailer.Status():find("Sent 1 mail", 1, true))
    end)

    it("on the Inbox (mouse), Send says to switch to the Send Mail tab and sends nothing", function()
        SendMailFrame:Hide()
        InboxFrame:Show()
        _G.MailworthyInboxButton:Click()
        _G.MailworthyMailSend:Click()
        WowStub.runTimers()
        assert.equal(0, #WowStub.state.sent)
        assert.truthy(ns.Mailer.Status():find("Send Mail tab", 1, true))
        assert.equal("Open the Send Mail tab", text("MailworthyMailSend"), "the button says why it can't send")
    end)

    describe("the Inbox's 'Open the Send Mail tab' button", function()
        local function open()
            SendMailFrame:Hide()
            InboxFrame:Show()
            _G.MailworthyInboxButton:Click()
            return ns.MailWindow.TabButton()
        end

        it("is a secure click on Blizzard's Send Mail tab, over Send, and no Mailworthy code clicks the tab", function()
            local b = open()
            assert.truthy(b.template:find("SecureActionButtonTemplate", 1, true))
            assert.equal(UIParent, b:GetParent(), "on UIParent, not inside the window")
            assert.equal("click", b:GetAttribute("type"))
            assert.equal(_G.MailFrameTab2, b:GetAttribute("clickbutton"))
            assert.is_nil(b.scripts.OnClick, "the template's secure OnClick, never one of ours")
            assert.is_true(b:IsShown())
            assert.is_false(_G.MailworthyMailSend:IsShown(), "it takes Send's place")
            b:Click() -- in the stub nothing runs: in game Blizzard's SECURE_ACTIONS.click presses the tab
            assert.equal(0, WowStub.tabClicks)
            InboxFrame:Hide() -- the secure click switched tabs
            SendMailFrame:Show()
            _G.MailworthyTabWatcher.scripts.OnUpdate(_G.MailworthyTabWatcher, 0.3)
            assert.is_false(b:IsShown())
            assert.is_true(_G.MailworthyMailSend:IsShown())
            assert.equal("Send to Roknua", text("MailworthyMailSend"))
        end)

        it("is hidden before combat starts and comes back after it", function()
            local b = open()
            ns.Fire("PLAYER_REGEN_DISABLED") -- runs before lockdown
            WowStub.state.inCombat = true
            assert.is_false(b:IsShown())
            assert.is_true(_G.MailworthyMailSend:IsShown())
            ns.MailWindow.Refresh()
            assert.is_false(b:IsShown(), "never shown in combat")
            WowStub.state.inCombat = false
            ns.Fire("PLAYER_REGEN_ENABLED")
            assert.is_true(b:IsShown())
        end)

        it("goes away with the window", function()
            local b = open()
            ns.MailWindow.Frame():Hide()
            assert.is_false(b:IsShown())
        end)

        it("never with the controller UI (Cross presses are addon code)", function()
            WowStub.state.gamepadUI = true
            SendMailFrame:Hide()
            InboxFrame:Show()
            ns.MailWindow.Show("inbox")
            assert.is_false(ns.MailWindow.TabButton():IsShown())
        end)

        it("/mw feature tabButton off: not created; Send only says what to do", function()
            ns = loadAddon()
            MailworthyDB.features = { tabButton = false }
            ns.Fire("PLAYER_LOGIN")
            ns.Config.SetBankAlt("Roknua Themicrulah")
            assert.is_nil(ns.MailWindow.TabButton())
            SendMailFrame:Hide()
            InboxFrame:Show()
            _G.MailworthyInboxButton:Click()
            assert.equal("Open the Send Mail tab", text("MailworthyMailSend"))
            assert.is_true(_G.MailworthyMailSend:IsShown())
        end)
    end)

    it("opened on the Inbox, follows the player to the Send Mail tab, where Send works", function()
        SendMailFrame:Hide()
        InboxFrame:Show()
        _G.MailworthyInboxButton:Click()
        assert.is_true(ns.MailWindow.OnInbox())
        local watcher = _G.MailworthyTabWatcher
        watcher.scripts.OnUpdate(watcher, 0.3)
        assert.equal(InboxFrame, ns.MailWindow.Frame():GetParent(), "stays while the Inbox shows")
        InboxFrame:Hide() -- the player clicks the Send Mail tab
        SendMailFrame:Show()
        watcher.scripts.OnUpdate(watcher, 0.3)
        assert.equal(SendMailFrame, ns.MailWindow.Frame():GetParent())
        assert.is_true(ns.MailWindow.Frame():IsVisible())
        assert.is_false(ns.MailWindow.OnInbox())
        assert.equal("Send to Roknua", text("MailworthyMailSend"))
        _G.MailworthyMailSend:Click()
        WowStub.runTimers()
        assert.equal(1, #WowStub.state.sent)
        for _, line in ipairs(ns.Log.Lines()) do assert.is_nil(line:find("error", 1, true), line) end
    end)

    it("on the bank alt itself: nothing is sent", function()
        ns.Config.SetBankAlt("Roknua Themicrulah")
        MailworthyDB.bankAlts["Classic Beta PvP|Alliance"] = "Rettana Quilwrit"
        ns.MailWindow.Show("send")
        assert.equal("Send", text("MailworthyMailSend"))
        _G.MailworthyMailSend:Click()
        WowStub.runTimers()
        assert.equal(0, #WowStub.state.sent)
    end)

    it("pages long lists", function()
        for i = 1, 10 do
            WowStub.setBag(1, i % 4 + 1, nil)
        end
        WowStub.state.numSlots[1], WowStub.state.numSlots[2] = 20, 20
        for i = 1, 10 do
            WowStub.setBag(1, i, WowStub.item(4000 + i, "Ore " .. i, { count = 5, sell = 5 }))
            prices[WowStub.link(4000 + i, "Ore " .. i)] = 500
        end
        ns.MailWindow.Show("send")
        assert.equal(11, #ns.MailWindow.Result().mail)
        assert.is_true(_G.MailworthyMailPage:IsShown())
        assert.equal("1/2  >", text("MailworthyMailPage"))
        _G.MailworthyMailPage:Click()
        assert.equal("2/2  >", text("MailworthyMailPage"))
        assert.equal(3, #rowNames("MailworthyMailRow", ns.MailWindow.MAIL_ROWS))
    end)

    it("controller: Triangle opens it, Cross on Send sends, Circle closes it", function()
        WowStub.state.gamepadUI = true
        WowStub.state.activeFrame = MailFrame
        local watcher = _G.MailworthyPadWatcher
        watcher.scripts.OnUpdate(watcher, 0.2)
        _G.MailworthyPadTriangle:Click()
        assert.is_true(ns.MailWindow.Frame():IsShown())
        watcher.scripts.OnUpdate(watcher, 0.2)
        assert.equal("CLICK MailworthyPadCross:LeftButton", WowStub.state.bindings.PAD1)
        ns.Nav.Select(_G.MailworthyMailSend)
        WowStub.state.now = WowStub.state.now + 1
        _G.MailworthyPadCross:Click()
        WowStub.runTimers()
        assert.equal(1, #WowStub.state.sent)
        WowStub.state.now = WowStub.state.now + 1
        _G.MailworthyPadCircle:Click()
        assert.is_false(ns.MailWindow.Frame():IsShown())
    end)
end)
