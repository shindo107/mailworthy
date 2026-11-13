-- Mailworthy's own controller bindings: Triangle at a focused mail window; the
-- D-pad, Cross and Circle while the Mailworthy window is open; L3 in the bags.
-- Re-applied when Blizzard replaces them; cleared on focus loss and combat.
local loadAddon = require("spec.support.load_addon")

local function click(name) return "CLICK " .. name .. ":LeftButton" end

describe("controller bindings", function()
    local ns, watcher
    local function tick() watcher.scripts.OnUpdate(watcher, 0.2) end

    before_each(function()
        ns = loadAddon()
        WowStub.state.gamepadUI = true
        ns.Fire("PLAYER_LOGIN")
        ns.Config.SetBankAlt("Roknua Themicrulah")
        watcher = _G.MailworthyPadWatcher
        MailFrame:Show()
        SendMailFrame:Show()
    end)

    -- The watcher runs Check inside pcall and logs errors, so a failing Check
    -- doesn't fail a test by itself (alpha5 logged one ten times a second).
    after_each(function()
        for _, line in ipairs(ns.Log.Lines()) do
            assert.is_nil(line:find("check error", 1, true), line)
        end
    end)

    it("does nothing, and logs nothing, while nothing of ours is focused", function()
        for _ = 1, 5 do tick() end
        assert.same({}, WowStub.state.bindings)
        assert.equal(0, ns.PadKey.stats.applies)
    end)

    it("binds only Triangle while the mail window is focused", function()
        tick()
        assert.is_nil(WowStub.state.bindings.PAD4, "not focused yet")
        WowStub.state.activeFrame = MailFrame
        tick()
        assert.equal(click("MailworthyPadTriangle"), WowStub.state.bindings.PAD4)
        assert.is_nil(WowStub.state.bindings.PADDUP)
    end)

    it("with the window open: D-pad, Cross and Circle drive Mailworthy's navigation", function()
        WowStub.state.activeFrame = MailFrame
        tick()
        _G.MailworthyPadTriangle:Click()
        tick()
        local b = WowStub.state.bindings
        assert.equal(click("MailworthyPadUp"), b.PADDUP)
        assert.equal(click("MailworthyPadRight"), b.PADDRIGHT)
        assert.equal(click("MailworthyPadCross"), b.PAD1)
        assert.equal(click("MailworthyPadCircle"), b.PAD2)
        assert.truthy(ns.Nav.Current(), "the highlight starts on the top-left button")
        WowStub.state.now = WowStub.state.now + 1
        _G.MailworthyPadCircle:Click()
        assert.is_false(ns.MailWindow.Frame():IsShown())
        tick()
        assert.is_nil(b.PADDUP, "back to Triangle only")
        assert.equal(click("MailworthyPadTriangle"), b.PAD4)
    end)

    it("re-applies when Blizzard replaces a binding", function()
        WowStub.state.activeFrame = MailFrame
        tick()
        WowStub.state.bindings.PAD4 = ""
        tick()
        assert.equal(click("MailworthyPadTriangle"), WowStub.state.bindings.PAD4)
    end)

    it("L3 in the bags locks the selected item; bags keep their own Triangle", function()
        WowStub.setBag(0, 3, WowStub.item(2770, "Copper Ore", { count = 5 }))
        WowStub.state.activeFrame = ContainerFrameCombinedBags
        tick()
        assert.equal(click("MailworthyPadLock"), WowStub.state.bindings.PADLSTICK)
        assert.is_nil(WowStub.state.bindings.PAD4)
        WowStub.state.navButton = WowStub.itemButton(0, 3)
        _G.MailworthyPadLock:Click()
        assert.is_true(ns.Locks.IsItemLocked(2770))
    end)

    it("R3 in the bags pins the selected item for the bank; each stick has its own switch", function()
        WowStub.setBag(0, 3, WowStub.item(2770, "Copper Ore", { count = 5 }))
        WowStub.state.activeFrame = ContainerFrameCombinedBags
        tick()
        assert.equal(click("MailworthyPadPin"), WowStub.state.bindings.PADRSTICK)
        WowStub.state.navButton = WowStub.itemButton(0, 3)
        _G.MailworthyPadPin:Click()
        assert.equal("bank", ns.Pins.Kind(2770))
        assert.is_false(ns.Locks.IsItemLocked(2770), "a pin is not a lock")

        WowStub.state.activeFrame = nil
        tick()
        MailworthyDB.features.padPin = false
        WowStub.state.activeFrame = ContainerFrameCombinedBags
        tick()
        assert.is_nil(WowStub.state.bindings.PADRSTICK, "padPin off: R3 stays Blizzard's")
        assert.equal(click("MailworthyPadLock"), WowStub.state.bindings.PADLSTICK, "L3 still ours")

        WowStub.state.activeFrame = nil
        tick()
        MailworthyDB.features.padPin, MailworthyDB.features.padLock = true, false
        WowStub.state.activeFrame = ContainerFrameCombinedBags
        tick()
        assert.equal(click("MailworthyPadPin"), WowStub.state.bindings.PADRSTICK, "padLock off: R3 still ours")
        assert.is_nil(WowStub.state.bindings.PADLSTICK)
    end)

    it("Triangle at a focused merchant window opens the vendor window; its own switch gives the key back", function()
        MailFrame:Hide()
        SendMailFrame:Hide()
        MerchantFrame:Show()
        ns.Fire("MERCHANT_SHOW")
        WowStub.state.activeFrame = MerchantFrame
        tick()
        assert.equal(click("MailworthyPadVendor"), WowStub.state.bindings.PAD4)
        _G.MailworthyPadVendor:Click()
        assert.is_true(ns.Vendor.Frame():IsShown())
        tick()
        assert.equal(click("MailworthyPadCross"), WowStub.state.bindings.PAD1, "our window: the D-pad set")
        ns.Vendor.Frame():Hide()
        WowStub.state.activeFrame = nil
        tick()
        MailworthyDB.features.padVendor = false
        WowStub.state.activeFrame = MerchantFrame
        tick()
        assert.is_nil(WowStub.state.bindings.PAD4, "padVendor off: Triangle stays Blizzard's")
        MerchantFrame:Hide()
    end)

    it("lets go when nothing of ours is focused, at combat, and without the controller UI", function()
        WowStub.state.activeFrame = MailFrame
        tick()
        WowStub.state.activeFrame = nil
        tick()
        assert.is_nil(WowStub.state.bindings.PAD4)
        WowStub.state.activeFrame = MailFrame
        tick()
        WowStub.state.inCombat = true
        ns.Fire("PLAYER_REGEN_DISABLED")
        assert.is_nil(WowStub.state.bindings.PAD4, "cleared as combat starts")
        tick()
        assert.is_nil(WowStub.state.bindings.PAD4, "and not re-bound in combat")
        WowStub.state.inCombat = false
        WowStub.state.gamepadUI = false
        tick()
        assert.is_nil(WowStub.state.bindings.PAD4)
    end)

    it("one press delivered as down + up counts once", function()
        WowStub.state.activeFrame = MailFrame
        local b = _G.MailworthyPadTriangle
        b.scripts.OnClick(b, "LeftButton", true)
        b.scripts.OnClick(b, "LeftButton", false)
        assert.is_true(ns.MailWindow.Frame():IsShown())
        assert.equal(1, ns.PadKey.stats.presses)
    end)
end)

describe("controller highlight across windows", function()
    local ns, watcher
    local function tick() watcher.scripts.OnUpdate(watcher, 0.2) end
    local function press(button)
        ns.Nav.Select(button)
        WowStub.state.now = WowStub.state.now + 1
        _G.MailworthyPadCross:Click()
        tick()
    end

    before_each(function()
        ns = loadAddon()
        _G.Minimap = WowStub.newWidget("Frame", "Minimap")
        WowStub.state.gamepadUI = true
        ns.Fire("PLAYER_LOGIN")
        ns.Config.SetBankAlt("Roknua Themicrulah")
        watcher = _G.MailworthyPadWatcher
        MailFrame:Show()
        SendMailFrame:Show()
        WowStub.state.activeFrame = MailFrame
        tick()
        WowStub.state.now = WowStub.state.now + 1
        _G.MailworthyPadTriangle:Click()
        tick()
    end)

    after_each(function()
        _G.Minimap = nil
        for _, line in ipairs(ns.Log.Lines()) do assert.is_nil(line:find("error", 1, true), line) end
    end)

    -- Before: the highlight stayed on the window below and the first D-pad press only moved it.
    it("moves to the window opened on top, and back to the opener's button when it closes", function()
        local mailHighlight = _G.MailworthyMailWindowNavHighlight
        press(_G.MailworthyMailSettings)
        assert.equal(MailworthySettingsFrame, ns.Nav.Root())
        assert.is_true(ns.Nav.Current():IsVisible())
        local onSettings = false
        for _, c in ipairs(ns.Nav.Candidates()) do onSettings = onSettings or c.button == ns.Nav.Current() end
        assert.is_true(onSettings, "on a settings button at once, before any D-pad press")
        assert.is_true(_G.MailworthySettingsFrameNavHighlight:IsShown())
        assert.is_false(mailHighlight:IsShown(), "no highlight left on the window below")
        MailworthySettingsFrame:Hide() -- closed by mouse or Escape: no press of ours
        tick()
        assert.equal(_G.MailworthyMailSettings, ns.Nav.Current(), "back on the button that opened it")
        assert.is_true(mailHighlight:IsShown())
        press(_G.MailworthyMailSettings)
        WowStub.state.now = WowStub.state.now + 1
        _G.MailworthyPadCircle:Click()
        assert.equal(_G.MailworthyMailSettings, ns.Nav.Current(), "Circle returns there too")
        local follows, returns = ns.PadKey.Report():match("highlight followed (%d+) window change%(s%), (%d+) back to the")
        assert.truthy(tonumber(follows) >= 3 and tonumber(returns) >= 2, ns.PadKey.Report())
    end)

    it("a window shown again starts at its top-left button", function()
        press(_G.MailworthyMailSettings)
        MailworthySettingsFrame:Hide()
        tick()
        ns.MailWindow.Frame():Hide()
        tick()
        WowStub.state.now = WowStub.state.now + 1
        _G.MailworthyPadTriangle:Click()
        tick()
        local top = ns.Nav.TopLeft(ns.Nav.Candidates())
        assert.equal(top.button, ns.Nav.Current())
    end)

    it("lets go of Cross and the D-pad when the interface is hidden (Alt+Z), then takes them back", function()
        assert.equal("CLICK MailworthyPadCross:LeftButton", WowStub.state.bindings.PAD1)
        watcher.scripts.OnHide(watcher)
        assert.is_nil(WowStub.state.bindings.PAD1, "Cross jumps again")
        assert.is_nil(WowStub.state.bindings.PADDUP)
        tick()
        assert.equal("CLICK MailworthyPadCross:LeftButton", WowStub.state.bindings.PAD1, "shown again: back")
    end)
end)
