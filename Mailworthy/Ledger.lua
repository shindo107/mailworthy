-- Mail ledger (operator, 2026-11-07): "a player exportable log of everything that was sent,
-- in case someone ever needs to validate where items went", and, from it, what another player
-- mailed you beyond what you have mailed back ("encourage players to pay back who sent them
-- materials"; "i dont ever want to see a list of 'who owes me'").
--
-- The log: every mail this account's characters send (Mailworthy's own runs and Blizzard's
-- Send button) and every item or gold they take out of the mailbox, with the date, both
-- names, the subject, each item and count, and its value. Account-wide per realm + faction,
-- the newest LOG_MAX entries; /mw ledger's Export log puts it in the copy box.
--
-- The balance, per other player (not this account's characters, not the auction house or
-- other system mail, not cash on delivery): what they mailed you (items at their value, plus
-- gold) minus what you mailed them. Only your own side ever shows: a player you received more
-- from than you sent back ("you've received 10s more from Bob than you've sent back"). Nobody
-- is ever listed as owing you. Kept as running totals, so they outlive the log's pruning.
--
-- Values, "captured at the time of send": what you send is valued with your own prices when it
-- goes. What you receive takes the sender's value when their Mailworthy told yours (a "V2"
-- whisper right after the send, or as soon as they hear from you later), else your own price
-- when you take it. A sender's value counts at most PRICE_CAP times your own price, so a
-- made-up value can't run up a debt. Without a price an item is listed by count only.
--
-- How it sees mail: hooksecurefunc post-hooks on SendMail, TakeInboxItem, AutoLootMailItem and
-- TakeInboxMoney (AGENTS: post-hooks are allowed), confirmed by MAIL_SEND_SUCCESS and
-- MAIL_SUCCESS, dropped on MAIL_FAILED. Mailworthy's own sends are recorded by Mailer.lua
-- with exactly what it attached. Nothing here writes to a Blizzard frame or sends mail.
-- Switch: /mw feature ledger off. Unseen in game yet (README "Beta unknowns").
local _, ns = ...

local Ledger = {}
ns.Ledger = Ledger

Ledger.LOG_MAX = 2000      -- log entries kept per realm + faction (the balances are kept apart)
Ledger.PRICE_CAP = 3       -- a sender's value counts at most 3x the receiver's own price
Ledger.EXPECT_DAYS = 31    -- a sender's values wait this long for the mail (mail lasts 30 days)
Ledger.OUTBOX_DAYS = 30    -- values for a player not heard from wait this long
Ledger.MAX_EXPECT = 200    -- values kept per sender
Ledger.MAX_COPPER = 1e9    -- 100,000g: anything above is not a value
Ledger.MAX_COUNT = 1000
Ledger.MAX_NAMES = 30      -- item names kept per player and direction
Ledger.RECEIVE_SLOTS = 16  -- ATTACHMENTS_MAX_RECEIVE
Ledger.CHAT_DELAY = 1      -- seconds: takes from one sender in this window share a chat line

local function call(fn, ...)
    if type(fn) ~= "function" then return nil end
    local results = { pcall(fn, ...) }
    if not results[1] then return nil end
    return unpack(results, 2, table.maxn(results))
end

local function now() return call(GetServerTime) or time() end
local function clean(name) return ns.Routes.Clean(name) end
local function money(c) return ns.Valuation.Money(c) end

local function realmKey()
    local _, realm, faction = ns.Characters.Current()
    return tostring(realm) .. "|" .. tostring(faction)
end

local function tableOr(t) return type(t) == "table" and t or {} end

local function store()
    MailworthyDB.ledger = tableOr(MailworthyDB.ledger)
    local key = realmKey()
    local s = tableOr(MailworthyDB.ledger[key])
    MailworthyDB.ledger[key] = s
    s.log, s.players, s.expect, s.outbox = tableOr(s.log), tableOr(s.players), tableOr(s.expect), tableOr(s.outbox)
    return s
end
Ledger.Store = store

function Ledger.On() return ns.Features.On("ledger") end

--- Pure: "[Linen Cloth]" out of an item link, or nil.
function Ledger.NameOf(link)
    return type(link) == "string" and link:match("%[(.-)%]") or nil
end

--- Is `name` this character, another character of this account here, or the bank alt?
function Ledger.IsOwn(name)
    name = clean(name)
    if not name then return false end
    local lower = name:lower()
    if lower == tostring(ns.PlayerName()):lower() then return true end
    for _, c in ipairs(ns.Characters.Mailable()) do
        if tostring(c.name):lower() == lower then return true end
    end
    local bank = clean(ns.Config.BankAlt())
    return bank ~= nil and bank:lower() == lower
end

--- The player behind a character: a Mailworthy peer whose hello lists `name` as one of their
--- characters, else `name` itself (cleaned). Balances are shown per player.
function Ledger.Owner(name)
    name = clean(name)
    if not name or not ns.Comms then return name end
    local lower = name:lower()
    for _, peer in pairs(ns.Comms.Peers()) do
        if type(peer) == "table" then
            if tostring(peer.name):lower() == lower then return peer.name end
            for _, c in ipairs(type(peer.characters) == "table" and peer.characters or {}) do
                if tostring(c.name):lower() == lower then return peer.name end
            end
        end
    end
    return name
end

--- This account's own value of one unit (copper): the price the decision rule uses (the last
--- scan, capped by the recent median), or nil without one.
function Ledger.UnitValue(link)
    local price = link and ns.Prices.Lookup(link)
    if type(price) ~= "table" or price.ah == nil then return nil end
    local unit = ns.Valuation.SmoothedPrice(price)
    return unit and math.floor(unit + 0.5) or nil
end

--- Pure: a sender's value checked against our own: { value, source = "sender" / "capped" /
--- "mine" }. `claimed` and `own` are totals for the stack (copper or nil).
function Ledger.Choose(claimed, own, cap)
    cap = cap or Ledger.PRICE_CAP
    if claimed == nil then return own, own and "mine" or nil end
    if own ~= nil and claimed > own * cap then return own * cap, "capped" end
    return claimed, "sender"
end

--- Pure: the priced total of an entry's items plus its gold, and how many items had no price.
function Ledger.Total(entry)
    local total, unpriced = tonumber(entry.money) or 0, 0
    for _, it in ipairs(entry.items or {}) do
        if it.value then total = total + it.value else unpriced = unpriced + 1 end
    end
    return total, unpriced
end

--- Pure: does this entry move the balance with `entry.other`? Not this account's characters,
--- not system mail (the auction house, NPCs, GMs), not cash on delivery (a sale).
function Ledger.Counts(entry)
    return not entry.own and not entry.system and (tonumber(entry.cod) or 0) == 0
end

local function remember(map, name, count)
    if not name then return end
    if map[name] == nil then
        local n = 0
        for _ in pairs(map) do n = n + 1 end
        if n >= Ledger.MAX_NAMES then return end
        map[name] = 0
    end
    map[name] = map[name] + count
end

--- Pure: apply a counted entry to a player's running totals (`p` = { received, sent, ... }).
--- A returned mail coming back is what we had sent that player, so it takes back the "sent".
function Ledger.Apply(p, entry)
    local total = Ledger.Total(entry)
    p.received, p.sent = tonumber(p.received) or 0, tonumber(p.sent) or 0
    p.inItems, p.outItems = tableOr(p.inItems), tableOr(p.outItems)
    if entry.dir == "sent" then
        p.sent = p.sent + total
        for _, it in ipairs(entry.items or {}) do remember(p.outItems, it.name, it.count or 1) end
    elseif entry.returned then
        p.sent = math.max(0, p.sent - total)
    else
        p.received = p.received + total
        for _, it in ipairs(entry.items or {}) do remember(p.inItems, it.name, it.count or 1) end
        if (tonumber(entry.money) or 0) > 0 then p.gold = (tonumber(p.gold) or 0) + entry.money end
    end
    p.at = entry.at
    return p
end

local function player(name)
    local players = store().players
    local key = tostring(name):lower()
    players[key] = tableOr(players[key])
    players[key].name = players[key].name or name
    return players[key]
end

local listeners = {}
--- fn() after the log or a balance changed (the ledger window, the mail window's line).
function Ledger.OnChanged(fn) listeners[#listeners + 1] = fn end
local function changed() for _, fn in ipairs(listeners) do pcall(fn) end end

--- Add an entry to the log (and its balance when it counts). Returns the entry.
function Ledger.Add(entry)
    local s = store()
    entry.at = entry.at or now()
    entry.char = entry.char or ns.PlayerName()
    if entry.own == nil then entry.own = Ledger.IsOwn(entry.other) end
    entry.counted = Ledger.Counts(entry)
    s.log[#s.log + 1] = entry
    while #s.log > Ledger.LOG_MAX do table.remove(s.log, 1) end
    if entry.counted and entry.other then Ledger.Apply(player(entry.other), entry) end
    local total, unpriced = Ledger.Total(entry)
    ns.Log.Add("ledger", "%s %s %s: %d item(s), %s%s%s", entry.dir, entry.dir == "sent" and "to" or "from",
        tostring(entry.other), #(entry.items or {}), money(total), unpriced > 0 and (", " .. unpriced .. " unpriced") or "",
        entry.counted and "" or " (not counted)")
    changed()
    return entry
end

-- Balances ------------------------------------------------------------------------------

--- What `name`'s player (Ledger.Owner) mailed this account beyond what it mailed them, in
--- copper (0 or less: nothing to pay back), and their records.
function Ledger.Net(name)
    local owner = Ledger.Owner(name)
    if not owner then return 0, {} end
    local net, records = 0, {}
    for _, p in pairs(store().players) do
        if type(p) == "table" and tostring(Ledger.Owner(p.name)):lower() == owner:lower() then
            net = net + (tonumber(p.received) or 0) - (tonumber(p.sent) or 0) - (tonumber(p.settled) or 0)
            records[#records + 1] = p
        end
    end
    return net, records
end

--- Pure: "20 Linen Cloth, 5 Wool Cloth" (most first, at most `max` names, "and N more").
function Ledger.ItemsText(map, max)
    local list = {}
    for name, count in pairs(type(map) == "table" and map or {}) do list[#list + 1] = { name = name, count = count } end
    table.sort(list, function(a, b) if a.count ~= b.count then return a.count > b.count end return a.name < b.name end)
    local parts = {}
    for i, it in ipairs(list) do
        if i > (max or 3) then
            parts[#parts + 1] = string.format("and %d more", #list - (max or 3))
            break
        end
        parts[#parts + 1] = it.count .. " " .. it.name
    end
    return table.concat(parts, ", ")
end

--- The players this account received more from than it sent back, most first:
--- { { name, net, items = "20 Linen Cloth, ...", gold }, ... }. Never the other way round.
function Ledger.Debts()
    local byOwner, list = {}, {}
    for _, p in pairs(store().players) do
        if type(p) == "table" and p.name then
            local owner = Ledger.Owner(p.name)
            if not byOwner[owner:lower()] then
                local net, records = Ledger.Net(owner)
                local items, gold = {}, 0
                for _, r in ipairs(records) do
                    for n, c in pairs(tableOr(r.inItems)) do items[n] = (items[n] or 0) + c end
                    gold = gold + (tonumber(r.gold) or 0)
                end
                byOwner[owner:lower()] = true
                if net > 0 then list[#list + 1] = { name = owner, net = net, items = Ledger.ItemsText(items), gold = gold } end
            end
        end
    end
    table.sort(list, function(a, b) if a.net ~= b.net then return a.net > b.net end return a.name < b.name end)
    return list
end

--- Pure: "You've received 10s more from Bob than you've sent back." or nil (nothing to pay back).
function Ledger.DebtText(name, net)
    if not net or net <= 0 then return nil end
    return string.format("You've received %s more from %s than you've sent back.", money(net), tostring(name))
end

--- The player marks what they owe `name` as paid another way (a trade, a favour): the balance
--- starts again from zero. Logged.
function Ledger.MarkPaid(name)
    local net, records = Ledger.Net(name)
    if net <= 0 then return false end
    for _, p in ipairs(records) do
        p.settled = (tonumber(p.received) or 0) - (tonumber(p.sent) or 0)
    end
    local s = store()
    s.log[#s.log + 1] = { at = now(), dir = "paid", char = ns.PlayerName(), other = Ledger.Owner(name), money = net, items = {},
        counted = false }
    ns.Log.Add("ledger", "marked paid: %s %s", tostring(Ledger.Owner(name)), money(net))
    changed()
    return true
end

-- Values between Mailworthys --------------------------------------------------------------

--- Pure: the value messages for one sent mail: "V2|<from>|<to>|<at>|<itemID>:<count>:<copper>;..."
--- split to fit Comms.MAX_MESSAGE; priced items only.
function Ledger.EncodeValues(from, to, at, items)
    local head = string.format("V%d|%s|%s|%d|", ns.Comms.VERSION, tostring(from), tostring(to), math.floor(at))
    local messages, parts = {}, {}
    local function flush()
        if #parts > 0 then messages[#messages + 1] = head .. table.concat(parts, ";") end
        parts = {}
    end
    for _, it in ipairs(items or {}) do
        if it.value and it.itemID then
            local part = string.format("%d:%d:%d", it.itemID, it.count or 1, math.floor(it.value))
            if #head + #table.concat(parts, ";") + #part + 1 > ns.Comms.MAX_MESSAGE then flush() end
            parts[#parts + 1] = part
        end
    end
    flush()
    return messages
end

--- Pure: the body of a "V" message (after "V2|"), or nil: { from, to, at, items = { { itemID,
--- count, value } } }. Every field is checked; anything odd drops the message.
function Ledger.DecodeValues(rest)
    local from, to, at, list = tostring(rest):match("^([^|]+)|([^|]+)|(%d+)|([%d:;]+)$")
    from, to = from and clean(from), to and clean(to)
    if not from or not to or #from > ns.Comms.MAX_NAME or #to > ns.Comms.MAX_NAME or #at > 12 then return nil end
    local items = {}
    for id, count, value in list:gmatch("(%d+):(%d+):(%d+)") do
        id, count, value = tonumber(id), tonumber(count), tonumber(value)
        if id < 1 or count < 1 or count > Ledger.MAX_COUNT or value > Ledger.MAX_COPPER then return nil end
        items[#items + 1] = { itemID = id, count = count, value = value }
        if #items > Ledger.RECEIVE_SLOTS then return nil end
    end
    if #items == 0 then return nil end
    return { from = from, to = to, at = tonumber(at), items = items }
end

local heard = {} -- lower-case names heard from this session (online, running Mailworthy)

local function namesOf(name)
    local names = { [tostring(name):lower()] = true }
    local peer = ns.Comms and ns.Comms.Peer(name)
    for _, c in ipairs(type(peer) == "table" and type(peer.characters) == "table" and peer.characters or {}) do
        names[tostring(c.name):lower()] = true
    end
    return names
end

--- Send the values waiting for `name` or one of their characters, to `name` (who is online:
--- we just heard from them). Returns how many messages went.
function Ledger.Flush(name)
    name = clean(name)
    if not name or not Ledger.On() or not ns.Comms or not ns.Comms.On() then return 0 end
    local outbox, sent = store().outbox, 0
    for key in pairs(namesOf(name)) do
        local waiting = outbox[key]
        if type(waiting) == "table" then
            for _, item in ipairs(waiting) do
                for _, m in ipairs(type(item.messages) == "table" and item.messages or {}) do
                    if ns.Comms.Whisper(name, m) then sent = sent + 1 end
                end
            end
            outbox[key] = nil
        end
    end
    if sent > 0 then ns.Log.Add("ledger", "sent %d value message(s) to %s", sent, name) end
    return sent
end

--- Another Mailworthy spoke (any message): they are online, so values waiting for them go now.
function Ledger.Heard(name)
    name = clean(name)
    if not name then return end
    heard[name:lower()] = true
    Ledger.Flush(name)
end

local function queueValues(entry)
    if not ns.Comms or not ns.Comms.On() then return end
    local messages = Ledger.EncodeValues(entry.char, entry.other, entry.at, entry.items)
    if #messages == 0 then return end
    local key = tostring(entry.other):lower()
    local outbox = store().outbox
    outbox[key] = tableOr(outbox[key])
    table.insert(outbox[key], { at = entry.at, messages = messages })
    for online in pairs(heard) do
        if namesOf(online)[key] then return Ledger.Flush(online) end
    end
    ns.Comms.Ask() -- whoever is online answers with a hello, and the values follow it
end

--- A "V" message from `sender`: the values of a mail sent to one of this account's characters.
--- `from` (the mail's sender) must be the whisperer or one of the characters their hello lists.
function Ledger.HearValues(sender, msg)
    sender = clean(sender)
    if not sender or type(msg) ~= "table" or not Ledger.On() then return nil end
    if not Ledger.IsOwn(msg.to) then return nil end
    if not namesOf(sender)[msg.from:lower()] then
        ns.Log.Add("ledger", "values from %s for %s's mail dropped: not their character", sender, msg.from)
        return nil
    end
    local at = now()
    if msg.at > at + 600 or msg.at < at - Ledger.EXPECT_DAYS * 86400 then return nil end
    local expect = store().expect
    local key = msg.from:lower()
    expect[key] = tableOr(expect[key])
    for _, it in ipairs(msg.items) do
        table.insert(expect[key], { at = msg.at, to = msg.to, itemID = it.itemID, count = it.count, value = it.value })
    end
    while #expect[key] > Ledger.MAX_EXPECT do table.remove(expect[key], 1) end
    ns.Log.Add("ledger", "values from %s: %d item(s) mailed to %s", msg.from, #msg.items, msg.to)
    return msg
end

--- The sender's value for `count` of `itemID` from `from`, used once (the oldest match), or nil.
function Ledger.Claim(from, itemID, count)
    local list = store().expect[tostring(clean(from)):lower()]
    if type(list) ~= "table" then return nil end
    for i, e in ipairs(list) do
        if e.itemID == itemID and e.count == count then
            table.remove(list, i)
            return tonumber(e.value)
        end
    end
    return nil
end

--- Drop values nobody claimed in EXPECT_DAYS and messages nobody picked up in OUTBOX_DAYS.
function Ledger.Prune(at)
    at = at or now()
    local s = store()
    for key, list in pairs(s.expect) do
        local keep = {}
        for _, e in ipairs(tableOr(list)) do
            if (tonumber(e.at) or 0) >= at - Ledger.EXPECT_DAYS * 86400 then keep[#keep + 1] = e end
        end
        s.expect[key] = #keep > 0 and keep or nil
    end
    for key, list in pairs(s.outbox) do
        local keep = {}
        for _, e in ipairs(tableOr(list)) do
            if (tonumber(e.at) or 0) >= at - Ledger.OUTBOX_DAYS * 86400 then keep[#keep + 1] = e end
        end
        s.outbox[key] = #keep > 0 and keep or nil
    end
end

-- Sending -----------------------------------------------------------------------------------

local function valued(items)
    local out = {}
    for _, it in ipairs(items or {}) do
        local link = it.link or (it.itemID and ("item:" .. it.itemID)) or nil
        local unit = Ledger.UnitValue(link)
        out[#out + 1] = { itemID = tonumber(it.itemID), name = it.name or Ledger.NameOf(it.link) or ("item " .. tostring(it.itemID)),
            count = tonumber(it.count) or 1, value = unit and unit * (tonumber(it.count) or 1) or nil,
            source = unit and "mine" or nil }
    end
    return out
end

--- A mail that went (MAIL_SEND_SUCCESS): { to, subject, items = { { itemID, link, name, count } },
--- money, cod }; `via` = "Mailworthy" (Mailer.lua) or "mail" (Blizzard's Send button).
function Ledger.RecordSent(mail, via)
    if not Ledger.On() or type(mail) ~= "table" then return nil end
    local entry = Ledger.Add({ dir = "sent", other = clean(mail.to) or tostring(mail.to), subject = mail.subject,
        items = valued(mail.items), money = tonumber(mail.money) or 0, cod = tonumber(mail.cod) or 0, via = via })
    if entry.counted then queueValues(entry) end
    return entry
end

-- What Blizzard's Send Mail tab carries, read when it changes and again in the SendMail hook
-- (the attachments may be gone by then; the last reading stands in).
local snapshot = { items = {}, money = 0, cod = 0 }
local pendingSend

local function readSendTab()
    local items = {}
    for i = 1, tonumber(rawget(_G, "ATTACHMENTS_MAX_SEND")) or 12 do
        local name, itemID, _, count = call(GetSendMailItem, i)
        if itemID then
            items[#items + 1] = { itemID = tonumber(itemID), name = name, count = tonumber(count) or 1,
                link = call(rawget(_G, "GetSendMailItemLink"), i) }
        end
    end
    return { items = items, money = tonumber((call(rawget(_G, "GetSendMailMoney")))) or 0,
        cod = tonumber((call(rawget(_G, "GetSendMailCOD")))) or 0 }
end

local function mailerBusy() return ns.Mailer and ns.Mailer.Busy() end

local function takeSnapshot()
    if Ledger.On() and not mailerBusy() then snapshot = readSendTab() end
end

local function onSendMail(to, subject)
    if mailerBusy() then return end -- Mailer.lua records its own mails
    local tab = readSendTab()
    pendingSend = { to = to, subject = subject, items = #tab.items > 0 and tab.items or snapshot.items,
        money = tab.money > 0 and tab.money or snapshot.money, cod = tab.cod > 0 and tab.cod or snapshot.cod }
end

-- Receiving -----------------------------------------------------------------------------

local pendingTakes = {} -- takes waiting for MAIL_SUCCESS / MAIL_FAILED, oldest first
local taken = {}        -- this session: what was already queued (a second click on the same item)
local chat = {}         -- sender -> { items, total, unpriced } waiting for the chat line

local function header(i)
    local _, _, sender, subject, cash, cod, daysLeft, _, _, wasReturned, _, canReply, isGM = call(GetInboxHeaderInfo, i)
    if sender == nil then return nil end
    local invoice = call(rawget(_G, "GetInboxInvoiceInfo"), i)
    return { sender = clean(sender) or tostring(sender), subject = subject, money = tonumber(cash) or 0,
        cod = tonumber(cod) or 0, returned = wasReturned == true,
        system = canReply == false or isGM == true or invoice ~= nil,
        expires = math.floor((now() + (tonumber(daysLeft) or 0) * 86400) / 60) }
end

local function queueItem(i, a)
    local h = header(i)
    local name, itemID, _, count = call(GetInboxItem, i, a)
    if not h or not itemID then return end
    local key = table.concat({ h.sender, tostring(h.subject), h.expires, a, itemID, tostring(count) }, "|")
    if taken[key] then return end
    taken[key] = true
    pendingTakes[#pendingTakes + 1] = { h = h, itemID = tonumber(itemID), item = { itemID = tonumber(itemID), name = name,
        count = tonumber(count) or 1, link = call(rawget(_G, "GetInboxItemLink"), i, a) } }
end

local function queueMoney(i)
    local h = header(i)
    if not h or h.money <= 0 then return end
    local key = table.concat({ h.sender, tostring(h.subject), h.expires, "money", h.money }, "|")
    if taken[key] then return end
    taken[key] = true
    pendingTakes[#pendingTakes + 1] = { h = h, money = h.money }
end

local function chatLine(sender)
    local c = chat[sender]
    chat[sender] = nil
    if not c then return end
    local what = Ledger.ItemsText(c.items, 4)
    if c.gold > 0 then what = what ~= "" and (what .. " and " .. money(c.gold)) or money(c.gold) end
    local value = ""
    if next(c.items) then
        value = c.total > 0 and (" (" .. money(c.total) .. (c.unpriced > 0 and ", some without a price" or "") .. ")")
            or (c.unpriced > 0 and " (no price yet)" or "")
    end
    local owner = Ledger.Owner(sender)
    local text = string.format("Received %s%s from %s.", what, value, sender)
    local debt = Ledger.DebtText(owner, (Ledger.Net(owner)))
    ns.Print(debt and (text .. " " .. debt) or text)
end

local function commit(take)
    local h = take.h
    local items = {}
    if take.item then
        local own = Ledger.UnitValue(take.item.link or ("item:" .. take.item.itemID))
        own = own and own * take.item.count or nil
        local claimed = not h.returned and Ledger.Claim(h.sender, take.item.itemID, take.item.count) or nil
        local value, source = Ledger.Choose(claimed, own)
        items[1] = { itemID = take.item.itemID, name = take.item.name or Ledger.NameOf(take.item.link)
            or ("item " .. tostring(take.item.itemID)), count = take.item.count, value = value, source = source }
    end
    local entry = Ledger.Add({ dir = "received", other = h.sender, subject = h.subject, items = items,
        money = take.money or 0, cod = h.cod, returned = h.returned or nil, system = h.system or nil, via = "mail" })
    if entry.counted and not entry.returned then
        local c = chat[h.sender]
        if not c then
            c = { items = {}, total = 0, unpriced = 0, gold = 0 }
            chat[h.sender] = c
            if C_Timer and type(C_Timer.After) == "function" then
                C_Timer.After(Ledger.CHAT_DELAY, function() pcall(chatLine, h.sender) end)
            end
        end
        for _, it in ipairs(items) do
            remember(c.items, it.name, it.count)
            if it.value then c.total = c.total + it.value else c.unpriced = c.unpriced + 1 end
        end
        c.gold = c.gold + (take.money or 0)
    end
end

local function settle(itemID, ok)
    for i, take in ipairs(pendingTakes) do
        local match = (itemID == nil and take.money ~= nil) or (itemID ~= nil and take.itemID == itemID)
        if match then
            table.remove(pendingTakes, i)
            if ok then commit(take) end
            return true
        end
    end
    if ok and pendingTakes[1] then -- confirmed without a match: the oldest one
        local take = table.remove(pendingTakes, 1)
        if ok then commit(take) end
        return true
    end
    return false
end

--- Test and report hook: takes still waiting for the server's answer.
function Ledger.Pending() return #pendingTakes, pendingSend ~= nil end

-- Export and report ---------------------------------------------------------------------

local function itemText(it)
    local value = it.value and money(it.value) or "no price"
    if it.source == "sender" then value = value .. ", sender's value"
    elseif it.source == "capped" then value = value .. ", capped at " .. Ledger.PRICE_CAP .. "x my price" end
    return string.format("%dx %s (item %s, %s)", it.count or 1, tostring(it.name), tostring(it.itemID), value)
end

--- Pure: one log line.
function Ledger.LineText(e)
    local stamp = date("%Y-%m-%d %H:%M", tonumber(e.at) or 0)
    if e.dir == "paid" then
        return string.format("%s  MARKED PAID  %s: %s set back to zero by %s", stamp, tostring(e.other),
            money(e.money), tostring(e.char))
    end
    local from, to = e.char, e.other
    if e.dir == "received" then from, to = e.other, e.char end
    local parts = {}
    for _, it in ipairs(e.items or {}) do parts[#parts + 1] = itemText(it) end
    if (tonumber(e.money) or 0) > 0 then parts[#parts + 1] = money(e.money) .. " gold" end
    local flags = {}
    if e.via == "Mailworthy" then flags[#flags + 1] = "sent by Mailworthy" end
    if (tonumber(e.cod) or 0) > 0 then flags[#flags + 1] = "COD " .. money(e.cod) end
    if e.returned then flags[#flags + 1] = "returned mail" end
    if e.own then flags[#flags + 1] = "own character" end
    if e.system then flags[#flags + 1] = "system mail" end
    return string.format("%s  %-8s  %s -> %s  \"%s\"  %s%s", stamp, e.dir == "sent" and "SENT" or "RECEIVED",
        tostring(from), tostring(to), tostring(e.subject or ""), #parts > 0 and table.concat(parts, ", ") or "nothing",
        #flags > 0 and ("  [" .. table.concat(flags, "; ") .. "]") or "")
end

--- The whole log as text for the copy box, oldest first.
function Ledger.ExportText()
    local _, realm, faction = ns.Characters.Current()
    local log = store().log
    local lines = {
        string.format("Mailworthy %s mail log, %s %s, exported %s by %s", ns.VERSION, tostring(realm), tostring(faction),
            date("%Y-%m-%d %H:%M"), tostring(ns.PlayerName())),
        string.format("%d entries (the newest %d are kept). Values: copper per stack at the time of the mail.",
            #log, Ledger.LOG_MAX),
        "",
    }
    for _, e in ipairs(log) do lines[#lines + 1] = Ledger.LineText(e) end
    if #log == 0 then lines[#lines + 1] = "Nothing mailed or received yet." end
    return table.concat(lines, "\n")
end

--- For /mw report: counts only, never names or balances.
function Ledger.ReportLines()
    local s, outbox, expect, players = store(), 0, 0, 0
    for _, list in pairs(s.outbox) do outbox = outbox + #tableOr(list) end
    for _, list in pairs(s.expect) do expect = expect + #tableOr(list) end
    for _ in pairs(s.players) do players = players + 1 end
    return { string.format("ledger: %s, %d log entries, %d players, %d mail(s) of values waiting to go, %d values "
        .. "received, %d take(s) unconfirmed", Ledger.On() and "on" or "off", #s.log, players, outbox, expect, #pendingTakes) }
end

-- Hooks and events ----------------------------------------------------------------------

local hooked = false
function Ledger.Install()
    if hooked or not Ledger.On() or type(hooksecurefunc) ~= "function" then return end
    hooked = true
    for fn, hook in pairs({
        SendMail = function(to, subject) pcall(onSendMail, to, subject) end,
        TakeInboxItem = function(i, a) pcall(queueItem, i, a) end,
        TakeInboxMoney = function(i) pcall(queueMoney, i) end,
        AutoLootMailItem = function(i)
            for a = 1, tonumber(rawget(_G, "ATTACHMENTS_MAX_RECEIVE")) or Ledger.RECEIVE_SLOTS do pcall(queueItem, i, a) end
            pcall(queueMoney, i)
        end,
    }) do
        if type(rawget(_G, fn)) == "function" then
            local ok, err = pcall(hooksecurefunc, fn, hook)
            if not ok then ns.Log.Add("ledger", "hook %s error: %s", fn, tostring(err)) end
        end
    end
    ns.Log.Add("ledger", "mail hooks installed")
end

ns.On("PLAYER_LOGIN", function()
    if not Ledger.On() then return end
    Ledger.Prune()
    Ledger.Install()
end)
for _, event in ipairs({ "MAIL_SEND_INFO_UPDATE", "SEND_MAIL_MONEY_CHANGED", "SEND_MAIL_COD_CHANGED" }) do
    ns.On(event, takeSnapshot)
end
ns.On("MAIL_SEND_SUCCESS", function()
    local mail = pendingSend
    pendingSend = nil
    snapshot = { items = {}, money = 0, cod = 0 }
    if mail and not mailerBusy() then Ledger.RecordSent(mail, "mail") end
end)
ns.On("MAIL_SUCCESS", function(itemID) settle(tonumber(itemID), true) end)
ns.On("MAIL_FAILED", function(itemID)
    if pendingSend or mailerBusy() then -- a send failed, not a take
        pendingSend = nil
        return
    end
    settle(tonumber(itemID), false)
end)
-- Takes the server never answered by the time the mailbox closes did happen (a failure says
-- so with MAIL_FAILED, as Blizzard's Open All relies on).
ns.On("MAIL_CLOSED", function()
    while #pendingTakes > 0 do commit(table.remove(pendingTakes, 1)) end
    pendingSend, taken = nil, {}
    snapshot = { items = {}, money = 0, cod = 0 }
end)
