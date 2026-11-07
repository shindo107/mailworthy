-- The mail ledger (Ledger.lua, LedgerUI.lua; operator, 2026-11-07): every mail sent and taken
-- is logged and exportable; what another player mailed you beyond what you mailed back shows
-- as yours to pay back, valued when it was sent (the sender's value over the addon channel when
-- both run Mailworthy); gold counts; nobody is ever shown as owing you.
local loadAddon = require("spec.support.load_addon")

local BOB = "Bob Surname"
local BANK_ALT = "Roknua Themicrulah"
local LINEN = { id = 2589, name = "Linen Cloth" }
local ORE = { id = 2770, name = "Copper Ore" }

describe("mail ledger", function()
    local ns, prices

    local function price(it, copper) prices[WowStub.link(it.id, it.name)] = copper end

    --- Bob's mail with `count` of `it` (and options) at inbox index 1.
    local function inboxMail(it, count, o)
        o = o or {}
        local mail = { sender = o.sender or BOB, subject = o.subject or "mats", money = o.money, cod = o.cod,
            returned = o.returned, canReply = o.canReply, isGM = o.isGM, daysLeft = 29.9,
            items = it and { { itemID = it.id, name = it.name, count = count } } or {} }
        WowStub.state.inbox = { mail }
        return mail
    end

    local function take(itemID)
        TakeInboxItem(1, 1)
        ns.Fire("MAIL_SUCCESS", itemID)
        WowStub.runTimers(2)
    end

    --- Blizzard's Send button: attach, the tab updates, SendMail, the server says yes.
    local function sendByHand(to, it, count, money)
        WowStub.state.attached = {}
        if it then
            table.insert(WowStub.state.attached, WowStub.item(it.id, it.name, { count = count }))
        end
        WowStub.state.money = money or 0
        ns.Fire("MAIL_SEND_INFO_UPDATE")
        SendMail(to, "for you", "")
        ns.Fire("MAIL_SEND_SUCCESS")
    end

    local function lastPrint() return WowStub.printed[#WowStub.printed] or "" end

    before_each(function()
        ns = loadAddon()
        ns.Fire("PLAYER_LOGIN")
        ns.Config.SetBankAlt(BANK_ALT)
        prices = {}
        _G.Auctionator = { API = { v1 = {
            GetAuctionPriceByItemLink = function(_, l) return prices[l] end,
            GetAuctionAgeByItemLink = function() return 0 end,
        } } }
        price(LINEN, 50)  -- 20 = 10s
        price(ORE, 60)    -- 20 = 12s
        MailFrame:Show()
        SendMailFrame:Show()
        ns.Fire("MAIL_SHOW")
    end)
    after_each(function()
        for _, line in ipairs(ns.Log.Lines()) do assert.is_nil(line:find("error", 1, true), line) end
        _G.Auctionator = nil
    end)

    it("received materials are yours to pay back, valued when taken, with a chat line", function()
        inboxMail(LINEN, 20)
        take(LINEN.id)
        assert.equal(1000, (ns.Ledger.Net(BOB)))
        assert.equal("Received 20 Linen Cloth (10s) from Bob Surname. You've received 10s more from Bob Surname than "
            .. "you've sent back.", lastPrint():gsub("^|cff33ff99Mailworthy|r: ", ""))
        local debts = ns.Ledger.Debts()
        assert.equal(1, #debts)
        assert.equal(BOB, debts[1].name)
        assert.equal("20 Linen Cloth", debts[1].items)
    end)

    it("paying back by hand: 12s of ore for 10s of linen leaves nothing to show, never Bob owing you", function()
        inboxMail(LINEN, 20)
        take(LINEN.id)
        sendByHand(BOB, ORE, 20)
        assert.equal(-200, (ns.Ledger.Net(BOB)))
        assert.same({}, ns.Ledger.Debts(), "a player who owes you is never listed")
        assert.equal("", ns.RoutesUI.OwedText(BOB))
        assert.is_nil(ns.MailWindow.OwedText(ns.Ledger.Debts()))
    end)

    it("the other side: 10s of linen sent, 12s of ore received leaves 2s to pay back", function()
        sendByHand(BOB, LINEN, 20)
        inboxMail(ORE, 20)
        take(ORE.id)
        assert.equal(200, (ns.Ledger.Net(BOB)))
        assert.truthy(lastPrint():find("You've received 2s more from Bob Surname than you've sent back.", 1, true))
    end)

    it("gold counts both ways", function()
        inboxMail(nil, 0, { money = 1000 })
        TakeInboxMoney(1)
        ns.Fire("MAIL_SUCCESS")
        WowStub.runTimers(2)
        assert.equal(1000, (ns.Ledger.Net(BOB)))
        assert.truthy(lastPrint():find("Received 10s from Bob Surname. You've received 10s more", 1, true), lastPrint())
        sendByHand(BOB, nil, 0, 1000)
        assert.equal(0, (ns.Ledger.Net(BOB)))
    end)

    it("the sender's Mailworthy value is used, at most 3x the receiver's own price", function()
        local msg = ns.Ledger.EncodeValues(BOB, "Rettana Quilwrit", WowStub.state.serverTime, {
            { itemID = LINEN.id, count = 20, value = 1500 }, { itemID = ORE.id, count = 20, value = 99999 } })
        assert.equal(1, #msg)
        ns.Fire("CHAT_MSG_ADDON", "Mailworthy", msg[1], "WHISPER", BOB)
        inboxMail(LINEN, 20)
        take(LINEN.id)
        assert.equal(1500, (ns.Ledger.Net(BOB)), "the sender's value, captured when it was sent")
        inboxMail(ORE, 20)
        take(ORE.id)
        assert.equal(1500 + 1200 * 3, (ns.Ledger.Net(BOB)), "a made-up value is capped")
        assert.truthy(ns.Ledger.ExportText():find("capped at 3x my price", 1, true))
    end)

    describe("the more up-to-date scan at the time of send wins (operator, 2026-11-07)", function()
        local ages, rows

        --- Bob's values for 20 Linen Cloth mailed `daysAgo` days ago, his scan `theirAge` days old then.
        local function bobSent(value, theirAge, daysAgo)
            local item = { itemID = LINEN.id, count = 20, value = value, age = theirAge }
            local m = ns.Ledger.EncodeValues(BOB, "Rettana Quilwrit", WowStub.state.serverTime - daysAgo * 86400, { item })
            ns.Fire("CHAT_MSG_ADDON", "Mailworthy", m[1], "WHISPER", BOB)
            inboxMail(LINEN, 20, { subject = "mats " .. #ns.Ledger.Store().log }) -- a new mail each time
            take(LINEN.id)
            return ns.Ledger.Store().log[#ns.Ledger.Store().log].items[1]
        end

        before_each(function()
            ages, rows = {}, {}
            local api = _G.Auctionator.API.v1
            api.GetAuctionAgeByItemLink = function(_, l) return ages[l] end
            _G.Auctionator.Database = { GetPriceHistory = function(_, key) return rows[key] end }
            _G.Auctionator.Utilities = { BasicDBKeyFromLink = function(l) return l end }
        end)

        it("their scan is fresher: their value", function()
            ages[WowStub.link(LINEN.id, LINEN.name)] = 5 -- ours: 50c each, 5 days old
            local it = bobSent(1400, 0, 0)
            assert.equal(1400, it.value)
            assert.equal("sender", it.source)
            assert.equal(0, it.age)
        end)

        it("ours is fresher: our value, even under theirs", function()
            ages[WowStub.link(LINEN.id, LINEN.name)] = 1 -- ours: 50c each, a day old
            local it = bobSent(1400, 6, 0)
            assert.equal(1000, it.value)
            assert.equal("fresher", it.source)
            assert.truthy(ns.Ledger.ExportText():find("my scan was more up to date, scan 1 day old", 1, true))
        end)

        it("ours as it stood that day: a scan since the send doesn't count, Auctionator's history does", function()
            local l = WowStub.link(LINEN.id, LINEN.name)
            ages[l] = 0 -- scanned today, after Bob's mail two days ago
            rows[l] = { { rawDay = 100, minSeen = 40, maxSeen = 45 }, { rawDay = 97, minSeen = 30, maxSeen = 35 } }
            local it = bobSent(1400, 3, 2) -- that day (raw day 98), our latest scan was day 97: 1 day old
            assert.equal(600, it.value, "20 at day 97's 30c")
            assert.equal("fresher", it.source)
            assert.equal(1, it.age)
            rows[l] = nil
            local again = bobSent(1400, 3, 2)
            assert.equal(1400, again.value, "no history back to that day: theirs")
        end)

        it("a tie, or a sender's value without an age (v0.25.0), keeps theirs", function()
            ages[WowStub.link(LINEN.id, LINEN.name)] = 2
            assert.equal("sender", bobSent(1400, 2, 0).source)
            assert.equal("sender", bobSent(1400, nil, 0).source)
        end)

        it("the age goes in the message, and v0.25.0's reader still gets the values", function()
            local m = ns.Ledger.EncodeValues(BOB, "Rettana Quilwrit", 1, {
                { itemID = LINEN.id, count = 20, value = 1000, age = 3 }, { itemID = ORE.id, count = 20, value = 1200 } })
            assert.equal("V2|Bob Surname|Rettana Quilwrit|1|2589:20:1000:3;2770:20:1200", m[1])
            local decoded = ns.Comms.Decode(m[1]).values.items
            assert.equal(3, decoded[1].age)
            assert.is_nil(decoded[2].age)
            local old = {}
            for id, count, value in m[1]:match("|([%d:;]+)$"):gmatch("(%d+):(%d+):(%d+)") do
                old[#old + 1] = id .. "x" .. count .. "=" .. value
            end
            assert.same({ "2589x20=1000", "2770x20=1200" }, old)
            assert.is_nil(ns.Comms.Decode("V2|Bob|Rettana|1|2589:20:5:1234"))
        end)

        it("pure: the fresher scan, the cap on theirs, either side missing", function()
            local Pick = ns.Ledger.Pick
            assert.same({ 900, "fresher", 1 }, { Pick(5000, 4, 900, 1) })
            assert.same({ 2700, "capped", 4 }, { Pick(5000, 4, 900, 4) })
            assert.same({ 5000, "sender", 2 }, { Pick(5000, 2, nil, nil) })
            assert.same({ 900, "mine", 1 }, { Pick(nil, nil, 900, 1) })
        end)
    end)

    it("value messages: only whispers, only for this account's characters, only from the mail's sender", function()
        local function hear(from, to, channel, sender)
            local m = ns.Ledger.EncodeValues(from, to, WowStub.state.serverTime, { { itemID = LINEN.id, count = 20, value = 9000 } })
            ns.Fire("CHAT_MSG_ADDON", "Mailworthy", m[1], channel, sender)
        end
        hear(BOB, "Rettana Quilwrit", "GUILD", BOB)
        hear(BOB, "Someone Else", "WHISPER", BOB)
        hear("Carl Other", "Rettana Quilwrit", "WHISPER", BOB)
        assert.is_nil(next(ns.Ledger.Store().expect))
        assert.is_nil(ns.Comms.Decode("V2|Bob|Rettana|1|2589:20:99999999999"))
        assert.is_nil(ns.Comms.Decode("V2|Bob|Rettana|1|"))
        assert.is_nil(ns.Comms.Decode("V2|Bob|Rettana|x|2589:20:5"))
    end)

    it("Mailworthy's own sends: the friend's mail counts and its values wait for the friend, the bank alt's don't", function()
        WowStub.setBag(0, 1, WowStub.item(10940, "Strange Dust", { count = 20, sell = 2, class = 7, subclass = 12 }))
        prices[WowStub.link(10940, "Strange Dust")] = 3
        WowStub.setBag(0, 2, WowStub.item(LINEN.id, LINEN.name, { count = 20, sell = 1, class = 7, subclass = 5 }))
        price(LINEN, 5000)
        ns.Routes.Add(BOB, 333)
        ns.MailWindow.Show()
        _G.MailworthyMailSend:Click()
        for _ = 1, 5 do
            WowStub.runTimers()
            if ns.Mailer.Busy() then ns.Fire("MAIL_SEND_SUCCESS") end
        end
        assert.equal(2, #WowStub.state.sent)
        local log = ns.Ledger.Store().log
        assert.equal(2, #log)
        assert.equal(BANK_ALT, log[1].other)
        assert.is_false(log[1].counted, "the bank alt is this account's: no balance")
        assert.equal(BOB, log[2].other)
        assert.is_true(log[2].counted)
        assert.equal("Mailworthy", log[2].via)
        assert.equal(-60, (ns.Ledger.Net(BOB)))
        local before = #WowStub.state.addonMessages
        ns.Fire("CHAT_MSG_ADDON", "Mailworthy", ns.Comms.Encode({}, {}), "GUILD", BOB)
        local whispers = {}
        for i = before + 1, #WowStub.state.addonMessages do
            local m = WowStub.state.addonMessages[i]
            if m.channel == "WHISPER" then whispers[#whispers + 1] = m end
        end
        assert.equal(1, #whispers, "the values go once Bob is heard from")
        assert.equal(BOB, whispers[1].target)
        assert.equal("V2|Rettana Quilwrit|Bob Surname|" .. WowStub.state.serverTime .. "|10940:20:60:0", whispers[1].message,
            "value and scan age (0 days)")
        assert.is_nil(next(ns.Ledger.Store().outbox))
    end)

    it("not counted: own characters, COD, system mail; a returned mail takes back what was sent", function()
        MailworthyDB.characters["Alt Person|Classic Beta PvP|Alliance"] = { name = "Alt Person", realm = "Classic Beta PvP",
            faction = "Alliance" }
        inboxMail(LINEN, 20, { sender = "Alt Person" })
        take(LINEN.id)
        inboxMail(LINEN, 20, { cod = 500 })
        take(LINEN.id)
        inboxMail(LINEN, 20, { sender = "Auction House", canReply = false })
        take(LINEN.id)
        assert.same({}, ns.Ledger.Debts())
        assert.equal(0, (ns.Ledger.Net(BOB)))
        sendByHand(BOB, ORE, 20)
        assert.equal(-1200, (ns.Ledger.Net(BOB)))
        inboxMail(ORE, 20, { returned = true })
        take(ORE.id)
        assert.equal(0, (ns.Ledger.Net(BOB)), "Bob sent it back unopened")
        assert.equal(5, #ns.Ledger.Store().log, "everything is still in the log")
    end)

    it("a failed take is not counted; an unanswered one counts when the mailbox closes", function()
        inboxMail(LINEN, 20)
        TakeInboxItem(1, 1)
        ns.Fire("MAIL_FAILED", LINEN.id)
        assert.equal(0, #ns.Ledger.Store().log)
        WowStub.state.inbox[1].subject = "again"
        TakeInboxItem(1, 1)
        assert.equal(1, (ns.Ledger.Pending()))
        ns.Fire("MAIL_CLOSED")
        assert.equal(1000, (ns.Ledger.Net(BOB)))
    end)

    it("Open All and shift-click (AutoLootMailItem) take every attachment and the gold", function()
        local mail = inboxMail(LINEN, 20, { money = 300 })
        table.insert(mail.items, { itemID = ORE.id, name = ORE.name, count = 20 })
        AutoLootMailItem(1)
        ns.Fire("MAIL_SUCCESS", LINEN.id)
        ns.Fire("MAIL_SUCCESS", ORE.id)
        ns.Fire("MAIL_SUCCESS")
        assert.equal(1000 + 1200 + 300, (ns.Ledger.Net(BOB)))
    end)

    it("export: one line per mail, oldest first, with both names, items, ids and values", function()
        sendByHand(BOB, ORE, 20)
        inboxMail(LINEN, 20)
        take(LINEN.id)
        local text = ns.Ledger.ExportText()
        local sent = text:find("SENT      Rettana Quilwrit -> Bob Surname  \"for you\"  "
            .. "20x Copper Ore (item 2770, 12s, scan 0 days old)", 1, true)
        local got = text:find("RECEIVED  Bob Surname -> Rettana Quilwrit  \"mats\"  "
            .. "20x Linen Cloth (item 2589, 10s, scan 0 days old)", 1, true)
        assert.truthy(sent, text)
        assert.truthy(got, text)
        assert.is_true(sent < got)
        _G.MailworthyLedgerExport:Click()
        assert.equal(text, ns.Report.Text())
    end)

    it("the windows: the ledger lists what you owe, Mark paid takes two presses; the mailbox and friends show it", function()
        ns.Routes.Add(BOB, 333)
        inboxMail(LINEN, 20)
        take(LINEN.id)
        assert.equal("You've received 10s more from Bob Surname than you've sent back.",
            ns.MailWindow.OwedText(ns.Ledger.Debts()))
        ns.MailWindow.Show()
        assert.is_true(_G.MailworthyMailLedger:IsShown())
        assert.truthy(ns.RoutesUI.OwedText(BOB):find("10s more from them", 1, true))
        _G.MailworthyMailLedger:Click()
        assert.is_true(ns.LedgerUI.Frame():IsShown())
        assert.is_true(_G.MailworthyLedgerPaid1:IsShown())
        _G.MailworthyLedgerPaid1:Click()
        assert.equal("Sure?", _G.MailworthyLedgerPaid1:GetText())
        assert.equal(1000, (ns.Ledger.Net(BOB)))
        _G.MailworthyLedgerPaid1:Click()
        assert.equal(0, (ns.Ledger.Net(BOB)))
        assert.is_false(_G.MailworthyLedgerPaid1:IsShown())
        assert.truthy(ns.Ledger.ExportText():find("MARKED PAID  Bob Surname: 10s", 1, true))
        ns.HandleSlash("ledger")
        assert.is_true(ns.LedgerUI.Frame():IsShown())
    end)

    it("a peer's characters count as one player", function()
        ns.Fire("CHAT_MSG_ADDON", "Mailworthy", ns.Comms.Encode({ { skillLine = 197 } },
            { { name = "Bobs Tailor", professions = { { skillLine = 197 } } } }), "GUILD", BOB)
        inboxMail(LINEN, 20, { sender = "Bobs Tailor" })
        take(LINEN.id)
        assert.equal(1000, (ns.Ledger.Net(BOB)))
        sendByHand(BOB, LINEN, 20)
        assert.equal(0, (ns.Ledger.Net("Bobs Tailor")))
    end)

    it("the report says how much is logged, never who or how much", function()
        inboxMail(LINEN, 20)
        take(LINEN.id)
        local line = ns.Ledger.ReportLines()[1]
        assert.truthy(line:find("1 log entries", 1, true))
        assert.is_nil(line:find("Bob", 1, true))
        assert.truthy(ns.Report.Build():find(line, 1, true))
    end)

    it("the log keeps the newest LOG_MAX entries; balances outlive it", function()
        ns.Ledger.LOG_MAX = 3
        inboxMail(LINEN, 20)
        for i = 1, 5 do
            WowStub.state.inbox[1].subject = "mats " .. i
            take(LINEN.id)
        end
        assert.equal(3, #ns.Ledger.Store().log)
        assert.equal(5000, (ns.Ledger.Net(BOB)))
    end)

    it("switched off: no hooks, nothing logged", function()
        ns = loadAddon()
        MailworthyDB.features.ledger = false
        ns.Fire("PLAYER_LOGIN")
        inboxMail(LINEN, 20)
        take(LINEN.id)
        sendByHand(BOB, ORE, 20)
        assert.equal(0, #(MailworthyDB.ledger and next(MailworthyDB.ledger) and select(2, next(MailworthyDB.ledger)).log or {}))
    end)
end)
