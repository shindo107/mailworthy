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
        ns.Valuation.DEFAULTS.minGain = 500 -- these fixtures were built on the old 5s default (1s since 2026-11-07)
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

    it("Skip once beside the bank alt: its items move to Staying, Send has nothing for it, Undo puts them back", function()
        -- operator, 2026-11-08: "Players should be able to click skip once for their bank alt sends too"
        _G.MailworthyMailButton:Click()
        local skip = _G.MailworthyMailSkipBankAlt
        assert.is_true(skip:IsShown())
        assert.equal("Skip once", text("MailworthyMailSkipBankAlt"))
        skip:Click()
        local result = ns.MailWindow.Result()
        assert.equal(0, #result.mail)
        assert.equal("bank alt skipped", result.keep[1].result.held, "the auction item tops Staying")
        assert.equal("|cffffd100To:|r Roknua Themicrulah", ns.MailWindow.Texts().to[1])
        assert.equal("Undo skip", text("MailworthyMailSkipBankAlt"))
        assert.equal("Send", text("MailworthyMailSend"), "nothing goes to the bank alt: not named on Send")
        skip:Click()
        assert.equal(1, #ns.MailWindow.Result().mail)
        assert.equal("Skip once", text("MailworthyMailSkipBankAlt"))
    end)

    it("the recipient lines: the skipped bank alt stays first, so Undo skip sits beside it", function()
        local R = ns.MailWindow.Recipients
        local friendOnly = { recipients = { "Bob Surname" }, byRecipient = { ["Bob Surname"] = { mails = 1, what = {} } } }
        local lines = R(friendOnly, "Roknua Themicrulah", false, true)
        assert.equal(2, #lines)
        assert.same({ name = "Roknua Themicrulah", note = "your bank alt · skipped this time", bank = true }, lines[1])
        assert.equal("Bob Surname", lines[2].name)
        lines = R(friendOnly, "Roknua Themicrulah", false, false)
        assert.equal("Bob Surname", lines[1].name, "not skipped and nothing for it: the friend alone")
        lines = R({ recipients = {} }, nil, false, false)
        assert.truthy(lines[1].name:find("No bank alt", 1, true))
        assert.equal("optional: Settings", lines[1].note)
    end)

    it("formats item names and reasons for people", function()
        assert.equal("|cffffffffCopper Ore|r |cffaaaaaax20|r", ns.MailWindow.ItemText(WowStub.link(2770, "Copper Ore"), 20))
        assert.equal("sells better at a vendor", ns.MailWindow.StayReason({ reason = "not worth it", gain = -10 }))
        assert.equal("only 4s 10c more than a vendor (needs 5s)",
            ns.MailWindow.StayReason({ reason = "not worth it", gain = 410, threshold = 500 }))
        assert.equal("no auction price yet", ns.MailWindow.StayReason({ reason = "no price" }))
        assert.equal("the price lookup failed", ns.MailWindow.StayReason({ reason = "no price", failed = true }))
        assert.equal("profession tool", ns.MailWindow.StayReason({ reason = "profession tool" }))
    end)

    it("the total counts what goes with no price yet, and says what goes without a price source (Codex review)", function()
        local S = { cut = 0.05, duration = 3 }
        local line, note = ns.MailWindow.TotalText({ priced = true, settings = S,
            totals = { gain = 902, unpriced = 2, postage = 90, items = 3 } })
        assert.equal("+9s 2c more than vendoring, 2 with no price yet", line)
        assert.equal("after the 5% AH cut, 24h deposits and 90c postage", note)
        line = ns.MailWindow.TotalText({ priced = true, settings = S, totals = { gain = 902, unpriced = 0, postage = 0 } })
        assert.equal("+9s 2c more than vendoring", line)
        line, note = ns.MailWindow.TotalText({ priced = false, settings = S, totals = { items = 1, postage = 30 } })
        assert.equal("1 item to mail", line)
        assert.equal("No Auctionator: white items and staple trade goods go. Postage 30c.", note)
    end)

    it("the Staying count says how many are locked", function()
        assert.equal("18 items", ns.MailWindow.StayCountText(18, 0))
        assert.equal("|cff4da6ff3 locked|r · 18 items", ns.MailWindow.StayCountText(18, 3))
        assert.equal("1 item", ns.MailWindow.StayCountText(1, 0))
    end)

    it("pressing a row locks the item (it moves to staying); pressing it again unlocks it", function()
        _G.MailworthyMailButton:Click()
        _G.MailworthyMailRow1:Click()
        assert.is_true(ns.Locks.IsItemLocked(2770))
        assert.equal(0, #ns.MailWindow.Result().mail)
        assert.equal(2, #ns.MailWindow.Result().keep)
        -- locked items come first in Staying (one press away), then the rest by gain
        assert.equal(2770, ns.MailWindow.Result().keep[1].itemID)
        assert.equal(1, ns.MailWindow.Result().locked)
        assert.equal("locked (press to unlock)", ns.MailWindow.StayReason(ns.MailWindow.Result().keep[1].result))
        _G.MailworthyStayRow1:Click()
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

    it("on the Inbox: Send is greyed out and says Click Send Mail; pressing it sends nothing, no tab is clicked", function()
        -- operator, 2026-11-08: "the button should be greyed out with a 'click send mail' text"
        SendMailFrame:Hide()
        InboxFrame:Show()
        _G.MailworthyInboxButton:Click()
        assert.is_true(_G.MailworthyMailSend:IsShown())
        assert.is_false(_G.MailworthyMailSend:IsEnabled())
        assert.equal("Click Send Mail", text("MailworthyMailSend"))
        assert.is_nil(_G.MailworthyOpenSendTab, "v0.16.1's secure button is gone")
        _G.MailworthyMailSend:Click()
        ns.MailWindow.Send() -- and the code path itself refuses on the Inbox
        WowStub.runTimers()
        assert.equal(0, #WowStub.state.sent)
        assert.is_false(ns.Mailer.Busy())
        assert.equal(0, WowStub.tabClicks)
        WowStub.state.gamepadUI = true
        ns.MailWindow.Refresh()
        assert.equal("Send Mail tab: R1", text("MailworthyMailSend"), "the controller's way to the tab")
    end)

    it("the Send Mail tab opens the window by itself, once per showing; the switch turns it off", function()
        -- operator, 2026-11-08: "when you click send mail mailworthy should open"
        local watcher = _G.MailworthyTabWatcher
        local function tick() watcher.scripts.OnUpdate(watcher, 0.3) end
        SendMailFrame:Hide()
        InboxFrame:Show()
        tick()
        assert.is_false(ns.MailWindow.Frame():IsShown() and ns.MailWindow.Frame():IsVisible(), "not on the Inbox")
        InboxFrame:Hide()
        SendMailFrame:Show() -- the player clicks the Send Mail tab
        tick()
        assert.is_true(ns.MailWindow.Frame():IsVisible())
        assert.is_true(_G.MailworthyMailSend:IsEnabled())
        assert.equal("Send to Roknua", text("MailworthyMailSend"))
        ns.MailWindow.Frame():Hide() -- closed with the X: stays closed on this tab
        tick()
        assert.is_false(ns.MailWindow.Frame():IsShown())
        SendMailFrame:Hide()
        InboxFrame:Show()
        tick()
        InboxFrame:Hide()
        SendMailFrame:Show()
        tick()
        assert.is_true(ns.MailWindow.Frame():IsVisible(), "the tab shown again: open again")
        ns.MailWindow.Frame():Hide()
        MailworthyDB.features = { autoOpen = false }
        SendMailFrame:Hide()
        tick()
        SendMailFrame:Show()
        tick()
        assert.is_false(ns.MailWindow.Frame():IsShown(), "/mw feature autoOpen off")
        assert.equal(0, WowStub.tabClicks)
    end)

    it("auto-open: on the bank alt only while its window mails; a mailbox reopened between ticks still opens", function()
        local watcher = _G.MailworthyTabWatcher
        local function tick() watcher.scripts.OnUpdate(watcher, 0.3) end
        ns.Config.SetBankAltHere()
        ns.HandleSlash("feature bankAltMail off") -- its button opens the summary: no window by itself (Codex review)
        SendMailFrame:Show()
        tick()
        assert.is_false(ns.MailWindow.Frame():IsShown() and ns.MailWindow.Frame():IsVisible())
        ns.HandleSlash("feature bankAltMail on") -- the default since 2026-11-08: the bank alt mails too
        SendMailFrame:Hide()
        tick()
        SendMailFrame:Show()
        tick()
        assert.is_true(ns.MailWindow.Frame():IsVisible())
        ns.MailWindow.Frame():Hide()
        ns.Config.SetBankAlt("Roknua Themicrulah")
        SendMailFrame:Hide()
        tick()
        SendMailFrame:Show()
        tick()
        assert.is_true(ns.MailWindow.Frame():IsVisible())
        ns.MailWindow.Frame():Hide()
        ns.Fire("MAIL_CLOSED") -- closed and reopened on Send Mail before the next tick
        tick()
        assert.is_true(ns.MailWindow.Frame():IsVisible(), "a new visit opens it again")
    end)

    it("on the Inbox Send stays greyed out while a send runs (Codex review)", function()
        _G.MailworthyMailButton:Click()
        _G.MailworthyMailSend:Click()
        assert.is_true(ns.Mailer.Busy())
        SendMailFrame:Hide()
        InboxFrame:Show()
        ns.MailWindow.Refresh(true)
        assert.is_false(_G.MailworthyMailSend:IsEnabled())
        assert.equal("Sending...", text("MailworthyMailSend"))
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

    it("on the Send Mail tab the Send button shows, however the window got there (v0.20.1 hid it)", function()
        -- Opened on the Send Mail tab, the player looks at the Inbox, comes back.
        InboxFrame:Hide()
        SendMailFrame:Show()
        _G.MailworthyMailButton:Click()
        assert.is_true(_G.MailworthyMailSend:IsShown())
        SendMailFrame:Hide()
        InboxFrame:Show()
        local watcher = _G.MailworthyTabWatcher
        watcher.scripts.OnUpdate(watcher, 0.3)
        _G.MailworthyInboxButton:Click() -- hidden with the Send Mail tab, shown here, not "toggled off"
        assert.is_true(ns.MailWindow.Frame():IsVisible())
        assert.is_false(_G.MailworthyMailSend:IsEnabled())
        InboxFrame:Hide()
        SendMailFrame:Show()
        watcher.scripts.OnUpdate(watcher, 0.3)
        assert.is_true(ns.MailWindow.Frame():IsVisible())
        assert.is_true(_G.MailworthyMailSend:IsEnabled())
        assert.truthy(text("MailworthyMailSend"):find("^Send to"))
    end)

    it("a stale Inbox draw on the Send Mail tab is redrawn by the watcher", function()
        InboxFrame:Hide()
        SendMailFrame:Show()
        ns.MailWindow.Show("send")
        -- Something drew it while the Inbox showed (both frames shown at once, as a tab switch passes).
        SendMailFrame:Hide()
        InboxFrame:Show()
        ns.MailWindow.Refresh()
        InboxFrame:Hide()
        SendMailFrame:Show()
        assert.is_false(_G.MailworthyMailSend:IsEnabled())
        local watcher = _G.MailworthyTabWatcher
        watcher.scripts.OnUpdate(watcher, 0.3)
        assert.is_true(_G.MailworthyMailSend:IsEnabled())
        assert.truthy(ns.Report.Build():find("mail tabs: SendMailFrame shown true visible true", 1, true))
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
