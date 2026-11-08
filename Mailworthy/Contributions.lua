-- Guild contributions (Raid Ledger story ROK-2148; operator rulings, 2026-11-08): how much each of
-- this account's characters has mailed because of the guild template (Guild.lua), for Raid Ledger's
-- guild contributions widget. LedgerLink reads it through the read-only API below at export time and
-- carries it in its export string; Raid Ledger owns that wire format (its spec, section B: keys,
-- nesting and caps are copied from it, never changed here).
--
-- What counts (operator): only mail a guild template rule routed (Routes.Divert tags it, Mailer.lua
-- passes it here at MAIL_SEND_SUCCESS); personal and class bindings, the bank alt, Return to sender and
-- Blizzard's Send button never do. Items are stack units (20 Strange Dust in one mail = 20), per
-- sending character. Mail to this account's own characters (Ledger.IsOwn) is never counted, even when
-- an alt is the rule's player. No backfill: what went before this build can't be attributed.
--
-- Stored apart from the mail log, so its 2000-entry pruning never touches it:
--   MailworthyDB.guildGiven["realm|faction|guild"][lower(name)] =
--     { name, total (units since `since`), since (server time of its first counted mail),
--       days = { [UTC day number] = units } (the last DAYS days only) }
-- Older SavedVariables have no such table: it starts empty (Migrate cleans a damaged one).
--
-- The API: MailworthyAPI.v1.GetGuildExport(guildName) -> nil or a fresh table (never a reference into
-- MailworthyDB), never an error:
--   { generatedAt,
--     template = { rev, author, rules = { { professionSkillLineId, recipientName } } }   (no caps, no use)
--     peers  = { { name, lastSeenAt } }   Mailworthy users on this guild's roster, heard in 60 days,
--                                         newest first, at most 1000
--     givers = { { characterName, itemsAllTime, countingSince, days = { { day, items } } } }
--              this account's characters with anything counted, most first, at most 50; days ascending,
--              the last 35 UTC days, non-zero only }
-- Each part is left out when there's nothing in it; nil when there's nothing at all or no guild.
-- Names longer than NAME_MAX are left out, never shortened. Reads only; nothing here sends mail.
local _, ns = ...

local Contributions = {}
ns.Contributions = Contributions

Contributions.DAYS = 35                -- day buckets kept and exported (Raid Ledger: 30 days + clock slack)
Contributions.NAME_MAX = 48            -- Comms.MAX_NAME; Raid Ledger's name cap
Contributions.RULES_MAX = 8            -- Guild.MAX_RULES
Contributions.PEERS_MAX = 1000
Contributions.GIVERS_MAX = 50
Contributions.UNIX_MAX = 4102444800    -- Raid Ledger's unix-seconds ceiling (2100-01-01)
Contributions.COUNT_MAX = 2147483647   -- Postgres int4
Contributions.DAY_MAX = 47482          -- floor(UNIX_MAX / 86400)
Contributions.ROSTER_GAP = 10          -- seconds between roster reads on GUILD_ROSTER_UPDATE (one more follows)

local function call(fn, ...)
    if type(fn) ~= "function" then return nil end
    local results = { pcall(fn, ...) }
    if not results[1] then return nil end
    return unpack(results, 2, table.maxn(results))
end

local function now() return call(GetServerTime) or time() end
local function tableOr(t) return type(t) == "table" and t or {} end

--- Pure: a whole number from 0 to COUNT_MAX, or nil.
local function whole(x)
    x = tonumber(x)
    if not x or x ~= x or x < 0 or x == math.huge then return nil end
    return math.min(math.floor(x), Contributions.COUNT_MAX)
end

--- Pure: server time in whole seconds (1 to UNIX_MAX), or nil.
local function unixTime(x)
    x = tonumber(x)
    if not x or x ~= x or x < 1 or x > Contributions.UNIX_MAX then return nil end
    return math.floor(x)
end

--- Pure: a player name as Mailworthy holds it (no realm), 1 to NAME_MAX bytes, or nil.
local function cleanName(name)
    name = type(name) == "string" and ns.Routes.Clean(name) or nil
    if not name or #name > Contributions.NAME_MAX or name:find("%c") then return nil end
    return name
end

--- Pure: the UTC day number of a server time.
function Contributions.Day(at) return math.floor((tonumber(at) or 0) / 86400) end

--- Pure: `day` is one of the last DAYS UTC days up to `today` (a later one, from a clock that ran
--- ahead, would push a real day out of the export's 35; Codex review).
function Contributions.InWindow(day, today)
    return day > today - Contributions.DAYS and day <= today and day <= Contributions.DAY_MAX
end

-- Counting -------------------------------------------------------------------------------------

function Contributions.Store()
    MailworthyDB.guildGiven = tableOr(MailworthyDB.guildGiven)
    return MailworthyDB.guildGiven
end

--- Pure: a counter as SavedVariables hold it, cleaned and with days before the window dropped
--- (`today`: a UTC day number), as a new table; nil when nothing is left of it.
function Contributions.Clean(c, today)
    if type(c) ~= "table" then return nil end
    local name = cleanName(c.name)
    if not name then return nil end
    local days, sum = {}, 0
    for day, units in pairs(tableOr(c.days)) do
        day, units = whole(day), whole(units)
        if day and units and units > 0 and Contributions.InWindow(day, today) then
            days[day] = units
            sum = sum + units
        end
    end
    local total = math.min(Contributions.COUNT_MAX, math.max(whole(c.total) or 0, sum))
    if total <= 0 then return nil end
    return { name = name, total = total, since = unixTime(c.since) or unixTime(now()), days = days }
end

--- Clean every counter (older or damaged SavedVariables) and drop day buckets past the window.
function Contributions.Migrate(at)
    local today = Contributions.Day(at or now())
    local all = Contributions.Store()
    for key, guild in pairs(all) do
        if type(key) ~= "string" or type(guild) ~= "table" then
            all[key] = nil
        else
            for who, c in pairs(guild) do
                local kept = type(who) == "string" and Contributions.Clean(c, today) or nil
                guild[who] = kept and kept.name:lower() == who and kept or nil
            end
            if next(guild) == nil then all[key] = nil end
        end
    end
end

--- Pure: a sent mail's guild rule (the first stack a guild rule routed: Routes.Divert's `guild`)
--- with the stack units those stacks carried, or nil: { key, profession, rev, units }.
function Contributions.Tag(mail)
    local tag
    for _, stack in ipairs(type(mail) == "table" and tableOr(mail.attached) or {}) do
        local result = type(stack) == "table" and type(stack.item) == "table" and stack.item.result
        local guild = type(result) == "table" and result.guild
        if type(guild) == "table" and tonumber(guild.profession) then
            tag = tag or { key = guild.key, profession = tonumber(guild.profession), rev = tonumber(guild.rev), units = 0 }
            tag.units = tag.units + (whole(stack.count) or 1)
        end
    end
    return tag
end

--- Count a guild rule's mail (Contributions.Tag) that went to `to`, for `char` (default: this
--- character) at server time `at`. Returns true, or false and why not.
function Contributions.Count(to, tag, at, char)
    if type(tag) ~= "table" or type(tag.key) ~= "string" then return false, "no guild rule" end
    local units = whole(tag.units) or 0
    if units <= 0 then return false, "nothing attached" end
    if ns.Ledger.IsOwn(to) then
        ns.Log.Add("contributions", "not counted: %d unit(s) to %s, this account's own character", units, tostring(to))
        return false, "own character"
    end
    char = cleanName(char or ns.PlayerName())
    if not char then return false, "no name" end
    at = unixTime(at or now()) or unixTime(time())
    local today = Contributions.Day(at)
    local all = Contributions.Store()
    local guild = tableOr(all[tag.key])
    all[tag.key] = guild
    local c = Contributions.Clean(guild[char:lower()], today) or { name = char, total = 0, since = at, days = {} }
    c.name = char
    c.total = math.min(Contributions.COUNT_MAX, c.total + units)
    c.days[today] = math.min(Contributions.COUNT_MAX, (c.days[today] or 0) + units)
    guild[char:lower()] = c
    ns.Log.Add("contributions", "%d unit(s) of %s to %s counted for %s", units,
        tostring(ns.Routes.ProfessionName(tag.profession) or tag.profession), tostring(to), char)
    return true
end

-- The guild roster (who may be listed as a peer) ------------------------------------------------

local roster = { guild = nil, names = nil, at = -math.huge }

local function readRoster()
    if call(IsInGuild) ~= true then return nil end
    local names, n = {}, 0
    local function add(name)
        name = type(name) == "string" and ns.Routes.Clean(name) or nil
        if name then
            names[name:lower()] = true
            n = n + 1
        end
    end
    local club = rawget(_G, "C_Club")
    local clubId = type(club) == "table" and call(club.GetGuildClubId) or nil
    local members = clubId and call(club.GetClubMembers, clubId) or nil
    if type(members) == "table" and #members > 0 then
        for _, memberId in ipairs(members) do
            local info = call(club.GetMemberInfo, clubId, memberId)
            if type(info) == "table" then add(info.name) end
        end
    else
        for i = 1, tonumber((call(GetNumGuildMembers))) or 0 do add((call(GetGuildRosterInfo, i))) end
    end
    return n > 0 and names or nil
end

--- The lower-case names on `guild`'s roster, or nil when it can't be read: read now while this
--- character is in that guild, else the last read of it this session (at logout the roster may be gone
--- already; GUILD_ROSTER_UPDATE keeps that read at most ROSTER_GAP seconds behind).
function Contributions.Roster(guild)
    if type(guild) ~= "string" then return nil end
    if ns.Guild.Mine() == guild then
        local names = readRoster()
        if names then roster.guild, roster.names, roster.at = guild, names, call(GetTime) or 0 end
    end
    return roster.guild == guild and roster.names or nil
end

-- GUILD_ROSTER_UPDATE: read the roster again, at most every ROSTER_GAP seconds; an update inside the gap
-- gets one read when it ends, so a member who left drops out (Codex review).
local trailing = false
local function onRosterUpdate()
    local guild = ns.Guild.Mine()
    if not guild then return end
    local wait = roster.at + Contributions.ROSTER_GAP - (call(GetTime) or 0)
    if wait <= 0 then return Contributions.Roster(guild) end
    if trailing then return end
    trailing = true
    local timer = rawget(_G, "C_Timer")
    if type(timer) ~= "table" or type(timer.After) ~= "function" then
        trailing = false
        return Contributions.Roster(guild)
    end
    timer.After(wait, function()
        trailing = false
        local g = ns.Guild.Mine()
        if g then pcall(Contributions.Roster, g) end
    end)
end

-- The export --------------------------------------------------------------------------------------

--- Pure: the export table from what Mailworthy holds, every table new. `input`: now (server time),
--- template (Guild's saved template), peers (Comms' peers here), roster (Contributions.Roster, nil =
--- unknown: no peers), givers (this guild's counters). Nil when nothing is left.
function Contributions.Build(input)
    input = tableOr(input)
    local at = unixTime(input.now)
    if not at then return nil end
    local out, any = { generatedAt = at }, false

    local t = input.template
    if type(t) == "table" then
        local rev, author = unixTime(t.rev), cleanName(t.from)
        if rev and author then
            local rules = {}
            for _, r in ipairs(tableOr(t.rules)) do
                if #rules >= Contributions.RULES_MAX then break end
                local id, to = type(r) == "table" and whole(r.profession), type(r) == "table" and cleanName(r.to)
                if id and id > 0 and to then rules[#rules + 1] = { professionSkillLineId = id, recipientName = to } end
            end
            out.template = { rev = rev, author = author, rules = rules }
            any = true
        end
    end

    if type(input.roster) == "table" then
        local peerDays = ns.Comms and ns.Comms.PEER_DAYS or 60
        local list = {}
        for _, p in pairs(tableOr(input.peers)) do
            local name, seen = type(p) == "table" and cleanName(p.name), type(p) == "table" and unixTime(p.at)
            if name and seen and seen >= at - peerDays * 86400 and input.roster[name:lower()] then
                list[#list + 1] = { name = name, lastSeenAt = seen }
            end
        end
        table.sort(list, function(a, b)
            if a.lastSeenAt ~= b.lastSeenAt then return a.lastSeenAt > b.lastSeenAt end
            return a.name < b.name
        end)
        for i = #list, Contributions.PEERS_MAX + 1, -1 do list[i] = nil end
        if #list > 0 then out.peers, any = list, true end
    end

    local today, givers = Contributions.Day(at), {}
    for _, c in pairs(tableOr(input.givers)) do
        local name, since = type(c) == "table" and cleanName(c.name), type(c) == "table" and unixTime(c.since)
        if name and since then
            local days, sum = {}, 0
            for day, units in pairs(tableOr(c.days)) do
                day, units = whole(day), whole(units)
                if day and units and units > 0 and Contributions.InWindow(day, today) then
                    days[#days + 1] = { day = day, items = units }
                end
            end
            table.sort(days, function(a, b) return a.day < b.day end)
            while #days > Contributions.DAYS do table.remove(days, 1) end -- the newest DAYS
            for _, d in ipairs(days) do sum = sum + d.items end
            local total = math.min(Contributions.COUNT_MAX, math.max(whole(c.total) or 0, sum))
            if total > 0 then
                givers[#givers + 1] = { characterName = name, itemsAllTime = total, countingSince = since, days = days }
            end
        end
    end
    table.sort(givers, function(a, b)
        if a.itemsAllTime ~= b.itemsAllTime then return a.itemsAllTime > b.itemsAllTime end
        return a.characterName < b.characterName
    end)
    for i = #givers, Contributions.GIVERS_MAX + 1, -1 do givers[i] = nil end
    if #givers > 0 then out.givers, any = givers, true end

    return any and out or nil
end

--- The export for `guildName` (default: this character's guild; LedgerLink passes the name it cached,
--- since the guild may be gone at logout). Reads MailworthyDB, never writes it.
function Contributions.Export(guildName)
    local guild = type(guildName) == "string" and guildName ~= "" and guildName or ns.Guild.Mine()
    if not guild or type(MailworthyDB) ~= "table" then return nil end
    local key = ns.Guild.Key(guild)
    local _, realm, faction = ns.Characters.Current()
    local templates, peers, given = tableOr(MailworthyDB.guildTemplates), tableOr(MailworthyDB.peers),
        tableOr(MailworthyDB.guildGiven)
    return Contributions.Build({ now = now(), template = templates[key],
        peers = peers[tostring(realm) .. "|" .. tostring(faction)], roster = Contributions.Roster(guild),
        givers = given[key] })
end

--- Lines for /mw report: counts only, never names.
function Contributions.ReportLines()
    local key = ns.Guild.Key()
    local guild = key and tableOr(tableOr(MailworthyDB.guildGiven)[key]) or {}
    local chars, total = 0, 0
    for _, c in pairs(guild) do
        chars = chars + 1
        total = total + (whole(type(c) == "table" and c.total) or 0)
    end
    local lines = { string.format("guild contributions: %s, %d character(s), %d unit(s) counted",
        key and "this guild" or "no guild", chars, total) }
    local e = MailworthyAPI.v1.GetGuildExport()
    if e then
        lines[#lines + 1] = string.format("guild export: template %s, %d peer(s), %d giver(s)",
            e.template and string.format("rev %d, %d rule(s)", e.template.rev, #e.template.rules) or "none",
            #(e.peers or {}), #(e.givers or {}))
    else
        lines[#lines + 1] = "guild export: nothing (no guild, or nothing known)"
    end
    if Contributions.lastError then lines[#lines + 1] = "guild export error: " .. Contributions.lastError end
    return lines
end

-- The read-only API (pattern: Auctionator.API.v1). Never errors; nil when there's nothing to say.
MailworthyAPI = type(MailworthyAPI) == "table" and MailworthyAPI or {}
MailworthyAPI.v1 = type(MailworthyAPI.v1) == "table" and MailworthyAPI.v1 or {}
function MailworthyAPI.v1.GetGuildExport(guildName)
    local ok, result = pcall(Contributions.Export, guildName)
    if ok and type(result) == "table" then return result end
    -- Kept in memory for /mw report, never logged: the API writes nothing to SavedVariables (Codex review).
    if not ok then Contributions.lastError = tostring(result) end
    return nil
end

ns.On("PLAYER_LOGIN", function() Contributions.Migrate() end)
ns.On("GUILD_ROSTER_UPDATE", onRosterUpdate)
