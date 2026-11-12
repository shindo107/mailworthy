-- "Your Mailworthy is out of date" (operator, 2026-11-08: "can we show a your version is outdated
-- message when someone encounters another player with a newer version of mailworthy in game?").
-- A release build sends "U2|vX.Y.Z" after its hello; a peer's newer version gives one chat line
-- per session, a line in the Mailworthy window's footer and the settings window, and a report
-- line. A dev build (the packager's placeholder) and alpha/beta tags never send or get told.
local loadAddon = require("spec.support.load_addon")

describe("version notice", function()
    local ns
    local BOB, CID, BANK = "Bob Surname", "Cid Third", "Roknua Themicrulah"
    local DEV -- the checkout's placeholder (ns.VERSION as loaded)

    local function say(sender, text, channel) ns.Fire("CHAT_MSG_ADDON", "Mailworthy", text, channel or "GUILD", sender) end
    local function printed() return table.concat(WowStub.printed, "\n") end
    local function count(text, needle)
        local n, at = 0, 1
        while true do
            local i = text:find(needle, at, true)
            if not i then return n end
            n, at = n + 1, i + #needle
        end
    end
    local function messages()
        local out = {}
        for _, m in ipairs(WowStub.state.addonMessages) do out[#out + 1] = m.message end
        return out
    end
    local function release(v) ns.VERSION = v end

    before_each(function()
        ns = loadAddon()
        DEV = ns.VERSION
        _G.Minimap = WowStub.newWidget("Frame", "Minimap")
        ns.Fire("PLAYER_LOGIN")
        WowStub.state.guild = { clubId = 3, members = {
            { name = BOB, level = 30, online = true }, { name = CID, level = 30, online = true },
        } }
    end)
    after_each(function()
        _G.Minimap = nil
        _G.Auctionator = nil
        for _, line in ipairs(ns.Log.Lines()) do assert.is_nil(line:find("error", 1, true), line) end
        assert.equal(0, WowStub.focusCalls)
    end)

    describe("comparing versions (pure)", function()
        it("compares major, minor and patch as numbers", function()
            local N = ns.Version.Newer
            assert.is_true(N("v0.31.0", "v0.30.0"))
            assert.is_true(N("v0.30.1", "v0.30.0"))
            assert.is_true(N("v1.0.0", "v0.99.99"))
            assert.is_true(N("v0.30.10", "v0.30.9"), "10 > 9, not text order")
            assert.is_false(N("v0.30.0", "v0.30.0"), "the same version is not newer")
            assert.is_false(N("v0.29.9", "v0.30.0"))
            assert.is_false(N("v0.9.0", "v0.10.0"))
        end)

        it("anything that isn't vX.Y.Z is never newer and never older", function()
            local junk = { "0.31.0", "v0.31", "v0.31.0.1", "v0.31.0-beta1", "v0.31.0-alpha", "V0.31.0", "v 0.31.0",
                "v0.31.0 ", " v0.31.0", "v0.31.0\n", "v12345.0.0", "v-1.0.0", "v0.31.x", "", "|cffff0000v9.9.9|r",
                "v0.31.0|extra", DEV, string.rep("9", 300), 31, true, {} }
            for _, v in ipairs(junk) do
                assert.is_nil(ns.Version.Parse(v), tostring(v))
                assert.is_false(ns.Version.Newer(v, "v0.30.0"), tostring(v))
                assert.is_false(ns.Version.Newer("v0.30.0", v), tostring(v))
            end
            assert.is_false(ns.Version.Newer(nil, nil))
            assert.same({ 9999, 0, 0 }, ns.Version.Parse("v9999.0.0"), "four digits a part at most")
        end)
    end)

    describe("a dev build (the packager's placeholder)", function()
        it("is never out of date and never claims a version", function()
            assert.truthy(DEV:find("project", 1, true), "a checkout keeps the placeholder")
            assert.is_nil(ns.Version.Own())
            assert.is_nil(ns.Version.Message())
            ns.Comms.Announce("test")
            for _, m in ipairs(messages()) do assert.is_nil(m:find("^U"), m) end
            say(BOB, "H2||")
            say(BOB, "U2|v99.0.0")
            assert.equal("v99.0.0", ns.Comms.Peer(BOB).release, "still kept: the report shows it")
            assert.is_nil(printed():find("is out", 1, true))
            assert.is_nil(ns.Version.Text())
            assert.truthy(ns.Version.ReportLines()[1]:find("a dev build: never out of date", 1, true))
        end)

        it("an alpha or beta tag counts as a dev build", function()
            release("v0.31.0-beta1")
            assert.is_nil(ns.Version.Message())
            say(BOB, "U2|v0.32.0")
            assert.is_nil(ns.Version.Text())
            assert.equal("", printed())
        end)
    end)

    describe("a release build", function()
        before_each(function() release("v0.30.0") end)

        it("says its version right after the hello (and the other messages), on the same channels", function()
            ns.Comms.Announce("test")
            local m = messages()
            assert.equal("H2|", m[1]:sub(1, 3))
            assert.equal("S2|", m[2]:sub(1, 3))
            assert.equal("U2|v0.30.0", m[#m])
            assert.equal("GUILD", WowStub.state.addonMessages[#m].channel)
        end)

        it("a newer version from a peer: one chat line naming it, and the windows' line", function()
            say(BOB, "H2||")
            say(BOB .. "-Classic Beta PvP", "U2|v0.31.0")
            assert.equal("|cff33ff99Mailworthy|r: Mailworthy v0.31.0 is out (Bob Surname has it); you have v0.30.0. "
                .. "Update from CurseForge.", printed())
            assert.equal("|cffffd100Mailworthy v0.31.0 is out (you have v0.30.0): update from CurseForge|r",
                ns.Version.Text())
            assert.equal("v0.31.0", ns.Comms.Peer(BOB).release)
        end)

        it("at most one chat line a session; the windows follow the newest", function()
            say(BOB, "U2|v0.31.0")
            say(BOB, "U2|v0.31.0", "PARTY")
            WowStub.state.now = WowStub.state.now + 60
            say(BOB, "U2|v0.31.0")
            say(CID, "U2|v0.32.0")
            assert.equal(1, count(printed(), "is out"), printed())
            assert.truthy(ns.Version.Text():find("v0.32.0 is out", 1, true))
            assert.truthy(ns.Version.ReportLines()[1]:find("out of date: v0.32.0 heard from Cid Third", 1, true))
            assert.truthy(ns.Version.ReportLines()[1]:find("told in chat this session", 1, true))
        end)

        it("the same or an older version: nothing", function()
            say(BOB, "U2|v0.30.0")
            say(CID, "U2|v0.29.5")
            assert.equal("", printed())
            assert.is_nil(ns.Version.Text())
            assert.truthy(ns.Version.ReportLines()[1]:find("up to date (newest heard v0.30.0 from Bob Surname)", 1, true))
        end)

        it("malformed versions are dropped: no chat, nothing kept", function()
            say(BOB, "H2||")
            for _, text in ipairs({ "U2|v0.31", "U2|0.31.0", "U2|v0.31.0-beta", "U2|v99999.0.0", "U2|",
                "U2|v0.31.0 ", "U2|" .. string.rep("v", 260), "U2|\124cffff0000v9.9.9\124r", "U2v0.31.0" }) do
                assert.is_nil(ns.Comms.Decode(text), text)
                say(BOB, text)
                WowStub.state.now = WowStub.state.now + 10
            end
            assert.is_nil(ns.Comms.Peer(BOB).release)
            assert.equal("", printed())
            assert.is_nil(ns.Version.Hear(BOB, "v0.31"))
            assert.is_nil(ns.Version.Hear(nil, "v0.31.0"))
            assert.is_nil(ns.Version.Text())
        end)

        it("fields after the version are left out (a later build may add some)", function()
            assert.same({ kind = "release", version = 2, release = "v0.31.0" }, ns.Comms.Decode("U2|v0.31.0|more|fields"))
            assert.same({ kind = "release", version = 3, release = "v0.31.0" }, ns.Comms.Decode("U3|v0.31.0"))
        end)

        it("/mw feature versionNotice off: no chat line, no windows' line; the version still goes out", function()
            MailworthyDB.features.versionNotice = false
            say(BOB, "U2|v0.31.0")
            assert.equal("", printed())
            assert.is_nil(ns.Version.Text())
            assert.truthy(ns.Version.ReportLines()[1]:find("notice off", 1, true))
            ns.Comms.Announce("test")
            local m = messages()
            assert.equal("U2|v0.30.0", m[#m])
        end)

        it("comms off: nothing sent, nothing heard", function()
            MailworthyDB.features.comms = false
            ns.Comms.Announce("test")
            assert.equal(0, #messages())
            say(BOB, "U2|v0.31.0")
            assert.equal("", printed())
        end)

        it("kept with the peer: a new hello keeps it, the next login shows the line without chat", function()
            say(BOB, "H2||")
            say(BOB, "U2|v0.31.0")
            WowStub.state.now = WowStub.state.now + 60
            say(BOB, "H2|197|")
            assert.equal("v0.31.0", ns.Comms.Peer(BOB).release, "a hello doesn't forget it")
            local saved = { db = MailworthyDB, charDB = MailworthyCharDB }
            ns = loadAddon(saved) -- a new session
            release("v0.30.0")
            ns.Fire("PLAYER_LOGIN")
            assert.equal("", printed(), "the chat line is for meeting someone")
            assert.truthy(ns.Version.Text():find("v0.31.0 is out", 1, true))
            release("v0.31.0") -- updated
            assert.is_nil(ns.Version.Text())
            release("v0.30.0")
            ns.Comms.Prune(WowStub.state.serverTime + 61 * 86400)
            assert.is_nil(ns.Version.Text(), "gone with the peer")
        end)

        it("a new session tells again", function()
            say(BOB, "U2|v0.31.0")
            ns.Version.ResetSession()
            say(CID, "U2|v0.31.0")
            assert.equal(2, count(printed(), "is out"))
        end)
    end)

    describe("older Mailworthys", function()
        it("the hello is unchanged, the version goes in a message of its own", function()
            ns.Comms.Announce("dev")
            local dev = messages()
            WowStub.state.addonMessages = {}
            WowStub.state.now = WowStub.state.now + 60
            release("v0.30.0")
            ns.Comms.Announce("release")
            local rel = messages()
            assert.equal(#dev + 1, #rel)
            for i, m in ipairs(dev) do assert.equal(m, rel[i]) end
        end)

        it("a build without the version message (v0.30.0 and before) drops it and keeps the hello", function()
            ns.Version = nil -- what an older build is: no Version.lua; unknown kinds decode to nil
            assert.is_nil(ns.Comms.Decode("U2|v0.31.0"))
            assert.is_nil(ns.Comms.Hear(BOB, "U2|v0.31.0", "GUILD"))
            say(BOB, "H2|197|")
            assert.same({ 197 }, ns.Comms.Peer(BOB).professions)
            assert.equal("", printed())
        end)

        it("an older peer that sends no version: its hello is kept, no notice", function()
            release("v0.31.0")
            say(BOB, "H2|197|")
            say(BOB, "S2|197:120|")
            say(BOB, "F2|1")
            assert.same({ 197 }, ns.Comms.Peer(BOB).professions)
            assert.is_nil(ns.Comms.Peer(BOB).release)
            assert.is_nil(ns.Version.Text())
            assert.truthy(ns.Version.ReportLines()[1]:find("no other version heard", 1, true))
        end)
    end)

    describe("where it shows", function()
        before_each(function() release("v0.30.0") end)

        it("the settings window: a line under Prices, the window grows to fit it, and redraws when heard", function()
            WowStub.state.layout = true -- sizes are read back
            ns.SettingsUI.Show()
            local before = ns.SettingsUI.Frame():GetHeight()
            assert.equal(548, before)
            assert.equal("", ns.SettingsUI.VersionLine())
            say(BOB, "U2|v0.31.0")
            assert.equal(ns.Version.Text(), ns.SettingsUI.VersionLine())
            assert.equal(before + 20, ns.SettingsUI.Frame():GetHeight())
        end)

        it("a peer already known (hello first) still redraws the open windows (Codex review)", function()
            say(BOB, "H2||")
            ns.SettingsUI.Show()
            assert.equal("", ns.SettingsUI.VersionLine())
            local calls = 0
            ns.Version.OnChanged(function() calls = calls + 1 end)
            say(BOB, "U2|v0.31.0")
            assert.equal(1, calls)
            assert.equal(ns.Version.Text(), ns.SettingsUI.VersionLine())
        end)

        it("the Mailworthy window's footer: the line, then the mark's key and the controller legend", function()
            ns.Config.SetBankAlt(BANK)
            _G.Auctionator = { API = { v1 = {
                GetAuctionPriceByItemLink = function() return 174 end,
                GetAuctionAgeByItemLink = function() return 0 end,
            } } }
            WowStub.setBag(0, 1, WowStub.item(2770, "Copper Ore", { count = 20, sell = 5 }))
            MailFrame:Show()
            SendMailFrame:Show()
            _G.MailworthyMailButton:Click()
            assert.equal("", ns.MailWindow.Footer())
            say(BOB, "U2|v0.31.0")
            assert.equal(ns.Version.Text(), ns.MailWindow.Footer(), "redrawn when heard")
            ns.MailButton.GamepadUI = function() return true end
            ns.MailWindow.Refresh()
            assert.equal(ns.Version.Text() .. "\n" .. ns.Widgets.Legend(), ns.MailWindow.Footer())
        end)

        it("/mw report has the version line", function()
            say(BOB, "U2|v0.31.0")
            ns.Report.Open()
            local text = ns.Report.Text()
            assert.truthy(text:find("version: v0.30.0, out of date: v0.31.0 heard from Bob Surname; notice on", 1, true), text)
        end)
    end)
end)
