-- "Your Mailworthy is out of date" (operator, 2026-11-08: "can we show a your version is
-- outdated message when someone encounters another player with a newer version of mailworthy
-- in game?").
--
-- Each released Mailworthy says its version right after its hello (Comms: "U2|v0.31.0", a
-- message kind older Mailworthys drop, as they drop any kind they don't know; fields after the
-- version are left out, so a later build can add some). ns.VERSION is the release tag the
-- packager put in (v0.31.0); a git checkout keeps the packager's placeholder, and an alpha or
-- beta tag has a suffix: neither parses as vX.Y.Z, so such a build never sends its version and
-- is never told it is out of date.
--
-- When a peer's version is newer than this one: one chat line, at most once per session, a line
-- in the Mailworthy window's footer and in the settings window (so nothing depends on chat or
-- hovering), and a line in /mw report. The version is kept with the peer (MailworthyDB.peers,
-- gone with the peer after Comms.PEER_DAYS), so the lines show at the next login too.
--
-- What arrives is untrusted: at most MAX_TEXT characters, exactly v<major>.<minor>.<patch> with
-- at most four digits each; anything else is dropped. It is only ever compared and shown.
-- Versions are not passed on: every online guild Mailworthy hears each other's hello on GUILD
-- already, and a relayed version could not be traced to a player who has it, so one bad claim
-- would spread through every guild it reached.
-- Switch: /mw feature versionNotice off (sending this build's version follows the comms switch).
local _, ns = ...

local Version = {}
ns.Version = Version

Version.MAX_TEXT = 16
Version.CURSEFORGE = "CurseForge"

local told = false   -- the chat line went out this session
local heard          -- { version, from }: the newest version heard this session (newer or not)
local listeners = {}

function Version.On() return ns.Features.On("versionNotice") end

--- Pure: "v0.31.0" -> { 0, 31, 0 }, or nil for anything else (a dev build's placeholder, an
--- alpha or beta tag, junk from another player).
function Version.Parse(text)
    if type(text) ~= "string" or #text > Version.MAX_TEXT then return nil end
    local a, b, c = text:match("^v(%d%d?%d?%d?)%.(%d%d?%d?%d?)%.(%d%d?%d?%d?)$")
    if not a then return nil end
    return { tonumber(a), tonumber(b), tonumber(c) }
end

--- Pure: whether release `a` is strictly newer than release `b` (false when either doesn't parse).
function Version.Newer(a, b)
    local x, y = Version.Parse(a), Version.Parse(b)
    if not x or not y then return false end
    for i = 1, 3 do
        if x[i] ~= y[i] then return x[i] > y[i] end
    end
    return false
end

--- This build's release version ("v0.30.0"), or nil for a dev, alpha or beta build.
function Version.Own()
    return Version.Parse(ns.VERSION) and ns.VERSION or nil
end

--- The message sent after a hello ("U2|v0.30.0"), or nil (a dev build claims nothing).
function Version.Message()
    local own = Version.Own()
    return own and string.format("U%d|%s", ns.Comms.VERSION, own) or nil
end

--- Call `fn` (no arguments) when a newer version is first heard (windows redraw their line).
function Version.OnChanged(fn)
    if type(fn) == "function" then listeners[#listeners + 1] = fn end
end

local function notify()
    for _, fn in ipairs(listeners) do
        local ok, err = pcall(fn)
        if not ok then ns.Log.Add("error", "version redraw: %s", tostring(err)) end
    end
end

--- The newest version heard from any peer, this session or kept with the peers, and who has
--- it: version, name (nil, nil when none was heard).
function Version.Newest()
    local best, from
    if heard then best, from = heard.version, heard.from end
    for _, peer in pairs(ns.Comms.Peers()) do
        local v = type(peer) == "table" and peer.release
        if Version.Parse(v) and (not best or Version.Newer(v, best)) then best, from = v, peer.name end
    end
    return best, from
end

--- The newer version and who has it when this build is out of date, else nil.
function Version.Outdated()
    local own = Version.Own()
    if not own then return nil end
    local newest, from = Version.Newest()
    if newest and Version.Newer(newest, own) then return newest, from end
    return nil
end

--- Pure: the chat line.
function Version.ChatText(newer, from, own)
    return string.format("Mailworthy %s is out (%s has it); you have %s. Update from %s.", newer,
        tostring(from), own, Version.CURSEFORGE)
end

--- Pure: the windows' line (one short line, coloured to stand out).
function Version.LineText(newer, own)
    return string.format("|cffffd100Mailworthy %s is out (you have %s): update from %s|r", newer, own,
        Version.CURSEFORGE)
end

--- The windows' line while this build is out of date (and the switch is on), else nil.
function Version.Text()
    if not Version.On() then return nil end
    local newer = Version.Outdated()
    return newer and Version.LineText(newer, Version.Own()) or nil
end

--- A version `text` from peer `name` (Comms.Hear: the name is already cleaned). Returns the
--- version kept, or nil when it was dropped.
function Version.Hear(name, text)
    if not Version.Parse(text) or type(name) ~= "string" then return nil end
    local peer = ns.Comms.Peer(name)
    if type(peer) == "table" then peer.release = text end
    local before = Version.Outdated()
    if not heard or Version.Newer(text, heard.version) then heard = { version = text, from = name } end
    local own = Version.Own()
    ns.Log.Add("comms", "version from %s: %s", name, text)
    if own and Version.Newer(text, own) and Version.On() then
        if not told then
            told = true
            ns.Print(Version.ChatText(text, name, own))
        end
        if Version.Outdated() ~= before then notify() end
    end
    return text
end

--- Lines for /mw report.
function Version.ReportLines()
    local own = Version.Own()
    local newest, from = Version.Newest()
    local state
    if not own then
        state = "a dev build: never out of date"
    elseif not newest then
        state = "no other version heard"
    elseif Version.Newer(newest, own) then
        state = string.format("out of date: %s heard from %s", newest, tostring(from))
    else
        state = string.format("up to date (newest heard %s from %s)", newest, tostring(from))
    end
    return { string.format("version: %s, %s; notice %s%s", own or tostring(ns.VERSION), state,
        Version.On() and "on" or "off", told and ", told in chat this session" or "") }
end

--- Specs: forget the session (a new login).
function Version.ResetSession()
    told, heard = false, nil
end
