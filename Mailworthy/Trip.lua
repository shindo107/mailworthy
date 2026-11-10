-- "Worth a mailbox trip": when the bags are nearly full away from a mailbox and something in
-- them would be mailed, one chat line a session ("2 bag slots left. 14 items are worth mailing:
-- +2g 10s more than vendoring."), and the same result as a line in the minimap button's tooltip
-- ("Worth mailing now: 14 items, +2g 10s"). Chat reads the same with a controller.
--
-- Cost: the bags are valued (Bags.Evaluate, the scan the Mailworthy window runs) only at or under
-- THRESHOLD free slots, out of combat, and only when what is in the bags, the settings or the
-- bindings changed since the last scan (Codex review: the free-slot count alone missed junk
-- swapped for ore); above the threshold nothing is scanned.
--
-- Free slots are counted the way the backpack button's number is: the backpack and bags 1-4,
-- general-purpose bags only (bag family 0). A herb bag's or the reagent bag's empty slots don't
-- hold loot. C_Container.GetContainerNumFreeSlots(bag) -> numFreeSlots, bagFamily
-- (Forever's Blizzard_APIDocumentationGenerated/ContainerDocumentation.lua); pcall'd, and one
-- bag without an answer means no count at all (a partial sum would read as "nearly full").
--
-- What "would be mailed" means is Bags.Evaluate's answer with the saved settings: without a bank
-- alt (or on the bank alt itself) its share stays in the bags, so the line only shows when a
-- binding would mail. Display only: nothing is attached or sent from here.
-- Defaults the operator was asked about and did not answer (2026-11-09): 4 or fewer free slots,
-- once per session, only when something is worth mailing. Switch: /mw feature tripNudge off.
local _, ns = ...

local Trip = {}
ns.Trip = Trip

Trip.THRESHOLD = 4 -- free bag slots at or under which the bags are valued

local atMailbox = false -- between MAIL_SHOW and MAIL_CLOSED
local said = false      -- the chat line was printed this session (until /reload or logout)
local last              -- { key, hold, summary = Trip.Summary's or nil } of the last scan, while nearly full

function Trip.On() return ns.Features.On("tripNudge") end

--- Free slots in the backpack and bags 1-4, general-purpose bags only; nil when the game's call
--- is missing or failed for any bag (then nothing is scanned or said).
function Trip.FreeSlots()
    local fn = type(C_Container) == "table" and C_Container.GetContainerNumFreeSlots
    if type(fn) ~= "function" then return nil end
    local total = 0
    for bag = 0, tonumber(NUM_BAG_SLOTS) or 4 do
        local ok, free, family = pcall(fn, bag)
        if not ok or type(free) ~= "number" then return nil end
        if (tonumber(family) or 0) == 0 then total = total + free end
    end
    return total
end

--- What a scan's answer depends on that can be read cheaply: every bag slot's item and count, the
--- settings (with why the bank alt's share is held) and the bindings. Prices are not in it.
local function scanKey(settings)
    local parts, keys = {}, {}
    for k, v in pairs(settings) do
        if type(v) ~= "table" and type(v) ~= "function" then keys[#keys + 1] = k end
    end
    table.sort(keys)
    for _, k in ipairs(keys) do parts[#parts + 1] = k .. "=" .. tostring(settings[k]) end
    for _, r in ipairs(ns.Routes.Active()) do
        parts[#parts + 1] = table.concat({ "route", tostring(r.to), tostring(r.profession or r.class), tostring(r.cap) }, ":")
    end
    for _, slot in ipairs(ns.Bags.Slots()) do
        parts[#parts + 1] = table.concat({ slot.bag, slot.slot, slot.link, slot.count, tostring(slot.inUse) }, ":")
    end
    return table.concat(parts, "|")
end

--- Pure: what a scan (Bags.Evaluate) would mail, or nil when nothing. `gain` is the bank alt's
--- share over vendoring (a binding's stacks have none); `priced` = an auction price source.
function Trip.Summary(scan)
    local t = type(scan) == "table" and scan.totals
    if not t or #scan.mail == 0 or (t.items or 0) <= 0 then return nil end
    return { items = t.items, gain = scan.priced and t.gain or 0 }
end

local function itemsText(n) return string.format("%d item%s", n, n == 1 and "" or "s") end

--- Pure: the chat line.
function Trip.ChatText(free, summary)
    local slots = free == 0 and "No bag slots left." or string.format("%d bag slot%s left.", free, free == 1 and "" or "s")
    local n = summary.items
    if summary.gain > 0 then
        return string.format("%s %s %s worth mailing: +%s more than vendoring.", slots, itemsText(n), n == 1 and "is" or "are",
            ns.Valuation.Money(summary.gain))
    end
    return string.format("%s %s %s ready to mail.", slots, itemsText(n), n == 1 and "is" or "are")
end

--- The minimap tooltip's line from the last scan, or nil (not nearly full, nothing to mail, at a
--- mailbox, or switched off).
function Trip.TooltipText()
    local summary = Trip.On() and not atMailbox and last and last.summary
    -- The bank alt was set or cleared since the scan: the cached answer is no longer true.
    if not summary or last.hold ~= ns.Bags.HoldReason() then return nil end
    return "Worth mailing now: " .. itemsText(summary.items)
        .. (summary.gain > 0 and (", +" .. ns.Valuation.Money(summary.gain)) or "")
end

local function inCombat()
    return type(InCombatLockdown) == "function" and InCombatLockdown() == true
end

local function mailboxOpen()
    if atMailbox then return true end
    local frame = rawget(_G, "MailFrame") -- read only; covers a /reload at an open mailbox
    return type(frame) == "table" and type(frame.IsShown) == "function" and frame:IsShown() == true
end

--- After a bag change: value the bags when they are nearly full, and say so once.
function Trip.Check()
    if not Trip.On() then
        last = nil
        return
    end
    if mailboxOpen() then return end
    local free = Trip.FreeSlots()
    if not free or free > Trip.THRESHOLD then
        last = nil -- room again: the tooltip line goes, and no scan
        return
    end
    if inCombat() then return end -- PLAYER_REGEN_ENABLED checks again
    local settings = ns.Bags.CurrentSettings()
    local key = scanKey(settings)
    if last and last.key == key then return end
    local summary = Trip.Summary(ns.Bags.Evaluate())
    last = { key = key, hold = settings.hold, summary = summary }
    ns.Log.Add("trip", "%d free slot(s): %s", free, summary and (summary.items .. " item(s) to mail, gain "
        .. ns.Valuation.Money(summary.gain)) or "nothing to mail")
    if summary and not said then
        said = true
        ns.Print(Trip.ChatText(free, summary))
    end
end

ns.On("BAG_UPDATE_DELAYED", function() Trip.Check() end)
ns.On("PLAYER_REGEN_ENABLED", function() Trip.Check() end)
-- At a mailbox the Mailworthy window shows the list itself; after the visit the bags have changed.
ns.On("MAIL_SHOW", function() atMailbox, last = true, nil end)
ns.On("MAIL_CLOSED", function() atMailbox, last = false, nil end)
