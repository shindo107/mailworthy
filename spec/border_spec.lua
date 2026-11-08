-- Blue glow on locked items (the quest-item border, tinted): textures on the
-- game's bag buttons, refreshed after UpdateItems, on lock changes and when the
-- Mailworthy window shows or hides; shown only while that window is open at the
-- mailbox (operator, 2026-11-07) unless the "glow everywhere" setting is on; a
-- tooltip line says why an item glows; no field is written on Blizzard's buttons
-- (the stub errors if one is).
local loadAddon = require("spec.support.load_addon")

--- At the mailbox with the Mailworthy window open.
local function openWindow(ns)
    MailFrame:Show()
    SendMailFrame:Show()
    ns.Fire("MAIL_SHOW")
    ns.MailWindow.Show("send")
end

--- The mailbox closes (the game hides the window with the mail frame it lives under).
local function closeMailbox(ns)
    ns.MailWindow.Frame():Hide()
    MailFrame:Hide()
    SendMailFrame:Hide()
    ns.Fire("MAIL_CLOSED")
end

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
        openWindow(ns) -- most of these run with the Mailworthy window open at the mailbox
    end)

    it("shows only while the Mailworthy window is open", function()
        MailworthyCharDB.lockedItems[2770] = { link = "Copper Ore" }
        closeMailbox(ns)
        combined:UpdateItems()
        assert.is_false(shown(combined.Items[2]), "away from the mailbox: no glow")
        ns.Locks.Toggle(0, 1, "test")
        assert.is_true(ns.Locks.IsItemLocked(2589))
        WowStub.state.now = WowStub.state.now + ns.Border.FLASH
        WowStub.runTimers(ns.Border.FLASH)
        assert.is_false(shown(combined.Items[1]), "after its flash a lock away from the mailbox draws nothing")
        openWindow(ns)
        assert.is_true(shown(combined.Items[1]), "opening the window refreshes the open bags")
        assert.is_true(shown(combined.Items[2]))
        ns.MailWindow.Frame():Hide()
        assert.is_true(MailFrame:IsShown(), "the mailbox is still open")
        assert.is_false(shown(combined.Items[1]), "closing the window clears them")
        ns.MailWindow.Show("send")
        assert.is_true(shown(combined.Items[1]))
        closeMailbox(ns)
        assert.is_false(shown(combined.Items[1]), "closing the mailbox clears them")
        assert.is_false(shown(combined.Items[3]))
    end)

    it("a fresh lock away from the mailbox flashes for a moment, so the player sees it worked", function()
        closeMailbox(ns)
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

    it("an unlock during the flash ends it; the window opening keeps a flashed item lit", function()
        closeMailbox(ns)
        ns.Locks.Toggle(0, 1, "L3")
        assert.is_true(shown(combined.Items[1]))
        ns.Locks.Toggle(0, 1, "L3")
        assert.is_false(shown(combined.Items[1]))
        ns.Locks.Toggle(0, 1, "L3")
        openWindow(ns)
        WowStub.state.now = WowStub.state.now + ns.Border.FLASH
        WowStub.runTimers(ns.Border.FLASH)
        assert.is_true(shown(combined.Items[1]), "at the mailbox the glow is the normal one")
    end)

    it("the glow everywhere setting keeps it on away from the mailbox", function()
        MailworthyCharDB.lockedItems[2770] = { link = "Copper Ore" }
        closeMailbox(ns)
        ns.Config.Set("glowEverywhere", true)
        combined:UpdateItems()
        assert.is_true(shown(combined.Items[2]))
        _G.MailworthySettingsGlow:Click()
        assert.is_false(ns.Config.Flag("glowEverywhere"))
        assert.is_false(shown(combined.Items[2]), "the settings button refreshes the bags at once")
        assert.equal("Lock glow: in Mailworthy", _G.MailworthySettingsGlow:GetText())
    end)

    -- Operator, 2026-11-07: "i dont want the bag to always show the blue slots, only when looking
    -- at the mailbox with the addon open". Before, any open mailbox lit the bags.
    it("an open mailbox alone doesn't light the bags: only the Mailworthy window does", function()
        MailworthyCharDB.lockedItems[2770] = { link = "Copper Ore" }
        ns.MailWindow.Frame():Hide()
        assert.is_true(MailFrame:IsShown())
        ns.Fire("MAIL_SHOW")
        combined:UpdateItems()
        assert.is_false(shown(combined.Items[2]))
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

    -- v0.22.0 on Forever 1.60.1 (2026-11-07): "Border.lua:113: attempt to index local 'button'
    -- (a nil value)" at every login, bag update and mailbox visit. The combined bags' size counts
    -- every bag's slots while Items holds only the buttons laid out so far, so Blizzard's
    -- iterator yields nil buttons, and the error stopped the bank alt tags' redraw with it.
    it("skips the missing buttons Forever's iterator yields, and still draws the rest", function()
        MailworthyCharDB.lockedItems[2770] = { link = "Copper Ore" }
        combined.Items = { WowStub.itemButton(0, 1), nil, WowStub.itemButton(1, 1) }
        combined.size = 20
        ns.Fire("BAG_UPDATE_DELAYED")
        ns.Fire("MAIL_SHOW")
        ns.Border.RefreshAll()
        combined:UpdateItems()
        for _, line in ipairs(MailworthyDB.log or {}) do
            assert.is_nil(line:find("%[error%]"), line)
            assert.is_nil(line:find("refresh error"), line)
        end
        assert.is_false(shown(combined.Items[1]))
        assert.is_true(shown(combined.Items[3]), "a button after the hole still glows")
    end)

    -- rl-companion's BugGrabber data (2026-11-07): RefreshAll ran 37 times in one session from
    -- Auctionator's scan alone, bags open or not. A closed frame is redrawn when it opens
    -- (Forever: GenerateFrame -> Update -> UpdateItems, which the hook follows).
    it("skips closed bag frames, and draws them when they open", function()
        MailworthyCharDB.lockedItems[2770] = { link = "Copper Ore" }
        local reads = 0
        combined.IsShown = function() return false end
        for _, b in ipairs(combined.Items) do
            local getID = b.GetID
            rawset(b, "GetID", function(self) reads = reads + 1 return getID(self) end)
        end
        ns.Border.RefreshAll()
        assert.equal(0, reads, "a closed frame's slots aren't read")
        assert.is_false(shown(combined.Items[2]))
        combined.IsShown = function() return true end
        combined:UpdateItems() -- the game opens the bags
        assert.is_true(shown(combined.Items[2]), "drawn once it opens")
        assert.is_true(reads > 0)
    end)

    it("covers the individual bag frames too", function()
        local bag = ContainerFrameContainer.ContainerFrames[1]
        bag.Items = { WowStub.itemButton(1, 1) }
        MailworthyCharDB.lockedItems[2770] = { link = "Copper Ore" }
        bag:UpdateItems()
        assert.is_true(shown(bag.Items[1]))
    end)
end)

-- Baganator replaces the game's bags (2026-11-07: "I'm not seeing the icon borders anymore on my
-- bag menu"). Its corner-widget API is stubbed the way its source calls it: onInit(itemButton)
-- once per button, onUpdate(widget, details) on every redraw.
describe("locked-item glow in Baganator", function()
    local ns, registered, refreshes
    local function baganatorButton(bag, slot)
        local b = WowStub.itemButton(bag, slot)
        local parent = { GetID = function() return bag end }
        rawset(b, "GetParent", function() return parent end) -- the spec's own stub, not addon code
        return b
    end
    local function glowing(button)
        for _, t in ipairs(ns.Border.Glow(button)) do if not t:IsShown() then return false end end
        return true
    end
    before_each(function()
        ns = loadAddon()
        registered, refreshes = nil, 0
        _G.Baganator = { API = {
            RegisterCornerWidget = function(label, id, onUpdate, onInit, defaultPosition)
                registered = { label = label, id = id, onUpdate = onUpdate, onInit = onInit, position = defaultPosition }
            end,
            RequestItemButtonsRefresh = function() refreshes = refreshes + 1 end,
        } }
        WowStub.setBag(0, 1, WowStub.item(2589, "Linen Cloth", { count = 6 }))
        ns.Fire("PLAYER_LOGIN")
    end)
    after_each(function() _G.Baganator = nil end)

    it("registers a corner widget at login that never takes the corner", function()
        assert.equal("mailworthy_lock", registered.id)
        assert.same({ corner = "top_left", priority = 1 }, registered.position)
        local button = baganatorButton(0, 1)
        local widget = registered.onInit(button)
        assert.is_false(widget:IsShown())
        assert.is_false(registered.onUpdate(widget, { itemID = 2589 }), "false: the corner stays free")
    end)

    it("glows a locked item while the Mailworthy window is open, by the item Baganator shows", function()
        local button = baganatorButton(0, 1)
        local widget = registered.onInit(button)
        openWindow(ns)
        registered.onUpdate(widget, { itemID = 2589, itemLink = "[Linen Cloth]" })
        assert.is_false(glowing(button), "not locked")
        local before = refreshes
        ns.Locks.ToggleItem(2589, "[Linen Cloth]", "spec")
        assert.is_true(refreshes > before, "a lock change asks Baganator to redraw")
        registered.onUpdate(widget, { itemID = 2589 })
        assert.is_true(glowing(button))
        local before2 = refreshes
        closeMailbox(ns)
        assert.is_true(refreshes > before2, "closing asks Baganator to redraw")
        registered.onUpdate(widget, { itemID = 2589 })
        assert.is_false(glowing(button), "away from the mailbox: no glow")
    end)

    it("without Baganator nothing is registered and nothing breaks", function()
        _G.Baganator = nil
        local ns2 = loadAddon()
        ns2.Fire("PLAYER_LOGIN")
        assert.is_false(ns2.Border.InstallBaganator())
    end)
end)

-- Hovering a glowing item says why it is blue (operator, 2026-11-07: "give a hover tooltip
-- indicating why they are blue"): one line through TooltipDataProcessor, only while it glows.
describe("why a locked item glows: the tooltip line", function()
    local ns, postCalls, lines
    local function hover(itemID)
        lines = {}
        for _, fn in ipairs(postCalls) do fn(GameTooltip, { id = itemID }) end
        return lines
    end
    before_each(function()
        ns = loadAddon()
        postCalls = {}
        _G.Enum = { TooltipDataType = { Item = 0 } }
        _G.TooltipDataProcessor = { AddTooltipPostCall = function(_, fn) table.insert(postCalls, fn) end }
        rawset(GameTooltip, "AddLine", function(_, text, r, g, b) table.insert(lines, { text, r, g, b }) end)
        WowStub.setBag(0, 1, WowStub.item(2589, "Linen Cloth", { count = 6 }))
        WowStub.setBag(0, 2, WowStub.item(2770, "Copper Ore", { count = 5 }))
        ns.Fire("PLAYER_LOGIN")
        MailworthyCharDB.lockedItems[2770] = { link = "Copper Ore" }
    end)
    after_each(function()
        _G.Enum, _G.TooltipDataProcessor = nil, nil
        rawset(GameTooltip, "AddLine", nil)
        for _, line in ipairs(ns.Log.Lines()) do assert.is_nil(line:find("error", 1, true), line) end
    end)

    it("explains the glow on a locked item while the window is open, in the glow's blue", function()
        openWindow(ns)
        local got = hover(2770)
        assert.equal(1, #got)
        assert.equal(ns.Border.TOOLTIP, got[1][1])
        assert.matches("never mailed", got[1][1])
        assert.matches("Alt%+click", got[1][1])
        assert.matches("L3", got[1][1])
        assert.same(ns.Border.COLOR, { got[1][2], got[1][3], got[1][4] })
        for _, line in ipairs(hover(2589)) do
            assert.is_not.equal(ns.Border.TOOLTIP, line[1], "an unlocked item: no glow line")
        end
    end)

    it("says nothing where the item doesn't glow, and follows the flash and the setting", function()
        assert.equal(0, #hover(2770), "window closed: no glow, no line")
        ns.Locks.Toggle(0, 1, "Alt+click") -- Linen Cloth: a fresh lock flashes
        assert.equal(1, #hover(2589), "during the flash it glows, so it says why")
        WowStub.state.now = WowStub.state.now + ns.Border.FLASH
        WowStub.runTimers(ns.Border.FLASH)
        assert.equal(0, #hover(2589))
        ns.Config.Set("glowEverywhere", true)
        assert.equal(1, #hover(2770), "glow everywhere: the line everywhere")
    end)

    it("the slotBorder switch turns the line off with the glow", function()
        MailworthyDB.features = { slotBorder = false }
        openWindow(ns)
        assert.equal(0, #hover(2770))
    end)
end)
