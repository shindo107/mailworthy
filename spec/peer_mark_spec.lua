-- The Mailworthy mark (operator, 2026-11-08: "i want an a mailworthy icon or some sort of
-- indicator on the mailworth ui when a player's name is mentioned showing if they have
-- mailworthy as well"): wherever Mailworthy's own windows name a player, the addon's icon
-- follows the name when that player runs Mailworthy (heard from over Comms, a character their
-- hello listed, or one of this account's own characters), and the window's footer says what the
-- icon means, so nothing depends on hovering. Switch: /mw feature peerMark off.
local loadAddon = require("spec.support.load_addon")

describe("Mailworthy mark", function()
    local ns, prices
    local BOB, ALICE, STRANGER, BANK = "Bob Surname", "Alice Alt", "Zed Stranger", "Roknua Themicrulah"
    local ENCHANTING = 333

    local function hello(sender, text) ns.Fire("CHAT_MSG_ADDON", "Mailworthy", text, "GUILD", sender) end
    local function marked(text) return tostring(text):find(ns.Comms.MARK, 1, true) ~= nil end
    local function knowCharacter(name)
        MailworthyDB.characters[ns.Characters.Key(name, "Classic Beta PvP", "Alliance")] = {
            name = name, realm = "Classic Beta PvP", faction = "Alliance", class = "WARRIOR", level = 8,
        }
    end

    before_each(function()
        ns = loadAddon()
        _G.Minimap = WowStub.newWidget("Frame", "Minimap")
        ns.Fire("PLAYER_LOGIN")
        WowStub.state.guild = { clubId = 3, members = {
            { name = BOB, level = 30, online = true, professions = { ENCHANTING } },
            { name = STRANGER, level = 20, online = true },
        } }
        hello(BOB .. "-Classic Beta PvP", "H2|333|" .. ALICE .. "=165")
    end)
    after_each(function()
        _G.Minimap = nil
        _G.Auctionator = nil
        for _, line in ipairs(ns.Log.Lines()) do assert.is_nil(line:find("error", 1, true), line) end
        assert.equal(0, WowStub.focusCalls)
    end)

    describe("who runs Mailworthy", function()
        it("a player heard from, a character their hello listed, this account's characters, this one", function()
            assert.is_true(ns.Comms.Runs(BOB))
            assert.is_true(ns.Comms.Runs("bob surname-Classic Beta PvP"), "realm suffix and case don't matter")
            assert.is_true(ns.Comms.Runs(ALICE), "Bob's hello lists Alice Alt as his")
            assert.is_false(ns.Comms.Runs(STRANGER), "a guild member never heard from")
            assert.is_false(ns.Comms.Runs(BANK))
            knowCharacter(BANK)
            assert.is_true(ns.Comms.Runs(BANK), "Mailworthy recorded it: one of this account's characters")
            assert.is_true(ns.Comms.Runs(ns.PlayerName()))
            assert.is_false(ns.Comms.Runs(nil))
            assert.is_false(ns.Comms.Runs(""))
        end)

        it("forgets a peer with the peers (60 days)", function()
            ns.Comms.Prune(WowStub.state.serverTime + 61 * 86400)
            assert.is_false(ns.Comms.Runs(BOB))
            assert.is_false(ns.Comms.Runs(ALICE))
        end)

        it("the mark goes after the text shown, and says whether it was added", function()
            local text, m = ns.Comms.Mark(BOB)
            assert.equal(BOB .. " " .. ns.Comms.MARK, text)
            assert.is_true(m)
            text = ns.Comms.Mark(BOB, "Bob")
            assert.equal("Bob " .. ns.Comms.MARK, text, "a first name shown, the full name looked up")
            assert.same({ STRANGER, false }, { ns.Comms.Mark(STRANGER) })
            assert.truthy(ns.Comms.MARK:find("Interface\\AddOns\\Mailworthy\\Textures\\Icon", 1, true))
            assert.equal(ns.Comms.MARK .. " runs Mailworthy", ns.Comms.MARK_KEY)
        end)

        it("/mw feature peerMark off: no mark anywhere", function()
            MailworthyDB.features.peerMark = false
            assert.same({ BOB, false }, { ns.Comms.Mark(BOB) })
        end)

        it("the footer: the key while a mark shows, the controller legend with a controller", function()
            assert.equal("", ns.Widgets.Footer(false, false))
            assert.equal(ns.Comms.MARK_KEY, ns.Widgets.Footer(false, true))
            assert.equal(ns.Widgets.Legend(), ns.Widgets.Footer(true, false))
            assert.equal(ns.Comms.MARK_KEY .. "\n" .. ns.Widgets.Legend(), ns.Widgets.Footer(true, true, "\n"))
        end)
    end)

    describe("friends and guild window", function()
        it("the add list marks Mailworthy users only, and the footer explains the mark", function()
            ns.RoutesUI.Show()
            assert.equal("add", ns.RoutesUI.View())
            local bob, stranger
            for i = 1, ns.RoutesUI.CANDIDATE_ROWS do
                local b = _G["MailworthyFriendsPick" .. i]
                local text = b:IsShown() and b:GetText() or ""
                if text:find(BOB, 1, true) then bob = text end
                if text:find(STRANGER, 1, true) then stranger = text end
            end
            assert.truthy(bob and bob:find(BOB .. " " .. ns.Comms.MARK .. " - Enchanting", 1, true), bob)
            assert.is_false(marked(stranger), stranger)
            assert.equal(ns.Comms.MARK_KEY, ns.RoutesUI.Footer())
        end)

        it("step 2 names the picked player with the mark", function()
            ns.RoutesUI.Show()
            for i = 1, ns.RoutesUI.CANDIDATE_ROWS do
                local b = _G["MailworthyFriendsPick" .. i]
                if b:IsShown() and b:GetText():find(BOB, 1, true) then b:Click() break end
            end
            assert.equal(BOB, ns.RoutesUI.Picked().name)
            assert.is_true(marked(ns.RoutesUI.ChosenLabel():GetText()))
        end)

        it("a binding row marks its player; none marked, no key", function()
            ns.Routes.Add(STRANGER, ENCHANTING)
            ns.RoutesUI.Show()
            assert.equal("list", ns.RoutesUI.View())
            assert.is_false(ns.RoutesUI.Marked())
            assert.equal("", ns.RoutesUI.Footer())
            ns.Routes.Add(BOB, 197)
            ns.RoutesUI.Refresh()
            assert.is_true(ns.RoutesUI.Marked())
            assert.equal(ns.Comms.MARK_KEY, ns.RoutesUI.Footer())
        end)

        it("the guild template line marks its author", function()
            ns.Guild.On = function() return true end
            ns.Guild.Mine = function() return "Guildies" end
            ns.Guild.CanPublish = function() return false end
            ns.Guild.Template = function()
                return { rev = 1, from = BOB, rules = { { profession = ENCHANTING, to = STRANGER, key = "guild|333" } } }
            end
            ns.RoutesUI.ShowGuild()
            assert.equal("guild", ns.RoutesUI.View())
            assert.is_true(ns.RoutesUI.Marked(), "Bob published it")
            assert.equal(ns.Comms.MARK_KEY, ns.RoutesUI.Footer())
            local text = ns.RoutesUI.GuildText(ns.Guild.Template(), false, ns.Comms.Mark(BOB))
            assert.truthy(text:find("Guild template from " .. BOB .. " " .. ns.Comms.MARK .. ": 1 rule", 1, true), text)
            assert.truthy(ns.RoutesUI.GuildText(ns.Guild.Template(), false):find("from " .. BOB .. ": 1 rule", 1, true),
                "without a text for the author: the name as before")
        end)
    end)

    describe("mailbox window", function()
        local function dust(count)
            return WowStub.item(10940, "Strange Dust", { count = count or 20, sell = 2, class = 7, subclass = 12 })
        end
        before_each(function()
            ns.Config.SetBankAlt(BANK)
            prices = {}
            _G.Auctionator = { API = { v1 = {
                GetAuctionPriceByItemLink = function(_, l) return prices[l] end,
                GetAuctionAgeByItemLink = function() return 0 end,
            } } }
            WowStub.setBag(0, 1, WowStub.item(2770, "Copper Ore", { count = 20, sell = 5 }))
            prices[WowStub.link(2770, "Copper Ore")] = 174
            MailFrame:Show()
            SendMailFrame:Show()
        end)

        it("the bank alt's To line is marked once Mailworthy knows it; the footer explains it", function()
            _G.MailworthyMailButton:Click()
            assert.equal("|cffffd100To:|r " .. BANK, ns.MailWindow.Texts().to[1], "not known: no mark")
            assert.equal("", ns.MailWindow.Footer())
            knowCharacter(BANK)
            ns.MailWindow.Refresh()
            assert.equal("|cffffd100To:|r " .. BANK .. " " .. ns.Comms.MARK, ns.MailWindow.Texts().to[1])
            assert.equal(ns.Comms.MARK_KEY, ns.MailWindow.Footer())
        end)

        it("a binding's recipient line is marked; the no-bank-alt line never is", function()
            ns.Config.ClearBankAlt()
            _G.MailworthyMailButton:Click()
            local to = ns.MailWindow.Texts().to
            assert.truthy(to[1]:find("No bank alt", 1, true), to[1])
            assert.is_false(marked(to[1]), to[1])
            assert.equal("", ns.MailWindow.Footer())
            ns.Routes.Add(BOB, ENCHANTING)
            WowStub.setBag(0, 2, dust())
            prices[WowStub.link(10940, "Strange Dust")] = 30
            ns.MailWindow.Refresh()
            to = ns.MailWindow.Texts().to
            local bobLine
            for _, line in ipairs(to) do if line:find(BOB, 1, true) then bobLine = line end end
            assert.truthy(bobLine and bobLine:find(BOB .. " " .. ns.Comms.MARK, 1, true), table.concat(to, " / "))
            assert.equal(ns.Comms.MARK_KEY, ns.MailWindow.Footer())
        end)

        it("a binding row delivered to the friend's crafter marks both: the crafter and the friend", function()
            ns.Routes.Add(BOB, 165) -- Leatherworking: Bob's hello says Alice Alt has it
            _G.MailworthyMailButton:Click()
            local line = ns.MailWindow.RouteLine(1)
            assert.truthy(line:find("to Alice " .. ns.Comms.MARK, 1, true), line)
            assert.truthy(line:find("Bob's crafter " .. ns.Comms.MARK, 1, true), line)
        end)

        it("with a controller the key and the legend stack", function()
            knowCharacter(BANK)
            ns.MailButton.GamepadUI = function() return true end
            _G.MailworthyMailButton:Click()
            assert.equal(ns.Comms.MARK_KEY .. "\n" .. ns.Widgets.Legend(), ns.MailWindow.Footer())
        end)
    end)

    describe("a hello while a window is open", function()
        local CAROL = "Carol Late"
        local function heard()
            hello(CAROL, "H2|197|")
            WowStub.runTimers(ns.Comms.MARK_DELAY)
        end

        it("the friends window's binding rows pick up the mark", function()
            ns.Routes.Add(CAROL, ENCHANTING)
            ns.RoutesUI.Show()
            assert.equal("list", ns.RoutesUI.View())
            assert.is_false(ns.RoutesUI.Marked())
            heard()
            assert.is_true(ns.RoutesUI.Marked())
            assert.equal(ns.Comms.MARK_KEY, ns.RoutesUI.Footer())
        end)

        it("the settings picker and the ledger pick it up", function()
            ns.Config.SetBankAlt(CAROL)
            ns.SettingsUI.Show()
            assert.equal("", ns.SettingsUI.Footer())
            ns.Ledger.Debts = function() return { { name = CAROL, net = 1000, items = "", gold = 0 } } end
            ns.LedgerUI.Show()
            assert.is_false(marked(ns.LedgerUI.RowLine(1)))
            heard()
            assert.equal(ns.Comms.MARK_KEY, ns.SettingsUI.Footer())
            assert.is_true(marked(ns.LedgerUI.RowLine(1)))
        end)

        it("the mailbox window redraws from the scan on screen", function()
            ns.Config.SetBankAlt(CAROL)
            WowStub.setBag(0, 1, WowStub.item(2589, "Linen Cloth", { count = 20, sell = 10 }))
            MailFrame:Show()
            SendMailFrame:Show()
            _G.MailworthyMailButton:Click()
            local before = ns.MailWindow.Result()
            assert.is_false(marked(ns.MailWindow.Texts().to[1]))
            heard()
            assert.is_true(marked(ns.MailWindow.Texts().to[1]), ns.MailWindow.Texts().to[1])
            assert.equal(before, ns.MailWindow.Result(), "no new scan: the list shown stays the list sent")
        end)

        it("one redraw per burst, none for a peer already known or a message that names nobody new", function()
            WowStub.runTimers(ns.Comms.MARK_DELAY) -- Bob's first hello (before_each)
            local redraws = 0
            ns.Comms.OnMarksChanged(function() redraws = redraws + 1 end)
            hello(BOB, "H2|333|" .. ALICE .. "=165") -- known: same names
            hello(BOB, "A2")
            hello(BOB, "Q2|0")
            WowStub.runTimers(ns.Comms.MARK_DELAY)
            assert.equal(0, redraws)
            hello(CAROL, "H2|197|")
            hello("Dan New", "H2|197|")
            hello(BOB, "H2|333|" .. ALICE .. "=165;Eve Alt=197") -- a new character of Bob's
            assert.equal(0, redraws, "not before the timer")
            WowStub.runTimers(ns.Comms.MARK_DELAY)
            assert.equal(1, redraws)
            assert.is_true(ns.Comms.Runs("Eve Alt"))
        end)
    end)

    describe("ledger and settings", function()
        it("a ledger row marks the player", function()
            ns.Ledger.Debts = function()
                return { { name = BOB, net = 1000, items = "20 Linen Cloth", gold = 0 },
                    { name = STRANGER, net = 500, items = "5 Linen Cloth", gold = 0 } }
            end
            ns.LedgerUI.Show()
            assert.truthy(ns.LedgerUI.RowLine(1):find("|cffffd100" .. BOB .. " " .. ns.Comms.MARK .. "|r: 10s", 1, true),
                ns.LedgerUI.RowLine(1))
            assert.is_false(marked(ns.LedgerUI.RowLine(2)))
            assert.equal(ns.Comms.MARK_KEY, ns.LedgerUI.Footer())
            assert.equal("|cffffd100" .. BOB .. "|r: 10s more than you've sent back",
                (ns.LedgerUI.RowText({ name = BOB, net = 1000, items = "" })), "pure, without a name text: as before")
        end)

        it("the settings' bank alt row and picker mark known Mailworthy characters", function()
            knowCharacter(BANK)
            ns.Config.SetBankAlt(BANK)
            ns.SettingsUI.Show()
            assert.equal("main", ns.SettingsUI.View())
            assert.equal(ns.Comms.MARK_KEY, ns.SettingsUI.Footer())
            assert.truthy(ns.SettingsUI.BankAltText(BANK, false, ns.Config.Choices(), ns.Comms.MARK)
                :find(BANK .. "|r " .. ns.Comms.MARK, 1, true))
            _G.MailworthySettingsChange:Click()
            assert.equal("pick", ns.SettingsUI.View())
            assert.is_true(marked(_G.MailworthySettingsChoice1:GetText()), _G.MailworthySettingsChoice1:GetText())
            assert.equal(ns.Comms.MARK_KEY, ns.SettingsUI.Footer())
        end)

        it("no bank alt: nothing marked, no key", function()
            ns.SettingsUI.Show()
            assert.equal("", ns.SettingsUI.Footer())
        end)
    end)
end)
