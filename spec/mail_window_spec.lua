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
        assert.equal("Nothing to send", text("MailworthyMailSend"), "nothing goes to the bank alt")
        assert.is_false(_G.MailworthyMailSend:IsEnabled())
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

    describe("row tooltips (operator, 2026-11-09: click to lock)", function()
        local lines, shows, hides
        before_each(function()
            lines, shows, hides = {}, 0, 0
            rawset(GameTooltip, "SetOwner", function(self, owner) rawset(self, "owner", owner); lines = {} end)
            rawset(GameTooltip, "AddLine", function(_, t) lines[#lines + 1] = t end)
            rawset(GameTooltip, "Show", function() shows = shows + 1 end)
            rawset(GameTooltip, "Hide", function() hides = hides + 1 end)
        end)
        after_each(function()
            for _, k in ipairs({ "SetOwner", "AddLine", "Show", "Hide" }) do rawset(GameTooltip, k, nil) end
        end)
        local function enter(row) row.scripts.OnEnter(row) end
        local function said(needle)
            return table.concat(lines, "\n"):find(needle, 1, true) ~= nil
        end

        it("the lines: where the item stands and what a press does, by mouse and by controller", function()
            local L = ns.MailWindow.TooltipLines
            local where, press = L({ result = { route = "ah" } }, false, false, "Roknua Themicrulah")
            assert.equal("Mailing to Roknua.", where)
            assert.equal("Click to lock: it stays in your bags and is never mailed.", press)
            where = L({ result = { route = "friend", to = "Bob Smith" } }, false, false, "Roknua")
            assert.equal("Mailing to Bob.", where, "a binding's recipient, as the row's chip says")
            where = L({ result = { route = "return", to = "Ann" } }, false, false, "Roknua")
            assert.equal("Going back to Ann.", where)
            where, press = L({ result = { reason = "locked" } }, true, true)
            assert.equal("Locked in Mailworthy: it stays in your bags and is never mailed.", where)
            assert.equal("Press to unlock.", press)
            where, press = L({ result = { reason = "not worth it", gain = 0 } }, true, false)
            assert.equal("It stays: sells better at a vendor.", where)
            assert.equal("Click to lock it, so it always stays.", press)
        end)

        it("the mouse over a Mailing row says click to lock; over the locked row, click to unlock", function()
            _G.MailworthyMailButton:Click()
            enter(_G.MailworthyMailRow1)
            assert.is_true(said("Mailing to Roknua."))
            assert.is_true(said("Click to lock"))
            _G.MailworthyMailRow1:Click() -- locked: it moved to Staying, the row is gone
            assert.is_true(hides > 0, "no tooltip left on a row that went away")
            enter(_G.MailworthyStayRow1)
            assert.is_true(said("Click to unlock."))
            assert.equal(2770, ns.MailWindow.TooltipItem())
            _G.MailworthyStayRow1.scripts.OnLeave(_G.MailworthyStayRow1)
            assert.is_nil(ns.MailWindow.TooltipItem())
        end)

        it("the tooltip follows a redraw: the row under the mouse now holds another item", function()
            _G.MailworthyMailButton:Click()
            enter(_G.MailworthyStayRow1) -- Linen Cloth: sells better at a vendor
            assert.is_true(said("Click to lock it"))
            ns.Locks.ToggleItem(2770, WowStub.link(2770, "Copper Ore"), "spec") -- the locked ore takes row 1
            assert.equal(2770, ns.MailWindow.TooltipItem())
            assert.is_true(said("Click to unlock."))
        end)

        it("controller: the highlight on a row shows the same tooltip with Press; off the rows it goes", function()
            WowStub.state.gamepadUI = true
            WowStub.state.activeFrame = MailFrame
            _G.MailworthyMailButton:Click()
            ns.Nav.Select(_G.MailworthyMailRow1)
            assert.is_true(shows > 0)
            assert.is_true(said("Press to lock: it stays in your bags and is never mailed."))
            assert.is_true(ns.PadKey.Report():find("1 row tooltip(s) shown", 1, true) ~= nil, ns.PadKey.Report())
            hides = 0
            ns.Nav.Select(_G.MailworthyMailSend)
            assert.is_true(hides > 0, "the highlight left the rows")
            assert.is_nil(ns.MailWindow.TooltipItem())
            ns.Nav.Select(_G.MailworthyMailRow1)
            ns.Nav.Press() -- Cross locks it: the row went away, the tooltip with it or on to what is there
            assert.is_true(ns.Locks.IsItemLocked(2770))
            assert.is_true(ns.MailWindow.TooltipItem() == nil or said("Press to"))
            ns.Nav.Select(_G.MailworthyStayRow1)
            assert.is_true(said("Press to unlock."))
            ns.MailWindow.Frame():Hide()
            assert.is_nil(ns.MailWindow.TooltipItem(), "closed with the window")
        end)

        it("while a send runs a press changes nothing, and the tooltip says so (Codex review)", function()
            local _, press = ns.MailWindow.TooltipLines({ result = { route = "ah" } }, false, false, "Roknua", true)
            assert.equal(ns.MailWindow.BUSY_LINE, press)
            _G.MailworthyMailButton:Click()
            _G.MailworthyMailSend:Click()
            assert.is_true(ns.Mailer.Busy())
            enter(_G.MailworthyMailRow1)
            assert.is_true(said(ns.MailWindow.BUSY_LINE))
            assert.is_false(said("to lock"))
            _G.MailworthyMailRow1:Click()
            assert.is_false(ns.Locks.IsItemLocked(2770), "the press did nothing, as the tooltip said")
            WowStub.runTimers()
        end)

        it("the lines come back when the game rebuilds the tooltip, and only on the row's own (Codex review)", function()
            local postCalls = {}
            _G.Enum = { TooltipDataType = { Item = 0 } }
            _G.TooltipDataProcessor = { AddTooltipPostCall = function(_, fn) table.insert(postCalls, fn) end }
            assert.is_true(ns.MailWindow.InstallTooltip())
            local function build(id)
                lines = {}
                for _, fn in ipairs(postCalls) do fn(GameTooltip, { id = id }) end
            end
            _G.MailworthyMailButton:Click()
            -- In game SetBagItem builds the tooltip, post-calls and all: the lines are there once.
            rawset(GameTooltip, "SetBagItem", function()
                for _, fn in ipairs(postCalls) do fn(GameTooltip, { id = 2770 }) end
            end)
            enter(_G.MailworthyMailRow1)
            assert.equal(3, #lines, "not added twice: the build added them")
            rawset(GameTooltip, "SetBagItem", nil)
            enter(_G.MailworthyMailRow1)
            build(2770)
            assert.is_true(said("Click to lock"))
            build(2770) -- item data arrived: the game cleared the tooltip and built it again
            assert.is_true(said("Click to lock"))
            build(2589)
            assert.is_false(said("Click to lock"), "another item's data")
            GameTooltip:SetOwner(_G.MailworthyMailSend) -- the same ore hovered somewhere else
            build(2770)
            assert.is_false(said("Click to lock"))
            assert.is_nil(ns.MailWindow.TooltipItem())
            -- Mid-send the item has left its slot: no item data, no build, and the lines still show.
            enter(_G.MailworthyStayRow1) -- no build for this one (the stub's SetBagItem does nothing)
            assert.equal(3, #lines)
            assert.is_true(said("It stays: "))
            _G.MailworthyMailSend:Click()
            WowStub.runTimers()
            assert.is_true(ns.Mailer.Busy())
            assert.is_true(_G.MailworthyMailRow1:IsShown(), "the list on screen is the one being sent")
            enter(_G.MailworthyMailRow1)
            assert.equal(3, #lines)
            assert.is_true(said(ns.MailWindow.BUSY_LINE))
            _G.Enum, _G.TooltipDataProcessor = nil, nil
            for _, line in ipairs(ns.Log.Lines()) do assert.is_nil(line:find("tooltip error", 1, true), line) end
        end)

        it("the mouse leaving a row doesn't take the controller's tooltip off another row", function()
            _G.MailworthyMailButton:Click()
            ns.Nav.Select(_G.MailworthyMailRow1)
            _G.MailworthyStayRow1.scripts.OnLeave(_G.MailworthyStayRow1)
            assert.equal(2770, ns.MailWindow.TooltipItem())
        end)

        it("/mw feature tooltipLines off: the item's own tooltip by mouse, none from the controller", function()
            MailworthyDB.features = MailworthyDB.features or {}
            MailworthyDB.features.tooltipLines = false
            _G.MailworthyMailButton:Click()
            enter(_G.MailworthyMailRow1)
            assert.equal(1, shows)
            assert.equal(0, #lines)
            assert.is_nil(ns.MailWindow.TooltipItem())
            _G.MailworthyMailRow1.scripts.OnLeave(_G.MailworthyMailRow1)
            shows = 0
            ns.Nav.Select(_G.MailworthyMailRow1)
            assert.equal(0, shows)
        end)
    end)

    describe("the send path (QoL pass, operator 2026-11-09: Stop, receipt, postage, nothing to send)", function()
        local send
        before_each(function()
            _G.MailworthyMailButton:Click()
            send = _G.MailworthyMailSend
        end)
        local function printed() return table.concat(WowStub.printed, "\n") end

        it("the Send button's text and state", function()
            local S = ns.MailWindow.SendState
            assert.same({ "Send to Roknua", true }, { S({ mails = 2, send = "Send to Roknua" }) })
            assert.same({ "Stop", true }, { S({ busy = true, mails = 2, send = "Send to Roknua" }) })
            assert.same({ "Stopping...", false }, { S({ busy = true, stopping = true, mails = 2 }) })
            assert.same({ "Nothing to send", false }, { S({ mails = 0, send = "Send" }) })
            assert.same({ "Postage: 3s 60c", false }, { S({ mails = 2, need = 360, send = "Send to Roknua" }) })
            assert.same({ "Click Send Mail", false }, { S({ inbox = true, mails = 2 }) })
            assert.same({ "Send Mail tab: R1", false }, { S({ inbox = true, pad = true, mails = 0 }) })
            assert.same({ "Sending...", false }, { S({ inbox = true, busy = true, mails = 2 }) }, "no Stop on the Inbox")
        end)

        it("with nothing on the list Send is greyed out and says so", function()
            assert.equal("Send to Roknua", text("MailworthyMailSend"))
            _G.MailworthyMailRow1:Click() -- locked: nothing left to mail
            assert.equal("Nothing to send", text("MailworthyMailSend"))
            assert.is_false(send:IsEnabled())
            send:Click()
            WowStub.runTimers()
            assert.equal(0, #WowStub.state.sent)
        end)

        it("Stop before the mail leaves: what was attached goes back, nothing is sent", function()
            send:Click()
            assert.is_true(ns.Mailer.Busy())
            assert.equal("Stop", text("MailworthyMailSend"))
            assert.is_true(send:IsEnabled())
            assert.equal(1, #WowStub.state.attached)
            send:Click()
            assert.is_false(ns.Mailer.Busy())
            assert.equal(0, #WowStub.state.attached, "given back")
            WowStub.runTimers()
            assert.equal(0, #WowStub.state.sent)
            assert.equal("Stopped after 0 of 1 mail: stopped by you.\n1 item left for the vendor.", ns.MailWindow.Texts().note)
            assert.equal("Send to Roknua", text("MailworthyMailSend"), "the list is still there to send")
            assert.truthy(printed():find("Stopped after 0 of 1 mail: stopped by you.", 1, true))
            assert.equal(0, #WowStub.state.sounds, "no sound for a stopped run")
        end)

        it("a press while sending never replaces the progress with 'already sending'", function()
            send:Click()
            WowStub.runTimers() -- the mail is with the game: waiting for its answer
            assert.truthy(ns.Mailer.Status():find("Sending mail 1 of 1", 1, true))
            ns.MailWindow.Send()
            assert.truthy(ns.Mailer.Status():find("Sending mail 1 of 1", 1, true))
            assert.is_nil(printed():find("already sending", 1, true))
        end)

        it("Stop while a mail waits for the game: that mail is counted, then the run ends", function()
            WowStub.setBag(0, 4, WowStub.item(2771, "Tin Ore", { count = 20, sell = 5 }))
            prices[WowStub.link(2771, "Tin Ore")] = 300
            ns.Mailer.PER_MAIL = 1 -- two mails
            ns.MailWindow.Refresh()
            send:Click()
            WowStub.runTimers()
            assert.equal(1, #WowStub.state.sent)
            send:Click()
            assert.is_true(ns.Mailer.Busy(), "the mail on its way can't be called back")
            assert.equal("Stopping...", text("MailworthyMailSend"))
            assert.is_false(send:IsEnabled())
            ns.Fire("MAIL_SEND_SUCCESS")
            WowStub.runTimers()
            assert.is_false(ns.Mailer.Busy())
            assert.equal(1, #WowStub.state.sent, "the second mail never went")
            assert.equal(0, #WowStub.state.attached)
            local receipt = ns.Mailer.Receipt()
            assert.equal(1, receipt.sent)
            assert.equal("stopped by you", receipt.stopped)
            assert.truthy(ns.MailWindow.Texts().note:find("Stopped after 1 of 2 mails: stopped by you. Sent to Roknua", 1, true))
            assert.equal(1, #ns.MailWindow.Result().mail, "the other ore is still on the list")
            ns.Mailer.PER_MAIL = 12
        end)

        it("controller: Cross on the Send button stops the run", function()
            WowStub.state.gamepadUI = true
            WowStub.state.activeFrame = MailFrame
            local watcher = _G.MailworthyPadWatcher
            watcher.scripts.OnUpdate(watcher, 0.2)
            send:Click()
            ns.Nav.Select(send)
            WowStub.state.now = WowStub.state.now + 1
            _G.MailworthyPadCross:Click()
            assert.is_false(ns.Mailer.Busy())
            WowStub.runTimers()
            assert.equal(0, #WowStub.state.sent)
        end)

        it("after a send: the receipt in the window and in chat, one sound", function()
            WowStub.setBag(0, 4, WowStub.item(769, "Chunk of Boar Meat", { count = 3, sell = 15 }))
            prices[WowStub.link(769, "Chunk of Boar Meat")] = 16 -- not worth mailing: left for the vendor
            ns.MailWindow.Refresh()
            send:Click()
            WowStub.runTimers()
            ns.Fire("MAIL_SEND_SUCCESS")
            WowStub.runTimers()
            assert.is_false(ns.Mailer.Busy())
            local texts = ns.MailWindow.Texts()
            assert.truthy(texts.total:find("^Sent 1 mail to Roknua: %+"), texts.total)
            assert.truthy(texts.note:find("left for the vendor.", 1, true), texts.note)
            assert.truthy(printed():find("Sent 1 mail (1 stack) to Roknua Themicrulah: +", 1, true), printed())
            assert.truthy(printed():find("more than vendoring.", 1, true))
            assert.same({ 856 }, WowStub.state.sounds)
            local _, count = printed():gsub("Sent 1 mail %(1 stack%)", "")
            assert.equal(1, count, "printed once")
            _G.MailworthyStayRow1:Click() -- the player changes the list: the receipt has had its say
            assert.is_nil(ns.Mailer.Receipt())
            assert.is_nil(ns.MailWindow.Texts().total:find("^Sent"))
        end)

        it("the receipt's words", function()
            local R = ns.Mailer.ReceiptText
            local head, notes, chat = R({ sent = 3, planned = 3, stacks = 18, gain = 16679, priced = true,
                recipients = { "Penny Ledgerwick", "Bob Thornfield" },
                stayed = { { link = WowStub.link(2770, "Copper Ore"), why = "count changed" } } }, 2)
            assert.equal("Sent 3 mails to Penny and Bob: +1g 66s 79c", head)
            assert.equal("1 stack stayed: Copper Ore (count changed). Check the list.\n2 items left for the vendor.", notes)
            assert.equal("Sent 3 mails (18 stacks) to Penny Ledgerwick and Bob Thornfield: +1g 66s 79c more than vendoring."
                .. " 1 stack stayed (Copper Ore: count changed). 2 items left for the vendor.", chat)
            head, notes, chat = R({ sent = 1, planned = 1, stacks = 2, gain = 0, priced = false,
                recipients = { "Roknua Themicrulah" }, stayed = {} }, 0)
            assert.equal("Sent 1 mail to Roknua.", head)
            assert.equal("", notes)
            assert.equal("Sent 1 mail (2 stacks) to Roknua Themicrulah.", chat, "no price source: no gain")
            head = R({ sent = 1, planned = 3, stacks = 12, gain = 500, priced = true, recipients = { "Penny Ledgerwick" },
                stayed = {}, stopped = "combat" }, 0)
            assert.equal("Stopped after 1 of 3 mails: combat. Sent to Penny: +5s.", head)
            head = R({ sent = 0, planned = 2, stacks = 0, gain = 0, priced = false, recipients = {},
                stayed = { { link = "x", why = "gone" }, { link = "y", why = "gone" } } }, 0)
            assert.equal("Nothing was sent.", head)
        end)

        it("short on postage: Send is greyed out with the postage, the note says what is missing; money brings it back", function()
            WowStub.state.gold = 10
            ns.MailWindow.Refresh()
            assert.equal("Postage: 30c", text("MailworthyMailSend"))
            assert.is_false(send:IsEnabled())
            assert.truthy(ns.MailWindow.Texts().note:find(
                "Postage is 30c and you have 10c. Press an item to keep it, or come back with 20c more.", 1, true))
            send:Click()
            WowStub.runTimers()
            assert.equal(0, #WowStub.state.sent)
            assert.is_false(ns.Mailer.Start(ns.MailWindow.Result().mail, "Roknua Themicrulah"), "the mailer refuses too")
            assert.equal("Can't send: postage is 30c and you have 10c.", ns.Mailer.Status())
            WowStub.state.gold = 5000
            ns.Fire("PLAYER_MONEY")
            assert.equal("Send to Roknua", text("MailworthyMailSend"))
            assert.is_true(send:IsEnabled())
        end)

        it("money gone mid-run: the attachments go back and nothing is sent", function()
            WowStub.state.gold = 5000
            send:Click()
            WowStub.state.gold = 5
            WowStub.runTimers()
            assert.is_false(ns.Mailer.Busy())
            assert.equal(0, #WowStub.state.sent)
            assert.equal(0, #WowStub.state.attached)
            assert.truthy(ns.Mailer.Status():find("postage for mail 1 is 30c and you have 5c", 1, true), ns.Mailer.Status())
        end)
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
        assert.equal("Nothing to send", text("MailworthyMailSend"))
        assert.is_false(_G.MailworthyMailSend:IsEnabled())
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
