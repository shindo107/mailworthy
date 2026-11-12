-- Pins: "always bank this item". A pin belongs to the ITEM (its item ID), like a lock (Locks.lua),
-- but it is saved for the whole account (MailworthyDB.pins), so the bank alt knows it too: a main
-- pins an item once, Send mails it to the bank alt every time, and it shows the B (Bank) tag there
-- and here, whatever the auction house or this character's professions say.
--
-- A pin is a wish, not a safety rule: every hard keep still wins (locked, soulbound, quest,
-- conjured, in use, a profession tool; Valuation.Evaluate), and it goes only to the bank alt, the
-- recipient the window shows (a binding never takes a pinned item: Routes.Divert).
--
-- Ways to toggle a pin, none of which writes into Blizzard's UI (the lock's techniques):
--   * keyboard / mouse: Ctrl+Alt+click a bag item. The post-hook on the global
--     HandleModifiedItemClick the lock uses for Alt alone; with Ctrl held too Blizzard's own
--     dress-up case may also run for a piece of gear (it opens the dressing room; harmless).
--   * controller: R3 while the bags have focus (PadKey: our own binding; the selected slot is
--     read from SmartNavigation, read-only).
-- /mw pins lists them. Switches: /mw feature pinClick off, /mw feature padPin off.
local _, ns = ...

local Pins = {}
ns.Pins = Pins

Pins.BANK = "bank"

local listeners = {}

local function pins()
    MailworthyDB.pins = type(MailworthyDB.pins) == "table" and MailworthyDB.pins or {}
    return MailworthyDB.pins
end

function Pins.OnChanged(fn) table.insert(listeners, fn) end

--- The pin on an item: Pins.BANK, or nil.
function Pins.Kind(itemID)
    if itemID == nil or type(MailworthyDB) ~= "table" or type(MailworthyDB.pins) ~= "table" then return nil end
    local entry = MailworthyDB.pins[itemID]
    return type(entry) == "table" and entry.kind or nil
end

--- Pin an item (kind = Pins.BANK) or clear its pin (kind = nil). Returns the new kind.
function Pins.Set(itemID, link, kind, how)
    if not itemID then return nil end
    pins()[itemID] = kind and { kind = kind, link = link, at = time() } or nil
    ns.Log.Add("pin", "%s %s (item %d) by %s", kind and ("pinned " .. kind) or "unpinned", tostring(link), itemID,
        tostring(how))
    if kind == Pins.BANK then
        ns.Print(string.format("Bank pin on %s: Send always mails it to your bank alt, on every character.", tostring(link)))
        if ns.Locks.IsItemLocked(itemID) then
            ns.Print("It is locked on this character too, and a lock wins: it stays here until you unlock it.")
        end
    else
        ns.Print(string.format("Pin removed from %s.", tostring(link)))
    end
    for _, fn in ipairs(listeners) do pcall(fn, itemID, kind) end
    return kind
end

--- Toggle the bank pin on whatever item is in this bag slot.
function Pins.Toggle(bag, slot, how)
    local info = ns.Locks.ItemAt(bag, slot)
    if not info or not info.itemID then return nil end
    return Pins.Set(info.itemID, info.hyperlink, Pins.Kind(info.itemID) == nil and Pins.BANK or nil, how)
end

--- The pinned items, by name: { { itemID, link, name, kind } }.
function Pins.List()
    local list = {}
    for itemID, entry in pairs(pins()) do
        if type(entry) == "table" and entry.kind then
            local link = type(entry.link) == "string" and entry.link or nil
            list[#list + 1] = { itemID = itemID, link = link, name = ns.Locks.NameOf(itemID, link), kind = entry.kind }
        end
    end
    table.sort(list, function(a, b)
        if a.name:lower() ~= b.name:lower() then return a.name:lower() < b.name:lower() end
        return tostring(a.itemID) < tostring(b.itemID)
    end)
    return list
end

function Pins.PrintList()
    local list = Pins.List()
    if #list == 0 then
        ns.Print(ns.Gamepad.Fill("No pinned items. Ctrl+Alt+click an item in your bags (controller: {PADRSTICK}) to always"
            .. " bank it."))
        return
    end
    local names = {}
    for i, entry in ipairs(list) do names[i] = tostring(entry.link or entry.name) end
    ns.Print("Bank pins (always mailed to your bank alt): " .. table.concat(names, ", "))
end

--- For /mw report.
function Pins.Describe()
    local list = {}
    for _, entry in ipairs(Pins.List()) do list[#list + 1] = string.format("%d %s %s", entry.itemID, entry.kind, entry.name) end
    return #list > 0 and table.concat(list, ", ") or "none"
end

--- Post-hook of HandleModifiedItemClick(link, itemLocation): Ctrl+Alt (no Shift) + click on a bag item.
function Pins.OnModifiedItemClick(_, itemLocation)
    if not (IsAltKeyDown() and IsControlKeyDown()) or IsShiftKeyDown() then return end
    if type(itemLocation) ~= "table" or type(itemLocation.IsBagAndSlot) ~= "function" then return end
    local okIs, isBag = pcall(itemLocation.IsBagAndSlot, itemLocation)
    if not okIs or not isBag then return end
    local ok, bag, slot = pcall(itemLocation.GetBagAndSlot, itemLocation)
    if ok and ns.Bags.IsBag(bag) and type(slot) == "number" then Pins.Toggle(bag, slot, "Ctrl+Alt+click") end
end

--- Controller (R3 in the bags): the bag slot smart navigation has selected (read-only).
function Pins.ToggleSelectedBagSlot()
    local nav = rawget(_G, "SmartNavigation")
    if type(nav) ~= "table" or type(nav.GetCurrentButton) ~= "function" then return nil end
    local ok, button = pcall(nav.GetCurrentButton, nav)
    if not ok or type(button) ~= "table" or button.buttonContext ~= ns.Locks.BAG_BUTTON_CONTEXT
        or type(button.GetBagID) ~= "function" then
        ns.Log.Add("pin", "R3: no bag item selected")
        return nil
    end
    local okBag, bag = pcall(button.GetBagID, button)
    local okSlot, slot = pcall(button.GetID, button)
    if okBag and okSlot and ns.Bags.IsBag(bag) then return Pins.Toggle(bag, slot, "R3") end
    return nil
end

function Pins.Install()
    if not ns.Features.On("pinClick") then
        ns.Log.Add("pin", "Ctrl+Alt+click pin off (/mw feature pinClick on, then /reload)")
        return false
    end
    if type(HandleModifiedItemClick) ~= "function" then
        ns.Log.Add("pin", "HandleModifiedItemClick missing: no Ctrl+Alt+click pin")
        return false
    end
    local ok, err = pcall(hooksecurefunc, "HandleModifiedItemClick", function(link, itemLocation)
        local okHook, errHook = pcall(Pins.OnModifiedItemClick, link, itemLocation)
        if not okHook then ns.Log.Add("pin", "Ctrl+Alt+click hook error: %s", tostring(errHook)) end
    end)
    ns.Log.Add("pin", "Ctrl+Alt+click pin hook %s", ok and "installed" or ("failed: " .. tostring(err)))
    return ok
end

ns.On("PLAYER_LOGIN", function() Pins.Install() end)
