-- Bank pins: "always bank this item". A pin belongs to the item (its ID) and to the whole
-- account, so the bank alt sees it; toggled by Ctrl+Alt+click (mouse) or R3 in the bags
-- (controller, the selected slot read from SmartNavigation); never via the gamepad More menu.
local loadAddon = require("spec.support.load_addon")

describe("bank pins", function()
    local ns, original
    before_each(function()
        original = HandleModifiedItemClick
        ns = loadAddon()
        _G.Menu = setmetatable({}, { __index = function() error("Mailworthy touched Menu") end })
        WowStub.setBag(0, 3, WowStub.item(2770, "Copper Ore", { count = 5 }))
        WowStub.setBag(0, 4, WowStub.item(2770, "Copper Ore", { count = 7 }))
        ns.Fire("PLAYER_LOGIN")
    end)
    after_each(function()
        _G.HandleModifiedItemClick = original
        _G.Menu = { ModifyMenu = function(tag, fn) WowStub.menuModifiers[tag] = fn end }
    end)

    it("Ctrl+Alt+click pins the item for the bank and again unpins it; Alt alone still only locks", function()
        WowStub.state.mods = { alt = true, ctrl = true }
        HandleModifiedItemClick("link", WowStub.itemLocation(0, 3))
        assert.equal("bank", ns.Pins.Kind(2770))
        assert.is_false(ns.Locks.IsItemLocked(2770), "a pin is not a lock")
        assert.truthy(WowStub.printed[#WowStub.printed]:find("Bank pin on", 1, true))
        HandleModifiedItemClick("link", WowStub.itemLocation(0, 4)) -- the other stack: the same item
        assert.is_nil(ns.Pins.Kind(2770))

        WowStub.state.mods = { alt = true }
        HandleModifiedItemClick("link", WowStub.itemLocation(0, 3))
        assert.is_true(ns.Locks.IsItemLocked(2770))
        assert.is_nil(ns.Pins.Kind(2770), "Alt alone never pins")
    end)

    it("ignores other modifier sets and clicks outside the bags", function()
        WowStub.state.mods = { ctrl = true }
        HandleModifiedItemClick("link", WowStub.itemLocation(0, 3))
        WowStub.state.mods = { alt = true, ctrl = true, shift = true }
        HandleModifiedItemClick("link", WowStub.itemLocation(0, 3))
        WowStub.state.mods = { alt = true, ctrl = true }
        HandleModifiedItemClick("link", WowStub.itemLocation(-1, 3)) -- bank
        HandleModifiedItemClick("link", WowStub.itemLocation(nil, nil)) -- equipment slot
        HandleModifiedItemClick("link", nil)
        assert.same({}, MailworthyDB.pins)
        assert.same({}, MailworthyCharDB.lockedItems, "and Ctrl+Alt never locks")
    end)

    it("R3: pins the bag item smart navigation has selected, and nothing else", function()
        WowStub.state.navButton = WowStub.itemButton(0, 3)
        assert.equal("bank", ns.Pins.ToggleSelectedBagSlot())
        assert.equal("bank", ns.Pins.Kind(2770))
        WowStub.state.navButton = { buttonContext = "ButtonContext_PaperDollItemSlotButton" }
        assert.is_nil(ns.Pins.ToggleSelectedBagSlot())
        WowStub.state.navButton = nil
        assert.is_nil(ns.Pins.ToggleSelectedBagSlot())
        assert.equal("bank", ns.Pins.Kind(2770))
    end)

    it("is saved for the account, not the character: the bank alt knows the pin", function()
        ns.Pins.Toggle(0, 3, "test")
        assert.is_table(MailworthyDB.pins[2770])
        assert.is_nil(MailworthyCharDB.pins)
        local saved = MailworthyDB.pins
        local alt = loadAddon() -- another character: a fresh MailworthyCharDB, the same account table
        MailworthyDB.pins = saved
        alt.Fire("PLAYER_LOGIN")
        assert.equal("bank", alt.Pins.Kind(2770))
    end)

    it("says when a pinned item is locked here too: the lock wins", function()
        ns.Locks.Toggle(0, 3, "test")
        ns.Pins.Toggle(0, 3, "test")
        assert.truthy(WowStub.printed[#WowStub.printed]:find("a lock wins", 1, true))
    end)

    it("tells listeners (tags, window) when a pin changes", function()
        local seen = {}
        ns.Pins.OnChanged(function(itemID, kind) seen[#seen + 1] = { itemID, kind } end)
        ns.Pins.Toggle(0, 3, "test")
        ns.Pins.Toggle(0, 3, "test")
        assert.same({ { 2770, "bank" }, { 2770 } }, seen)
    end)

    it("/mw pins lists them by name; /mw report carries them", function()
        ns.HandleSlash("pins")
        assert.truthy(WowStub.printed[#WowStub.printed]:find("No pinned items", 1, true))
        ns.Pins.Toggle(0, 3, "test")
        ns.HandleSlash("pins")
        assert.truthy(WowStub.printed[#WowStub.printed]:find("Copper Ore", 1, true))
        assert.equal("2770 bank Copper Ore", ns.Pins.Describe())
    end)

    describe("the rule", function()
        local function item(extra)
            local it = { link = WowStub.link(2770, "Copper Ore"), itemID = 2770, count = 5, stacks = 1, quality = 1,
                classID = 7, subclassID = 7, vendor = 5, pin = "bank" }
            for k, v in pairs(extra or {}) do it[k] = v end
            return it
        end
        local function settings(extra)
            local s = ns.Valuation.Settings({}, false)
            s.postage = 30
            for k, v in pairs(extra or {}) do s[k] = v end
            return s
        end

        it("a pinned item is mailed for the bank, priced or not, worth it or not", function()
            for _, price in ipairs({ { ah = 174, age = 0 }, { ah = 1, age = 0 }, {} }) do
                local r = ns.Valuation.Evaluate(item(), price, settings())
                assert.equal("mail", r.action)
                assert.equal("bank", r.route)
                assert.is_true(r.pinned)
                assert.equal(25, r.vendor)
                assert.equal(30, r.postage)
            end
            local r = ns.Valuation.Evaluate(item({ quality = 0 }), nil, settings())
            assert.equal("bank", r.route, "junk without a price source too")
        end)

        it("every hard keep still wins over a pin", function()
            for field, reason in pairs({ locked = "locked", bound = "soulbound", quest = "quest item", inUse = "in use",
                conjured = ns.Conjured.REASON }) do
                local r = ns.Valuation.Evaluate(item({ [field] = true }), { ah = 174, age = 0 }, settings())
                assert.equal("keep", r.action, field)
                assert.equal(reason, r.reason)
            end
            local r = ns.Valuation.Evaluate(item({ questFor = "Redridge Goulash" }), { ah = 174, age = 0 }, settings())
            assert.equal("a quest needs it", r.reason)
            r = ns.Valuation.Evaluate(item({ itemID = 2901, classID = 2, subclassID = 14 }), { ah = 174, age = 0 }, settings())
            assert.equal("profession tool", r.reason)
        end)

        it("a pin beats this character's own crafting keep", function()
            local s = settings({ keepProfessionMats = true, professions = { 164 } }) -- Blacksmithing: copper ore is its material
            assert.equal("keep", ns.Valuation.Evaluate(item({ pin = false }), { ah = 174, age = 0 }, s).action)
            assert.equal("bank", ns.Valuation.Evaluate(item(), { ah = 174, age = 0 }, s).route)
        end)

        it("an item without a pin is valued as before", function()
            local r = ns.Valuation.Evaluate(item({ pin = false }), { ah = 174, age = 0 }, settings())
            assert.equal("ah", r.route)
            assert.is_nil(r.pinned)
        end)

        it("the tag is B and the tooltip says why, here and on the bank alt", function()
            local it = item()
            it.result = ns.Valuation.Evaluate(it, { ah = 174, age = 0 }, settings())
            assert.equal("b", ns.BankAlt.Verdict(it))
            it.advice = "b"
            local lines = ns.BankAlt.TooltipLines(it, nil, settings())
            local text = {}
            for _, l in ipairs(lines) do text[#text + 1] = l[1] end
            assert.truthy(table.concat(text, " "):find("you pinned this item for your bank alt", 1, true), table.concat(text, " "))
            assert.truthy(lines[1][1]:find("[Pinned]", 1, true), "the label")
            assert.same(ns.Pins.COLOR, { lines[2][2], lines[2][3], lines[2][4] }, "the reason in the pin's green")
        end)

        it("no price source: a pinned item goes anyway, white or not, junk too (operator, 2026-11-13)", function()
            for _, quality in ipairs({ 0, 1, 2, 3 }) do
                local r = ns.Valuation.Evaluate(item({ quality = quality, classID = 4, subclassID = 0 }), nil, settings())
                assert.equal("bank", r.route, "quality " .. quality)
            end
        end)

        it("a pin waits for the item's data, and a failed price call still keeps it", function()
            local unloaded = item()
            unloaded.vendor = nil
            local r = ns.Valuation.Evaluate(unloaded, { ah = 174, age = 0 }, settings())
            assert.equal("item info not loaded yet", r.reason)
            r = ns.Valuation.Evaluate(item(), { failed = true }, settings())
            assert.equal("keep", r.action)
            assert.is_true(r.failed)
        end)

        it("the chip and the row tooltip in the Mailworthy window say pinned, in green", function()
            local r = ns.Valuation.Evaluate(item(), { ah = 174, age = 0 }, settings())
            assert.equal(ns.MailWindow.CHIPS.pinned, ns.MailWindow.ChipFor(r))
            assert.same(ns.Pins.COLOR, { ns.MailWindow.CHIPS.pinned[2], ns.MailWindow.CHIPS.pinned[3],
                ns.MailWindow.CHIPS.pinned[4] })
            assert.equal(ns.MailWindow.CHIPS.bank, ns.MailWindow.ChipFor({ route = "bank" }))
            local where = ns.MailWindow.TooltipLines({ result = r }, false, false, "Roknua Themicrulah", false)
            assert.equal("Mailing to Roknua: you pinned it for your bank alt.", where)
        end)

        it("the bags carry the pin into the rule", function()
            ns.Config.SetBankAlt("Roknua Themicrulah")
            ns.Pins.Toggle(0, 3, "test")
            local result = ns.Bags.Evaluate()
            assert.equal(1, #result.mail)
            assert.equal(2770, result.mail[1].itemID)
            assert.equal("bank", result.mail[1].result.route)
            assert.equal(2, result.mail[1].stacks, "both stacks")
        end)
    end)

    it("a pin can't change while a send runs: what is on its way was previewed (Codex review)", function()
        local busy = ns.Mailer.Busy
        ns.Mailer.Busy = function() return true end
        WowStub.state.mods = { alt = true, ctrl = true }
        HandleModifiedItemClick("link", WowStub.itemLocation(0, 3))
        assert.is_nil(ns.Pins.Kind(2770))
        assert.truthy(WowStub.printed[#WowStub.printed]:find(ns.Pins.BUSY, 1, true))
        ns.Mailer.Busy = busy
        HandleModifiedItemClick("link", WowStub.itemLocation(0, 3))
        WowStub.state.mods = {}
        assert.equal("bank", ns.Pins.Kind(2770), "pins again once it's done")
    end)

    it("/mw feature pinClick off: no hook, Ctrl+Alt+click does nothing", function()
        _G.HandleModifiedItemClick = original
        local ns2 = loadAddon()
        WowStub.setBag(0, 3, WowStub.item(2770, "Copper Ore", { count = 5 }))
        MailworthyDB.features = { pinClick = false }
        ns2.Fire("PLAYER_LOGIN")
        WowStub.state.mods = { alt = true, ctrl = true }
        HandleModifiedItemClick("link", WowStub.itemLocation(0, 3))
        assert.is_nil(ns2.Pins.Kind(2770))
    end)
end)
