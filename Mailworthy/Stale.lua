-- Stale auction prices: a nudge at the mailbox when this character's Auctionator
-- prices are too old to count (Valuation's maxAgeDays, 7), louder when another
-- Mailworthy user nearby has scanned recently (operator, 2026-11-06: "8 of them
-- have scanned the AH but 2 haven't scanned in a week ... the 2 get a signal next
-- time they look at the mailbox button").
--
-- Freshness = how many days ago Auctionator last saw the freshest of a dozen
-- trade goods that sell every day (WATCH), read with Auctionator's
-- GetAuctionAgeByItemID (API v1; nil past 21 days or never seen). Each Mailworthy
-- sends its scan day after its hello (Comms: "F2|<server day>", a message kind
-- older Mailworthys ignore) and keeps the days it hears in MailworthyDB.fresh per
-- realm + faction. What it hears is display only: it never changes what is mailed,
-- and no prices are ever sent between players.
--
-- Shown: a "!" on the Mailworthy button, a line at the top of the Mailworthy window,
-- and (only when a peer is fresher) one chat line per mailbox visit. Logging in with
-- stale prices asks the guild and group to say hello, so fresh peers answer.
-- Switch: /mw feature staleNudge off (sending the scan day follows the comms switch).
local _, ns = ...

local Stale = {}
ns.Stale = Stale

Stale.WATCH = {
    2589, 2592, 4306,  -- Linen, Wool, Silk Cloth
    2770, 2771, 2835,  -- Copper Ore, Tin Ore, Rough Stone
    2840,              -- Copper Bar
    2318, 2319,        -- Light, Medium Leather
    2447, 765,         -- Peacebloom, Silverleaf
    10940,             -- Strange Dust
}
Stale.VERSION = 2
Stale.PEER_FRESH_DAYS = 2   -- a peer's scan counts as fresh this many days after it
Stale.HEARD_DAYS = 14       -- and only if we heard it in the last two weeks
Stale.KEEP_DAYS = 60
Stale.MAX_AGE = 21          -- Auctionator returns no age past 21 days

local function call(fn, ...)
    if type(fn) ~= "function" then return nil end
    local results = { pcall(fn, ...) }
    if not results[1] then return nil end
    return unpack(results, 2, table.maxn(results))
end

local function serverTime() return call(GetServerTime) or time() end

--- Pure: the server day (days since the epoch) of a server time.
function Stale.Day(t) return math.floor((t or serverTime()) / 86400) end

function Stale.On() return ns.Features.On("staleNudge") end

--- Days since Auctionator last saw the freshest watched trade good: 0 = today;
--- math.huge when none was seen in 21 days (or ever); nil without Auctionator.
function Stale.OwnAge()
    local api = ns.Prices.Auctionator()
    if not api then return nil end
    local best = math.huge
    for _, id in ipairs(Stale.WATCH) do
        local age
        if type(api.GetAuctionAgeByItemID) == "function" then
            age = tonumber((call(api.GetAuctionAgeByItemID, ns.Prices.CALLER, id)))
        else
            age = tonumber((call(api.GetAuctionAgeByItemLink, ns.Prices.CALLER, "item:" .. id)))
        end
        if age and age >= 0 and age < best then best = age end
    end
    return best
end

--- This character's scan day (server day of its freshest watched price), or nil.
function Stale.ScanDay(today)
    local age = Stale.OwnAge()
    if age == nil or age == math.huge then return nil end
    return (today or Stale.Day()) - math.floor(age)
end

--- Pure: the message that follows a hello: "F2|<server day>".
function Stale.Encode(day) return string.format("F%d|%d", Stale.VERSION, day) end

--- The message to send now, or nil (no Auctionator, nothing scanned in 21 days).
function Stale.Message()
    local day = Stale.ScanDay()
    return day and Stale.Encode(day) or nil
end

local function realmKey()
    local _, realm, faction = ns.Characters.Current()
    return tostring(realm) .. "|" .. tostring(faction)
end

local function store()
    MailworthyDB.fresh = type(MailworthyDB.fresh) == "table" and MailworthyDB.fresh or {}
    local key = realmKey()
    MailworthyDB.fresh[key] = type(MailworthyDB.fresh[key]) == "table" and MailworthyDB.fresh[key] or {}
    return MailworthyDB.fresh[key]
end

function Stale.Peers() return store() end

--- Record another Mailworthy's scan day (already a cleaned name). Data, never instructions:
--- a day in the future or older than KEEP_DAYS is dropped.
function Stale.Hear(name, day, at)
    at = at or serverTime()
    local today = Stale.Day(at)
    day = tonumber(day)
    if not day or day ~= math.floor(day) or day > today + 1 or day < today - Stale.KEEP_DAYS then return nil end
    local entry = { name = name, day = day, at = at }
    store()[tostring(name):lower()] = entry
    ns.Log.Add("stale", "%s scanned on day %d (%d day(s) ago)", tostring(name), day, today - day)
    return entry
end

--- Drop scan days not heard in KEEP_DAYS.
function Stale.Prune(at)
    at = at or serverTime()
    for key, e in pairs(store()) do
        if type(e) ~= "table" or (tonumber(e.at) or 0) < at - Stale.KEEP_DAYS * 86400 then store()[key] = nil end
    end
end

--- Pure: the freshest peer heard within HEARD_DAYS: { name, day } or nil.
function Stale.Freshest(peers, at)
    local best
    for _, e in pairs(peers or {}) do
        if type(e) == "table" and tonumber(e.day) and (tonumber(e.at) or 0) >= at - Stale.HEARD_DAYS * 86400
            and (not best or e.day > best.day) then
            best = e
        end
    end
    return best
end

--- Pure: the nudge to show, or nil. `ownAge` from OwnAge (nil = no Auctionator: no nudge,
--- the window already says there are no prices). Stale = older than `maxAgeDays`.
--- { level = "peer" (someone scanned within PEER_FRESH_DAYS) or "self", age, peer, peerAgo }.
function Stale.Nudge(ownAge, freshest, today, maxAgeDays)
    if ownAge == nil or ownAge <= (maxAgeDays or 7) then return nil end
    local nudge = { level = "self", age = ownAge }
    if freshest and today - freshest.day <= Stale.PEER_FRESH_DAYS and today - freshest.day < ownAge then
        nudge.level, nudge.peer, nudge.peerAgo = "peer", freshest.name, today - freshest.day
    end
    return nudge
end

local function ageText(days)
    if days == math.huge or days >= Stale.MAX_AGE then return "over 3 weeks old" end
    return string.format("%d days old", days)
end

local function agoText(days)
    if days <= 0 then return "today" end
    if days == 1 then return "yesterday" end
    return days .. " days ago"
end

local function firstName(name) return tostring(name):match("^(%S+)") or tostring(name) end

--- Pure: the line at the top of the Mailworthy window.
function Stale.Text(nudge)
    if not nudge then return nil end
    if nudge.level == "peer" then
        return string.format("|cffff8040Your auction prices are %s; %s scanned %s.|r Run an Auctionator scan at the "
            .. "auction house: until then, items with old prices stay in your bags.", ageText(nudge.age),
            firstName(nudge.peer), agoText(nudge.peerAgo))
    end
    return string.format("|cffaaaaaaYour auction prices are %s: items with old prices stay in your bags until an "
        .. "Auctionator scan.|r", ageText(nudge.age))
end

--- Pure: the chat line at the mailbox (only when a peer is fresher).
function Stale.ChatText(nudge)
    if not nudge or nudge.level ~= "peer" then return nil end
    return string.format("Your auction prices are %s and %s scanned %s. Run an Auctionator scan at the auction house "
        .. "for up-to-date verdicts.", ageText(nudge.age), firstName(nudge.peer), agoText(nudge.peerAgo))
end

--- The nudge right now, or nil (switched off, no Auctionator, prices fresh).
function Stale.Current()
    if not Stale.On() then return nil end
    local at = serverTime()
    return Stale.Nudge(Stale.OwnAge(), Stale.Freshest(store(), at), Stale.Day(at), ns.Config.Values().maxAgeDays)
end

--- For /mw report.
function Stale.ReportLines()
    local age = Stale.OwnAge()
    local lines = { "price freshness: " .. (age == nil and "no Auctionator"
        or (age == math.huge and "no watched trade good seen in 21 days")
        or string.format("freshest watched trade good seen %d day(s) ago", age)) }
    local today = Stale.Day()
    local peers = {}
    for _, e in pairs(store()) do
        if type(e) == "table" then
            peers[#peers + 1] = string.format("price stamp: %s scanned %d day(s) ago (heard %s)", tostring(e.name),
                today - (tonumber(e.day) or today), date("%b %d", e.at or 0))
        end
    end
    table.sort(peers)
    for _, l in ipairs(peers) do lines[#lines + 1] = l end
    local nudge = Stale.Current()
    lines[#lines + 1] = "stale nudge: " .. (nudge and nudge.level or "none")
    return lines
end

ns.On("PLAYER_LOGIN", function()
    Stale.Prune()
    -- Stale here: ask the guild and group to say hello, so fresh peers answer with their scan day.
    if C_Timer and type(C_Timer.After) == "function" then
        C_Timer.After((ns.Comms and ns.Comms.HELLO_DELAY or 8) + 2, function()
            local ok, nudge = pcall(Stale.Current)
            if ok and nudge and ns.Comms then pcall(ns.Comms.Ask) end
        end)
    end
end)

ns.On("MAIL_SHOW", function()
    local ok, nudge = pcall(Stale.Current)
    if not ok then return ns.Log.Add("stale", "error: %s", tostring(nudge)) end
    local text = Stale.ChatText(nudge)
    if text then ns.Print(text) end
end)
