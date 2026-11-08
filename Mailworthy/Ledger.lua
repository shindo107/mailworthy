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
-- goes, with the age of that Auctionator scan. What you receive: when the sender's Mailworthy
-- told yours its value and scan age (a "V2" whisper right after the send, or as soon as they
-- hear from you later), the more up-to-date of the two at the time of send wins (operator,
-- 2026-11-07: "we should trust the more up to date value at time of send"): your own price as
-- it stood that day (your last scan then, or that day in Auctionator's history) against theirs;
-- a tie or an unknown age keeps the sender's. A sender's value counts at most PRICE_CAP times
-- your own, so a made-up value can't run up a debt. Without their value, your own price when
-- you take it. Without any price an item is listed by count only. When the receiver's value
-- differs from the sender's, its Mailworthy answers ("R2", held like the values until the sender
-- is heard from) and the sender's log and balance take the agreed value, so both sides match
-- (operator, 2026-11-07); an answer more than PRICE_CAP times off the sender's own is ignored.
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
--- characters while `name`'s own hello lists them back, else `name` itself (cleaned). Balances
--- are shown per player.
local function lists(peer, lower)
    for _, c in ipairs(type(peer) == "table" and type(peer.characters) == "table" and peer.characters or {}) do
        if tostring(c.name):lower() == lower then return true end
    end
    return false
end

function Ledger.Owner(name)
    name = clean(name)
    if not name or not ns.Comms then return name end
    local lower = name:lower()
    local own, owner = ns.Comms.Peer(name), name
    for _, peer in pairs(ns.Comms.Peers()) do
        -- A hello is anyone's word: two names are one player only when each one's own hello lists
        -- the other (a stranger claiming "Bob is my alt" never takes Bob's balance). The group is
        -- named after its alphabetically first name, so every member gives the same answer.
        if type(peer) == "table" and tostring(peer.name):lower() ~= lower and lists(peer, lower)
            and lists(own, tostring(peer.name):lower()) and tostring(peer.name):lower() < owner:lower() then
            owner = peer.name
        end
    end
    return owner
end

--- This account's own value of one unit (copper): the price the decision rule uses (the last
--- scan, capped by the recent median), or nil without one; and the scan's age in days (nil
--- when Auctionator doesn't say).
function Ledger.UnitValue(link)
    local price = link and ns.Prices.Lookup(link)
    if type(price) ~= "table" or price.ah == nil then return nil end
    local unit = ns.Valuation.SmoothedPrice(price)
    if not unit then return nil end
    local age = tonumber(price.age)
    return math.floor(unit + 0.5), age and math.max(0, math.floor(age)) or nil
end

--- Auctionator's scan day for a server time: floor((local time - SCAN_DAY_0) / 86400), as its
--- database counts days (SCAN_DAY_0 = local midnight, Jan 1 2020; a price's age is today's scan
--- day minus its newest). The client clock's offset from the server's is applied, so "how many
--- scan days since the mail went" crosses the same boundary Auctionator does.
function Ledger.ScanDay(serverTime)
    local a = rawget(_G, "Auctionator")
    local day0 = type(a) == "table" and type(a.Constants) == "table" and tonumber(a.Constants.SCAN_DAY_0)
        or call(time, { year = 2020, month = 1, day = 1, hour = 0 }) or 0
    local offset = (call(time) or 0) - (call(GetServerTime) or call(time) or 0)
    return math.floor(((tonumber(serverTime) or 0) + offset - day0) / 86400)
end

--- Pure: our own price for one unit as it stood `daysAgo` scan days ago, and how old its scan was then.
--- `price` = Prices.Lookup's table, `unit` = today's value of it (Ledger.UnitValue). Our last scan
--- was already in when it is at least `daysAgo` old; a scan since then is newer than that day,
--- so the day comes from Auctionator's history (the latest scanned day up to it, its lowest
--- price seen), or nil when the history doesn't reach back.
function Ledger.PriceThen(price, unit, daysAgo)
    if type(price) ~= "table" or not unit then return nil end
    local age = tonumber(price.age)
    if age == nil then return unit, nil end
    age = math.max(0, math.floor(age))
    daysAgo = math.max(0, math.floor(daysAgo or 0))
    if age >= daysAgo then return unit, age - daysAgo end
    local history = type(price.history) == "table" and price.history or {}
    if not history[1] or not tonumber(history[1].day) then return nil end
    local thatDay = history[1].day + age - daysAgo
    for _, row in ipairs(history) do -- newest first
        if tonumber(row.day) and row.day <= thatDay and tonumber(row.minSeen) then
            return math.floor(row.minSeen + 0.5), thatDay - row.day
        end
    end
    return nil
end

--- Pure: the value of a received stack from the sender's (`claimed`, its scan `claimedAge` days
--- old at the time of send) and ours as it stood then (`mine`, `mineAge`); totals in copper.
--- The more up-to-date scan wins; a tie or an unknown age keeps the sender's, which counts at
--- most `cap` times ours. Returns value, source ("sender" / "capped" / "fresher" / "mine"), age.
function Ledger.Pick(claimed, claimedAge, mine, mineAge, cap)
    cap = cap or Ledger.PRICE_CAP
    if claimed == nil then return mine, mine and "mine" or nil, mineAge end
    if mine == nil then return claimed, "sender", claimedAge end
    if claimedAge ~= nil and mineAge ~= nil and mineAge < claimedAge then return mine, "fresher", mineAge end
    if claimed > mine * cap then return mine * cap, "capped", mineAge end
    return claimed, "sender", claimedAge
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
local function changed_() for _, fn in ipairs(listeners) do pcall(fn) end end

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
    changed_()
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
    changed_()
    return true
end

-- Values between Mailworthys --------------------------------------------------------------

--- Pure: the value messages for one sent mail: "V2|<from>|<to>|<at>|<itemID>:<count>:<copper>[:<scan
--- age in days>];..." split to fit Comms.MAX_MESSAGE; priced items only. (v0.25.0 sent no age, and
--- reads these as before: its pattern skips the fourth number.)
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
                .. (tonumber(it.age) and (":" .. math.floor(it.age)) or "")
            if #head + #table.concat(parts, ";") + #part + 1 > ns.Comms.MAX_MESSAGE then flush() end
            parts[#parts + 1] = part
        end
    end
    flush()
    return messages
end

--- Pure: the body of a "V" message (after "V2|"), or nil: { from, to, at, items = { { itemID,
--- count, value, age (nil when not sent) } } }. Every field is checked; anything odd drops it.
function Ledger.DecodeValues(rest)
    local from, to, at, list = tostring(rest):match("^([^|]+)|([^|]+)|(%d+)|([%d:;]+)$")
    from, to = from and clean(from), to and clean(to)
    if not from or not to or #from > ns.Comms.MAX_NAME or #to > ns.Comms.MAX_NAME or #at > 12 then return nil end
    local items = {}
    for part in list:gmatch("[^;]+") do
        local id, count, value, age = part:match("^(%d+):(%d+):(%d+):?(%d*)$")
        if not id or #age > 3 then return nil end
        id, count, value, age = tonumber(id), tonumber(count), tonumber(value), tonumber(age)
        if id < 1 or count < 1 or count > Ledger.MAX_COUNT or value > Ledger.MAX_COPPER then return nil end
        items[#items + 1] = { itemID = id, count = count, value = value, age = age }
        if #items > Ledger.RECEIVE_SLOTS then return nil end
    end
    if #items == 0 then return nil end
    return { from = from, to = to, at = tonumber(at), items = items }
end

-- lower-case name -> { name, at = GetTime() } of the last message heard from them. A whisper to
-- an offline player prints "No player named ... is currently playing" in the sender's chat, so
-- messages go at once only to a player heard within HEARD_FRESH seconds; otherwise Mailworthy
-- asks for hellos and waits for theirs, which proves they're online.
local heard = {}
Ledger.HEARD_FRESH = 60

-- Values and answers go to, and are taken from, the exact character the mail names: a hello's
-- list of "my other characters" is anyone's word, so it never decides who may read or settle a
-- mail (Codex review, 2026-11-07: a stranger listing Bob as their alt got Bob's values and could
-- answer for him).

--- Send the messages waiting for `name`, to `name` (who is online: we just heard from them).
--- Returns how many messages went.
function Ledger.Flush(name)
    name = clean(name)
    if not name or not Ledger.On() or not ns.Comms or not ns.Comms.On() then return 0 end
    local outbox, sent = store().outbox, 0
    local waiting = outbox[name:lower()]
    if type(waiting) == "table" then
        for _, item in ipairs(waiting) do
            for _, m in ipairs(type(item.messages) == "table" and item.messages or {}) do
                if ns.Comms.Whisper(name, m) then sent = sent + 1 end
            end
        end
        outbox[name:lower()] = nil
    end
    if sent > 0 then ns.Log.Add("ledger", "sent %d value message(s) to %s", sent, name) end
    return sent
end

--- Another Mailworthy spoke (any message): they are online, so values waiting for them go now.
function Ledger.Heard(name)
    name = clean(name)
    if not name then return end
    heard[name:lower()] = { name = name, at = call(GetTime) or 0 }
    Ledger.Flush(name)
end

--- Hold `messages` for `name` and send them as soon as they are heard from: at once when that
--- happened within HEARD_FRESH seconds.
local function queueFor(name, at, messages)
    if not ns.Comms or not ns.Comms.On() or #messages == 0 then return end
    local key = tostring(name):lower()
    local outbox = store().outbox
    outbox[key] = tableOr(outbox[key])
    table.insert(outbox[key], { at = at, messages = messages })
    local h = heard[key]
    if h and (call(GetTime) or 0) - h.at <= Ledger.HEARD_FRESH then return Ledger.Flush(h.name) end
    ns.Comms.Ask() -- whoever is online answers with a hello, and the messages follow it
end

local function queueValues(entry)
    queueFor(entry.other, entry.at, Ledger.EncodeValues(entry.char, entry.other, entry.at, entry.items))
end

--- Pure: the answer messages for values a receiver settled differently: "R2|<receiver>|<mail's
--- sender>|<mail's time>|<itemID>:<count>:<copper>;..." (each { itemID, count, value }).
function Ledger.EncodeAnswers(receiver, sender, at, items)
    local head = string.format("R%d|%s|%s|%d|", ns.Comms.VERSION, tostring(receiver), tostring(sender), math.floor(at))
    local messages, parts = {}, {}
    for _, it in ipairs(items or {}) do
        local part = string.format("%d:%d:%d", it.itemID, it.count or 1, math.floor(it.value))
        if #parts > 0 and #head + #table.concat(parts, ";") + #part + 1 > ns.Comms.MAX_MESSAGE then
            messages[#messages + 1] = head .. table.concat(parts, ";")
            parts = {}
        end
        parts[#parts + 1] = part
    end
    if #parts > 0 then messages[#messages + 1] = head .. table.concat(parts, ";") end
    return messages
end

--- Pure: the body of an "R" message (after "R2|"), or nil: { receiver, from (the mail's sender),
--- at, items = { { itemID, count, value } } }.
function Ledger.DecodeAnswers(rest)
    local receiver, from, at, list = tostring(rest):match("^([^|]+)|([^|]+)|(%d+)|([%d:;]+)$")
    receiver, from = receiver and clean(receiver), from and clean(from)
    if not receiver or not from or #receiver > ns.Comms.MAX_NAME or #from > ns.Comms.MAX_NAME or #at > 12 then return nil end
    local items = {}
    for part in list:gmatch("[^;]+") do
        local id, count, value = part:match("^(%d+):(%d+):(%d+)$")
        if not id then return nil end
        id, count, value = tonumber(id), tonumber(count), tonumber(value)
        if id < 1 or count < 1 or count > Ledger.MAX_COUNT or value > Ledger.MAX_COPPER then return nil end
        items[#items + 1] = { itemID = id, count = count, value = value }
        if #items > Ledger.RECEIVE_SLOTS then return nil end
    end
    if #items == 0 then return nil end
    return { receiver = receiver, from = from, at = tonumber(at), items = items }
end

--- An "R" message from `whisperer`: the value a receiver settled on for a mail one of this
--- account's characters sent. The mail's entry in the log and the balance take it, when the
--- receiver is the whisperer and the value is within PRICE_CAP times
--- either way of our own. Returns how many items changed.
function Ledger.HearAnswers(whisperer, msg)
    whisperer = clean(whisperer)
    if not whisperer or type(msg) ~= "table" or not Ledger.On() or not Ledger.IsOwn(msg.from) then return 0 end
    if msg.receiver:lower() ~= whisperer:lower() then
        ns.Log.Add("ledger", "answer from %s for %s dropped: not the recipient", whisperer, msg.receiver)
        return 0
    end
    local entry
    for _, e in ipairs(store().log) do
        if e.dir == "sent" and e.at == msg.at and tostring(e.other):lower() == msg.receiver:lower()
            and tostring(e.char):lower() == msg.from:lower() then entry = e end
    end
    if not entry then return 0 end
    local changed = 0
    for _, a in ipairs(msg.items) do
        for _, it in ipairs(entry.items or {}) do
            if it.itemID == a.itemID and it.count == a.count and not it.agreed and it.value then
                if a.value * Ledger.PRICE_CAP >= it.value and a.value <= it.value * Ledger.PRICE_CAP then
                    local delta = a.value - it.value
                    it.mine, it.value, it.agreed, it.source = it.value, a.value, entry.other, "agreed"
                    if entry.counted then
                        local p = player(entry.other)
                        p.sent = math.max(0, (tonumber(p.sent) or 0) + delta)
                    end
                    changed = changed + 1
                else
                    ns.Log.Add("ledger", "answer from %s for %s ignored: %s against our %s", whisperer, tostring(it.name),
                        money(a.value), money(it.value))
                end
                break
            end
        end
    end
    if changed > 0 then
        ns.Log.Add("ledger", "%s's values agreed for %d item(s) of the mail of %s", msg.receiver, changed,
            date("%Y-%m-%d %H:%M", msg.at))
        changed_()
    end
    return changed
end

--- A "V" message from `sender`: the values of a mail sent to one of this account's characters.
--- `from` (the mail's sender) must be the whisperer.
function Ledger.HearValues(sender, msg)
    sender = clean(sender)
    if not sender or type(msg) ~= "table" or not Ledger.On() then return nil end
    if not Ledger.IsOwn(msg.to) then return nil end
    if msg.from:lower() ~= sender:lower() then
        ns.Log.Add("ledger", "values from %s for %s's mail dropped: not the sender", sender, msg.from)
        return nil
    end
    local at = now()
    if msg.at > at + 600 or msg.at < at - Ledger.EXPECT_DAYS * 86400 then return nil end
    local expect = store().expect
    local key = msg.from:lower()
    expect[key] = tableOr(expect[key])
    for _, it in ipairs(msg.items) do
        table.insert(expect[key], { at = msg.at, to = msg.to, itemID = it.itemID, count = it.count, value = it.value,
            age = it.age })
    end
    while #expect[key] > Ledger.MAX_EXPECT do table.remove(expect[key], 1) end
    ns.Log.Add("ledger", "values from %s: %d item(s) mailed to %s", msg.from, #msg.items, msg.to)
    return msg
end

--- The sender's value for `count` of `itemID` that `from` mailed to `to` (the character taking
--- it), used once (the oldest match), or nil: { value, age (their scan's age at send, or nil), at
--- (when they sent it), to }.
function Ledger.Claim(from, itemID, count, to)
    local list = store().expect[tostring(clean(from)):lower()]
    if type(list) ~= "table" then return nil end
    for i, e in ipairs(list) do
        if e.itemID == itemID and e.count == count and tostring(e.to):lower() == tostring(clean(to)):lower() then
            table.remove(list, i)
            return tonumber(e.value) and { value = tonumber(e.value), age = tonumber(e.age), at = tonumber(e.at), to = e.to }
                or nil
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
        local unit, age = Ledger.UnitValue(link)
        out[#out + 1] = { itemID = tonumber(it.itemID), name = it.name or Ledger.NameOf(it.link) or ("item " .. tostring(it.itemID)),
            count = tonumber(it.count) or 1, value = unit and unit * (tonumber(it.count) or 1) or nil,
            source = unit and "mine" or nil, age = unit and age or nil }
    end
    return out
end

--- A mail that went (MAIL_SEND_SUCCESS): { to, subject, items = { { itemID, link, name, count } },
--- money, cod }; `via` = "Mailworthy" (Mailer.lua) or "mail" (Blizzard's Send button).
function Ledger.RecordSent(mail, via)
    if not Ledger.On() or type(mail) ~= "table" then return nil end
    local other, at = clean(mail.to) or tostring(mail.to), now()
    -- The send time names the mail in values and answers, so it is unique per sender and
    -- recipient: a second mail in the same second is stamped a second later (Codex review).
    local log = store().log
    for i = #log, math.max(1, #log - 50), -1 do
        local e = log[i]
        if e.dir == "sent" and tostring(e.other):lower() == other:lower() and tostring(e.char) == tostring(ns.PlayerName())
            and (tonumber(e.at) or 0) >= at then
            at = e.at + 1
        end
    end
    local entry = Ledger.Add({ at = at, dir = "sent", other = other, subject = mail.subject,
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
        local link, count = take.item.link or ("item:" .. take.item.itemID), take.item.count
        local unit, age = Ledger.UnitValue(link)
        local value, source = unit and unit * count or nil, unit and "mine" or nil
        local claim = not h.returned and Ledger.Claim(h.sender, take.item.itemID, count, ns.PlayerName()) or nil
        if claim then -- their value and ours, each as it stood when the mail went
            local daysAgo = Ledger.ScanDay(now()) - Ledger.ScanDay(claim.at or now())
            local mine, mineAge = Ledger.PriceThen(unit and ns.Prices.Lookup(link), unit, daysAgo)
            value, source, age = Ledger.Pick(claim.value, claim.age, mine and mine * count or nil, mineAge)
            if value and value ~= claim.value and claim.at then -- tell the sender, so both logs match
                queueFor(h.sender, now(), Ledger.EncodeAnswers(claim.to, h.sender, claim.at,
                    { { itemID = take.item.itemID, count = count, value = value } }))
            end
        end
        items[1] = { itemID = take.item.itemID, name = take.item.name or Ledger.NameOf(take.item.link)
            or ("item " .. tostring(take.item.itemID)), count = count, value = value, source = source,
            age = value and age or nil }
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
    elseif it.source == "capped" then value = value .. ", capped at " .. Ledger.PRICE_CAP .. "x my price"
    elseif it.source == "fresher" then value = value .. ", my price: my scan was more up to date"
    elseif it.source == "agreed" then
        value = value .. string.format(", agreed with %s (mine said %s)", tostring(it.agreed), money(it.mine or 0))
    end
    if it.value and tonumber(it.age) then
        value = value .. string.format(", scan %d day%s old", it.age, it.age == 1 and "" or "s")
    end
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
