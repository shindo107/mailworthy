-- Blue glow on locked items (the quest-item border, tinted): textures on the
-- game's bag buttons, refreshed after UpdateItems, on lock changes and when the
-- mailbox opens or closes; shown only while a mailbox is open unless the
-- "glow everywhere" setting is on; no field is written on Blizzard's buttons
-- (the stub errors if one is).
local loadAddon = require("spec.support.load_addon")

local function shown(button)
    if #button.textures == 0 then return false end
    for _, t in ipairs(button.textures) do if not t:IsShown() then return false end end
    return true
end

describe("locked-item glow", function()
    local ns, combined
    before_each(function()
        ns = loadAddon()
        WowStub.setBag(0, 1, WowStub.item(2589, "Linen Cloth", { count = 6 }))
        WowStub.setBag(0, 2, WowStub.item(2770, "Copper Ore", { count = 5 }))
        WowStub.setBag(1, 1, WowStub.item(2770, "Copper Ore", { count = 9 }))
        combined = ContainerFrameCombinedBags
        combined.Items = { WowStub.itemButton(0, 1), WowStub.itemButton(0, 2), WowStub.itemButton(1, 1) }
        ns.Fire("PLAYER_LOGIN")
        ns.Fire("MAIL_SHOW") -- most of these run at the mailbox
    end)

    it("shows only while a mailbox is open", function()
        MailworthyCharDB.lockedItems[2770] = { link = "Copper Ore" }
        ns.Fire("MAIL_CLOSED")
        combined:UpdateItems()
        assert.is_false(shown(combined.Items[2]), "away from the mailbox: no glow")
        ns.Locks.Toggle(0, 1, "test")
        assert.is_true(ns.Locks.IsItemLocked(2589))
        WowStub.state.now = WowStub.state.now + ns.Border.FLASH
        WowStub.runTimers(ns.Border.FLASH)
        assert.is_false(shown(combined.Items[1]), "after its flash a lock away from the mailbox draws nothing")
        ns.Fire("MAIL_SHOW")
        assert.is_true(shown(combined.Items[1]), "opening the mailbox refreshes the open bags")
        assert.is_true(shown(combined.Items[2]))
        ns.Fire("MAIL_CLOSED")
        assert.is_false(shown(combined.Items[1]), "closing it clears them")
        assert.is_false(shown(combined.Items[3]))
    end)

    it("a fresh lock away from the mailbox flashes for a moment, so the player sees it worked", function()
        ns.Fire("MAIL_CLOSED")
        ns.Locks.Toggle(0, 2, "Alt+click") -- Copper Ore (the Alt+click hook itself: locks_spec)
        assert.is_true(shown(combined.Items[2]))
        assert.is_true(shown(combined.Items[3]), "every stack of the item")
        assert.is_false(shown(combined.Items[1]))
        combined:UpdateItems()
        assert.is_true(shown(combined.Items[2]), "a bag refresh during the flash keeps it")
        WowStub.state.now = WowStub.state.now + ns.Border.FLASH
        WowStub.runTimers(ns.Border.FLASH)
        assert.is_false(shown(combined.Items[2]), "gone after the flash")
        assert.is_true(ns.Locks.IsItemLocked(2770), "the lock stays")
        -- Unlocking shows nothing
        ns.Locks.Toggle(0, 2, "Alt+click")
        assert.is_false(shown(combined.Items[2]))
        assert.is_false(ns.Locks.IsItemLocked(2770))
    end)

    it("an unlock during the flash ends it; the mailbox opening keeps a flashed item lit", function()
        ns.Fire("MAIL_CLOSED")
        ns.Locks.Toggle(0, 1, "L3")
        assert.is_true(shown(combined.Items[1]))
        ns.Locks.Toggle(0, 1, "L3")
        assert.is_false(shown(combined.Items[1]))
        ns.Locks.Toggle(0, 1, "L3")
        ns.Fire("MAIL_SHOW")
        WowStub.state.now = WowStub.state.now + ns.Border.FLASH
        WowStub.runTimers(ns.Border.FLASH)
        assert.is_true(shown(combined.Items[1]), "at the mailbox the glow is the normal one")
    end)

    it("the glow everywhere setting keeps it on away from the mailbox", function()
        MailworthyCharDB.lockedItems[2770] = { link = "Copper Ore" }
        ns.Fire("MAIL_CLOSED")
        ns.Config.Set("glowEverywhere", true)
        combined:UpdateItems()
        assert.is_true(shown(combined.Items[2]))
        _G.MailworthySettingsGlow:Click()
        assert.is_false(ns.Config.Flag("glowEverywhere"))
        assert.is_false(shown(combined.Items[2]), "the settings button refreshes the bags at once")
        assert.equal("Lock glow: mailbox only", _G.MailworthySettingsGlow:GetText())
    end)

    it("Blizzard's mail window being shown counts as a mailbox too", function()
        MailworthyCharDB.lockedItems[2770] = { link = "Copper Ore" }
        ns.Fire("MAIL_CLOSED")
        MailFrame:Show()
        combined:UpdateItems()
        assert.is_true(shown(combined.Items[2]))
    end)

    it("glows every stack of a locked item after the bags update", function()
        MailworthyCharDB.lockedItems[2770] = { link = "Copper Ore" }
        combined:UpdateItems()
        assert.is_false(shown(combined.Items[1]))
        assert.is_true(shown(combined.Items[2]))
        assert.is_true(shown(combined.Items[3]))
        assert.equal(2, #combined.Items[2].textures, "border + additive glow")
    end)

    it("follows a lock change at once, and recomputes pooled buttons", function()
        ns.Locks.Toggle(0, 1, "test")
        assert.is_true(shown(combined.Items[1]))
        combined.Items[1].slot = 2 -- the pool reused the button for another slot (Copper Ore)
        combined:UpdateItems()
        assert.is_false(shown(combined.Items[1]))
    end)

    it("covers the individual bag frames too", function()
        local bag = ContainerFrameContainer.ContainerFrames[1]
        bag.Items = { WowStub.itemButton(1, 1) }
        MailworthyCharDB.lockedItems[2770] = { link = "Copper Ore" }
        bag:UpdateItems()
        assert.is_true(shown(bag.Items[1]))
    end)
end)
