-- Addon messages between Mailworthy users (C_ChatInfo, prefix "Mailworthy"), so a
-- binding reaches the friend's character that has the profession (operator,
-- 2026-10-26: "get the materials to the friend that actually has the profession,
-- not to their alt for the AH") and the friends window can mark who runs
-- Mailworthy and what they craft. Each Mailworthy says hello to its guild and
-- group at login, when the group changes, and when another Mailworthy asks (the
-- friends window asks when it opens):
--
--   H2|<this character's crafting skill lines>|<other characters on this realm + faction
--       that have a crafting profession: Name=333,197;Other Name=165>
--   A2                                                   (ask: please say hello)
--   F2|<server day of this character's freshest Auctionator scan>  (Stale.lua; right after
--       a hello; Mailworthys before v0.15 drop it, as they drop any kind they don't know)
--   T2|<revision>|<author>|<i>/<n>|<skill line>=<Name>:<cap>   (a guild template rule: Guild.lua;
--       GUILD only; any member passes a copy on; an odd cap on the Enchanting rule is its Gear
--       switch, Guild.WireCap)
--   Q2|<revision held>                    (ask: whoever holds a newer guild template sends it)
--   S2|<this character's crafting skills: 129:80,197:130>|<other characters here:
--       Name=197:150,333:120;Other Name=165:90>   (right after a hello, for the material
--       tiers: a binding stops taking what the bound player's skill is past; Mailworthys
--       before v0.18 drop it)
--   M2|<mail's sender>|<recipient>|<server time>|<mail id>|<itemID>:<count>:<copper>:<scan age>:<k>;...
--       (Ledger.lua: what a mail to another player was worth when it went; WHISPER only, to the
--       recipient once heard from. v0.25.0 sent V2|<sender>|<recipient>|<time>|<itemID>:<count>:<copper>;...,
--       still read, and drops M2)
--   R2|<recipient>|<mail's sender>|<mail id>|<itemID>:<count>:<copper>:<k>;...   (Ledger.lua: the value the
--       recipient settled on when it differs from the M2 one, so the sender's log matches; WHISPER only,
--       held until the sender is heard from)
--   U2|<this build's release: v0.31.0>   (Version.lua: right after a hello, release builds only;
--       fields after the version are left out; v0.30.0 and older drop it)
--   G2|<asOf>|<i>/<n>|<total>|<since>|<days back>:<units>;...   (Contributions.lua: this character's own
--       guild-rule giving, right after a hello and after a mailbox visit that counted some; GUILD only;
--       information only, for Raid Ledger's guild contributions; older Mailworthys drop it)
--
-- What arrives is data from other players, never instructions: names are
-- cleaned and length-checked, professions must be crafting skill lines
-- Mailworthy knows, anything else is dropped. Peers are kept per realm +
-- faction in MailworthyDB.peers for PEER_DAYS. Switch: /mw feature comms off.
-- The API is Forever's documented C_ChatInfo (RegisterAddonMessagePrefix,
-- SendAddonMessage, CHAT_MSG_ADDON); unseen in game yet (README "Beta unknowns").
local _, ns = ...

local Comms = {}
ns.Comms = Comms

Comms.PREFIX = "Mailworthy"
Comms.VERSION = 2
Comms.MAX_MESSAGE = 255   -- the addon-message limit; characters past it are left out
Comms.PEER_DAYS = 60
Comms.HELLO_DELAY = 8      -- seconds after login (the guild roster and group are in by then)
Comms.THROTTLE = 10        -- seconds between hellos
Comms.ASK_THROTTLE = 30    -- seconds between asks
Comms.MAX_NAME = 48
-- A player in both our guild and our group sends every message on GUILD and PARTY; the copy
-- that arrives within this many seconds is dropped (rl-companion log, 2026-11-08: every hello
-- was heard, stored and logged twice).
Comms.DUPLICATE_WINDOW = 5

local lastHello, lastAsk, pendingHello = -math.huge, -math.huge, false
local recent, recentCount = {}, 0 -- "sender\ntext" -> GetTime() it was last heard (Comms.Duplicate)
local groupSeen = {}              -- lower-case name -> true: the online group members at the last roster change
Comms.stats = { heard = 0, copies = 0, hellos = 0, rosterQuiet = 0 }
local announcedSteps -- "129:1,197:2": the tier steps (Tiers.Step) last told to peers

--- Pure: the tier steps of a professions list, as text to compare ("129:1,197:2").
function Comms.Steps(professions)
    local out = {}
    for _, p in ipairs(type(professions) == "table" and professions or {}) do
        local id = tonumber(type(p) == "table" and p.skillLine)
        if id and ns.Valuation.PROFESSION_MATS[id] then out[#out + 1] = id .. ":" .. ns.Tiers.Step(id, p.rank) end
    end
    table.sort(out)
    return table.concat(out, ",")
end

local function call(fn, ...)
    if type(fn) ~= "function" then return nil end
    local results = { pcall(fn, ...) }
    if not results[1] then return nil end
    return unpack(results, 2, table.maxn(results))
end

local function now() return call(GetTime) or 0 end
local function serverTime() return call(GetServerTime) or time() end

local function realmKey()
    local _, realm, faction = ns.Characters.Current()
    return tostring(realm) .. "|" .. tostring(faction)
end

local function store()
    MailworthyDB.peers = type(MailworthyDB.peers) == "table" and MailworthyDB.peers or {}
    local key = realmKey()
    MailworthyDB.peers[key] = type(MailworthyDB.peers[key]) == "table" and MailworthyDB.peers[key] or {}
    return MailworthyDB.peers[key]
end

function Comms.On() return ns.Features.On("comms") end

--- Pure: the crafting skill lines in a professions list ({ skillLine = } entries or ids), sorted.
local function craftingIds(professions)
    local ids = {}
    for _, p in ipairs(type(professions) == "table" and professions or {}) do
        local id = tonumber(type(p) == "table" and p.skillLine or p)
        if id and ns.Valuation.PROFESSION_MATS[id] then ids[#ids + 1] = id end
    end
    table.sort(ids)
    return ids
end

local function idText(ids)
    local out = {}
    for i, id in ipairs(ids) do out[i] = tostring(id) end
    return table.concat(out, ",")
end

local function goodName(name)
    name = ns.Routes.Clean(name)
    if not name or #name > Comms.MAX_NAME or name:find("[%c=;|]") then return nil end
    return name
end

--- Pure: this character's hello: its crafting professions and the account's other
--- characters here that craft ({ { name, professions }, ... }), as many as fit.
function Comms.Encode(professions, characters)
    local head = string.format("H%d|%s|", Comms.VERSION, idText(craftingIds(professions)))
    local parts = {}
    for _, c in ipairs(type(characters) == "table" and characters or {}) do
        local ids, name = craftingIds(c.professions), goodName(c.name)
        if name and #ids > 0 then
            local part = name .. "=" .. idText(ids)
            local candidate = head .. table.concat(parts, ";") .. (#parts > 0 and ";" or "") .. part
            if #candidate <= Comms.MAX_MESSAGE then parts[#parts + 1] = part end
        end
    end
    return head .. table.concat(parts, ";")
end

local function skillText(professions)
    local out = {}
    for _, p in ipairs(type(professions) == "table" and professions or {}) do
        local id, rank = tonumber(type(p) == "table" and p.skillLine), tonumber(type(p) == "table" and p.rank)
        if id and rank and ns.Valuation.PROFESSION_MATS[id] then out[#out + 1] = { id, math.floor(rank) } end
    end
    table.sort(out, function(a, b) return a[1] < b[1] end)
    for i, e in ipairs(out) do out[i] = e[1] .. ":" .. e[2] end
    return table.concat(out, ",")
end

--- Pure: the skills message: this character's crafting skills and the account's other
--- characters' here ({ { name, professions = { { skillLine, rank } } } }), as many as fit.
function Comms.EncodeSkills(professions, characters)
    local head = string.format("S%d|%s|", Comms.VERSION, skillText(professions))
    local parts = {}
    for _, c in ipairs(type(characters) == "table" and characters or {}) do
        local skills, name = skillText(c.professions), goodName(c.name)
        if name and skills ~= "" then
            local part = name .. "=" .. skills
            local candidate = head .. table.concat(parts, ";") .. (#parts > 0 and ";" or "") .. part
            if #candidate <= Comms.MAX_MESSAGE then parts[#parts + 1] = part end
        end
    end
    return head .. table.concat(parts, ";")
end

-- Pure: "129:80,197:130" -> { [129] = 80, [197] = 130 } (crafting skill lines Mailworthy knows,
-- ranks 0-999), and whether any was found.
local function decodeSkills(text)
    local skills, any = {}, false
    for id, rank in tostring(text):gmatch("(%d+):(%d+)") do
        id, rank = tonumber(id), tonumber(rank)
        if ns.Routes.ProfessionName(id) and rank <= 999 then skills[id], any = rank, true end
    end
    return skills, any
end

--- Pure: a message from another Mailworthy, or nil. { kind = "hello", version, professions =
--- { ids }, characters = { { name, professions = { ids } }, ... } }, { kind = "ask", version }
--- or { kind = "fresh", version, day } (a scan day: Stale.lua), or { kind = "skills", version,
--- skills = { [id] = rank }, characters = { { name, skills } } } (the material tiers), or
--- { kind = "release", version, release = "v0.31.0" } (Version.lua).
function Comms.Decode(text)
    if type(text) ~= "string" or #text > Comms.MAX_MESSAGE then return nil end
    local kind, version, rest = text:match("^(%a)(%d+)|?(.*)$")
    if kind == "A" then return { kind = "ask", version = tonumber(version) } end
    if kind == "Q" then
        local rev = rest:match("^(%d*)$")
        return rev and #rev <= 10 and { kind = "templateAsk", version = tonumber(version), rev = tonumber(rev) or 0 } or nil
    end
    if kind == "T" then
        local part = ns.Guild.DecodePart(rest)
        return part and { kind = "template", version = tonumber(version), part = part } or nil
    end
    if kind == "S" then
        local own, chars = rest:match("^([%d:,]*)|?([^|]*)$")
        if own == nil then return nil end
        local characters = {}
        for part in tostring(chars):gmatch("[^;]+") do
            local name, list = part:match("^([^=]+)=([%d:,]*)$")
            name = name and goodName(name)
            local skills, any = decodeSkills(list)
            if name and any then characters[#characters + 1] = { name = name, skills = skills } end
        end
        return { kind = "skills", version = tonumber(version), skills = (decodeSkills(own)), characters = characters }
    end
    if kind == "V" or kind == "M" then
        local values = ns.Ledger and ns.Ledger.DecodeValues(rest, kind)
        return values and { kind = "values", version = tonumber(version), values = values } or nil
    end
    if kind == "R" then
        local answers = ns.Ledger and ns.Ledger.DecodeAnswers(rest)
        return answers and { kind = "answers", version = tonumber(version), answers = answers } or nil
    end
    if kind == "U" then
        local release = text:match("^U%d+|([^|]*)") -- the separator is required: "U2v0.31.0" is junk
        return ns.Version and ns.Version.Parse(release) and { kind = "release", version = tonumber(version), release = release }
            or nil
    end
    if kind == "G" then
        local part = ns.Contributions and ns.Contributions.DecodePart(rest)
        return part and { kind = "giving", version = tonumber(version), part = part } or nil
    end
    if kind == "F" then
        local day = rest:match("^(%d+)$")
        return day and #day <= 7 and { kind = "fresh", version = tonumber(version), day = tonumber(day) } or nil
    end
    if kind ~= "H" then return nil end
    local profs, chars = rest:match("^([%d,]*)|?([^|]*)$")
    if profs == nil then return nil end
    local function known(list)
        local ids = {}
        for id in tostring(list):gmatch("%d+") do
            if ns.Routes.ProfessionName(tonumber(id)) then ids[#ids + 1] = tonumber(id) end
        end
        return ids
    end
    local characters = {}
    for part in tostring(chars):gmatch("[^;]+") do
        local name, ids = part:match("^([^=]+)=([%d,]*)$")
        name = name and goodName(name)
        if name and #known(ids) > 0 then characters[#characters + 1] = { name = name, professions = known(ids) } end
    end
    return { kind = "hello", version = tonumber(version), professions = known(profs), characters = characters }
end

local function channels()
    local list = {}
    if call(IsInGuild) == true then list[#list + 1] = "GUILD" end
    local n = tonumber((call(GetNumGroupMembers))) or 0
    if n > 0 then list[#list + 1] = call(IsInRaid) == true and "RAID" or "PARTY" end
    return list
end

-- A send result that means "sent": SendAddonMessage returns nothing on older clients, true, or
-- Enum.SendAddonMessageResult.Success (0).
local function sentOk(ok, result)
    return ok and (result == nil or result == true or result == 0)
end

-- Send `message` on the guild and group channels. Returns whether any channel took it and the
-- channels with their result ("GUILD, PARTY", or "GUILD, PARTY error 3" for one that failed).
local function send(message)
    local chat = rawget(_G, "C_ChatInfo")
    if type(chat) ~= "table" then return false, "no C_ChatInfo" end
    local sent, parts = false, {}
    for _, channel in ipairs(channels()) do
        local ok, result = pcall(chat.SendAddonMessage, Comms.PREFIX, message, channel)
        sent = sent or sentOk(ok, result) -- a rejected send (error code, no throw) didn't go out
        parts[#parts + 1] = sentOk(ok, result) and channel or (channel .. " error " .. tostring(result))
    end
    return sent, #parts > 0 and table.concat(parts, ", ") or "no guild or group"
end

--- Send one message to the guild only (Guild.lua's template and asks).
function Comms.SendGuild(message)
    if not Comms.On() or call(IsInGuild) ~= true then return false end
    local chat = rawget(_G, "C_ChatInfo")
    if type(chat) ~= "table" then return false end
    local ok, result = pcall(chat.SendAddonMessage, Comms.PREFIX, message, "GUILD")
    ns.Log.Add("comms", "%s on GUILD: %s", message:sub(1, 2), ok and tostring(result) or ("error " .. tostring(result)))
    return ok
end

--- Whisper one message to one player (Ledger.lua's values; only to a player just heard from,
--- so never to someone offline).
function Comms.Whisper(target, message)
    if not Comms.On() or not target then return false end
    local chat = rawget(_G, "C_ChatInfo")
    if type(chat) ~= "table" then return false end
    local ok, result = pcall(chat.SendAddonMessage, Comms.PREFIX, message, "WHISPER", target)
    ns.Log.Add("comms", "%s to %s: %s", message:sub(1, 2), tostring(target), ok and tostring(result) or ("error " .. tostring(result)))
    return ok
end

--- Say hello to the guild and group (throttled; a hello the throttle held back goes out at the
--- next mailbox). One log line per hello, whatever the number of channels and messages.
function Comms.Announce(reason)
    if not Comms.On() then return false end
    if now() - lastHello < Comms.THROTTLE then
        pendingHello = true
        return false
    end
    lastHello, pendingHello = now(), false
    local professions = ns.Characters.Professions()
    local sent, where = send(Comms.Encode(professions, ns.Characters.Mailable()))
    local results = { { "H2", where } }
    if sent then
        local _, skillsWhere = send(Comms.EncodeSkills(professions, ns.Characters.Mailable()))
        results[#results + 1] = { "S2", skillsWhere }
        announcedSteps = Comms.Steps(professions)
        Comms.stats.hellos = Comms.stats.hellos + 1
    end
    local fresh = ns.Stale and ns.Stale.Message()
    if sent and fresh then
        local _, freshWhere = send(fresh)
        results[#results + 1] = { fresh:sub(1, 2), freshWhere }
    end
    local release = ns.Version and ns.Version.Message() -- nil on a dev build
    if sent and release then
        local _, releaseWhere = send(release)
        results[#results + 1] = { release:sub(1, 2), releaseWhere }
    end
    -- This character's guild-rule giving (Contributions.lua), to the guild only.
    local giving = sent and ns.Contributions and ns.Contributions.Messages() or {}
    if #giving > 0 and call(IsInGuild) == true then
        local chat, givingWhere = rawget(_G, "C_ChatInfo"), "GUILD"
        for _, message in ipairs(giving) do
            local ok, result = pcall(chat.SendAddonMessage, Comms.PREFIX, message, "GUILD")
            if not sentOk(ok, result) then givingWhere = "GUILD error " .. tostring(result) end
        end
        results[#results + 1] = { "G2", givingWhere }
    end
    ns.Log.Add("comms", "hello (%s): %s", tostring(reason), Comms.ResultText(results))
    return sent
end

--- Pure: { { kind, where }, ... } as one log text: "H2 S2 F2 on GUILD, PARTY" when every message
--- went the same way, else each with its own ("H2 on GUILD; S2 on GUILD error 3"), so a failed
--- send still shows in the one line.
function Comms.ResultText(results)
    local kinds, same = {}, true
    for i, r in ipairs(results) do
        kinds[i] = r[1]
        same = same and r[2] == results[1][2]
    end
    if same and #results > 0 then return table.concat(kinds, " ") .. " on " .. tostring(results[1][2]) end
    local parts = {}
    for i, r in ipairs(results) do parts[i] = r[1] .. " on " .. tostring(r[2]) end
    return table.concat(parts, "; ")
end

--- Ask other Mailworthys to say hello (the friends window, throttled).
function Comms.Ask()
    if not Comms.On() or now() - lastAsk < Comms.ASK_THROTTLE then return false end
    lastAsk = now()
    local sent, where = send(string.format("A%d", Comms.VERSION))
    ns.Log.Add("comms", "ask (A2) on %s", where)
    return sent
end

--- Whether `text` from `name` is a copy of one heard less than DUPLICATE_WINDOW seconds ago
--- (the same message on GUILD and PARTY). Whispers are never copies. Records the first one.
function Comms.Duplicate(name, text, channel, at)
    if channel == "WHISPER" then return false end
    local key = tostring(name):lower() .. "\n" .. tostring(text)
    local last = recent[key]
    if last and at - last < Comms.DUPLICATE_WINDOW then return true end
    if not last then recentCount = recentCount + 1 end
    recent[key] = at
    if recentCount > 64 then -- forget what is past the window (a busy guild sends many kinds)
        recentCount = 0
        for k, t in pairs(recent) do
            if at - t >= Comms.DUPLICATE_WINDOW then recent[k] = nil else recentCount = recentCount + 1 end
        end
    end
    return false
end

--- Peers heard from on this realm + faction: lower-case name -> { name, professions, characters, version (the
--- wire format, 2), at, skills, release (the Mailworthy release they run, Version.lua) }.
function Comms.Peers()
    return store()
end

function Comms.Peer(name)
    name = ns.Routes.Clean(name)
    return name and store()[name:lower()] or nil
end

-- The Mailworthy mark (operator, 2026-11-08: "a mailworthy icon or some sort of indicator on the
-- mailworthy ui when a player's name is mentioned showing if they have mailworthy as well"): the
-- addon's icon right after a name, as a texture escape in our own font strings (no frame, no
-- texture on anything of Blizzard's, no tooltip). Each window that shows one says what it means in
-- its footer (MARK_KEY, Widgets.Footer), so nothing depends on hovering. Switch: peerMark.
Comms.MARK = "|TInterface\\AddOns\\Mailworthy\\Textures\\Icon:0|t"
Comms.MARK_KEY = Comms.MARK .. " runs Mailworthy"

--- Whether `name` is known to run Mailworthy: this character, one of the account's characters
--- on this realm + faction (Mailworthy recorded them), a player whose Mailworthy said hello, or a
--- character that player's hello listed as theirs. Peers go after PEER_DAYS (Prune).
function Comms.Runs(name)
    name = ns.Routes.Clean(name)
    if not name then return false end
    local lower = name:lower()
    if lower == tostring(ns.PlayerName()):lower() then return true end
    for _, entry in ipairs(ns.Characters.Mailable()) do
        if tostring(entry.name):lower() == lower then return true end
    end
    local peers = store()
    if type(peers[lower]) == "table" then return true end
    for _, peer in pairs(peers) do
        local characters = type(peer) == "table" and peer.characters
        for _, c in ipairs(type(characters) == "table" and characters or {}) do
            if type(c) == "table" and tostring(c.name):lower() == lower then return true end
        end
    end
    return false
end

-- Windows that show marks redraw when the names behind them change (a new peer, a peer's
-- characters or professions changed), once per burst of messages: never on every addon packet (Codex review).
Comms.MARK_DELAY = 1 -- seconds
local markListeners, markPending = {}, false

--- Call `fn` (no arguments) after the set of names known to run Mailworthy changed.
function Comms.OnMarksChanged(fn)
    if type(fn) == "function" then markListeners[#markListeners + 1] = fn end
end

local function notifyMarks()
    markPending = false
    for _, fn in ipairs(markListeners) do
        local ok, err = pcall(fn)
        if not ok then ns.Log.Add("error", "mark redraw: %s", tostring(err)) end
    end
end

-- Pure: what a stored peer puts on screen, as text: the names it marks (the sender and the
-- characters its hello listed) with their professions, which decide where a binding delivers
-- (Routes.Crafter: "delivered to <their crafter>"; Codex review). Skill ranks are left out.
local function markNames(peer)
    if type(peer) ~= "table" then return "" end
    local function entry(name, professions)
        local ids = {}
        for i, id in ipairs(type(professions) == "table" and professions or {}) do ids[i] = tostring(id) end
        table.sort(ids)
        return tostring(name):lower() .. "=" .. table.concat(ids, ",")
    end
    local names = { entry(peer.name, peer.professions) }
    for _, c in ipairs(type(peer.characters) == "table" and peer.characters or {}) do
        if type(c) == "table" then names[#names + 1] = entry(c.name, c.professions) end
    end
    table.sort(names)
    return table.concat(names, ";")
end

local function marksChanged(old, new)
    if markNames(old) == markNames(new) or markPending then return end
    markPending = true
    if C_Timer and type(C_Timer.After) == "function" then
        C_Timer.After(Comms.MARK_DELAY, notifyMarks)
    else
        notifyMarks()
    end
end

--- `text` (default: the name) with the Mailworthy mark after it when `name` runs Mailworthy, and
--- whether it was marked (the window then shows MARK_KEY in its footer).
function Comms.Mark(name, text)
    text = text or tostring(name)
    if not ns.Features.On("peerMark") or not Comms.Runs(name) then return text, false end
    return text .. " " .. Comms.MARK, true
end

--- Record a hello from `sender` (a name, possibly with a realm suffix) on `channel`.
function Comms.Hear(sender, text, channel)
    local msg = Comms.Decode(text)
    local name = ns.Routes.Clean(sender)
    if not msg or not name or #name > Comms.MAX_NAME or name:find("%c") then return nil end
    if name:lower() == tostring(ns.PlayerName()):lower() then return nil end
    -- G2 counts only on GUILD: a copy on another channel is dropped before it could make the guild's copy a
    -- "duplicate" (Codex review).
    if msg.kind == "giving" and channel ~= "GUILD" then return nil end
    if Comms.Duplicate(name, text, channel, now()) then
        Comms.stats.copies = Comms.stats.copies + 1
        return nil
    end
    Comms.stats.heard = Comms.stats.heard + 1
    if msg.kind == "values" then
        if channel ~= "WHISPER" or not ns.Ledger then return nil end
        local values = ns.Ledger.HearValues(name, msg.values)
        ns.Ledger.Heard(name)
        return values
    end
    if msg.kind == "answers" then
        if channel ~= "WHISPER" or not ns.Ledger then return nil end
        local changed = ns.Ledger.HearAnswers(name, msg.answers)
        ns.Ledger.Heard(name)
        return changed
    end
    if ns.Ledger then pcall(ns.Ledger.Heard, name) end -- online: values waiting for them go now
    if msg.kind == "ask" then
        Comms.Announce("asked by " .. name)
        return msg
    end
    if msg.kind == "fresh" then
        return ns.Stale and ns.Stale.Hear(name, msg.day) or nil
    end
    if msg.kind == "release" then
        return ns.Version and ns.Version.Hear(name, msg.release) or nil
    end
    if msg.kind == "template" or msg.kind == "templateAsk" then
        return ns.Guild and ns.Guild.Hear(name, msg, channel) or nil
    end
    if msg.kind == "giving" then
        return ns.Contributions and ns.Contributions.Hear(name, msg.part, channel) or nil
    end
    local old = store()[name:lower()]
    if msg.kind == "skills" then
        local skills = { [name:lower()] = msg.skills }
        for _, c in ipairs(msg.characters) do
            if c.name:lower() ~= name:lower() then skills[c.name:lower()] = c.skills end
        end
        local peer = old
        if type(peer) ~= "table" then -- the hello got lost: the skills say the same and more
            local ids, characters = {}, {}
            for id in pairs(msg.skills) do ids[#ids + 1] = id end
            table.sort(ids)
            for _, c in ipairs(msg.characters) do
                local cids = {}
                for id in pairs(c.skills) do cids[#cids + 1] = id end
                table.sort(cids)
                if c.name:lower() ~= name:lower() then characters[#characters + 1] = { name = c.name, professions = cids } end
            end
            peer = { name = name, professions = ids, characters = characters, version = msg.version }
            store()[name:lower()] = peer
            marksChanged(old, peer)
        end
        peer.skills, peer.at = skills, serverTime()
        ns.Log.Add("comms", "skills from %s: %s", name, Comms.SkillText(msg.skills))
        return peer
    end
    local characters = {}
    for _, c in ipairs(msg.characters) do
        if c.name:lower() ~= name:lower() then characters[#characters + 1] = c end
    end
    local peer = { name = name, professions = msg.professions, characters = characters, version = msg.version, at = serverTime(),
        skills = type(old) == "table" and old.skills or nil, release = type(old) == "table" and old.release or nil }
    store()[name:lower()] = peer
    marksChanged(old, peer)
    ns.Log.Add("comms", "hello from %s: professions %s, %d other character(s)", name,
        #peer.professions > 0 and table.concat(peer.professions, ",") or "none", #characters)
    return peer
end

--- The skill in `profession` of a character some Mailworthy told us about (the sender or
--- one of their characters), or nil.
function Comms.Skill(name, profession)
    name = ns.Routes.Clean(name)
    if not name then return nil end
    local best
    for _, peer in pairs(store()) do
        local skills = type(peer) == "table" and type(peer.skills) == "table" and peer.skills[name:lower()]
        local rank = type(skills) == "table" and tonumber(skills[tonumber(profession)]) or nil
        if rank and (not best or rank > best) then best = rank end
    end
    return best
end

--- Pure: "First Aid 80, Tailoring 130" / "none".
function Comms.SkillText(skills)
    local parts = {}
    for id, rank in pairs(type(skills) == "table" and skills or {}) do
        parts[#parts + 1] = (ns.Routes.ProfessionName(id) or tostring(id)) .. " " .. tostring(rank)
    end
    table.sort(parts)
    return #parts > 0 and table.concat(parts, ", ") or "none"
end

--- Drop peers not heard from in PEER_DAYS.
function Comms.Prune(at)
    at = at or serverTime()
    for key, peer in pairs(store()) do
        if type(peer) ~= "table" or (tonumber(peer.at) or 0) < at - Comms.PEER_DAYS * 86400 then store()[key] = nil end
    end
end

--- Pure: "Enchanting, Tailoring" / "no crafting profession".
function Comms.ProfessionText(ids)
    local profs = {}
    for _, id in ipairs(ids or {}) do profs[#profs + 1] = ns.Routes.ProfessionName(id) or tostring(id) end
    table.sort(profs)
    return #profs > 0 and table.concat(profs, ", ") or "no crafting profession"
end

--- One line per peer for /mw report.
function Comms.ReportLines()
    local lines = {}
    for _, peer in pairs(store()) do
        local others = {}
        for _, c in ipairs(peer.characters or {}) do
            others[#others + 1] = tostring(c.name) .. " = " .. Comms.ProfessionText(c.professions)
        end
        local skills = type(peer.skills) == "table" and peer.skills[tostring(peer.name):lower()] or nil
        lines[#lines + 1] = string.format("mailworthy peer: %s (%s; skills: %s; other characters: %s; heard %s)",
            tostring(peer.name), Comms.ProfessionText(peer.professions), skills and Comms.SkillText(skills) or "not sent",
            #others > 0 and table.concat(others, ", ") or "none", date("%b %d", peer.at or 0))
    end
    table.sort(lines)
    local st = Comms.stats
    table.insert(lines, 1, string.format("comms this session: %d heard, %d copies dropped (guild + group), "
        .. "%d hello(s) sent, %d group change(s) with no one new (no hello)", st.heard, st.copies, st.hellos,
        st.rosterQuiet))
    return lines
end

function Comms.Register()
    if not Comms.On() then return end
    local chat = rawget(_G, "C_ChatInfo")
    if type(chat) ~= "table" then return end
    local ok, result = pcall(chat.RegisterAddonMessagePrefix, Comms.PREFIX)
    ns.Log.Add("comms", "prefix registered: %s", ok and tostring(result) or ("error " .. tostring(result)))
end

ns.On("CHAT_MSG_ADDON", function(prefix, text, channel, sender)
    if prefix ~= Comms.PREFIX or not Comms.On() then return end
    Comms.Hear(sender, text, channel)
end)

ns.On("PLAYER_LOGIN", function()
    Comms.Register()
    Comms.Prune()
    if not Comms.On() then return end
    if C_Timer and type(C_Timer.After) == "function" then
        C_Timer.After(Comms.HELLO_DELAY, function() pcall(Comms.Announce, "login") end)
    end
end)

--- The group's online members other than this character (lower-case names), from the units.
local function groupMembers()
    local members = {}
    local n = tonumber((call(GetNumGroupMembers))) or 0
    local raid = call(IsInRaid) == true
    local me = tostring(ns.PlayerName()):lower()
    for i = 1, n do
        local unit = raid and ("raid" .. i) or ("party" .. i)
        local name = ns.Routes.Clean(call(GetUnitName, unit, true) or call(UnitName, unit))
        if name and name:lower() ~= me and call(UnitIsConnected, unit) ~= false then members[name:lower()] = true end
    end
    return members
end

--- Pure: how many of `members` (lower-case name -> true) are not in `before`.
function Comms.Joined(before, members)
    local n = 0
    for name in pairs(members) do
        if not before[name] then n = n + 1 end
    end
    return n
end

-- A hello when someone new is in the group (joined, or came online): they haven't heard it. The
-- game fires GROUP_ROSTER_UPDATE for much more (leader, loot, subgroups, levels): rl-companion's
-- log showed a guildmate's hellos every 20-40 s from it, each one three messages to the guild.
ns.On("GROUP_ROSTER_UPDATE", function()
    local members = groupMembers()
    local joined = Comms.Joined(groupSeen, members)
    groupSeen = members
    if joined > 0 then return Comms.Announce("group") end
    if next(members) ~= nil then Comms.stats.rosterQuiet = Comms.stats.rosterQuiet + 1 end
end)

-- A hello the throttle held back goes out at the next mailbox (a natural moment to be known),
-- and so does one when a skill-up crossed a material tier since the last hello (Tiers), so a
-- friend's binding stops sending what this character is now past.
ns.On("MAIL_SHOW", function()
    if pendingHello then return Comms.Announce("pending") end
    if announcedSteps and Comms.Steps(ns.Characters.Professions()) ~= announcedSteps then Comms.Announce("tier") end
end)
