-- The settings window: every control is a button (mouse click or controller
-- Cross), the typed name is an optional fallback with a check, and the
-- controller drives it with Mailworthy's own bindings wherever it's open.
local loadAddon = require("spec.support.load_addon")

local function click(name) return "CLICK " .. name .. ":LeftButton" end

describe("settings window", function()
    local ns, watcher, box
    local function tick() watcher.scripts.OnUpdate(watcher, 0.2) end
    local function type_(text)
        box:SetText(text)
        box.scripts.OnTextChanged(box, true)
    end
    local function hint() return table.concat(WowStub.printed, "\n") end

    before_each(function()
        ns = loadAddon()
        _G.Minimap = WowStub.newWidget("Frame", "Minimap")
        ns.Fire("PLAYER_LOGIN")
        MailworthyDB.characters[ns.Characters.Key("Roknua Themicrulah", "Classic Beta PvP", "Alliance")] = {
            name = "Roknua Themicrulah", realm = "Classic Beta PvP", faction = "Alliance", class = "WARRIOR", level = 8,
        }
        watcher = _G.MailworthyPadWatcher
        box = _G.MailworthySettingsName
        ns.SettingsUI.Show()
    end)

    after_each(function()
        _G.Minimap = nil
        for _, line in ipairs(ns.Log.Lines()) do assert.is_nil(line:find("error", 1, true), line) end
        assert.equal(0, WowStub.focusCalls, "never moves keyboard focus")
    end)

    it("lists known characters as buttons; pressing one saves the bank alt", function()
        -- A bank alt is optional (operator, 2026-11-08): the settings open first, Choose... picks one.
        assert.equal("main", ns.SettingsUI.View(), "no bank alt yet: still the settings")
        assert.equal("Choose...", _G.MailworthySettingsChange:GetText())
        _G.MailworthySettingsChange:Click()
        assert.truthy(_G.MailworthySettingsChoice1:GetText():find("Roknua Themicrulah", 1, true))
        assert.is_false(_G.MailworthySettingsChoice2:IsShown())
        assert.is_false(_G.MailworthySettingsForget1:IsShown(), "known characters can't be forgotten")
        _G.MailworthySettingsChoice1:Click()
        assert.equal("Roknua Themicrulah", ns.Config.BankAlt())
        assert.truthy(hint():find("Bank alt: Roknua Themicrulah", 1, true))
        assert.equal("main", ns.SettingsUI.View(), "a pick returns to the settings")
        assert.is_false(_G.MailworthySettingsChoice1:IsShown())
        assert.truthy(_G.MailworthySettingsChange:IsShown())
        _G.MailworthySettingsChange:Click()
        assert.equal("pick", ns.SettingsUI.View())
        assert.truthy(_G.MailworthySettingsChoice1:GetText():find("> Roknua", 1, true), "marked as chosen")
        _G.MailworthySettingsBack:Click()
        assert.equal("main", ns.SettingsUI.View())
        assert.equal("Roknua Themicrulah", ns.Config.BankAlt(), "Back changes nothing")
    end)

    it("opens on the settings once a bank alt is set; the bank alt row names it", function()
        ns.Config.SetBankAlt("Roknua Themicrulah")
        MailworthySettingsFrame:Hide()
        ns.SettingsUI.Show()
        assert.equal("main", ns.SettingsUI.View())
        assert.equal("|cff33ff99Roknua Themicrulah|r  |cffaaaaaawarrior 8|r",
            ns.SettingsUI.BankAltText("Roknua Themicrulah", false, ns.Config.Choices()))
        assert.truthy(ns.SettingsUI.BankAltText(nil):find("None: what's worth selling stays in your bags", 1, true))
        assert.is_false(_G.MailworthySettingsHere:IsShown(), "the picker's buttons are hidden")
        assert.is_false(_G.MailworthySettingsName:IsShown())
    end)

    it("typed name: completes from known characters", function()
        type_("rok")
        _G.MailworthySettingsUseName:Click()
        assert.equal("Roknua Themicrulah", ns.Config.BankAlt())
        assert.equal("", box:GetText())
    end)

    it("typed name Mailworthy hasn't seen: a second press saves it, and it can be forgotten", function()
        type_("Newalt Somebody")
        _G.MailworthySettingsUseName:Click()
        assert.is_nil(ns.Config.BankAlt(), "first press only warns")
        _G.MailworthySettingsUseName:Click()
        assert.equal("Newalt Somebody", ns.Config.BankAlt())
        assert.equal("main", ns.SettingsUI.View())
        _G.MailworthySettingsChange:Click()
        assert.truthy(_G.MailworthySettingsChoice2:GetText():find("(not seen)", 1, true))
        assert.is_true(_G.MailworthySettingsForget2:IsShown())
        _G.MailworthySettingsForget2:Click()
        assert.is_false(_G.MailworthySettingsChoice2:IsShown())
    end)

    it("won't save this character or an empty name; a typed own name points at the button", function()
        type_("Rettana Quilwrit")
        _G.MailworthySettingsUseName:Click()
        _G.MailworthySettingsUseName:Click()
        assert.truthy(_G.MailworthySettingsName:GetText() ~= "", "the typed name stays")
        type_("  ")
        _G.MailworthySettingsUseName:Click()
        assert.is_nil(ns.Config.BankAlt())
    end)

    it("'This character is my bank alt' (a bank alt on a second WoW account) saves this character; again clears it",
        function()
            local here = _G.MailworthySettingsHere
            assert.equal("This character is my bank alt", here:GetText())
            here:Click()
            assert.equal("Rettana Quilwrit", ns.Config.BankAlt())
            assert.is_true(ns.BankAlt.IsBankAlt())
            assert.equal("bankalt", ns.BankAlt.Mode(), "no 'tags everywhere' needed")
            assert.equal("main", ns.SettingsUI.View())
            assert.truthy(ns.SettingsUI.BankAltText("Rettana Quilwrit", true, {}):find("this character", 1, true))
            _G.MailworthySettingsChange:Click()
            assert.truthy(here:GetText():find("> This character is my bank alt <", 1, true), "marked as chosen")
            assert.truthy(hint():find("Bank alt: Rettana Quilwrit (this character)", 1, true), hint())
            assert.is_false(_G.MailworthySettingsChoice1:GetText():find("> Roknua", 1, true) ~= nil)
            assert.equal("this character is the bank alt", ns.Mailer.Blocker(ns.Config.BankAlt(), {}),
                "the Mailworthy window still refuses to mail to itself")
            here:Click()
            assert.is_nil(ns.Config.BankAlt())
            assert.is_false(ns.BankAlt.IsBankAlt())
            assert.equal("This character is my bank alt", here:GetText())
            assert.truthy(hint():find("No bank alt set on this realm and faction any more.", 1, true))
            -- Picking another character afterwards works as before.
            _G.MailworthySettingsChoice1:Click()
            assert.equal("Roknua Themicrulah", ns.Config.BankAlt())
            assert.equal("This character is my bank alt", here:GetText())
        end)

    it("steppers, disenchant, listing length and the minimap button", function()
        ns.Config.SetBankAlt("Roknua Themicrulah")
        ns.SettingsUI.Show()
        assert.is_true(_G.MailworthySettingsAmountUp:IsShown())
        _G.MailworthySettingsAmountUp:Click()
        _G.MailworthySettingsPercentDown:Click()
        _G.MailworthySettingsDisenchant:Click()
        _G.MailworthySettingsDuration2:Click()
        local v = ns.Config.Values()
        assert.equal(200, v.minGain, "one step up from the 1s default")
        assert.equal(0.2, v.minGainPct)
        assert.is_true(v.disenchant)
        assert.equal(2, v.duration)
        assert.truthy(_G.MailworthySettingsDuration2:GetText():find("> 8h <", 1, true))
        assert.is_true(MailworthyMinimapButton:IsShown())
        _G.MailworthySettingsMinimap:Click()
        assert.is_false(MailworthyMinimapButton:IsShown())
        assert.equal("Minimap button: hidden", _G.MailworthySettingsMinimap:GetText())
        assert.equal("Lock glow: in Mailworthy", _G.MailworthySettingsGlow:GetText())
        _G.MailworthySettingsGlow:Click()
        assert.is_true(ns.Config.Flag("glowEverywhere"))
        assert.equal("Lock glow: always", _G.MailworthySettingsGlow:GetText())
        assert.equal("Keep my professions' materials: on (no crafting profession here)", _G.MailworthySettingsMats:GetText())
        WowStub.state.professions[2] = { index = 9, name = "Enchanting", rank = 1, maxRank = 75, skillLine = 333 }
        _G.MailworthySettingsMats:Click()
        assert.is_false(ns.Config.Get("keepProfessionMats"))
        assert.equal("Keep my professions' materials: off (Enchanting 1)",
            _G.MailworthySettingsMats:GetText())
        assert.equal("Sell what I gather: off (Mining)", _G.MailworthySettingsGather:GetText(), "the stub character mines")
        _G.MailworthySettingsGather:Click()
        assert.is_true(ns.Config.Get("sellGathered"))
        assert.equal("Sell what I gather: on (Mining)", _G.MailworthySettingsGather:GetText())
    end)

    it("the minimap button toggles the window", function()
        MailworthySettingsFrame:Hide()
        MailworthyMinimapButton:Click()
        assert.is_true(MailworthySettingsFrame:IsShown())
        MailworthyMinimapButton:Click()
        assert.is_false(MailworthySettingsFrame:IsShown())
    end)

    describe("controller", function()
        before_each(function() WowStub.state.gamepadUI = true end)

        it("binds the D-pad, Cross and Circle while it's open, with no Blizzard window focused", function()
            _G.MailworthySettingsChange:Click() -- Choose...: the picker
            WowStub.state.activeFrame = nil
            tick()
            local b = WowStub.state.bindings
            assert.equal(click("MailworthyPadCross"), b.PAD1)
            assert.equal(click("MailworthyPadCircle"), b.PAD2)
            assert.equal(click("MailworthyPadDown"), b.PADDDOWN)
            assert.is_nil(b.PAD4, "Triangle stays the game's")
            assert.truthy(ns.Nav.Current(), "the highlight starts on a settings button")
            local function reachable(button)
                for _, c in ipairs(ns.Nav.Candidates()) do
                    if c.button == button then return true end
                end
                return false
            end
            assert.is_true(reachable(_G.MailworthySettingsHere), "the D-pad reaches 'This character is my bank alt'")
            assert.is_false(reachable(_G.MailworthySettingsDuration1), "the settings wait behind the picker")
            ns.Nav.Select(_G.MailworthySettingsHere)
            WowStub.state.now = WowStub.state.now + 1
            _G.MailworthyPadCross:Click()
            assert.equal("Rettana Quilwrit", ns.Config.BankAlt(), "Cross declares this character the bank alt")
            assert.equal("main", ns.SettingsUI.View())
            assert.truthy(ns.Nav.Current():IsVisible(), "the highlight moved to a button that still shows")
            assert.is_true(reachable(_G.MailworthySettingsDuration1))
            assert.is_true(reachable(_G.MailworthySettingsChange))
            ns.Nav.Select(_G.MailworthySettingsDuration1)
            WowStub.state.now = WowStub.state.now + 1
            _G.MailworthyPadCross:Click()
            assert.equal(1, ns.Config.Get("duration"))
            WowStub.state.now = WowStub.state.now + 1
            _G.MailworthyPadCircle:Click()
            assert.is_false(MailworthySettingsFrame:IsShown())
            tick()
            assert.is_nil(b.PAD1, "bindings go when it closes")
        end)

        it("lets go in combat", function()
            tick()
            WowStub.state.inCombat = true
            ns.Fire("PLAYER_REGEN_DISABLED")
            tick()
            assert.is_nil(WowStub.state.bindings.PAD1)
        end)

        it("over the Mailworthy window at the mailbox: Circle closes settings, then the window takes over", function()
            MailFrame:Show()
            SendMailFrame:Show()
            WowStub.state.activeFrame = MailFrame
            MailworthySettingsFrame:Hide()
            ns.MailWindow.Show("send")
            tick()
            WowStub.state.now = WowStub.state.now + 1
            _G.MailworthyMailSettings:Click()
            assert.is_true(MailworthySettingsFrame:IsShown())
            assert.equal(MailworthySettingsFrame, ns.Nav.Root())
            tick()
            assert.is_nil(WowStub.state.bindings.PAD4, "settings set: no Triangle")
            _G.MailworthyPadCircle:Click()
            assert.is_false(MailworthySettingsFrame:IsShown())
            assert.is_true(ns.MailWindow.Frame():IsShown(), "only the top window closes")
            tick()
            assert.equal(click("MailworthyPadTriangle"), WowStub.state.bindings.PAD4)
            assert.equal(ns.MailWindow.Frame(), ns.Nav.Root())
        end)
    end)
end)
