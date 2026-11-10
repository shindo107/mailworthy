-- The locked items window (LocksUI.lua; QoL pass D, 2026-11-09): /mw locks and Settings > More
-- open it; one row per locked item with how many the bags hold, and Unlock, by mouse and by
-- controller; a lock on an item that is no longer in the bags can be removed there (the only
-- place: Alt+click and the controller's lock key need the item in a bag slot).
local loadAddon = require("spec.support.load_addon")

describe("the locked items window", function()
    local ns, watcher
    local function tick() watcher.scripts.OnUpdate(watcher, 0.2) end
    local function lock(id, name) MailworthyCharDB.lockedItems[id] = { link = WowStub.link(id, name), at = 1 } end

    before_each(function()
        ns = loadAddon()
        ns.Fire("PLAYER_LOGIN")
        watcher = _G.MailworthyPadWatcher
        WowStub.setBag(0, 3, WowStub.item(2770, "Copper Ore", { count = 5 }))
        WowStub.setBag(1, 2, WowStub.item(2770, "Copper Ore", { count = 4 }))
        lock(2770, "Copper Ore")
        lock(4338, "Mageweave Cloth") -- banked: not in the bags
    end)

    after_each(function()
        for _, line in ipairs(ns.Log.Lines()) do assert.is_nil(line:find("error", 1, true), line) end
        assert.equal(0, WowStub.focusCalls)
    end)

    it("/mw locks opens it: a row per locked item, by name, with what the bags hold", function()
        ns.HandleSlash("locks")
        assert.is_true(ns.LocksUI.Frame():IsShown())
        assert.equal(WowStub.link(2770, "Copper Ore") .. "  |cffaaaaaax9 in your bags|r", ns.LocksUI.RowLine(1))
        assert.equal(WowStub.link(4338, "Mageweave Cloth") .. "  |cffff8040not in your bags|r", ns.LocksUI.RowLine(2))
        assert.is_nil(ns.LocksUI.RowLine(3))
        assert.equal("Unlock", _G.MailworthyLocksUnlock1:GetText())
        assert.is_false(_G.MailworthyLocksUnlock3:IsShown())
        assert.is_false(_G.MailworthyLocksPage:IsShown(), "one page: no pager")
    end)

    it("a lock on an item that is not in the bags can be removed (mouse)", function()
        ns.HandleSlash("locks")
        assert.equal(0, ns.LocksUI.List()[2].count)
        _G.MailworthyLocksUnlock2:Click()
        assert.is_false(ns.Locks.IsItemLocked(4338))
        assert.is_nil(MailworthyCharDB.lockedItems[4338])
        assert.is_true(ns.Locks.IsItemLocked(2770), "the other lock stays")
    end)

    it("a lock on an item that is not in the bags can be removed (controller: D-pad and Cross)", function()
        WowStub.state.gamepadUI = true
        WowStub.state.layout = true -- real positions: the D-pad's direction search runs over them
        ns.HandleSlash("locks")
        tick()
        assert.equal("settings", ns.PadKey.Wanted(), "the window takes the controller like the others")
        for _ = 1, 2 do -- from the top (the X): the first row, then the second
            WowStub.state.now = WowStub.state.now + 1
            _G.MailworthyPadDown:Click()
        end
        assert.equal(_G.MailworthyLocksUnlock2, ns.Nav.Current())
        WowStub.state.now = WowStub.state.now + 1
        _G.MailworthyPadCross:Click()
        assert.is_false(ns.Locks.IsItemLocked(4338))
        assert.equal(_G.MailworthyLocksUnlock2, ns.Nav.Current(), "the highlight stays on the row")
        WowStub.state.now = WowStub.state.now + 1
        _G.MailworthyPadCircle:Click()
        assert.is_false(ns.LocksUI.Frame():IsShown(), "Circle closes it")
    end)

    it("an unlocked row stays until the window closes, and Lock puts the lock back", function()
        ns.HandleSlash("locks")
        _G.MailworthyLocksUnlock2:Click()
        assert.equal(WowStub.link(4338, "Mageweave Cloth") .. "  |cffaaaaaaunlocked|r", ns.LocksUI.RowLine(2))
        assert.equal("Lock", _G.MailworthyLocksUnlock2:GetText())
        _G.MailworthyLocksUnlock2:Click()
        assert.is_true(ns.Locks.IsItemLocked(4338))
        assert.equal(WowStub.link(4338, "Mageweave Cloth"), MailworthyCharDB.lockedItems[4338].link, "with its link")
        assert.equal("Unlock", _G.MailworthyLocksUnlock2:GetText())
        _G.MailworthyLocksUnlock2:Click()
        _G.MailworthyLocksDone:Click()
        assert.is_false(ns.LocksUI.Frame():IsShown())
        ns.HandleSlash("locks")
        assert.is_nil(ns.LocksUI.RowLine(2), "opened again: only what is locked")
        assert.equal(1, #ns.LocksUI.List())
    end)

    it("follows the bags and locks made elsewhere while it is open", function()
        ns.HandleSlash("locks")
        WowStub.setBag(0, 5, WowStub.item(4338, "Mageweave Cloth", { count = 12 }))
        ns.Fire("BAG_UPDATE_DELAYED")
        assert.truthy(ns.LocksUI.RowLine(2):find("x12 in your bags", 1, true))
        WowStub.setBag(0, 6, WowStub.item(2589, "Linen Cloth", { count = 2 }))
        ns.Locks.Toggle(0, 6, "Alt+click")
        assert.truthy(ns.LocksUI.RowLine(2):find("Linen Cloth", 1, true), "by name: Copper, Linen, Mageweave")
        assert.equal(3, #ns.LocksUI.List())
    end)

    it("pages both ways, wrapping", function()
        for i = 1, 7 do lock(5000 + i, "Thing " .. i) end -- 9 locks: two pages of 6
        ns.HandleSlash("locks")
        assert.equal("1/2  >", _G.MailworthyLocksPage:GetText())
        assert.is_true(_G.MailworthyLocksPageBack:IsShown())
        _G.MailworthyLocksPageBack:Click()
        assert.equal("2/2  >", _G.MailworthyLocksPage:GetText(), "back from the first page: the last")
        assert.truthy(ns.LocksUI.RowLine(3):find("Thing 7", 1, true))
        assert.is_nil(ns.LocksUI.RowLine(4))
        _G.MailworthyLocksUnlock3:Click()
        assert.is_false(ns.Locks.IsItemLocked(5007), "a row on the second page unlocks its own item")
        assert.equal("2/2  >", _G.MailworthyLocksPage:GetText(), "and the page stays")
        _G.MailworthyLocksPage:Click()
        assert.equal("1/2  >", _G.MailworthyLocksPage:GetText(), "forward from the last page: the first")
    end)

    it("no locks: says so, with Done", function()
        MailworthyCharDB.lockedItems = {}
        ns.HandleSlash("locks")
        assert.is_nil(ns.LocksUI.RowLine(1))
        assert.is_true(_G.MailworthyLocksDone:IsShown())
        assert.truthy(ns.LocksUI.Hint():find("Alt+click", 1, true))
    end)

    it("during a send nothing changes, and the window says why", function()
        ns.HandleSlash("locks")
        local busy = ns.Mailer.Busy
        ns.Mailer.Busy = function() return true end
        _G.MailworthyLocksUnlock1:Click()
        assert.is_true(ns.Locks.IsItemLocked(2770))
        assert.equal(ns.MailWindow.BUSY_LINE, ns.LocksUI.Hint())
        ns.Mailer.Busy = busy
        _G.MailworthyLocksUnlock1:Click()
        assert.is_false(ns.Locks.IsItemLocked(2770))
        assert.truthy(ns.LocksUI.Hint():find("Alt+click", 1, true))
    end)

    it("the hint names the lock key as the player's controller does", function()
        assert.equal("Lock from your bags: Alt+click, or L3 on a controller.", ns.LocksUI.HowText(false))
        WowStub.state.labelStyle = "Letters"
        assert.equal("Lock from your bags: Alt+click, or LS on a controller.", ns.LocksUI.HowText(false))
        assert.truthy(ns.LocksUI.HowText(true):find("Alt+click, or ", 1, true))
        assert.is_nil(ns.LocksUI.HowText(true):find("on a controller", 1, true), "with a controller: its icon")
    end)

    it("a lock saved without a link still lists and unlocks", function()
        MailworthyCharDB.lockedItems = { [777] = { at = 1 } }
        ns.HandleSlash("locks")
        assert.equal("item 777  |cffff8040not in your bags|r", ns.LocksUI.RowLine(1))
        _G.MailworthyLocksUnlock1:Click()
        assert.is_false(ns.Locks.IsItemLocked(777))
    end)

    describe("Settings > More", function()
        it("\"Locked items (N)...\" counts the locks, opens the window beside Settings, and follows", function()
            WowStub.state.layout = true
            ns.SettingsUI.Show()
            local button = _G.MailworthySettingsLocks
            assert.is_true(button:IsShown())
            assert.equal("Locked items (2)...", button:GetText())
            button:Click()
            assert.is_true(ns.LocksUI.Frame():IsShown())
            assert.is_true(ns.SettingsUI.Frame():IsShown(), "Settings stays open under it")
            _G.MailworthyLocksUnlock1:Click()
            assert.equal("Locked items (1)...", button:GetText())
            _G.MailworthyLocksUnlock2:Click()
            assert.equal("Locked items...", button:GetText())
        end)
    end)
end)
