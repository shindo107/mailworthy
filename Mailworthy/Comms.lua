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

local lastHello, lastAsk, pendingHello = -math.huge, -math.huge, false

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

--- Pure: a message from another Mailworthy, or nil. { kind = "hello", version, professions =
--- { ids }, characters = { { name, professions = { ids } }, ... } }, { kind = "ask", version }
--- or { kind = "fresh", version, day } (a scan day: Stale.lua).
function Comms.Decode(text)
    if type(text) ~= "string" or #text > Comms.MAX_MESSAGE then return nil end
    local kind, version, rest = text:match("^(%a)(%d+)|?(.*)$")
    if kind == "A" then return { kind = "ask", version = tonumber(version) } end
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

local function send(message)
    local chat = rawget(_G, "C_ChatInfo")
    if type(chat) ~= "table" then return false end
    local sent = false
    for _, channel in ipairs(channels()) do
        local ok, result = pcall(chat.SendAddonMessage, Comms.PREFIX, message, channel)
        sent = sent or ok
        ns.Log.Add("comms", "%s on %s: %s", message:sub(1, 2), channel, ok and tostring(result) or ("error " .. tostring(result)))
    end
    return sent
end

--- Say hello to the guild and group (throttled; the next tick sends a hello that was throttled).
function Comms.Announce(reason)
    if not Comms.On() then return false end
    if now() - lastHello < Comms.THROTTLE then
        pendingHello = true
        return false
    end
    lastHello, pendingHello = now(), false
    ns.Log.Add("comms", "hello (%s)", tostring(reason))
    local sent = send(Comms.Encode(ns.Characters.Professions(), ns.Characters.Mailable()))
    local fresh = ns.Stale and ns.Stale.Message()
    if sent and fresh then send(fresh) end
    return sent
end

--- Ask other Mailworthys to say hello (the friends window, throttled).
function Comms.Ask()
    if not Comms.On() or now() - lastAsk < Comms.ASK_THROTTLE then return false end
    lastAsk = now()
    return send(string.format("A%d", Comms.VERSION))
end

--- Peers heard from on this realm + faction: lower-case name -> { name, professions, characters, version, at }.
function Comms.Peers()
    return store()
end

function Comms.Peer(name)
    name = ns.Routes.Clean(name)
    return name and store()[name:lower()] or nil
end

--- Record a hello from `sender` (a name, possibly with a realm suffix).
function Comms.Hear(sender, text)
    local msg = Comms.Decode(text)
    local name = ns.Routes.Clean(sender)
    if not msg or not name or #name > Comms.MAX_NAME or name:find("%c") then return nil end
    if name:lower() == tostring(ns.PlayerName()):lower() then return nil end
    if msg.kind == "ask" then
        Comms.Announce("asked by " .. name)
        return msg
    end
    if msg.kind == "fresh" then
        return ns.Stale and ns.Stale.Hear(name, msg.day) or nil
    end
    local characters = {}
    for _, c in ipairs(msg.characters) do
        if c.name:lower() ~= name:lower() then characters[#characters + 1] = c end
    end
    local peer = { name = name, professions = msg.professions, characters = characters, version = msg.version, at = serverTime() }
    store()[name:lower()] = peer
    ns.Log.Add("comms", "hello from %s: professions %s, %d other character(s)", name,
        #peer.professions > 0 and table.concat(peer.professions, ",") or "none", #characters)
    return peer
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
        lines[#lines + 1] = string.format("mailworthy peer: %s (%s; other characters: %s; heard %s)", tostring(peer.name),
            Comms.ProfessionText(peer.professions), #others > 0 and table.concat(others, ", ") or "none",
            date("%b %d", peer.at or 0))
    end
    table.sort(lines)
    return lines
end

function Comms.Register()
    if not Comms.On() then return end
    local chat = rawget(_G, "C_ChatInfo")
    if type(chat) ~= "table" then return end
    local ok, result = pcall(chat.RegisterAddonMessagePrefix, Comms.PREFIX)
    ns.Log.Add("comms", "prefix registered: %s", ok and tostring(result) or ("error " .. tostring(result)))
end

ns.On("CHAT_MSG_ADDON", function(prefix, text, _, sender)
    if prefix ~= Comms.PREFIX or not Comms.On() then return end
    Comms.Hear(sender, text)
end)

ns.On("PLAYER_LOGIN", function()
    Comms.Register()
    Comms.Prune()
    if not Comms.On() then return end
    if C_Timer and type(C_Timer.After) == "function" then
        C_Timer.After(Comms.HELLO_DELAY, function() pcall(Comms.Announce, "login") end)
    end
end)

ns.On("GROUP_ROSTER_UPDATE", function()
    if tonumber((call(GetNumGroupMembers))) and tonumber((call(GetNumGroupMembers))) > 0 then Comms.Announce("group") end
end)

-- A hello the throttle held back goes out at the next mailbox (a natural moment to be known).
ns.On("MAIL_SHOW", function()
    if pendingHello then Comms.Announce("pending") end
end)
