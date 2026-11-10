-- The D-pad reaches every button of every view, and never leaves the highlight stuck: from the
-- top-left start each button is a chain of D-pad presses away, and from each button there is a
-- way back (no dead end). Nav's direction search runs over real positions here: the stub solves
-- the windows' SetPoint / SetSize anchors (WowStub.state.layout), so a button placed where no
-- direction leads to it fails this spec before it fails a player with a controller.
local loadAddon = require("spec.support.load_addon")

local BOB = "Bob Surname"
local ENCHANTING = 333

-- Windows walked by the specs below (by name), so the last one can check none was left out.
local walked = {}

describe("D-pad reach in every view", function()
    local ns, watcher
    local function tick() watcher.scripts.OnUpdate(watcher, 0.2) end

    --- Every button the D-pad can't get to from the top-left one, and every one it can't get
    --- back from; both empty when the view is fully navigable.
    local function walk()
        local candidates = ns.Nav.Candidates()
        local function name(c) return c.button:GetName() or "?" end
        local function reach(from)
            local seen, queue = { [from] = true }, { from }
            while #queue > 0 do
                local c = table.remove(queue, 1)
                for _, dir in ipairs({ "up", "down", "left", "right" }) do
                    local n = ns.Nav.Pick(c, candidates, dir)
                    if n and not seen[n] then seen[n], queue[#queue + 1] = true, n end
                end
            end
            return seen
        end
        local start = ns.Nav.TopLeft(candidates)
        local fromStart = reach(start)
        local unreachable, stuck = {}, {}
        for _, c in ipairs(candidates) do
            if not fromStart[c] then unreachable[#unreachable + 1] = name(c) end
            if not reach(c)[start] then stuck[#stuck + 1] = name(c) end
        end
        table.sort(unreachable)
        table.sort(stuck)
        return candidates, unreachable, stuck
    end

    local function assertNavigable(view, atLeast)
        local root = ns.Nav.Root()
        walked[root and root:GetName() or "?"] = true
        local candidates, unreachable, stuck = walk()
        assert.truthy(#candidates >= atLeast, view .. ": only " .. #candidates .. " buttons")
        local spots = {}
        for _, c in ipairs(candidates) do spots[c.x .. "," .. c.y] = true end
        local distinct = 0
        for _ in pairs(spots) do distinct = distinct + 1 end
        assert.truthy(distinct > #candidates / 2, view .. ": the layout wasn't solved")
        assert.same({}, unreachable, view .. ": the D-pad never gets to " .. table.concat(unreachable, ", "))
        assert.same({}, stuck, view .. ": no way back from " .. table.concat(stuck, ", "))
    end

    before_each(function()
        ns = loadAddon()
        WowStub.state.layout = true
        _G.Minimap = WowStub.newWidget("Frame", "Minimap")
        WowStub.state.guild = { clubId = 3, name = "Bank Of Azeroth", rank = 0, members = {
            { name = BOB, rank = 3, level = 30, online = true, professions = { ENCHANTING } },
            { name = "Ann Other", rank = 2, level = 20, online = true, professions = { 197 } },
            { name = "Rettana Quilwrit", rank = 0, online = true },
        } }
        WowStub.state.gamepadUI = true
        ns.Fire("PLAYER_LOGIN")
        MailworthyDB.characters[ns.Characters.Key("Roknua Themicrulah", "Classic Beta PvP", "Alliance")] = {
            name = "Roknua Themicrulah", realm = "Classic Beta PvP", faction = "Alliance", class = "WARRIOR", level = 8,
        }
        ns.Config.SetBankAlt("Roknua Themicrulah")
        watcher = _G.MailworthyPadWatcher
        for slot, it in ipairs({ { 2770, "Copper Ore" }, { 2589, "Linen Cloth" }, { 2592, "Wool Cloth" },
            { 2835, "Rough Stone" }, { 4306, "Silk Cloth" }, { 2318, "Light Leather" } }) do
            WowStub.setBag(0, slot, WowStub.item(it[1], it[2], { count = 10, sell = 5 }))
        end
        WowStub.setBag(0, 7, WowStub.item(6948, "Hearthstone", { bound = true }))
    end)

    after_each(function()
        _G.Minimap = nil
        for _, line in ipairs(ns.Log.Lines()) do assert.is_nil(line:find("error", 1, true), line) end
    end)

    it("the mailbox window, without and with bindings", function()
        MailFrame:Show()
        SendMailFrame:Show()
        WowStub.state.activeFrame = MailFrame
        ns.MailWindow.Show("send")
        tick()
        assertNavigable("mailbox window", 4)
        ns.Routes.Add(BOB, ENCHANTING)
        ns.Routes.Add("Ann Other", 197)
        ns.MailWindow.Refresh()
        assertNavigable("mailbox window with bindings", 8)
        for slot = 1, 16 do -- more than a page of rows: the page buttons show
            WowStub.setBag(1, slot, WowStub.item(3000 + slot, "Thing " .. slot, { count = 1, sell = 5 }))
        end
        WowStub.state.numSlots[1] = 16
        ns.MailWindow.Refresh()
        assert.is_true(_G.MailworthyMailPage:IsVisible(), "the Mailing list's page button")
        assert.is_true(_G.MailworthyMailPageBack:IsVisible(), "and its way back")
        assertNavigable("mailbox window, several pages", 11)
        -- No bank alt: Choose bank alt... sits on the To line.
        ns.Config.ClearBankAlt()
        ns.MailWindow.Refresh()
        assert.is_true(_G.MailworthyMailChooseAlt:IsVisible())
        assertNavigable("mailbox window, no bank alt", 5)
        ns.Routes.Remove(ns.Routes.List()[1].key)
        ns.Routes.Remove(ns.Routes.List()[1].key)
        ns.MailWindow.Refresh()
        assert.is_true(_G.MailworthyMailChooseAlt:IsVisible())
        assertNavigable("mailbox window, no bank alt, no bindings", 3)
    end)

    it("the Send shortcut: Up from every top-row button lands on Send, Down from the bottom row leads back", function()
        MailFrame:Show()
        SendMailFrame:Show()
        WowStub.state.activeFrame = MailFrame
        ns.MailWindow.Show("send")
        tick()
        local send = _G.MailworthyMailSend
        assert.is_true(send:IsEnabled())
        local candidates = ns.Nav.Candidates()
        local start = ns.Nav.TopLeft(candidates).button
        for _, c in ipairs(candidates) do
            if c.button ~= send and not ns.Nav.Pick(c, candidates, "up") then
                ns.Nav.Select(c.button)
                ns.Nav.Move("up")
                assert.equal(send, ns.Nav.Current(), "Up from " .. tostring(c.button:GetName()))
            end
            if not ns.Nav.Pick(c, candidates, "down") then
                ns.Nav.Select(c.button)
                ns.Nav.Move("down")
                assert.equal(start, ns.Nav.Current(), "Down from " .. tostring(c.button:GetName()))
            end
        end
    end)

    it("the mailbox window opened on the Inbox, and the report box", function()
        MailFrame:Show()
        InboxFrame:Show()
        WowStub.state.activeFrame = MailFrame
        ns.MailWindow.Show("inbox")
        tick()
        assertNavigable("mailbox window on the Inbox", 3)
        ns.MailWindow.Frame():Hide()
        ns.HandleSlash("report")
        tick()
        assertNavigable("report box", 1)
    end)

    it("settings: the main view and the bank alt picker", function()
        ns.SettingsUI.Show()
        tick()
        assertNavigable("settings", 15)
        _G.MailworthySettingsChange:Click()
        tick()
        assertNavigable("settings picker", 3)
    end)

    it("friends: the list, adding (both steps) and the guild template", function()
        ns.Routes.Add(BOB, ENCHANTING)
        ns.Routes.Add("Ann Other", 197)
        ns.RoutesUI.Show()
        tick()
        assertNavigable("friends list", 6)
        for i, prof in ipairs({ 164, 165, 171, 186 }) do ns.Routes.Add("Friend Number" .. i, prof) end
        ns.RoutesUI.Refresh()
        assert.is_true(_G.MailworthyFriendsBindPageBack:IsVisible(), "the bindings list's two-way pager")
        assertNavigable("friends list, several pages", 7)
        _G.MailworthyFriendsAdd:Click()
        tick()
        assertNavigable("friends add, step 1", 3)
        _G.MailworthyFriendsPick1:Click()
        tick()
        assertNavigable("friends add, step 2", 4)
        ns.RoutesUI.Frame():Hide()
        ns.Guild.DraftAdd(BOB, ENCHANTING)
        ns.RoutesUI.ShowGuild()
        tick()
        assertNavigable("guild template", 3)
    end)

    it("the ledger and the bank alt summary", function()
        local store = ns.Ledger.Store()
        store.players["bob surname"] = { name = BOB, received = 1000, sent = 0, inItems = {}, outItems = {}, at = 1 }
        store.players["ann other"] = { name = "Ann Other", received = 500, sent = 0, inItems = {}, outItems = {}, at = 1 }
        ns.LedgerUI.Show()
        tick()
        assertNavigable("ledger", 2)
        for i = 1, 8 do
            store.players["friend " .. i] = { name = "Friend " .. i, received = 100 * i, sent = 0, inItems = {}, outItems = {}, at = 1 }
        end
        ns.LedgerUI.Refresh()
        assert.is_true(_G.MailworthyLedgerPageBack:IsVisible(), "the ledger's two-way pager")
        assertNavigable("ledger, several pages", 4)
        ns.LedgerUI.Frame():Hide()
        ns.BankAlt.ShowWindow()
        tick()
        assertNavigable("summary", 1)
    end)

    -- CI's "controller" job runs this file: a new Mailworthy window (Nav.Attach) fails it until a
    -- spec above walks its views.
    it("walked every window the controller can drive", function()
        ns.Fire("PLAYER_LOGIN")
        local missing = {}
        for _, frame in ipairs(ns.Nav.Windows()) do
            local name = frame:GetName() or "?"
            if not walked[name] then missing[#missing + 1] = name end
        end
        table.sort(missing)
        assert.same({}, missing, "no D-pad reach spec for " .. table.concat(missing, ", "))
    end)
end)
