-- Item locks: items Mailworthy never mails. A lock belongs to the ITEM (its item
-- ID), not to a bag slot, so it follows the item when you move it or sort your
-- bags, and covers every stack of it. Saved per character. Slot locks from
-- earlier builds are converted at login from what's in those slots.
--
-- Ways to toggle a lock, none of which writes into Blizzard's UI:
--   * keyboard / mouse: Alt+click a bag item. A post-hook on the global
--     HandleModifiedItemClick, which the bag item button calls for modified
--     clicks; with only Alt held it matches none of its cases (chat link,
--     dress-up, expand), so Blizzard does nothing else with the click.
--   * controller: L3 while the bags have focus (PadKey: our own binding; the
--     selected slot is read from SmartNavigation, read-only), or pressing the
--     item's row in the Mailworthy window.
--   * either: Unlock in the locked items window (LocksUI.lua; /mw locks, Settings > More),
--     the only way for an item that is no longer in the bags.
--
-- Not the gamepad Triangle "More" menu: adding an entry there (Menu.ModifyMenu
-- on MORE_CONTEXT_ACTIONS) taints the gamepad UI by design; jumping, targeting
-- and item use got blocked (alpha1/alpha2, 2026-10-13). See docs/FOREVER-UI-NOTES.md.
local _, ns = ...

local Locks = {}
ns.Locks = Locks

Locks.BAG_BUTTON_CONTEXT = "ButtonContext_ContainerFrameItemButton"

local listeners = {}

local function items() return MailworthyCharDB and MailworthyCharDB.lockedItems or {} end

function Locks.OnChanged(fn) table.insert(listeners, fn) end

local function itemAt(bag, slot)
    local get = C_Container and C_Container.GetContainerItemInfo
    if type(get) ~= "function" then return nil end
    local ok, info = pcall(get, bag, slot)
    return ok and type(info) == "table" and info or nil
end
Locks.ItemAt = itemAt

function Locks.IsItemLocked(itemID)
    return itemID ~= nil and items()[itemID] ~= nil
end

--- Is the item currently in this bag slot locked?
function Locks.IsLocked(bag, slot)
    local info = itemAt(bag, slot)
    return info ~= nil and Locks.IsItemLocked(info.itemID)
end

--- Listeners get (itemID, locked) for a toggle (Border flashes a fresh lock).
local function notify(itemID, locked)
    for _, fn in ipairs(listeners) do pcall(fn, itemID, locked) end
end

function Locks.ToggleItem(itemID, link, how)
    if not itemID then return nil end
    local locked = not Locks.IsItemLocked(itemID)
    MailworthyCharDB.lockedItems[itemID] = locked and { link = link, at = time() } or nil
    ns.Log.Add("lock", "%s %s (item %d) by %s", locked and "locked" or "unlocked", tostring(link), itemID, tostring(how))
    ns.Print(string.format("%s %s (every stack, wherever it is).", locked and "Locked" or "Unlocked", tostring(link)))
    notify(itemID, locked)
    return locked
end

--- Toggle the lock on whatever item is in this bag slot.
function Locks.Toggle(bag, slot, how)
    local info = itemAt(bag, slot)
    if not info then return nil end
    return Locks.ToggleItem(info.itemID, info.hyperlink, how)
end

function Locks.PrintList()
    local list = {}
    for itemID, entry in pairs(items()) do list[#list + 1] = tostring(entry.link or itemID) end
    table.sort(list)
    ns.Print(#list == 0 and "No locked items." or ("Locked items: " .. table.concat(list, ", ")))
end

--- How many items are locked on this character.
function Locks.Count()
    local n = 0
    for _ in pairs(items()) do n = n + 1 end
    return n
end

--- Pure: an item's name out of its link ("|cff..|Hitem:2770..|h[Copper Ore]|h|r" -> "Copper Ore"),
--- or "item 2770" without one.
function Locks.NameOf(itemID, link)
    local name = type(link) == "string" and link:match("%[(.-)%]") or nil
    return name and name ~= "" and name or ("item " .. tostring(itemID))
end

--- itemID -> how many of it the bags hold now (backpack, bags 1-4, reagent bag; every stack).
function Locks.BagCounts()
    local counts = {}
    local numSlots = C_Container and C_Container.GetContainerNumSlots
    if type(numSlots) ~= "function" then return counts end
    for bag = 0, ns.Bags.LastBag() do
        local ok, n = pcall(numSlots, bag)
        for slot = 1, ok and tonumber(n) or 0 do
            local info = itemAt(bag, slot)
            if info and info.itemID then
                counts[info.itemID] = (counts[info.itemID] or 0) + (tonumber(info.stackCount) or 1)
            end
        end
    end
    return counts
end

--- The locked items, by name: { { itemID, link, name, count, locked = true } }, `count` = how many
--- the bags hold now (0: banked, used up, sold; the lock is still there and can be removed in
--- the locked items window, LocksUI.lua). `also` (itemID -> link): items to list too though
--- they aren't locked (the window keeps a row it just unlocked, so the press can be undone).
function Locks.List(also)
    local counts, list = Locks.BagCounts(), {}
    local function add(itemID, link, locked)
        link = type(link) == "string" and link or nil
        list[#list + 1] = { itemID = itemID, link = link, name = Locks.NameOf(itemID, link),
            count = counts[itemID] or 0, locked = locked }
    end
    for itemID, entry in pairs(items()) do add(itemID, type(entry) == "table" and entry.link, true) end
    for itemID, link in pairs(also or {}) do
        if not Locks.IsItemLocked(itemID) then add(itemID, link, false) end
    end
    table.sort(list, function(a, b)
        if a.name:lower() ~= b.name:lower() then return a.name:lower() < b.name:lower() end
        return tostring(a.itemID) < tostring(b.itemID)
    end)
    return list
end

function Locks.Describe()
    local list = {}
    for itemID, entry in pairs(items()) do list[#list + 1] = string.format("%d %s", itemID, tostring(entry.link)) end
    table.sort(list)
    return #list > 0 and table.concat(list, ", ") or "none"
end

--- Slot locks from alpha3/alpha4 ("bag:slot") become item locks for what's in those slots now.
function Locks.MigrateSlotLocks()
    local slots = MailworthyCharDB.lockedSlots
    if type(slots) ~= "table" then return 0 end
    local n = 0
    for key in pairs(slots) do
        local bag, slot = key:match("^(%-?%d+):(%d+)$")
        local info = bag and itemAt(tonumber(bag), tonumber(slot))
        if info and not Locks.IsItemLocked(info.itemID) then
            MailworthyCharDB.lockedItems[info.itemID] = { link = info.hyperlink, at = time() }
            n = n + 1
        end
    end
    MailworthyCharDB.lockedSlots = nil
    ns.Log.Add("lock", "converted %d slot lock(s) to item locks", n)
    return n
end

local function isBagSlot(bag)
    return ns.Bags.IsBag(bag) -- backpack, bags 1-4 and the reagent bag; not the bank
end

--- Post-hook of HandleModifiedItemClick(link, itemLocation): Alt (alone) + click on a bag item.
function Locks.OnModifiedItemClick(_, itemLocation)
    if not IsAltKeyDown() or IsShiftKeyDown() or IsControlKeyDown() then return end
    if type(itemLocation) ~= "table" or type(itemLocation.IsBagAndSlot) ~= "function" then return end
    local okIs, isBag = pcall(itemLocation.IsBagAndSlot, itemLocation)
    if not okIs or not isBag then return end
    local ok, bag, slot = pcall(itemLocation.GetBagAndSlot, itemLocation)
    if ok and isBagSlot(bag) and type(slot) == "number" then Locks.Toggle(bag, slot, "Alt+click") end
end

--- Controller (L3 in the bags): the bag slot smart navigation has selected (read-only).
function Locks.ToggleSelectedBagSlot()
    local nav = rawget(_G, "SmartNavigation")
    if type(nav) ~= "table" or type(nav.GetCurrentButton) ~= "function" then return nil end
    local ok, button = pcall(nav.GetCurrentButton, nav)
    if not ok or type(button) ~= "table" or button.buttonContext ~= Locks.BAG_BUTTON_CONTEXT
        or type(button.GetBagID) ~= "function" then
        ns.Log.Add("lock", "L3: no bag item selected")
        return nil
    end
    local okBag, bag = pcall(button.GetBagID, button)
    local okSlot, slot = pcall(button.GetID, button)
    if okBag and okSlot and isBagSlot(bag) then return Locks.Toggle(bag, slot, "L3") end
    return nil
end

function Locks.Install()
    if not ns.Features.On("altClickLock") then
        ns.Log.Add("lock", "Alt+click lock off (/mw feature altClickLock on, then /reload)")
        return false
    end
    if type(HandleModifiedItemClick) ~= "function" then
        ns.Log.Add("lock", "HandleModifiedItemClick missing: no Alt+click lock")
        return false
    end
    local ok, err = pcall(hooksecurefunc, "HandleModifiedItemClick", function(link, itemLocation)
        local okHook, errHook = pcall(Locks.OnModifiedItemClick, link, itemLocation)
        if not okHook then ns.Log.Add("lock", "Alt+click hook error: %s", tostring(errHook)) end
    end)
    ns.Log.Add("lock", "Alt+click lock hook %s", ok and "installed" or ("failed: " .. tostring(err)))
    return ok
end

ns.On("PLAYER_LOGIN", function()
    Locks.MigrateSlotLocks()
    Locks.Install()
end)
