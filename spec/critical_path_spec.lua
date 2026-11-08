-- CRITICAL PATH: the shipping gate. Every build must still mail, safely, the way a
-- player does it: a mailbox visit with a realistic bag, the mouse (the Mailworthy button or
-- the Send Mail tab alone) and the controller,
-- with and without Auctionator, with a binding (a profession's or a class's), with a guild
-- template, without a bank alt or with it skipped for the visit, and on SavedVariables an older
-- build left behind. CI runs this file on its own before the rest, and a tag can't publish
-- unless it passes.
--
-- These tests check outcomes, not tuning: what was previewed is exactly what was sent,
-- to exactly the recipients shown, and the AGENTS.md safety rules hold for every mail.
-- The mail log (Ledger.lua, the record players export to show where items went) holds
-- exactly what was sent: one entry per mail, same recipient, same stacks.
-- Thresholds and prices are other specs' business. Don't loosen an assertion here to
-- make a change pass: a red test here means a player's mail would break.
local loadAddon = require("spec.support.load_addon")

local BANK_ALT = "Roknua Themicrulah"
local BOB = "Bob Surname"
local ENCHANTING = 333
local REALM_KEY = "Classic Beta PvP|Alliance"

-- Items that must never leave the bags whatever they're worth (AGENTS.md "Safety").
local HARD_KEEPS = {
    [6948] = "soulbound (Hearthstone)",
    [6125] = "soulbound green",
    [5022] = "quest item",
    [2775] = "locked by the player",
    [2901] = "profession tool",
    [4306] = "in use (locked by the game)",
    [1081] = "an active quest's objective (Crisp Spider Meat for Redridge Goulash)",
}

--- A level-20ish character's bags on a fresh realm: trade goods, a BoE green, junk,
--- a quest item, soulbound gear, a tool, a locked item, the reagent bag in use, and
--- enough priced stacks for two mails. Returns the Auctionator price table.
local function fillBags()
    local S, item = WowStub.state, WowStub.item
    local prices = {}
    local function put(bag, slot, it, price)
        WowStub.setBag(bag, slot, it)
        if price then prices[it.hyperlink] = price end
    end
    S.numSlots[5] = 4 -- the reagent bag (v0.5.1 ignored it)
    put(0, 1, item(6948, "Hearthstone", { bound = true, sell = 0, class = 15 }))
    put(0, 2, item(2770, "Copper Ore", { count = 20, sell = 5, class = 7, subclass = 7 }), 174)
    put(0, 3, item(5022, "Bundle of Letters", { quest = true, class = 12 }), 9000)
    put(0, 4, item(2775, "Silver Ore", { count = 5, sell = 75, class = 7, subclass = 7 }), 9000)
    put(0, 5, item(2901, "Mining Pick", { sell = 16, class = 2, subclass = 14 }), 9000)
    put(0, 6, item(6125, "Brawler's Pants", { bound = true, quality = 2, sell = 300, class = 4, level = 20 }), 9000)
    put(0, 7, item(4865, "Ruined Pelt", { quality = 0, sell = 12, class = 15 }))
    put(0, 8, item(6515, "Spellbinder Robes", { quality = 2, sell = 300, class = 4, level = 20 }), 5000)
    put(0, 9, item(2318, "Light Leather", { count = 10, sell = 3, class = 7, subclass = 6 })) -- no price yet
    put(0, 10, item(858, "Lesser Healing Potion", { count = 5, sell = 5, class = 0 }))        -- no price
    local inUse = item(4306, "Silk Cloth", { count = 10, sell = 38, class = 7, subclass = 5 })
    inUse.isLocked = true -- picked up / being traded: the game's own lock
    put(0, 11, inUse, 9000)
    -- A plain trade good an active quest asks for (operator, 2026-11-08): worth listing, never mailed.
    put(0, 12, item(1081, "Crisp Spider Meat", { count = 5, sell = 250, class = 7, subclass = 8 }), 9000)
    S.quests = { { title = "Redridge Goulash", objectives = { { text = "Crisp Spider Meat: 5/5", type = "item" } } } }
    put(5, 1, item(2592, "Wool Cloth", { count = 20, sell = 33, class = 7, subclass = 5 }), 9000)
    for i = 1, 10 do -- bags 1 and 2: ten priced stacks, so the run needs a second mail
        local bag, slot = i <= 4 and 1 or 2, i <= 4 and i or i - 4
        put(bag, slot, item(3000 + i, "Ore " .. i, { count = 5, sell = 5, class = 7, subclass = 7 }), 500)
    end
    -- The game's combined bags as Forever has them (v0.22.0 errored on this at every login and
    -- mailbox visit): buttons for the slots laid out so far, a size that counts every slot.
    local combined = ContainerFrameCombinedBags
    combined.Items = { WowStub.itemButton(0, 1), WowStub.itemButton(0, 2), WowStub.itemButton(0, 4) }
    combined.size = 36
    return prices
end

local function useAuctionator(prices)
    _G.Auctionator = { API = { v1 = {
        GetAuctionPriceByItemLink = function(_, l) return prices[l] end,
        GetAuctionAgeByItemLink = function() return 0 end,
    } } }
end

local function mailbox()
    MailFrame:Show()
    SendMailFrame:Show()
end

--- itemID -> recipient, as the window previewed it.
local function previewed(ns)
    local out = {}
    for _, it in ipairs(ns.MailWindow.Result().mail) do out[it.itemID] = it.result.to or BANK_ALT end
    return out
end

--- Answer every mail the way the server does until the mailer is done.
local function deliver(ns)
    for _ = 1, 20 do
        WowStub.runTimers()
        if not ns.Mailer.Busy() then return end
        ns.Fire("MAIL_SEND_SUCCESS")
    end
    error("the mailer never finished")
end

--- The AGENTS.md safety rules, checked on every mail that went out, and the preview
--- delivered in full: each previewed item went to its previewed recipient, nothing else went.
local function assertSafeAndComplete(ns, preview, allowed)
    local sent, carried = WowStub.state.sent, WowStub.state.sentItems
    assert.is_true(#sent > 0, "nothing was mailed")
    local got = {}
    for i, mail in ipairs(sent) do
        assert.is_true(allowed[mail.name] == true, "mail " .. i .. " went to " .. tostring(mail.name))
        assert.equal(0, mail.money, "mail " .. i .. " carried money")
        assert.equal(0, mail.cod, "mail " .. i .. " was COD")
        assert.is_true(mail.count <= 12)
        for _, it in ipairs(carried[i]) do
            assert.is_nil(HARD_KEEPS[it.itemID], "mailed a hard keep: " .. tostring(HARD_KEEPS[it.itemID]))
            assert.is_false(it.bound, "mailed a soulbound item " .. it.itemID)
            assert.is_false(it.quest, "mailed a quest item " .. it.itemID)
            assert.is_false(ns.Locks.IsItemLocked(it.itemID), "mailed a locked item " .. it.itemID)
            assert.equal(preview[it.itemID], mail.name, "item " .. it.itemID .. " went to the wrong recipient")
            got[it.itemID] = true
        end
    end
    for itemID in pairs(preview) do assert.is_true(got[itemID], "previewed but not mailed: " .. itemID) end
    local logged = {}
    for _, e in ipairs(ns.Ledger.Store().log) do
        if e.dir == "sent" then logged[#logged + 1] = e end
    end
    assert.equal(#sent, #logged, "the mail log doesn't hold one entry per mail sent")
    for i, mail in ipairs(sent) do
        assert.equal(mail.name, logged[i].other, "mail " .. i .. " is logged to the wrong recipient")
        assert.equal(#carried[i], #logged[i].items, "mail " .. i .. " is logged with the wrong stacks")
        for j, it in ipairs(carried[i]) do
            assert.equal(it.itemID, logged[i].items[j].itemID, "mail " .. i .. " stack " .. j)
            assert.equal(it.count, logged[i].items[j].count, "mail " .. i .. " stack " .. j)
        end
    end
end

local function assertQuiet(ns)
    for _, line in ipairs(ns.Log.Lines()) do assert.is_nil(line:find("error", 1, true), line) end
    assert.same({}, MailworthyDB.blocked, "a blocked action was blamed on Mailworthy")
    assert.equal(0, WowStub.focusCalls, "SetFocus was called")
    assert.equal(0, WowStub.tabClicks, "Mailworthy switched mail tabs")
end

describe("critical path: mailing", function()
    local ns, prices

    before_each(function()
        ns = loadAddon()
        ns.Fire("PLAYER_LOGIN")
        ns.Config.SetBankAlt(BANK_ALT)
        prices = fillBags()
        useAuctionator(prices)
        ns.Locks.ToggleItem(2775, WowStub.link(2775, "Silver Ore"), "spec")
    end)
    after_each(function()
        assertQuiet(ns)
        _G.Auctionator = nil
    end)

    it("the .toc loads every addon file and only files that exist", function()
        local listed = {}
        for line in io.lines("Mailworthy/Mailworthy.toc") do
            if line:match("%.lua$") then listed[line] = true end
            if line:match("^## Interface:") then assert.equal("## Interface: 16001", line) end
        end
        local pipe = assert(io.popen("ls Mailworthy"))
        for file in pipe:lines() do
            if file:match("%.lua$") then
                assert.is_true(listed[file] == true, file .. " is not in Mailworthy.toc: the game would never load it")
                listed[file] = nil
            end
        end
        pipe:close()
        assert.is_nil(next(listed), "the .toc lists a file that doesn't exist")
    end)

    it("mouse: Mailworthy button, Send, every previewed item reaches the bank alt and nothing else leaves", function()
        ns.Fire("MAIL_SHOW")
        mailbox()
        _G.MailworthyMailButton:Click()
        assert.is_true(ns.MailWindow.Frame():IsShown())
        local preview = previewed(ns)
        assert.truthy(preview[6515], "a priced BoE green goes")
        assert.truthy(preview[2592], "the reagent bag is scanned")
        assert.truthy(preview[3010], "the last bag's items go")
        assert.is_true(_G.MailworthyMailSend:IsShown())
        _G.MailworthyMailSend:Click()
        deliver(ns)
        assert.is_true(#WowStub.state.sent >= 2, "more than 12 stacks: the run chains a second mail")
        assertSafeAndComplete(ns, preview, { [BANK_ALT] = true })
        assert.truthy(ns.Mailer.Status():find("^Sent %d+ mail"), ns.Mailer.Status())
        ns.Fire("BAG_UPDATE_DELAYED")
        assert.equal(0, #ns.MailWindow.Result().mail, "after sending, the window has nothing left to mail")
        ns.Fire("MAIL_CLOSED")
    end)

    it("the Send Mail tab opens the window by itself; on the Inbox Send is greyed out and sends nothing", function()
        -- operator, 2026-11-08: "when you click send mail mailworthy should open ... greyed out with a
        -- 'click send mail' text ... flip to the standard send to button"
        local watcher = _G.MailworthyTabWatcher
        local function tick() watcher.scripts.OnUpdate(watcher, 0.3) end
        ns.Fire("MAIL_SHOW")
        MailFrame:Show()
        InboxFrame:Show()
        _G.MailworthyInboxButton:Click()
        assert.equal("Click Send Mail", _G.MailworthyMailSend:GetText())
        _G.MailworthyMailSend:Click()
        WowStub.runTimers()
        assert.equal(0, #WowStub.state.sent, "nothing goes from the Inbox")
        ns.MailWindow.Frame():Hide()
        tick()
        InboxFrame:Hide()
        SendMailFrame:Show() -- the player clicks the Send Mail tab, nothing else
        tick()
        assert.is_true(ns.MailWindow.Frame():IsVisible())
        assert.equal("Send to Roknua", _G.MailworthyMailSend:GetText())
        local preview = previewed(ns)
        _G.MailworthyMailSend:Click()
        deliver(ns)
        assertSafeAndComplete(ns, preview, { [BANK_ALT] = true })
    end)

    it("controller: Triangle opens the window, Send is a D-pad target, Cross sends", function()
        WowStub.state.gamepadUI = true
        ns.Fire("MAIL_SHOW")
        mailbox()
        WowStub.state.activeFrame = MailFrame
        local watcher = _G.MailworthyPadWatcher
        local function tick() watcher.scripts.OnUpdate(watcher, 0.2) end
        local function press(name)
            WowStub.state.now = WowStub.state.now + 1
            _G[name]:Click()
            tick()
        end
        tick()
        press("MailworthyPadTriangle")
        assert.is_true(ns.MailWindow.Frame():IsShown())
        local preview = previewed(ns)
        assert.equal("CLICK MailworthyPadCross:LeftButton", WowStub.state.bindings.PAD1, "Cross isn't bound")
        press("MailworthyPadDown")
        assert.truthy(ns.Nav.Current(), "the D-pad doesn't move the highlight")
        -- The stub has no layout, so which press lands on Send is nav_spec's job (fixed
        -- coordinates); here Send must be a controller target and Cross must press it.
        local reachable = false
        for _, c in ipairs(ns.Nav.Candidates()) do reachable = reachable or c.button == _G.MailworthyMailSend end
        assert.is_true(reachable, "Send isn't a controller target")
        ns.Nav.Select(_G.MailworthyMailSend)
        press("MailworthyPadCross")
        deliver(ns)
        assertSafeAndComplete(ns, preview, { [BANK_ALT] = true })
        for _, line in ipairs(ns.Log.Lines()) do assert.is_nil(line:find("check error", 1, true), line) end
    end)

    it("without Auctionator only unlocked, tradeable white items are mailed", function()
        _G.Auctionator = nil
        mailbox()
        _G.MailworthyMailButton:Click()
        local preview = previewed(ns)
        assert.is_nil(preview[6515], "a green stays without prices")
        assert.is_nil(preview[4865], "junk stays without prices")
        _G.MailworthyMailSend:Click()
        deliver(ns)
        assertSafeAndComplete(ns, preview, { [BANK_ALT] = true })
        for i in ipairs(WowStub.state.sent) do
            for _, it in ipairs(WowStub.state.sentItems[i]) do assert.equal(1, it.quality, "item " .. it.itemID) end
        end
    end)

    it("with Auctionator an unpriced item stays, except a white trade good in launch days 0-13", function()
        mailbox()
        _G.MailworthyMailButton:Click()
        local preview = previewed(ns)
        assert.is_nil(preview[858], "an unpriced potion stays")
        assert.truthy(preview[2318], "an unpriced white trade good goes on a fresh realm")
        WowStub.state.serverTime = ns.Valuation.LAUNCH_EPOCH + 30 * 86400
        ns.MailWindow.Refresh()
        assert.is_nil(previewed(ns)[2318], "past launch day 13 it stays like anything unpriced")
    end)

    it("a binding: the friend gets their profession's materials, the bank alt the rest, nobody else", function()
        WowStub.setBag(2, 6, WowStub.item(10940, "Strange Dust", { count = 20, sell = 2, class = 7, subclass = 12 }))
        prices[WowStub.link(10940, "Strange Dust")] = 3 -- the rule alone would keep it
        ns.Routes.Add(BOB, ENCHANTING)
        mailbox()
        _G.MailworthyMailButton:Click()
        local preview = previewed(ns)
        assert.equal(BOB, preview[10940])
        assert.equal("Send to Roknua, Bob", _G.MailworthyMailSend:GetText())
        _G.MailworthyMailSend:Click()
        deliver(ns)
        assertSafeAndComplete(ns, preview, { [BANK_ALT] = true, [BOB] = true })
    end)

    it("a class binding: the mage friend gets the mage-only scroll, the bank alt the rest, nobody else", function()
        -- operator, 2026-11-08: "this is a mage only item, id like to be able to friend mail these types of items too"
        WowStub.setBag(0, 13, WowStub.item(211234, "Scroll: VOCE WELL", { sell = 15, class = 0 }))
        prices[WowStub.link(211234, "Scroll: VOCE WELL")] = 100
        WowStub.state.itemClasses[211234] = "Mage"
        WowStub.state.itemClasses[6515] = "Paladin" -- another class's item: not the mage's
        ns.Routes.Add(BOB, "MAGE")
        mailbox()
        _G.MailworthyMailButton:Click()
        local preview = previewed(ns)
        assert.equal(BOB, preview[211234])
        assert.equal(BANK_ALT, preview[6515])
        assert.equal("Send to Roknua, Bob", _G.MailworthyMailSend:GetText())
        _G.MailworthyMailSend:Click()
        deliver(ns)
        assertSafeAndComplete(ns, preview, { [BANK_ALT] = true, [BOB] = true })
    end)

    it("two bindings on one material: lowest skill first, and a recipient that changes after the preview holds Send", function()
        -- operator, 2026-11-07: Blacksmithing and Engineering both take metal and stone, "Lowest skill
        -- first". Codex review: a skill heard between the preview and Send must not move mail unseen.
        local SMITH, ENGINEER = "Smith Anvil", "Jold Ark"
        WowStub.state.guild = { clubId = 7, name = "Bank Of Azeroth", members = {
            { name = SMITH, online = true, professions = { 164 }, ranks = { 60 } },
            { name = ENGINEER, online = true, professions = { 202 }, ranks = { 100 } } } }
        ns.Routes.Add(SMITH, 164)
        ns.Routes.Add(ENGINEER, 202)
        mailbox()
        _G.MailworthyMailButton:Click()
        assert.equal(SMITH, previewed(ns)[2770], "Copper Ore: the blacksmith (60) is lower than the engineer (100)")
        WowStub.state.guild.members[1].ranks = { 110 } -- the roster updates; the window hasn't redrawn
        _G.MailworthyMailSend:Click()
        assert.is_false(ns.Mailer.Busy(), "nothing goes while a recipient differs from the list shown")
        WowStub.runTimers()
        assert.equal(0, #WowStub.state.sent)
        assert.truthy(table.concat(WowStub.printed, "\n"):find("Not sent: Copper Ore now goes to Jold instead of Smith", 1, true))
        local preview = previewed(ns)
        assert.equal(ENGINEER, preview[2770], "the list now shows the engineer")
        _G.MailworthyMailSend:Click()
        deliver(ns)
        assertSafeAndComplete(ns, preview, { [BANK_ALT] = true, [ENGINEER] = true })
    end)

    it("a bank alt picked after the preview holds Send until the list shows it (Codex review)", function()
        local NEW = "Newbank Alt"
        mailbox()
        _G.MailworthyMailButton:Click()
        ns.Config.SetBankAlt(NEW) -- Settings beside the mail window; the list still names the old one
        _G.MailworthyMailSend:Click()
        assert.is_false(ns.Mailer.Busy(), "nothing goes to a bank alt the list didn't name")
        WowStub.runTimers()
        assert.equal(0, #WowStub.state.sent)
        local preview = previewed(ns)
        for id in pairs(preview) do preview[id] = preview[id] == BANK_ALT and NEW or preview[id] end
        _G.MailworthyMailSend:Click()
        deliver(ns)
        assertSafeAndComplete(ns, preview, { [NEW] = true })
    end)

    it("no bank alt: the window opens, its share stays in the bags, and only the binding's friend gets mail", function()
        -- operator, 2026-11-08: "dont require a bank alt to use mailworthy"
        MailworthyDB.bankAlts = {}
        WowStub.setBag(2, 6, WowStub.item(10940, "Strange Dust", { count = 20, sell = 2, class = 7, subclass = 12 }))
        prices[WowStub.link(10940, "Strange Dust")] = 3
        ns.Routes.Add(BOB, ENCHANTING)
        mailbox()
        _G.MailworthyMailButton:Click()
        assert.is_true(ns.MailWindow.Frame():IsShown(), "no bank alt: the window, not the settings")
        local preview = previewed(ns)
        assert.same({ [10940] = BOB, [6515] = BOB }, preview, "only the binding's (dust, and the green to disenchant)")
        assert.equal("Send to Bob", _G.MailworthyMailSend:GetText())
        _G.MailworthyMailSend:Click()
        deliver(ns)
        assertSafeAndComplete(ns, preview, { [BOB] = true })
    end)

    it("Skip once for the bank alt: its share stays this visit, the binding still goes", function()
        -- operator, 2026-11-08: "Players should be able to click skip once for their bank alt sends too"
        WowStub.setBag(2, 6, WowStub.item(10940, "Strange Dust", { count = 20, sell = 2, class = 7, subclass = 12 }))
        prices[WowStub.link(10940, "Strange Dust")] = 3
        ns.Routes.Add(BOB, ENCHANTING)
        mailbox()
        _G.MailworthyMailButton:Click()
        assert.equal(BANK_ALT, previewed(ns)[2592])
        _G.MailworthyMailSkipBankAlt:Click()
        assert.equal("Undo skip", _G.MailworthyMailSkipBankAlt:GetText())
        local preview = previewed(ns)
        assert.same({ [10940] = BOB, [6515] = BOB }, preview)
        assert.equal("Send to Bob", _G.MailworthyMailSend:GetText())
        _G.MailworthyMailSend:Click()
        deliver(ns)
        assertSafeAndComplete(ns, preview, { [BOB] = true })
        ns.Fire("MAIL_CLOSED")
        mailbox()
        ns.MailWindow.Show("send")
        assert.equal(BANK_ALT, previewed(ns)[2592], "the next visit mails the bank alt again")
    end)

    --- The guild master's template (Guild.lua) arrives over the guild channel: Enchanting to Bob.
    local function guildTemplate()
        local gm = "Guild Master"
        WowStub.state.guild = { clubId = 7, name = "Bank Of Azeroth", members = {
            { name = gm, rank = 0, online = true }, { name = BOB, rank = 3, online = true } } }
        WowStub.setBag(2, 6, WowStub.item(10940, "Strange Dust", { count = 20, sell = 2, class = 7, subclass = 12 }))
        prices[WowStub.link(10940, "Strange Dust")] = 3 -- the rule alone would keep it
        -- passed on by a plain member: any guild member may hand on a copy (operator, 2026-11-07)
        for _, m in ipairs(ns.Guild.Encode(WowStub.state.serverTime - 60, gm, { { profession = ENCHANTING, to = BOB } })) do
            ns.Fire("CHAT_MSG_ADDON", "Mailworthy", m, "GUILD", BOB)
        end
    end

    it("a guild template: nothing goes to the guild until the player turns it on, then only the shown recipients", function()
        guildTemplate()
        mailbox()
        _G.MailworthyMailButton:Click()
        assert.is_nil(previewed(ns)[10940], "a template the player hasn't turned on mails nothing")
        ns.SettingsUI.Show()
        _G.MailworthySettingsGuild:Click() -- the Guild window (2026-11-07: out of Friends, into the settings)
        assert.is_true(_G.MailworthyFriendsGuildRules:IsShown())
        _G.MailworthyFriendsGuildRules:Click() -- "Use guild rules"
        ns.MailWindow.Refresh()
        local preview = previewed(ns)
        assert.equal(BOB, preview[10940])
        assert.equal("Send to Roknua, Bob", _G.MailworthyMailSend:GetText())
        _G.MailworthyMailSend:Click()
        deliver(ns)
        assertSafeAndComplete(ns, preview, { [BANK_ALT] = true, [BOB] = true })
    end)

    it("a guild template turned off in one press: only the bank alt gets mail", function()
        guildTemplate()
        ns.Guild.SetUse(true)
        mailbox()
        _G.MailworthyMailButton:Click()
        assert.equal(BOB, previewed(ns)[10940])
        _G.MailworthyMailGuildRules:Click() -- "Guild rules: on" -> off
        local preview = previewed(ns)
        assert.is_nil(preview[10940])
        _G.MailworthyMailSend:Click()
        deliver(ns)
        assertSafeAndComplete(ns, preview, { [BANK_ALT] = true })
    end)

    it("bags that change after the preview: Send re-reads them, and a slot that changes mid-run is skipped", function()
        local pants = function() return WowStub.item(6125, "Brawler's Pants", { bound = true, quality = 2, sell = 300, class = 4 }) end
        mailbox()
        _G.MailworthyMailButton:Click()
        local preview = previewed(ns)
        WowStub.setBag(0, 8, pants()) -- before Send: the green's slot now holds a soulbound item
        preview[6515] = nil
        local plan = ns.Mailer.Plan(ns.Bags.Evaluate().mail, BANK_ALT)
        assert.is_true(#plan >= 2)
        local later = plan[#plan].stacks[1] -- a stack the last mail would carry
        _G.MailworthyMailSend:Click()
        WowStub.runTimers()
        assert.equal(1, #WowStub.state.sent)
        WowStub.setBag(later.bag, later.slot, pants()) -- mid-run: that slot changes too
        preview[later.itemID] = nil
        ns.Fire("MAIL_SEND_SUCCESS")
        deliver(ns)
        assertSafeAndComplete(ns, preview, { [BANK_ALT] = true })
        assert.equal(1, ns.Mailer.state.skipped, "only the mid-run change is a skip; Send's re-read caught the first")
    end)
end)

describe("critical path: an older build's SavedVariables", function()
    -- What a player upgrading from an early alpha carries: the discovery self-test,
    -- slot locks (alpha3/alpha4), a 30-day-old mail record, and none of the tables
    -- later builds added (routes, peers, fresh, realms, tierCheck, features).
    local function oldSaved()
        return {
            db = {
                selftest = { answers = { U1 = "yes" }, log = { "old line" } },
                settings = { minGain = 500, duration = 2 },
                bankAlts = { [REALM_KEY] = BANK_ALT },
                names = { { name = BANK_ALT, realm = "Classic Beta PvP", faction = "Alliance" } },
                characters = { ["Roknua Themicrulah|Classic Beta PvP|Alliance"] = { name = BANK_ALT,
                    realm = "Classic Beta PvP", faction = "Alliance", class = "WARRIOR", level = 5 } },
                mailed = { [2770] = { at = 1700000000, route = "ah" } },
                blocked = {},
                log = {},
            },
            charDB = { lockedSlots = { ["0:4"] = true } }, -- the Silver Ore's slot
        }
    end

    it("loads, logs in, keeps the old lock, and mails", function()
        local ns = loadAddon(oldSaved())
        local prices = fillBags() -- the bags are there before login, as in game
        useAuctionator(prices)
        ns.Fire("ADDON_LOADED", "Mailworthy")
        ns.Fire("PLAYER_LOGIN")
        assert.is_true(ns.Locks.IsItemLocked(2775), "the alpha slot lock became an item lock")
        assert.is_nil(MailworthyDB.selftest, "the discovery self-test data is dropped")
        assert.equal(BANK_ALT, ns.Config.BankAlt())
        ns.Fire("MAIL_SHOW")
        mailbox()
        _G.MailworthyMailButton:Click()
        local preview = previewed(ns)
        assert.is_not_nil(next(preview))
        _G.MailworthyMailSend:Click()
        deliver(ns)
        assertSafeAndComplete(ns, preview, { [BANK_ALT] = true })
        assertQuiet(ns)
        local report = ns.Report.Build()
        assert.truthy(report:find(BANK_ALT, 1, true), "/mw report still builds")
        _G.Auctionator = nil
    end)
end)
