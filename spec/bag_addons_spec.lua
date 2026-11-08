-- Mailworthy's tags (AH / B / DE / V) and lock glow in the three most-downloaded bag addons with a
-- Forever build (operator, 2026-11-08: "id like to support the top 3 bag addons"): Baganator,
-- Bagnon, ArkInventory. Each addon is stubbed the way its source calls us (BagAddons.lua's header):
-- Baganator's corner widget + "ViewComplete" + region, Bagnon's ContainerItem.Update (its methods
-- copied into each button when it is built), ArkInventory's API.ItemFrameUpdated. Every stub
-- button errors on a Lua field written by Mailworthy, and no frame may be created while drawing.
local loadAddon = require("spec.support.load_addon")

local COPPER, LINEN, RING = 2770, 2589, 6360

--- The tag a button shows (BankAlt's font string), or nil.
local function tagOf(button)
    for _, f in ipairs(button.fontStrings or {}) do
        if f:IsShown() then return f.text end
    end
    return nil
end

local function glowing(ns, button)
    for _, t in ipairs(ns.Border.Glow(button)) do if not t:IsShown() then return false end end
    return true
end

--- A button another addon owns: textures / font strings may be created on it, any Lua field
--- written on it by Mailworthy is an error (the addon's own code uses rawset).
local function addonButton(methods)
    local b = { textures = {}, fontStrings = {} }
    function b.CreateTexture()
        local t = WowStub.newWidget("Texture")
        table.insert(b.textures, t)
        return t
    end
    function b.CreateFontString()
        local f = WowStub.newWidget("FontString")
        table.insert(b.fontStrings, f)
        return f
    end
    function b.IsVisible() return rawget(b, "hidden") ~= true end
    for k, v in pairs(methods or {}) do b[k] = v end
    return setmetatable(b, { __newindex = function(_, k) error("Mailworthy wrote field " .. tostring(k) .. " on a bag addon button") end })
end

--- Counts CreateFrame calls (none allowed while drawing: a gamepad panel may be open).
local function countFrames()
    local real, n = _G.CreateFrame, { 0 }
    _G.CreateFrame = function(...) n[1] = n[1] + 1 return real(...) end
    return n, function() _G.CreateFrame = real end
end

--- Bags with an AH item, a vendor item and a disenchant item; Auctionator prices; no bank alt (the
--- tags show on a character with none: BankAlt.Mode "self").
local function setup()
    local ns = loadAddon()
    ns.Valuation.DEFAULTS.minGain = 500
    local prices = {}
    _G.Auctionator = { API = { v1 = {
        GetAuctionPriceByItemLink = function(_, l) return prices[l] and prices[l].ah end,
        GetAuctionAgeByItemLink = function() return 0 end,
        IsAuctionDataExactByItemLink = function() return true end,
        GetDisenchantPriceByItemLink = function(_, l) return prices[l] and prices[l].de end,
    } } }
    _G.DisenchantryDB = {}
    WowStub.setBag(0, 1, WowStub.item(COPPER, "Copper Ore", { count = 5, sell = 5 }))
    prices[WowStub.link(COPPER, "Copper Ore")] = { ah = 174 }
    WowStub.setBag(0, 2, WowStub.item(LINEN, "Linen Cloth", { count = 20, sell = 10 }))
    prices[WowStub.link(LINEN, "Linen Cloth")] = { ah = 38 }
    WowStub.setBag(0, 3, WowStub.item(RING, "Green Ring", { quality = 2, class = 4, sell = 50 }))
    prices[WowStub.link(RING, "Green Ring")] = { de = 1000 }
    return ns
end

local function login(ns)
    ns.Fire("ADDON_LOADED", "Mailworthy")
    ns.Fire("PLAYER_LOGIN")
    ns.BankAlt.Redraw()
end

local function openWindow(ns)
    MailFrame:Show()
    SendMailFrame:Show()
    ns.Fire("MAIL_SHOW")
    ns.MailWindow.Show("send")
end

local function noErrors(ns)
    for _, line in ipairs(ns.Log.Lines()) do assert.is_nil(line:find("error", 1, true), line) end
end

local function cleanup()
    _G.Baganator, _G.Bagnon, _G.ArkInventory, _G.ARKINV_Frame1 = nil, nil, nil, nil
    _G.Auctionator, _G.DisenchantryDB = nil, nil
end

-- Baganator ------------------------------------------------------------------------------------------

local function stubBaganator()
    local reg = { refreshes = 0, callbacks = {} }
    _G.Baganator = {
        API = {
            RegisterCornerWidget = function(label, id, onUpdate, onInit, position)
                reg.widget = { label = label, id = id, onUpdate = onUpdate, onInit = onInit, position = position }
            end,
            RequestItemButtonsRefresh = function() reg.refreshes = reg.refreshes + 1 end,
            RegisterRegion = function(label, id, view, position, region)
                assert(region.SetParent and region.ClearAllPoints and region.SetPoint and region.GetWidth)
                reg.region = { label = label, id = id, view = view, position = position, region = region }
            end,
        },
        CallbackRegistry = {
            RegisterCallback = function(_, event, fn, owner) reg.callbacks[event] = { fn = fn, owner = owner } end,
        },
    }
    return reg
end

--- A live Baganator button (ContainerFrameItemButtonTemplate: GetBagID / GetID), reassignable.
local function baganatorLive(bag, slot)
    local at = { bag = bag, slot = slot }
    local b = addonButton({ GetBagID = function() return at.bag end, GetID = function() return at.slot end })
    return b, at
end

--- Baganator shows an item on a button: onInit once per button, then onUpdate with its details.
local function baganatorShow(reg, button, widgets, itemID)
    widgets[button] = widgets[button] or reg.widget.onInit(button)
    return reg.widget.onUpdate(widgets[button], { itemID = itemID })
end

describe("bag addons: Baganator", function()
    local ns, reg, widgets
    before_each(function()
        ns = setup()
        reg, widgets = stubBaganator(), {}
        login(ns)
    end)
    after_each(function() noErrors(ns) cleanup() end)

    it("registers its corner widget, the legend region and a ViewComplete redraw", function()
        assert.equal("mailworthy_lock", reg.widget.id, "the ID Baganator remembers from the glow-only widget")
        assert.equal("Mailworthy tags and lock glow", reg.widget.label)
        assert.same({ corner = "top_left", priority = 1 }, reg.widget.position)
        assert.equal("backpack", reg.region.view)
        assert.equal("bottom_left", reg.region.position)
        assert.truthy(reg.callbacks.ViewComplete, "redraws after each layout pass")
        assert.truthy(reg.region.region.text:find("AH", 1, true), "the legend explains the tags, no hover needed")
        assert.is_true(ns.BagAddons.Installed("baganator"))
    end)

    it("tags each live slot with its verdict and holds the corner only while a tag shows", function()
        local frames, restore = countFrames()
        local copper, linen, ring = baganatorLive(0, 1), baganatorLive(0, 2), baganatorLive(0, 3)
        assert.is_true(baganatorShow(reg, copper, widgets, COPPER))
        assert.equal("AH", tagOf(copper))
        baganatorShow(reg, linen, widgets, LINEN)
        assert.equal("V", tagOf(linen))
        baganatorShow(reg, ring, widgets, RING)
        assert.equal("DE", tagOf(ring))
        MailworthyCharDB.lockedItems[COPPER] = { link = "Copper Ore" }
        ns.BankAlt.Redraw()
        assert.is_false(baganatorShow(reg, copper, widgets, COPPER), "a locked item has no tag: the corner is free")
        assert.is_nil(tagOf(copper))
        restore()
        assert.equal(0, frames[1], "no frame created while drawing")
    end)

    it("follows a recycled button: another slot, an emptied slot, a stale item", function()
        local button, at = baganatorLive(0, 1)
        baganatorShow(reg, button, widgets, COPPER)
        assert.equal("AH", tagOf(button))
        at.slot = 2 -- Baganator reuses the button for the next slot
        baganatorShow(reg, button, widgets, LINEN)
        assert.equal("V", tagOf(button))
        baganatorShow(reg, button, widgets, COPPER)
        assert.is_nil(tagOf(button), "Baganator says Copper Ore but the slot holds Linen Cloth: drawn later")
        WowStub.setBag(0, 2, nil) -- the slot empties: Baganator calls no onUpdate for an empty slot
        reg.callbacks.ViewComplete.fn(reg.callbacks.ViewComplete.owner)
        assert.is_nil(tagOf(button), "ViewComplete clears it")
    end)

    it("ViewComplete goes by the item Baganator shows on the button (its details, read only)", function()
        local button = baganatorLive(0, 1)
        baganatorShow(reg, button, widgets, COPPER)
        assert.equal("AH", tagOf(button))
        rawset(button, "BGR", { itemID = LINEN }) -- Baganator hasn't caught up with the slot yet
        reg.callbacks.ViewComplete.fn(reg.callbacks.ViewComplete.owner)
        assert.is_nil(tagOf(button), "not drawn over an item Baganator doesn't show")
        rawset(button, "BGR", {}) -- an empty button
        reg.callbacks.ViewComplete.fn(reg.callbacks.ViewComplete.owner)
        assert.is_nil(tagOf(button))
        rawset(button, "BGR", { itemID = COPPER })
        reg.callbacks.ViewComplete.fn(reg.callbacks.ViewComplete.owner)
        assert.equal("AH", tagOf(button))
    end)

    it("draws nothing on another character's bags or a guild bank tab (no GetBagID)", function()
        local cached = addonButton({ GetID = function() return 1 end })
        assert.is_false(baganatorShow(reg, cached, widgets, COPPER))
        assert.is_nil(tagOf(cached))
        MailworthyCharDB.lockedItems[COPPER] = { link = "Copper Ore" }
        openWindow(ns)
        baganatorShow(reg, cached, widgets, COPPER)
        assert.is_false(glowing(ns, cached), "another character's locks aren't this one's")
    end)

    it("glows a locked item while the Mailworthy window is open, on the bank view too (no tag there)", function()
        WowStub.setBag(-1, 4, WowStub.item(COPPER, "Copper Ore", { count = 3, sell = 5 }))
        local bag, bank = baganatorLive(0, 1), baganatorLive(-1, 4)
        baganatorShow(reg, bag, widgets, COPPER)
        baganatorShow(reg, bank, widgets, COPPER)
        assert.is_false(glowing(ns, bag), "not locked")
        local before = reg.refreshes
        ns.Locks.ToggleItem(COPPER, "[Copper Ore]", "spec")
        assert.is_true(reg.refreshes > before, "a lock change asks Baganator to redraw")
        WowStub.state.now = WowStub.state.now + ns.Border.FLASH -- past the fresh lock's flash
        WowStub.runTimers(ns.Border.FLASH)
        assert.is_false(glowing(ns, bag), "the flash is over, the window is closed")
        openWindow(ns)
        assert.is_true(glowing(ns, bag), "redrawn at once when the window opens")
        assert.is_true(glowing(ns, bank))
        assert.is_nil(tagOf(bank), "bank items aren't valued: no tag")
        ns.MailWindow.Frame():Hide()
        MailFrame:Hide()
        ns.Fire("MAIL_CLOSED")
        assert.is_false(glowing(ns, bag), "away from the mailbox: no glow")
    end)

    it("is off cleanly with its switch: clears what it drew, then registers nothing after /reload", function()
        local button = baganatorLive(0, 1)
        baganatorShow(reg, button, widgets, COPPER)
        assert.equal("AH", tagOf(button))
        ns.HandleSlash("feature baganatorTags off")
        ns.BankAlt.Redraw()
        assert.is_nil(tagOf(button), "the next redraw clears it")
        assert.equal("", reg.region.region.text)
        local ns2 = loadAddon({ db = MailworthyDB, charDB = MailworthyCharDB })
        local reg2 = stubBaganator()
        login(ns2)
        assert.is_nil(reg2.widget, "nothing registered")
        assert.is_false(ns2.BagAddons.Installed("baganator"))
    end)

    it("without Baganator nothing is registered and nothing breaks", function()
        _G.Baganator = nil
        local ns2 = setup()
        login(ns2)
        assert.is_false(ns2.BagAddons.Installed("baganator"))
        assert.is_false(ns2.BagAddons.InstallBaganator())
    end)
end)

-- Bagnon ---------------------------------------------------------------------------------------------

--- Bagnon's engine as its source has it: Bagnon.ContainerItem.Update (a class method), copied into
--- each button when the button is built (BagBrother's Item:Bind), the inventory frame from
--- Bagnon.Frames:Get("inventory") once built.
local function stubBagnon()
    local class = {}
    function class.Update(self, info) rawset(self, "info", info or self:GetInfo()) end
    local inventory = WowStub.newWidget("Frame", "BagnonInventory1")
    local built = false
    _G.Bagnon = {
        ContainerItem = class,
        Frames = { Get = function() return built and inventory or { id = "inventory" } end },
    }
    local stub = { class = class, inventory = inventory }
    function stub.buildFrame() built = true end
    --- A button: `cached` for another character's bags.
    function stub.button(bag, slot, cached)
        local at = { bag = bag, slot = slot, cached = cached }
        local b = addonButton({
            GetBag = function() return at.bag end, GetID = function() return at.slot end,
            IsCached = function() return at.cached == true end,
            GetInfo = function() return C_Container.GetContainerItemInfo(at.bag, at.slot) or {} end,
        })
        rawset(b, "Update", class.Update) -- Item:Bind: the class's method at build time
        return b, at
    end
    return stub
end

describe("bag addons: Bagnon", function()
    local ns, bagnon
    before_each(function()
        ns = setup()
        bagnon = stubBagnon()
        login(ns)
    end)
    after_each(function() noErrors(ns) cleanup() end)

    it("hooks ContainerItem.Update at ADDON_LOADED, before Bagnon builds its buttons", function()
        local ns2 = setup()
        local b2 = stubBagnon()
        local original = b2.class.Update
        ns2.Fire("ADDON_LOADED", "Mailworthy")
        assert.is_true(ns2.BagAddons.Installed("bagnon"))
        assert.are_not.equal(original, b2.class.Update, "the class method is hooked before PLAYER_LOGIN")
    end)

    it("tags live buttons on every update, recycled to another slot or emptied", function()
        local frames, restore = countFrames()
        local button, at = bagnon.button(0, 1)
        button:Update()
        assert.equal("AH", tagOf(button))
        at.slot = 2
        button:Update()
        assert.equal("V", tagOf(button))
        WowStub.setBag(0, 2, nil)
        button:Update()
        assert.is_nil(tagOf(button), "an empty slot: cleared")
        restore()
        assert.equal(0, frames[1], "no frame created while drawing")
    end)

    it("draws nothing on another character's bags (Bagnon's offline view)", function()
        local button = bagnon.button(0, 1, true)
        button:Update({ itemID = COPPER })
        assert.is_nil(tagOf(button))
    end)

    it("redraws its shown buttons on a lock change and the window, and puts the legend under its bags", function()
        local button = bagnon.button(0, 1)
        bagnon.buildFrame()
        button:Update()
        ns.Locks.ToggleItem(COPPER, "[Copper Ore]", "spec")
        assert.is_nil(tagOf(button), "a lock redraws at once: locked items have no tag")
        WowStub.state.now = WowStub.state.now + ns.Border.FLASH -- past the fresh lock's flash
        WowStub.runTimers(ns.Border.FLASH)
        openWindow(ns)
        assert.is_true(glowing(ns, button))
        ns.MailWindow.Frame():Hide()
        assert.is_false(glowing(ns, button))
        assert.truthy(ns.Report.Build():find("bag addon: Bagnon", 1, true))
        assert.truthy(ns.Report.Build():find("legend shown under its bags", 1, true))
    end)

    it("is off cleanly with its switch", function()
        local button = bagnon.button(0, 1)
        button:Update()
        assert.equal("AH", tagOf(button))
        ns.HandleSlash("feature bagnonTags off")
        ns.BankAlt.Redraw()
        assert.is_nil(tagOf(button))
        local ns2 = loadAddon({ db = MailworthyDB, charDB = MailworthyCharDB })
        local b2 = stubBagnon()
        local original = b2.class.Update
        login(ns2)
        assert.equal(original, b2.class.Update, "not hooked")
    end)
end)

-- ArkInventory ---------------------------------------------------------------------------------------

--- ArkInventory's documented API (Core/ArkInventoryAPI.lua): window bag 1-5 = the game's bags 0-4,
--- location 3 = the bank (window bag 1 = container -1); `items[frame]` is the item table it shows.
local function stubArk()
    local stub = { offline = {}, items = {}, warnings = 0 }
    _G.ArkInventory = {
        Const = { Location = { Bag = 1, Bank = 3, Vault = 4 } },
        API = {
            ItemFrameUpdated = function() end,
            LocationIsOffline = function(loc) return stub.offline[loc] == true end,
            getBlizzardBagIdFromWindowId = function(loc, bag)
                if loc == 1 then return bag - 1 end
                if loc == 3 then return bag == 1 and -1 or bag + 4 end
                stub.warnings = stub.warnings + 1 -- ArkInventory prints a warning for anything else
                return nil
            end,
            ItemFrameItemTableGet = function(frame) return stub.items[frame] end,
        },
    }
    _G.ARKINV_Frame1 = WowStub.newWidget("Frame", "ARKINV_Frame1")
    function stub.frame() return addonButton() end
    --- ArkInventory redraws an item frame: (frame, location, window bag, slot).
    function stub.update(frame, loc, bag, slot, link)
        stub.items[frame] = link and { h = link } or {}
        _G.ArkInventory.API.ItemFrameUpdated(frame, loc, bag, slot)
    end
    return stub
end

describe("bag addons: ArkInventory", function()
    local ns, ark
    before_each(function()
        ns = setup()
        ark = stubArk()
        login(ns)
    end)
    after_each(function() noErrors(ns) cleanup() end)

    it("tags its bag frames through API.ItemFrameUpdated, by the game's bag of its window bag", function()
        local frames, restore = countFrames()
        local f1, f2 = ark.frame(), ark.frame()
        ark.update(f1, 1, 1, 1, WowStub.link(COPPER, "Copper Ore"))
        ark.update(f2, 1, 1, 2, WowStub.link(LINEN, "Linen Cloth"))
        assert.equal("AH", tagOf(f1))
        assert.equal("V", tagOf(f2))
        WowStub.setBag(0, 2, nil)
        ark.update(f2, 1, 1, 2, nil)
        assert.is_nil(tagOf(f2), "emptied")
        restore()
        assert.equal(0, frames[1], "no frame created while drawing")
        assert.truthy(_G.ARKINV_Frame1 and ns.Report.Build():find("legend shown under its bags", 1, true))
    end)

    it("draws nothing for another character (offline), a stale item, or a location that isn't bags", function()
        local f = ark.frame()
        ark.offline[1] = true
        ark.update(f, 1, 1, 1, WowStub.link(COPPER, "Copper Ore"))
        assert.is_nil(tagOf(f))
        ark.offline[1] = nil
        ark.update(f, 1, 1, 1, WowStub.link(LINEN, "Linen Cloth"))
        assert.is_nil(tagOf(f), "ArkInventory shows Linen Cloth where Copper Ore is: drawn on its next update")
        ark.update(f, 4, 1, 1, WowStub.link(COPPER, "Copper Ore"))
        assert.is_nil(tagOf(f))
        assert.equal(0, ark.warnings, "never asks ArkInventory for a bag id outside bags and bank")
    end)

    it("redraws on a lock change and is off cleanly with its switch", function()
        local f = ark.frame()
        ark.update(f, 1, 1, 1, WowStub.link(COPPER, "Copper Ore"))
        assert.equal("AH", tagOf(f))
        openWindow(ns)
        ns.Locks.ToggleItem(COPPER, "[Copper Ore]", "spec")
        assert.is_true(glowing(ns, f))
        assert.is_nil(tagOf(f))
        ns.HandleSlash("feature arkInventoryTags off")
        ns.BankAlt.Redraw()
        assert.is_false(glowing(ns, f), "cleared")
        local ns2 = loadAddon({ db = MailworthyDB, charDB = MailworthyCharDB })
        local ark2 = stubArk()
        local original = _G.ArkInventory.API.ItemFrameUpdated
        login(ns2)
        assert.equal(original, _G.ArkInventory.API.ItemFrameUpdated, "not hooked")
        assert.equal(0, ark2.warnings)
    end)
end)

-- All three at once, and the report --------------------------------------------------------------------

describe("bag addons: all three installed", function()
    after_each(cleanup)

    it("each draws its own buttons through the one helper; /mw report has a line for each", function()
        local ns = setup()
        local reg, bagnon, ark = stubBaganator(), stubBagnon(), stubArk()
        login(ns)
        local widgets = {}
        local b1 = baganatorLive(0, 1)
        baganatorShow(reg, b1, widgets, COPPER)
        local b2 = bagnon.button(0, 2)
        b2:Update()
        local b3 = ark.frame()
        ark.update(b3, 1, 1, 3, WowStub.link(RING, "Green Ring"))
        assert.equal("AH", tagOf(b1))
        assert.equal("V", tagOf(b2))
        assert.equal("DE", tagOf(b3))
        local report = ns.Report.Build()
        assert.truthy(report:find("bag addon: Baganator loaded, switch baganatorTags=on, hooked, 1 button(s) seen, 0 error(s)",
            1, true), report)
        assert.truthy(report:find("bag addon: Bagnon loaded, switch bagnonTags=on, hooked", 1, true))
        assert.truthy(report:find("bag addon: ArkInventory loaded, switch arkInventoryTags=on, hooked", 1, true))
        noErrors(ns)
    end)
end)
