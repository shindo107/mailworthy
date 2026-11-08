-- Mailworthy's bag tags (AH / B / DE / V, BankAlt.lua) and the lock glow (Border.lua) in the bag
-- addons that replace the game's bags (operator, 2026-11-08: "id like to support the top 3 bag
-- addons"). Picked by CurseForge downloads among bag addons with a Forever 1.60.1 build, read the
-- same day: Bagnon 170.3M, Baganator 41.6M, ArkInventory 14.0M (BetterBags 4.9M; AdiBags has no
-- Forever build of its own). Each through its own public interface, read in its source:
--
--   * Baganator (846): a corner widget (`Baganator.API.RegisterCornerWidget`: onInit(itemButton)
--     once per button, onUpdate(widget, details) whenever the button shows an item), the public
--     `Baganator.CallbackRegistry` "ViewComplete" after every layout pass (an emptied slot gets
--     no onUpdate), a "backpack" bottom-left region for the legend (`RegisterRegion`) and
--     `RequestItemButtonsRefresh`. Live buttons inherit ContainerFrameItemButtonTemplate
--     (GetBagID); another character's (cached) buttons and guild bank buttons don't.
--   * Bagnon (12.1.x, its BagBrother engine): a post-hook on the class method
--     `Bagnon.ContainerItem.Update` (every inventory and bank button, live or cached, runs it on
--     each redraw; `IsCached`, `GetBag`, `GetID`). BagBrother's `Item:Bind` copies the class's
--     methods into each button when it is built, so the hook goes in at our ADDON_LOADED, before
--     Bagnon builds its inventory at PLAYER_ENTERING_WORLD (Bagnon is an OptionalDep: it loads
--     first).
--   * ArkInventory: its documented API, `hooksecurefunc(ArkInventory.API, "ItemFrameUpdated")`
--     (frame, location, window bag, slot), `LocationIsOffline`, `getBlizzardBagIdFromWindowId`,
--     `ItemFrameItemTableGet` (the item's link as `.h`); bag and bank locations only.
--
-- Every button is drawn by Border.DrawBagSlot / Border.RefreshButton, the one helper the game's
-- bags and Auctionator's views use too: what is in the bag slot right now, cleared when the slot is
-- empty, when the addon shows something else there, or when it shows another character's bags.
-- Textures and font strings live in Border's and BankAlt's weak tables keyed by button; nothing is
-- written on the addons' frames, and no frame is created (the legend font strings are regions).
-- Switches: /mw feature baganatorTags / bagnonTags / arkInventoryTags off; each does nothing while
-- its addon isn't loaded. Every call into an addon is pcall'd (README "Beta unknowns").
local _, ns = ...

local BagAddons = {}
ns.BagAddons = BagAddons

BagAddons.LIST = { "baganator", "bagnon", "arkInventory" }
BagAddons.FEATURE = { baganator = "baganatorTags", bagnon = "bagnonTags", arkInventory = "arkInventoryTags" }
BagAddons.NAME = { baganator = "Baganator", bagnon = "Bagnon", arkInventory = "ArkInventory" }
-- Kept from v0.2x's lock-glow-only widget: Baganator remembers the corner it auto-added under this ID.
BagAddons.BAGANATOR_ID = "mailworthy_lock"
BagAddons.BAGANATOR_LABEL = "Mailworthy tags and lock glow"

local weak = { __mode = "k" }
local seen = { baganator = setmetatable({}, weak), bagnon = setmetatable({}, weak),
    arkInventory = setmetatable({}, weak) } -- button -> true (ArkInventory: { loc, bag, slot })
local installed, errors, legends = {}, { baganator = 0, bagnon = 0, arkInventory = 0 }, {}
local baganatorOwners = setmetatable({}, weak) -- widget -> its item button
local baganatorOwner = {} -- our owner key in Baganator's callback registry

local function logError(key, err)
    errors[key] = errors[key] + 1
    if errors[key] <= 5 then ns.Log.Add("bagaddons", "%s error: %s", BagAddons.NAME[key], tostring(err)) end
end

--- Is this addon's integration on: its switch, and the tags or the glow at all?
function BagAddons.On(key)
    return ns.Features.On(BagAddons.FEATURE[key]) and (ns.Features.On("slotBorder") or ns.Features.On("bankAltTags"))
end

local function visible(region)
    if type(region) ~= "table" or type(region.IsVisible) ~= "function" then return false end
    local ok, shown = pcall(region.IsVisible, region)
    return ok and shown == true
end

local function count(t)
    local n = 0
    for _ in pairs(t) do n = n + 1 end
    return n
end

-- Legends: the tags explained under each addon's bag window, no hover needed (Blizzard's bags have
-- theirs in BankAlt.lua). Font strings, kept here.

local function legendUnder(key, host)
    if legends[key] then return legends[key] end
    if type(host) ~= "table" or type(host.CreateFontString) ~= "function" then return nil end
    local ok, fs = pcall(host.CreateFontString, host, nil, "OVERLAY", "GameFontHighlightSmall")
    if not ok or type(fs) ~= "table" then return nil end
    fs:SetPoint("TOPRIGHT", host, "BOTTOMRIGHT", -10, -4)
    legends[key] = fs
    return fs
end

local function setLegend(key, fs)
    if not fs then return end
    local text = BagAddons.On(key) and ns.BankAlt.LegendText() or ""
    pcall(fs.SetText, fs, text)
end

-- Baganator ------------------------------------------------------------------------------------------

local function baganatorAPI()
    local b = rawget(_G, "Baganator")
    local api = type(b) == "table" and b.API or nil
    if type(api) == "table" and type(api.RegisterCornerWidget) == "function" then return api end
    return nil
end

--- A live Baganator button's bag and slot, or nil (another character's bags, a guild bank tab).
local function baganatorSlot(button)
    if type(button.GetBagID) ~= "function" or type(button.GetID) ~= "function" then return nil end
    local okBag, bag = pcall(button.GetBagID, button)
    local okSlot, slot = pcall(button.GetID, button)
    if okBag and okSlot and type(bag) == "number" and type(slot) == "number" then return bag, slot end
    return nil
end

--- Draw one Baganator button; true when it shows one of our tags.
local function drawBaganator(button, shownID, wanted)
    if not BagAddons.On("baganator") then
        ns.Border.Clear(button)
        return false
    end
    local bag, slot = baganatorSlot(button)
    if bag == nil then
        ns.Border.Clear(button)
        return false
    end
    ns.Border.DrawBagSlot(button, bag, slot, shownID, wanted)
    return ns.BankAlt.TagShown(button)
end

--- Baganator's onInit: an empty texture the size of our tag that remembers its button. A texture,
--- not a frame: Baganator may build buttons while a gamepad panel is open (AGENTS.md: no
--- CreateFrame then). It has no image, so it never draws anything itself.
function BagAddons.BaganatorInit(itemButton)
    local widget = itemButton:CreateTexture(nil, "OVERLAY")
    widget:SetSize(18, 11)
    widget:Hide()
    baganatorOwners[widget] = itemButton
    seen.baganator[itemButton] = true
    return widget
end

--- Baganator's onUpdate: draw the button; true while our tag shows, so Baganator keeps that corner
--- for it (no other top-left widget on top of the tag), false otherwise.
function BagAddons.BaganatorUpdate(widget, details)
    local button = baganatorOwners[widget]
    if not button then return false end
    local shownID = type(details) == "table" and tonumber(details.itemID) or nil
    local ok, shown = pcall(drawBaganator, button, shownID)
    if not ok then
        logError("baganator", shown)
        return false
    end
    return shown == true
end

--- What Baganator itself says the button shows (its `BGR` details, read only): the item ID, or
--- false for an empty button, or nil when it doesn't say.
local function baganatorShown(button)
    local ok, details = pcall(rawget, button, "BGR")
    if not ok or type(details) ~= "table" then return nil end
    return tonumber(details.itemID) or false
end

local function redrawBaganator(wanted)
    for button in pairs(seen.baganator) do
        if visible(button) then
            local shownID = baganatorShown(button)
            local ok, err
            if shownID == false then
                ok, err = pcall(ns.Border.Clear, button) -- Baganator shows nothing there
            else
                ok, err = pcall(drawBaganator, button, shownID, wanted)
            end
            if not ok then logError("baganator", err) end
        end
    end
    setLegend("baganator", legends.baganator)
end

function BagAddons.InstallBaganator()
    if installed.baganator then return true end
    local api = baganatorAPI()
    if not api then return false end
    local ok, err = pcall(api.RegisterCornerWidget, BagAddons.BAGANATOR_LABEL, BagAddons.BAGANATOR_ID,
        BagAddons.BaganatorUpdate, BagAddons.BaganatorInit, { corner = "top_left", priority = 1 })
    if not ok then
        ns.Log.Add("bagaddons", "Baganator corner widget failed: %s", tostring(err))
        return false
    end
    installed.baganator = true
    -- After each layout pass: an emptied or reassigned slot gets no onUpdate.
    local registry = rawget(_G, "Baganator").CallbackRegistry
    if type(registry) == "table" and type(registry.RegisterCallback) == "function" then
        pcall(registry.RegisterCallback, registry, "ViewComplete", function()
            local okRedraw, errRedraw = pcall(redrawBaganator)
            if not okRedraw then logError("baganator", errRedraw) end
        end, baganatorOwner)
    end
    -- The legend: a font string made here (UIParent's region), which Baganator places in the
    -- backpack's bottom-left button row.
    if type(api.RegisterRegion) == "function" and type(UIParent) == "table" then
        local okFs, fs = pcall(UIParent.CreateFontString, UIParent, nil, "OVERLAY", "GameFontHighlightSmall")
        if okFs and type(fs) == "table" and pcall(api.RegisterRegion, "Mailworthy tags", "mailworthy_legend",
            "backpack", "bottom_left", fs) then
            legends.baganator = fs
        end
    end
    ns.Log.Add("bagaddons", "Baganator: tags and lock glow registered (its settings, Icons, top left corner)")
    return true
end

-- Bagnon ---------------------------------------------------------------------------------------------

local function bagnonClass()
    local b = rawget(_G, "Bagnon")
    if type(b) ~= "table" then return nil end
    local ok, class = pcall(function() return b.ContainerItem end)
    if ok and type(class) == "table" and type(class.Update) == "function" then return class end
    return nil
end

local function bagnonLegend()
    if legends.bagnon then return legends.bagnon end
    local b = rawget(_G, "Bagnon")
    local frames = type(b) == "table" and b.Frames
    if type(frames) ~= "table" or type(frames.Get) ~= "function" then return nil end
    local ok, frame = pcall(frames.Get, frames, "inventory")
    -- Before it is built, Get returns the registry entry (a plain table, no CreateFontString).
    if not ok then return nil end
    return legendUnder("bagnon", frame)
end

local function drawBagnon(button, wanted)
    if not BagAddons.On("bagnon") then
        ns.Border.Clear(button)
        return
    end
    local okCached, cached = pcall(button.IsCached, button)
    local okBag, bag = pcall(button.GetBag, button)
    local okSlot, slot = pcall(button.GetID, button)
    if not (okCached and okBag and okSlot) or cached or type(bag) ~= "number" or type(slot) ~= "number" then
        ns.Border.Clear(button) -- another character's bags (Bagnon's offline view)
        return
    end
    local info = rawget(button, "info") -- read only: the item Bagnon shows on it
    local shownID = type(info) == "table" and tonumber(info.itemID) or nil
    ns.Border.DrawBagSlot(button, bag, slot, shownID, wanted)
end

--- The post-hook on Bagnon.ContainerItem.Update (self = the item button).
function BagAddons.BagnonUpdate(button)
    if type(button) ~= "table" then return end
    seen.bagnon[button] = true
    local ok, err = pcall(drawBagnon, button)
    if not ok then logError("bagnon", err) end
    if not legends.bagnon then setLegend("bagnon", bagnonLegend()) end
end

local function redrawBagnon(wanted)
    for button in pairs(seen.bagnon) do
        if visible(button) then
            local ok, err = pcall(drawBagnon, button, wanted)
            if not ok then logError("bagnon", err) end
        end
    end
    setLegend("bagnon", bagnonLegend())
end

function BagAddons.InstallBagnon()
    if installed.bagnon then return true end
    local class = bagnonClass()
    if not class then return false end
    if rawget(class, "__bindList") ~= nil then
        ns.Log.Add("bagaddons", "Bagnon built its buttons before Mailworthy loaded: no tags on them until /reload")
    end
    local ok, err = pcall(hooksecurefunc, class, "Update", BagAddons.BagnonUpdate)
    if not ok then
        ns.Log.Add("bagaddons", "Bagnon hook failed: %s", tostring(err))
        return false
    end
    installed.bagnon = true
    ns.Log.Add("bagaddons", "Bagnon: tags and lock glow hooked (ContainerItem.Update)")
    return true
end

-- ArkInventory ---------------------------------------------------------------------------------------

local function arkAPI()
    local a = rawget(_G, "ArkInventory")
    local api = type(a) == "table" and a.API or nil
    if type(api) == "table" and type(api.ItemFrameUpdated) == "function" then return api end
    return nil
end

--- ArkInventory's location IDs whose bags are the game's containers (Bag 1, Bank 3, its Const).
local function arkContainerLocation(loc)
    local a = rawget(_G, "ArkInventory")
    local ids = type(a) == "table" and type(a.Const) == "table" and type(a.Const.Location) == "table"
        and a.Const.Location or {}
    return loc == (tonumber(ids.Bag) or 1) or loc == (tonumber(ids.Bank) or 3)
end

local function arkLegend()
    if legends.arkInventory then return legends.arkInventory end
    local a = rawget(_G, "ArkInventory")
    local ids = type(a) == "table" and type(a.Const) == "table" and type(a.Const.Location) == "table"
        and a.Const.Location or {}
    return legendUnder("arkInventory", rawget(_G, "ARKINV_Frame" .. tostring(tonumber(ids.Bag) or 1)))
end

local function drawArk(frame, loc, bagWindow, slot, wanted)
    local api = arkAPI()
    if not api or not BagAddons.On("arkInventory") or not arkContainerLocation(loc) or type(slot) ~= "number" then
        ns.Border.Clear(frame)
        return
    end
    local okOffline, offline = pcall(api.LocationIsOffline, loc)
    local okBag, bag = pcall(api.getBlizzardBagIdFromWindowId, loc, bagWindow)
    if not (okOffline and okBag) or offline ~= false or type(bag) ~= "number" then
        ns.Border.Clear(frame) -- another character's bags, or a bank away from the bank
        return
    end
    local okItem, i = pcall(api.ItemFrameItemTableGet, frame)
    local shownID = okItem and type(i) == "table" and ns.Border.LinkID(i.h) or nil
    ns.Border.DrawBagSlot(frame, bag, slot, shownID, wanted)
end

--- The post-hook on ArkInventory.API.ItemFrameUpdated(frame, loc_id, bag_id, slot_id).
function BagAddons.ArkUpdated(frame, loc, bagWindow, slot)
    if type(frame) ~= "table" then return end
    seen.arkInventory[frame] = { loc, bagWindow, slot }
    local ok, err = pcall(drawArk, frame, loc, bagWindow, slot)
    if not ok then logError("arkInventory", err) end
    if not legends.arkInventory then setLegend("arkInventory", arkLegend()) end
end

local function redrawArk(wanted)
    for frame, at in pairs(seen.arkInventory) do
        if visible(frame) then
            local ok, err = pcall(drawArk, frame, at[1], at[2], at[3], wanted)
            if not ok then logError("arkInventory", err) end
        end
    end
    setLegend("arkInventory", arkLegend())
end

function BagAddons.InstallArkInventory()
    if installed.arkInventory then return true end
    local api = arkAPI()
    if not api then return false end
    local ok, err = pcall(hooksecurefunc, api, "ItemFrameUpdated", BagAddons.ArkUpdated)
    if not ok then
        ns.Log.Add("bagaddons", "ArkInventory hook failed: %s", tostring(err))
        return false
    end
    installed.arkInventory = true
    ns.Log.Add("bagaddons", "ArkInventory: tags and lock glow hooked (API.ItemFrameUpdated)")
    return true
end

-- All three ------------------------------------------------------------------------------------------

local INSTALL = { baganator = BagAddons.InstallBaganator, bagnon = BagAddons.InstallBagnon,
    arkInventory = BagAddons.InstallArkInventory }

function BagAddons.Install()
    for _, key in ipairs(BagAddons.LIST) do
        if not installed[key] and BagAddons.On(key) then INSTALL[key]() end
    end
end

function BagAddons.Installed(key) return installed[key] == true end

--- Border.RefreshAll's refresher: redraw every shown button of the installed addons (lock changes,
--- the Mailworthy window opening or closing, bag updates, new prices).
function BagAddons.RefreshAll(wanted)
    if installed.baganator then
        redrawBaganator(wanted)
        local api = baganatorAPI()
        if api and type(api.RequestItemButtonsRefresh) == "function" then pcall(api.RequestItemButtonsRefresh) end
    end
    if installed.bagnon then redrawBagnon(wanted) end
    if installed.arkInventory then redrawArk(wanted) end
end

local function loaded(name)
    local addons = rawget(_G, "C_AddOns")
    local isLoaded = type(addons) == "table" and addons.IsAddOnLoaded or rawget(_G, "IsAddOnLoaded")
    if type(isLoaded) ~= "function" then return nil end
    local ok, yes = pcall(isLoaded, name)
    return ok and yes and true or false
end

local function version(name)
    local addons = rawget(_G, "C_AddOns")
    local get = type(addons) == "table" and addons.GetAddOnMetadata or rawget(_G, "GetAddOnMetadata")
    if type(get) ~= "function" then return nil end
    local ok, v = pcall(get, name, "Version")
    return ok and v or nil
end

local PRESENT = { baganator = baganatorAPI, bagnon = bagnonClass, arkInventory = arkAPI }

--- /mw report: one line per bag addon.
function BagAddons.ReportLines()
    local lines = {}
    for _, key in ipairs(BagAddons.LIST) do
        local name = BagAddons.NAME[key]
        local present = PRESENT[key]() ~= nil or loaded(name) == true
        local text
        if not present then
            text = "not loaded"
        else
            local v = version(name)
            text = string.format("%s, switch %s=%s, %s, %d button(s) seen, %d error(s)%s",
                v and ("v" .. tostring(v)) or "loaded", BagAddons.FEATURE[key],
                ns.Features.On(BagAddons.FEATURE[key]) and "on" or "off",
                installed[key] and "hooked" or "not hooked", count(seen[key]), errors[key],
                legends[key] and ", legend shown under its bags" or "")
        end
        lines[#lines + 1] = "bag addon: " .. name .. " " .. text
    end
    return lines
end

ns.Border.AddRefresher(function(wanted) BagAddons.RefreshAll(wanted) end)

-- At our ADDON_LOADED (after Core's Init): before Bagnon builds its buttons. PLAYER_LOGIN again for
-- an addon loaded after us (Install is idempotent).
ns.On("ADDON_LOADED", function(name)
    if name == ns.NAME then BagAddons.Install() end
end)
ns.On("PLAYER_LOGIN", function() BagAddons.Install() end)
