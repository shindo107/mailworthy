-- Return to sender (Returns.lua; operator, 2026-11-08): a toggle on the Mailworthy window, on every
-- character, that puts what other characters mailed this one on the Mailing list to go back to
-- them; pressed again, the list is back to normal. Toggles that are on are lit (Widgets.SetToggled).
-- The mailing outcomes (recipients, hard keeps, preview = sent) are in critical_path_spec.
local loadAddon = require("spec.support.load_addon")

local ME = "Rettana Quilwrit"
local BOB = "Bob Surname"
local ANN = "Ann Other"

describe("return to sender", function()
    local ns, prices

    before_each(function()
        ns = loadAddon()
        ns.Fire("PLAYER_LOGIN")
        ns.Config.SetBankAlt("Roknua Themicrulah")
        prices = {}
        _G.Auctionator = { API = { v1 = {
            GetAuctionPriceByItemLink = function(_, l) return prices[l] end,
            GetAuctionAgeByItemLink = function() return 0 end,
        } } }
    end)
    after_each(function()
        _G.Auctionator = nil
        for _, line in ipairs(ns.Log.Lines()) do assert.is_nil(line:find("error", 1, true), line) end
    end)

    local function got(from, itemID, count, o)
        o = o or {}
        return { dir = "received", char = o.char or ME, other = from, at = o.at or 100,
            items = { { itemID = itemID, count = count } }, system = o.system, cod = o.cod, returned = o.returned }
    end
    local function sent(to, itemID, count, o)
        o = o or {}
        return { dir = "sent", char = o.char or ME, other = to, at = o.at or 200, items = { { itemID = itemID, count = count } } }
    end

    describe("Owed (pure)", function()
        it("counts what each player mailed this character, less what it mailed them since", function()
            local owed = ns.Returns.Owed({ got(BOB, 2592, 20), got(BOB, 2592, 10, { at = 150 }), sent(BOB, 2592, 12) }, ME)
            assert.same({ { to = BOB, count = 18, at = 150 } }, owed[2592])
        end)

        it("leaves out system mail, COD, returned mail, other characters' takes and this character", function()
            local owed = ns.Returns.Owed({
                got("Auction House", 1, 1, { system = true }),
                got(BOB, 2, 1, { cod = 500 }),
                got(BOB, 3, 1, { returned = true }),
                got(BOB, 4, 1, { char = "Someone Else" }),
                got(ME, 5, 1),
            }, ME)
            assert.same({}, owed)
        end)

        it("several senders of one item: the latest first; names lose their realm", function()
            local owed = ns.Returns.Owed({ got(BOB .. "-OtherRealm", 2592, 5, { at = 100 }), got(ANN, 2592, 7, { at = 300 }) }, ME)
            assert.same({ { to = ANN, count = 7, at = 300 }, { to = BOB, count = 5, at = 100 } }, owed[2592])
        end)

        it("never goes below nothing: a gift before anything was received owes nothing", function()
            local owed = ns.Returns.Owed({ sent(BOB, 2592, 20, { at = 50 }), got(BOB, 2592, 5) }, ME)
            assert.equal(5, owed[2592][1].count)
        end)

        it("damaged log entries never error", function()
            assert.same({}, ns.Returns.Owed({ true, {}, { dir = "received", char = ME, other = BOB, items = { {} } } }, ME))
            assert.same({}, ns.Returns.Owed(nil, ME))
        end)
    end)

    it("more recipients than To: lines: the last line still names each one", function()
        local r = { { name = "Roknua Themicrulah" }, { name = BOB }, { name = ANN }, { name = "Cid Third" } }
        assert.equal("|cffaaaaaa+ 2 more: Ann, Cid (see Mailing)|r", (ns.MailWindow.MoreRecipientsText(r, 3)))
        -- Codex review: many senders wrap, 4 names a row, and the window grows to fit them
        local many = { { name = "Roknua Themicrulah" } }
        for i = 1, 9 do many[#many + 1] = { name = "Sender" .. i .. " Surname" } end
        local text, rows = ns.MailWindow.MoreRecipientsText(many, 2)
        assert.equal(3, rows)
        assert.truthy(text:find("Sender1, Sender2, Sender3, Sender4,|r\n|cffaaaaaaSender5", 1, true), text)
        assert.equal("Sender9 (see Mailing)|r", text:sub(-#"Sender9 (see Mailing)|r"))
        local base = { to = 2, routes = 0, mail = 1, stay = 0 }
        local tall = { to = 2, toRows = 2, routes = 0, mail = 1, stay = 0 }
        assert.equal(ns.MailWindow.Layout(base) + 28, ns.MailWindow.Layout(tall))
    end)

    describe("Split (pure)", function()
        local function slot(bag, i, count) return { bag = bag, slot = i, count = count } end

        it("whole stacks, never past what is owed; the rest is left", function()
            local owed = { { to = BOB, count = 25 } }
            local parts, left = ns.Returns.Split({ slot(0, 1, 20), slot(0, 2, 20), slot(0, 3, 5) }, owed)
            assert.equal(1, #parts)
            assert.equal(BOB, parts[1].to)
            assert.equal(25, parts[1].count)
            assert.same({ slot(0, 1, 20), slot(0, 3, 5) }, parts[1].slots)
            assert.same({ slot(0, 2, 20) }, left)
            assert.equal(0, owed[1].count, "used up, for the item's next bag group")
        end)

        it("a stack bigger than what is owed stays (the mailer never splits a stack)", function()
            local parts, left = ns.Returns.Split({ slot(0, 1, 20) }, { { to = BOB, count = 5 } })
            assert.same({}, parts)
            assert.same({ slot(0, 1, 20) }, left)
        end)

        it("several senders share the stacks, the first listed first", function()
            local parts = ns.Returns.Split({ slot(0, 1, 20), slot(1, 1, 20) }, { { to = ANN, count = 20 }, { to = BOB, count = 20 } })
            assert.equal(ANN, parts[1].to)
            assert.equal(BOB, parts[2].to)
            assert.equal(20, parts[2].count)
        end)
    end)

    describe("in the window", function()
        local WOOL = { 2592, "Wool Cloth" }

        local function take(from, it, count)
            ns.Ledger.Add({ dir = "received", other = from, items = { { itemID = it[1], name = it[2], count = count } } })
        end

        before_each(function()
            MailFrame:Show()
            SendMailFrame:Show()
            WowStub.setBag(0, 1, WowStub.item(WOOL[1], WOOL[2], { count = 20, sell = 33, class = 7, subclass = 5 }))
            WowStub.setBag(0, 2, WowStub.item(WOOL[1], WOOL[2], { count = 20, sell = 33, class = 7, subclass = 5 }))
            prices[WowStub.link(WOOL[1], WOOL[2])] = 9000
        end)

        it("the toggle lists the received stacks back to their sender, lit, with a chat line; again: normal", function()
            take(BOB, WOOL, 20)
            ns.MailWindow.Show("send")
            assert.equal("Return to sender", _G.MailworthyMailReturn:GetText())
            assert.is_false(ns.Widgets.IsToggled(_G.MailworthyMailReturn))
            _G.MailworthyMailReturn:Click()
            assert.is_true(ns.Widgets.IsToggled(_G.MailworthyMailReturn))
            assert.equal("Return to sender: on", _G.MailworthyMailReturn:GetText())
            local mail = ns.MailWindow.Result().mail
            local back, alt = 0, 0
            for _, item in ipairs(mail) do
                if item.result.to == BOB then back = back + item.count else alt = alt + item.count end
            end
            assert.equal(20, back, "Bob's 20, one stack")
            assert.equal(20, alt, "the other stack wasn't mailed by anyone: the bank alt's, as before")
            assert.equal("Send to Roknua, Bob", _G.MailworthyMailSend:GetText())
            assert.truthy(table.concat(ns.MailWindow.Texts().to, "\n"):find("Returned items", 1, true))
            assert.equal("Return to sender on: 1 stack goes back to Bob. Check the list, then press Send.",
                WowStub.printed[#WowStub.printed]:gsub("^.-: ", "", 1))
            _G.MailworthyMailReturn:Click()
            assert.is_false(ns.Widgets.IsToggled(_G.MailworthyMailReturn))
            for _, item in ipairs(ns.MailWindow.Result().mail) do assert.is_nil(item.result.to) end
        end)

        it("three senders and the bank alt: every one of them is named above the list", function()
            take(BOB, WOOL, 20)
            for i, who in ipairs({ ANN, "Cid Third" }) do
                local id = 3000 + i
                WowStub.setBag(1, i, WowStub.item(id, "Thing " .. i, { count = 5, sell = 5, class = 7, subclass = 7 }))
                take(who, { id, "Thing " .. i }, 5)
            end
            ns.MailWindow.Show("send")
            _G.MailworthyMailReturn:Click()
            local to = table.concat(ns.MailWindow.Texts().to, "\n")
            for _, name in ipairs({ "Roknua", "Bob", "Ann", "Cid" }) do
                assert.truthy(to:find(name, 1, true), name .. " isn't shown:\n" .. to)
            end
        end)

        it("stacks moved between the preview and Send: nothing goes until the list shows the new split", function()
            -- Codex review, 2026-11-08: 20 to Bob and 10 to the bank alt on screen, 15 + 15 in the bags
            take(BOB, WOOL, 20)
            local wool = function(n) return WowStub.item(WOOL[1], WOOL[2], { count = n, sell = 33, class = 7, subclass = 5 }) end
            WowStub.setBag(0, 2, wool(10))
            ns.MailWindow.Show("send")
            _G.MailworthyMailReturn:Click()
            WowStub.setBag(0, 1, wool(15))
            WowStub.setBag(0, 2, wool(15)) -- no BAG_UPDATE_DELAYED yet: the list still says 20 / 10
            _G.MailworthyMailSend:Click()
            WowStub.runTimers()
            assert.equal(0, #WowStub.state.sent, "nothing goes while the amounts differ from the list")
            assert.truthy(WowStub.printed[#WowStub.printed]:find("Not sent: Wool Cloth to %a+ is now x15 %(the list said x%d+%)"),
                table.concat(WowStub.printed, "\n"))
            _G.MailworthyMailSend:Click() -- the list now shows the new split
            for _ = 1, 10 do
                WowStub.runTimers()
                if not ns.Mailer.Busy() then break end
                ns.Fire("MAIL_SEND_SUCCESS")
            end
            local delivered = {}
            for i, mail in ipairs(WowStub.state.sent) do
                for _, it in ipairs(WowStub.state.sentItems[i]) do delivered[mail.name] = (delivered[mail.name] or 0) + it.count end
            end
            assert.same({ [BOB] = 15, ["Roknua Themicrulah"] = 15 }, delivered)
        end)

        it("nothing received: says so, and the list is the usual one", function()
            ns.MailWindow.Show("send")
            _G.MailworthyMailReturn:Click()
            assert.truthy(WowStub.printed[#WowStub.printed]:find("nothing in your bags was mailed to you", 1, true))
            for _, item in ipairs(ns.MailWindow.Result().mail) do assert.is_nil(item.result.to) end
        end)

        it("a locked item stays; /mw scan says return to sender is on", function()
            take(BOB, WOOL, 40)
            ns.Locks.ToggleItem(WOOL[1], WowStub.link(WOOL[1], WOOL[2]), "spec")
            ns.MailWindow.Show("send")
            _G.MailworthyMailReturn:Click()
            assert.equal(0, #ns.MailWindow.Result().mail)
            assert.truthy(ns.Bags.Report(ns.Bags.Evaluate()):find("return to sender: on", 1, true))
        end)

        it("is off again when the mailbox closes", function()
            take(BOB, WOOL, 20)
            ns.MailWindow.Show("send")
            _G.MailworthyMailReturn:Click()
            ns.Fire("MAIL_CLOSED")
            assert.is_false(ns.Returns.On())
            ns.MailWindow.Show("send")
            assert.is_false(ns.Widgets.IsToggled(_G.MailworthyMailReturn))
        end)

        it("no button with /mw feature returnToSender off, or without the mail ledger", function()
            ns.HandleSlash("feature returnToSender off")
            ns.MailWindow.Show("send")
            assert.is_false(_G.MailworthyMailReturn:IsShown())
            _G.MailworthyMailReturn:Click()
            assert.is_false(ns.Returns.On())
            ns.HandleSlash("feature returnToSender on")
            ns.HandleSlash("feature ledger off")
            ns.MailWindow.Refresh()
            assert.is_false(_G.MailworthyMailReturn:IsShown())
        end)
    end)
end)

describe("toggled buttons are lit while on", function()
    local ns

    before_each(function()
        ns = loadAddon()
        ns.Fire("PLAYER_LOGIN")
        ns.Config.SetBankAlt("Roknua Themicrulah")
    end)

    it("the settings window's toggles and choices", function()
        ns.SettingsUI.Show()
        local lit = function(name) return ns.Widgets.IsToggled(_G[name]) end
        assert.is_true(lit("MailworthySettingsMats"), "keep my professions' materials is on by default")
        assert.is_false(lit("MailworthySettingsGather"))
        assert.is_false(lit("MailworthySettingsTags"))
        assert.is_false(lit("MailworthySettingsGlow"))
        assert.is_true(lit("MailworthySettingsMinimap"))
        assert.is_true(lit("MailworthySettingsDuration3"), "the 24h listing is chosen")
        assert.is_false(lit("MailworthySettingsDuration1"))
        _G.MailworthySettingsGather:Click()
        _G.MailworthySettingsGlow:Click()
        _G.MailworthySettingsMats:Click()
        assert.is_true(lit("MailworthySettingsGather"))
        assert.is_true(lit("MailworthySettingsGlow"))
        assert.is_false(lit("MailworthySettingsMats"))
        assert.equal(ns.Config.Get("disenchant") == true, lit("MailworthySettingsDisenchant"))
    end)

    it("the mailbox window's Skip once while skipped", function()
        MailFrame:Show()
        SendMailFrame:Show()
        WowStub.setBag(0, 1, WowStub.item(2589, "Linen Cloth", { count = 20, sell = 10 }))
        ns.MailWindow.Show("send")
        assert.is_false(ns.Widgets.IsToggled(_G.MailworthyMailSkipBankAlt))
        _G.MailworthyMailSkipBankAlt:Click()
        assert.is_true(ns.Widgets.IsToggled(_G.MailworthyMailSkipBankAlt))
        _G.MailworthyMailSkipBankAlt:Click()
        assert.is_false(ns.Widgets.IsToggled(_G.MailworthyMailSkipBankAlt))
    end)

    it("a button that was never a toggle stays unlit", function()
        ns.SettingsUI.Show()
        assert.is_false(ns.Widgets.IsToggled(_G.MailworthySettingsDone))
        ns.Widgets.SetToggled({}, true) -- not one of ours: ignored
    end)
end)
