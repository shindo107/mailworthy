-- Return to sender (operator, 2026-11-08: "a button that just allows me to 'queue up' a return
-- to sender list. it should be a toggle ... everything that was mailed to you by someone gets put
-- on the same list we use for regular mailworthy evaluations to mail back to them ... available
-- to everyone, not just bank alts. clicking it again returns it to normal mode").
--
-- A toggle on the Mailworthy window, for this mailbox visit (off again at MAIL_CLOSED, like Skip
-- once). While it is on, what another character mailed this one goes back to them, on the same
-- Mailing list as everything else, shown with its recipient before Send and sent only by Send.
--
-- Who mailed what comes from the mail ledger (Ledger.lua): every item this character took out
-- of the mailbox, with its sender. Counted per sender and item: what was received from them,
-- less what this character has mailed them since (a return already made, a gift back). Not
-- counted: system mail (the auction house, GMs), COD mail (a purchase), returned mail (our own
-- items coming back). Several senders of one item: the latest first. Whole stacks only (the
-- mailer never splits a stack): a stack bigger than what is still owed stays and follows the
-- normal rule. Hard keeps (locked, soulbound, quest, conjured, in use, a profession tool) never go.
-- Switch: /mw feature returnToSender off (no button).
local _, ns = ...

local Returns = {}
ns.Returns = Returns

Returns.WHAT = "Returned items" -- the recipient line's note and the Mailing list's group
Returns.REASON = "returned to sender"

local on = false

function Returns.Available()
    return ns.Features.On("returnToSender") and ns.Features.On("ledger")
end

function Returns.On() return on and Returns.Available() end

function Returns.Set(value)
    on = value == true
    ns.Log.Add("returns", "return to sender %s", on and "on" or "off")
end

function Returns.Toggle()
    Returns.Set(not on)
    return on
end

local function key(name)
    local clean = ns.Routes.Clean(name)
    return clean and clean:lower() or nil, clean
end

--- Pure: what this character (`me`) still holds for each player who mailed it items, from the
--- ledger's log (oldest first). Returns itemID -> { { to = name, count = n, at = last receipt },
--- ... }, the latest sender first.
function Returns.Owed(log, me)
    local mine = key(me)
    local byWho, names = {}, {}
    for _, e in ipairs(type(log) == "table" and log or {}) do
        local who, name = key(type(e) == "table" and e.other)
        if who and who ~= mine and key(e.char) == mine then
            local received = e.dir == "received" and not e.system and not e.returned and (tonumber(e.cod) or 0) == 0
            if received or e.dir == "sent" then
                names[who] = names[who] or name
                byWho[who] = byWho[who] or {}
                for _, it in ipairs(type(e.items) == "table" and e.items or {}) do
                    local id, count = tonumber(it.itemID), tonumber(it.count) or 1
                    if id then
                        local o = byWho[who][id] or { count = 0, at = 0 }
                        byWho[who][id] = o
                        if received then
                            o.count, o.at = o.count + count, tonumber(e.at) or o.at
                        else
                            o.count = math.max(0, o.count - count)
                        end
                    end
                end
            end
        end
    end
    local owed = {}
    for who, items in pairs(byWho) do
        for id, o in pairs(items) do
            if o.count > 0 then
                owed[id] = owed[id] or {}
                table.insert(owed[id], { to = names[who], count = o.count, at = o.at })
            end
        end
    end
    for _, list in pairs(owed) do
        table.sort(list, function(a, b)
            if a.at ~= b.at then return a.at > b.at end
            return a.to < b.to
        end)
    end
    return owed
end

--- What this character owes back right now (Returns.Owed over this realm + faction's ledger).
function Returns.Current()
    return Returns.Owed(ns.Ledger.Store().log, ns.PlayerName())
end

--- Pure: which of `slots` ({ bag, slot, count }) go back to whom, from `owed` (this item ID's
--- list from Returns.Owed; counts are used up, so several bag groups of one item share it).
--- Whole stacks, the biggest first, never past what is owed. Returns { { to, slots, count } },
--- and the slots left over.
function Returns.Split(slots, owed)
    local left = {}
    for _, s in ipairs(slots or {}) do left[#left + 1] = s end
    table.sort(left, function(a, b)
        if a.count ~= b.count then return a.count > b.count end
        if a.bag ~= b.bag then return a.bag < b.bag end
        return a.slot < b.slot
    end)
    local parts = {}
    for _, o in ipairs(owed or {}) do
        local part = { to = o.to, slots = {}, count = 0 }
        local keep = {}
        for _, s in ipairs(left) do
            if o.count > 0 and s.count <= o.count then
                part.slots[#part.slots + 1] = s
                part.count = part.count + s.count
                o.count = o.count - s.count
            else
                keep[#keep + 1] = s
            end
        end
        left = keep
        if #part.slots > 0 then parts[#parts + 1] = part end
    end
    -- Back in bag order, as the scan had them (the mailer attaches in this order).
    local function bagOrder(a, b)
        if a.bag ~= b.bag then return a.bag < b.bag end
        return a.slot < b.slot
    end
    for _, p in ipairs(parts) do table.sort(p.slots, bagOrder) end
    table.sort(left, bagOrder)
    return parts, left
end

--- The result of a stack group going back to `to` (Bags.Evaluate files it under Mailing).
function Returns.Result(to, stacks, settings)
    return { action = "mail", route = "return", to = to, what = Returns.WHAT, reason = Returns.REASON,
        postage = (settings and settings.postage or 0) * stacks }
end

ns.On("MAIL_CLOSED", function()
    if on then Returns.Set(false) end
end)
