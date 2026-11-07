-- Saved settings: bank alt per realm + faction (picked, or typed with a check),
-- the name history, steppers, the disenchant default that sticks once touched,
-- and everything surviving a /reload.
local loadAddon = require("spec.support.load_addon")

describe("config", function()
    local ns

    local function addChar(name, o)
        o = o or {}
        local realm, faction = o.realm or "Classic Beta PvP", o.faction or "Alliance"
        MailworthyDB.characters[ns.Characters.Key(name, realm, faction)] = {
            name = name, realm = realm, faction = faction, class = o.class or "WARRIOR", level = o.level or 8,
        }
    end

    before_each(function()
        ns = loadAddon()
        ns.Fire("PLAYER_LOGIN")
        addChar("Roknua Themicrulah")
        addChar("Horde Guy", { faction = "Horde" })
        addChar("Far Away", { realm = "Other Realm" })
    end)

    after_each(function() _G.DisenchantryDB = nil end)

    describe("server day", function()
        it("records when the realm was first seen, once, at login", function()
            local first = MailworthyDB.realms["Classic Beta PvP"].firstSeen
            assert.equal(WowStub.state.serverTime, first)
            WowStub.state.serverTime = WowStub.state.serverTime + 86400 * 3
            ns.Fire("PLAYER_LOGIN")
            assert.equal(first, ns.Config.FirstSeen(), "sticks")
            WowStub.state.realm = "Other Realm"
            assert.equal(WowStub.state.serverTime, ns.Config.FirstSeen(), "per realm")
        end)

        it("is the days since launch, or since the realm was first seen when that's earlier", function()
            local launch = ns.Valuation.LAUNCH_EPOCH
            MailworthyDB.realms["Classic Beta PvP"].firstSeen = launch
            WowStub.state.serverTime = launch + 5 * 86400 + 60
            assert.equal(5, ns.Config.ServerDay())
            MailworthyDB.realms["Classic Beta PvP"].firstSeen = launch - 30 * 86400
            assert.equal(35, ns.Config.ServerDay())
        end)

        it("falls back to the local clock when the server time is missing or fails", function()
            local saved = _G.GetServerTime
            _G.GetServerTime = nil
            assert.equal(ns.Valuation.ServerDay(os.time(), ns.Config.FirstSeen()), ns.Config.ServerDay())
            _G.GetServerTime = function() error("boom") end
            assert.is_number(ns.Config.ServerDay())
            _G.GetServerTime = saved
        end)
    end)

    describe("bank alt", function()
        it("offers known characters on this realm and faction only, not this character", function()
            local choices = ns.Config.Choices()
            assert.equal(1, #choices)
            assert.same({ name = "Roknua Themicrulah", known = true, class = "WARRIOR", level = 8 }, choices[1])
        end)

        it("is saved per realm + faction, with the known character's exact name", function()
            assert.is_nil(ns.Config.BankAlt())
            assert.equal("Roknua Themicrulah", ns.Config.SetBankAlt("  roknua   themicrulah "))
            assert.equal("Roknua Themicrulah", ns.Config.BankAlt())
            assert.equal("Roknua Themicrulah", MailworthyDB.bankAlts["Classic Beta PvP|Alliance"])
            WowStub.state.faction = "Horde"
            assert.is_nil(ns.Config.BankAlt(), "a Horde character has its own")
        end)

        it("keeps typed names in a history, offered after known characters, and can forget them", function()
            ns.Config.SetBankAlt("Newalt Somebody")
            assert.is_false(ns.Config.IsKnown("Newalt Somebody"))
            local choices = ns.Config.Choices()
            assert.equal("Roknua Themicrulah", choices[1].name)
            assert.same({ name = "Newalt Somebody", known = false }, choices[2])
            ns.Config.SetBankAlt("Roknua Themicrulah")
            assert.equal(2, #ns.Config.Choices(), "no duplicates")
            ns.Config.ForgetName("Newalt Somebody")
            assert.equal(1, #ns.Config.Choices())
            local log = table.concat(ns.Log.Lines(), "\n")
            assert.truthy(log:find("Newalt Somebody (not seen by Mailworthy)", 1, true))
        end)

        it("auto-completes from the choices, case-insensitive", function()
            local choices = ns.Config.Choices()
            assert.equal("Roknua Themicrulah", ns.Config.Complete("rok", choices))
            assert.equal("Roknua Themicrulah", ns.Config.Complete("Roknua T", choices))
            assert.is_nil(ns.Config.Complete("Zed", choices))
            assert.is_nil(ns.Config.Complete("  ", choices))
        end)

        it("ignores empty names", function()
            assert.is_nil(ns.Config.SetBankAlt("   "))
            assert.is_nil(ns.Config.SetBankAlt(nil))
            assert.is_nil(ns.Config.BankAlt())
        end)

        it("this character can declare itself the bank alt (a second WoW account), per realm + faction", function()
            assert.is_false(ns.Config.IsBankAltHere())
            assert.equal("Rettana Quilwrit", ns.Config.SetBankAltHere())
            assert.equal("Rettana Quilwrit", ns.Config.BankAlt())
            assert.equal("Rettana Quilwrit", MailworthyDB.bankAlts["Classic Beta PvP|Alliance"], "the same slot a pick uses")
            assert.is_true(ns.Config.IsBankAltHere())
            for _, c in ipairs(ns.Config.Choices()) do
                assert.not_equal("Rettana Quilwrit", c.name, "never offered to itself")
            end
            assert.equal(0, #MailworthyDB.names, "not in the typed-name history")
            local log = table.concat(ns.Log.Lines(), "\n")
            assert.truthy(log:find("bank alt for Classic Beta PvP|Alliance = Rettana Quilwrit (this character)", 1, true), log)
            WowStub.state.faction = "Horde"
            assert.is_nil(ns.Config.BankAlt(), "a Horde character has its own")
            assert.is_false(ns.Config.IsBankAltHere())
        end)

        it("clears the declared bank alt again, and a picked character is never 'here'", function()
            ns.Config.SetBankAltHere()
            ns.Config.ClearBankAlt()
            assert.is_nil(ns.Config.BankAlt())
            assert.is_false(ns.Config.IsBankAltHere())
            ns.Config.ClearBankAlt() -- nothing to clear: no error, no log line
            local cleared = 0
            for _, line in ipairs(ns.Log.Lines()) do
                if line:find("cleared", 1, true) then cleared = cleared + 1 end
            end
            assert.equal(1, cleared)
            ns.Config.SetBankAlt("Roknua Themicrulah")
            assert.is_false(ns.Config.IsBankAltHere())
            ns.Config.SetBankAltHere()
            assert.equal("Rettana Quilwrit", ns.Config.BankAlt(), "replaces the pick")
        end)
    end)

    describe("decision-rule settings", function()
        it("steps through fixed values from the nearest one", function()
            local steps = ns.Config.MIN_GAIN_STEPS
            assert.equal(1000, ns.Config.NextStep(steps, 500, 1))
            assert.equal(300, ns.Config.NextStep(steps, 500, -1))
            assert.equal(0, ns.Config.NextStep(steps, 0, -1), "stops at the ends")
            assert.equal(50000, ns.Config.NextStep(steps, 50000, 1))
            assert.equal(1000, ns.Config.NextStep(steps, 550, 1), "between steps: from the nearest")
            ns.Config.Step("minGain", 1)
            ns.Config.Step("minGainPct", -1)
            assert.equal(200, ns.Config.Get("minGain"), "one step up from the 1s default")
            assert.equal(0.2, ns.Config.Get("minGainPct"))
            assert.equal(200, ns.Bags.CurrentSettings().minGain, "the scan uses them")
        end)

        it("disenchant follows Disenchantry until the player sets it", function()
            assert.is_false(ns.Config.Get("disenchant"))
            _G.DisenchantryDB = {}
            assert.is_true(ns.Config.Get("disenchant"))
            ns.Config.Set("disenchant", false)
            assert.is_false(ns.Config.Get("disenchant"))
        end)

        it("ignores keys it doesn't know", function()
            ns.Config.Set("bogus", 1)
            assert.is_nil((MailworthyDB.settings or {}).bogus)
        end)
    end)

    it("everything survives a /reload (SavedVariables)", function()
        ns.Config.SetBankAlt("Roknua Themicrulah")
        ns.Config.Set("duration", 2)
        ns.Config.Set("minimapHidden", true)
        local saved = MailworthyDB
        local ns2 = loadAddon()
        _G.MailworthyDB = saved
        ns2.Init()
        assert.equal("Roknua Themicrulah", ns2.Config.BankAlt())
        assert.equal(2, ns2.Config.Get("duration"))
        assert.is_false(ns2.Config.MinimapShown())
    end)
end)
