-- Guild template (operator, 2026-11-07: "the guild master can setup a template for the
-- rest of the guild members to use ... send enchanting to this person, send herbs here
-- ... to help distribute materials amongst the guild"). A template is a set of rules,
-- one per crafting profession, each a binding (Routes.lua) to one guild member: herbs
-- are Alchemy's materials, cloth Tailoring's, and so on. Chosen with the operator:
--
-- * Authors: the guild master and the rank below (rank index 0 and 1, "GM and officers")
--   make and change it. Copies: anyone holding it passes it on (operator, same day: "whoever
--   is online gets the copy, and it can be copied from them by any member"). Each copy names
--   its author; the receiver checks the author's rank in its own guild roster (a copy by
--   anyone else is dropped), takes only rules for players in that roster, and keeps the
--   newest revision. A copy naming an author who never published it is corrected by that
--   author's Mailworthy when it hears it: it sends the real one with a newer revision.
-- * Opt-in once: a member's Mailworthy says a template arrived and does nothing until the
--   player turns the guild rules on (the Guild window: /mw guild, the settings' Guild button).
--   Later updates then apply on their own, with a chat line naming every rule. One press
--   turns the guild rules off again (the Guild window, and the mailbox window's Bindings heading).
-- * Personal wins: the player's own bindings come first (a rule for a profession they
--   bound themselves is left out), and a rule for a profession this character has is left
--   out (a tailor keeps their cloth), as is a rule naming this character. Skip once works
--   on guild rules at the mailbox like on any binding.
--
-- Safety: a guild rule is a binding the player turned on; everything Routes.Divert does
-- for bindings holds (never over a hard keep, the per-unit cap sends market highs to the
-- bank alt, delivery follows the profession, the recipient is shown before Send).
--
-- Wire (Comms prefix, GUILD channel only; older Mailworthys drop unknown kinds):
--   T2|<revision>|<author>|<i>/<n>|<skill line>=<Name>:<cap copper, 0 = none>   one per rule
--   T2|<revision>|<author>|0/0|                                               an empty template
--   Q2|<revision held, 0 = none>     (ask: whoever holds a newer copy answers, one of them)
-- The revision is the author's server time. Received data is validated like hellos:
-- known crafting skill lines, clean short names, at most MAX_RULES, a revision no more
-- than FUTURE seconds ahead. Switch: /mw feature guildTemplate off.
-- APIs: GetGuildInfo("player") (name, rank name, 0-based rank index), C_Club member info
-- guildRankOrder (1-based, Blizzard_Communities/GuildRoster.lua), GetGuildRosterInfo's
-- third return (0-based) as the fallback; all read in Ketho/wow-ui-source-forever.
local _, ns = ...

local Guild = {}
ns.Guild = Guild

Guild.MAX_RULES = 8         -- one per crafting profession
Guild.PUBLISHER_RANK = 1    -- rank index 0 (guild master) and 1 (the officer rank below)
Guild.ANSWER_THROTTLE = 30  -- seconds between answers to asks
Guild.ASK_THROTTLE = 30     -- seconds between asks
Guild.ASK_DELAY = 12        -- seconds after login (after the hello)
Guild.FUTURE = 600          -- a revision further ahead of our server time is refused

local partial, pending = {}, {} -- sender -> template being assembled / waiting for the roster
local lastAnswer, lastAsk, answering = -math.huge, -math.huge, false

local function call(fn, ...)
    if type(fn) ~= "function" then return nil end
    local results = { pcall(fn, ...) }
    if not results[1] then return nil end
    return unpack(results, 2, table.maxn(results))
end

local function now() return call(GetTime) or 0 end
local function serverTime() return call(GetServerTime) or time() end
local function lower(name) return tostring(name):lower() end

function Guild.On() return ns.Features.On("guildTemplate") end

--- This character's guild name and rank index (0 = guild master), or nil outside a guild
--- (and until the game knows the guild, shortly after login).
function Guild.Mine()
    if call(IsInGuild) ~= true then return nil end
    local name, _, rankIndex = call(GetGuildInfo, "player")
    if type(name) ~= "string" or name == "" then return nil end
    return name, tonumber(rankIndex)
end

--- This character may publish the guild's template (guild master or the rank below).
function Guild.CanPublish()
    local name, rank = Guild.Mine()
    return name ~= nil and rank ~= nil and rank <= Guild.PUBLISHER_RANK
end

--- A guild member's rank index (0 = guild master) from this character's roster, or nil
--- when they aren't in it (or the roster isn't loaded yet).
function Guild.RankOf(name)
    name = ns.Routes.Clean(name)
    if not name or call(IsInGuild) ~= true then return nil end
    local club = rawget(_G, "C_Club")
    local clubId = type(club) == "table" and call(club.GetGuildClubId) or nil
    local members = clubId and call(club.GetClubMembers, clubId) or nil
    if type(members) == "table" and #members > 0 then
        for _, memberId in ipairs(members) do
            local info = call(club.GetMemberInfo, clubId, memberId)
            if type(info) == "table" and info.name and lower(ns.Routes.Clean(info.name)) == lower(name) then
                local order = tonumber(info.guildRankOrder)
                return order and order - 1 or nil
            end
        end
        return nil
    end
    for i = 1, tonumber((call(GetNumGuildMembers))) or 0 do
        local member, _, rankIndex = call(GetGuildRosterInfo, i)
        if member and lower(ns.Routes.Clean(member)) == lower(name) then return tonumber(rankIndex) end
    end
    return nil
end

local function guildKey()
    local guild = Guild.Mine()
    if not guild then return nil end
    local _, realm, faction = ns.Characters.Current()
    return tostring(realm) .. "|" .. tostring(faction) .. "|" .. guild
end

local function store(field)
    MailworthyDB[field] = type(MailworthyDB[field]) == "table" and MailworthyDB[field] or {}
    return MailworthyDB[field]
end

--- The template this character's guild uses, or nil: { rev, from, at, rules = { { profession, to,
--- cap } }, use = nil (not chosen yet) / true / false }.
function Guild.Template()
    local key = guildKey()
    local t = key and store("guildTemplates")[key]
    return type(t) == "table" and t or nil
end

local function copyRules(rules)
    local out = {}
    for _, r in ipairs(type(rules) == "table" and rules or {}) do
        out[#out + 1] = { profession = r.profession, to = r.to, cap = r.cap }
    end
    return out
end

-- Pure: the rules sorted by profession name (a template's order for display and wire).
local function sorted(rules)
    table.sort(rules, function(a, b)
        return tostring(ns.Routes.ProfessionName(a.profession)) < tostring(ns.Routes.ProfessionName(b.profession))
    end)
    return rules
end

--- Pure: "Alchemy to Ann, Enchanting to Bob" / "no rules".
function Guild.RulesText(rules)
    local parts = {}
    for _, r in ipairs(rules or {}) do
        parts[#parts + 1] = tostring(ns.Routes.ProfessionName(r.profession)) .. " to " .. tostring(r.to)
    end
    return #parts > 0 and table.concat(parts, ", ") or "no rules"
end

-- On / off (one press) ----------------------------------------------------------------

--- The guild rules are turned on for this account in this guild.
function Guild.InUse()
    local t = Guild.Template()
    return Guild.On() and t ~= nil and t.use == true
end

function Guild.SetUse(on)
    local t = Guild.Template()
    if not t then return false end
    t.use = on == true
    ns.Log.Add("guild", "guild rules %s", t.use and "on" or "off")
    return true
end

function Guild.ToggleUse() return Guild.SetUse(not Guild.InUse()) end

--- The guild's rules that apply to this character, as bindings (scope "guild"), given the
--- player's own bindings (`personal`, Routes' lists): none while off; a rule for a
--- profession this character has, for a profession bound personally, or naming this
--- character, is left out ("personal wins").
function Guild.Rules(personal)
    if not Guild.InUse() then return {} end
    local own, bound = {}, {}
    for _, p in ipairs(ns.Characters.Professions()) do own[tonumber(p.skillLine) or -1] = true end
    for _, r in ipairs(personal or {}) do bound[tonumber(r.profession) or -1] = true end
    local me = lower(ns.PlayerName())
    local out = {}
    for _, r in ipairs(Guild.Template().rules or {}) do
        local id = tonumber(r.profession)
        if id and not own[id] and not bound[id] and r.to and lower(r.to) ~= me then
            out[#out + 1] = { to = r.to, profession = id, cap = r.cap, scope = "guild",
                key = "guild|" .. ns.Routes.Key(id, r.to), from = Guild.Template().from }
        end
    end
    return out
end

--- Pure: why a template rule doesn't apply here, or nil (for the friends window and the report).
function Guild.Why(rule, personal, professions, me)
    for _, p in ipairs(professions or {}) do
        if tonumber(p.skillLine) == tonumber(rule.profession) then return "you have " .. tostring(p.name) end
    end
    for _, r in ipairs(personal or {}) do
        if tonumber(r.profession) == tonumber(rule.profession) then return "your own binding comes first" end
    end
    if lower(rule.to) == lower(me) then return "that's you" end
    return nil
end

-- Wire ------------------------------------------------------------------------------------

--- Pure: a template's messages (one per rule; one empty message for no rules), naming its author.
function Guild.Encode(rev, author, rules)
    rev = math.floor(tonumber(rev) or 0)
    rules = rules or {}
    local head = string.format("T%d|%d|%s|", ns.Comms.VERSION, rev, tostring(author))
    if #rules == 0 then return { head .. "0/0|" } end
    local out = {}
    for i, r in ipairs(rules) do
        out[i] = head .. string.format("%d/%d|%d=%s:%d", i, #rules, tonumber(r.profession) or 0, tostring(r.to),
            math.floor(tonumber(r.cap) or 0))
    end
    return out
end

local function goodName(name)
    name = ns.Routes.Clean(name)
    if not name or #name > ns.Comms.MAX_NAME or name:find("[%c=;|:]") then return nil end
    return name
end

--- Pure: the body of a "T" message (after "T2|"), or nil: { rev, author, index, count, rule =
--- { profession, to, cap } or nil (an empty template) }.
function Guild.DecodePart(rest)
    local rev, author, index, count, body = tostring(rest):match("^(%d+)|([^|]+)|(%d+)/(%d+)|(.*)$")
    if not rev or #rev > 10 or #index > 2 or #count > 2 then return nil end
    author = goodName(author)
    if not author then return nil end
    rev, index, count = tonumber(rev), tonumber(index), tonumber(count)
    if count > Guild.MAX_RULES or index > count then return nil end
    if count == 0 then
        if index ~= 0 or body ~= "" then return nil end
        return { rev = rev, author = author, index = 0, count = 0 }
    end
    if index < 1 then return nil end
    local profession, name, cap = body:match("^(%d+)=([^:]+):(%d+)$")
    profession, name = tonumber(profession), name and goodName(name)
    if not profession or not ns.Routes.ProfessionName(profession) or not name or #cap > 9 then return nil end
    cap = tonumber(cap)
    return { rev = rev, author = author, index = index, count = count,
        rule = { profession = profession, to = name, cap = cap > 0 and cap or nil } }
end

local function myRev()
    local t = Guild.Template()
    return t and tonumber(t.rev) or 0
end

--- Send the copy of the template this character holds to the guild: anyone who has one may
--- (each receiver checks its author). Throttled unless `force`.
function Guild.Broadcast(reason, force)
    if not Guild.On() then return false end
    local t = Guild.Template()
    if not t then return false end
    if not force and now() - lastAnswer < Guild.ANSWER_THROTTLE then return false end
    lastAnswer = now()
    local sent = false
    for _, message in ipairs(Guild.Encode(t.rev, t.from, t.rules)) do sent = ns.Comms.SendGuild(message) or sent end
    ns.Log.Add("guild", "template sent (%s): %d rule(s) by %s", tostring(reason), #(t.rules or {}), tostring(t.from))
    return sent
end

--- Ask the guild for a template newer than ours (Q2|<our revision>, 0 = none); 30 s apart.
function Guild.Ask(reason)
    if not Guild.On() or call(IsInGuild) ~= true or now() - lastAsk < Guild.ASK_THROTTLE then return false end
    lastAsk = now()
    ns.Log.Add("guild", "asked for the template (%s)", tostring(reason))
    return ns.Comms.SendGuild(string.format("Q%d|%d", ns.Comms.VERSION, myRev()))
end

-- An ask that our copy answers: wait a moment (a publisher 1 s, anyone else 2-6 s) and send it,
-- unless someone else sends one at least as new meanwhile: one answer per ask, not the guild's.
local function answerSoon(asker)
    if answering then return end
    answering = true
    local timer = rawget(_G, "C_Timer")
    local function go()
        if not answering then return end
        answering = false
        Guild.Broadcast("asked by " .. asker)
    end
    if type(timer) ~= "table" or type(timer.After) ~= "function" then return go() end
    timer.After(Guild.CanPublish() and 1 or (2 + math.random() * 4), function() pcall(go) end)
end

local function refreshWindows()
    if ns.MailWindow and ns.MailWindow.RefreshIfShown then ns.MailWindow.RefreshIfShown() end
    if ns.RoutesUI and ns.RoutesUI.RefreshIfShown then ns.RoutesUI.RefreshIfShown() end
end

local function published(key)
    local all = store("guildPublished")
    all[key] = type(all[key]) == "table" and all[key] or {}
    return all[key]
end

-- Someone passed on a template in this character's name that it never published: send the
-- real one again with a newer revision, so every copy is replaced.
local function correct(key, forgedRev, sender)
    ns.Log.Add("guild", "template in my name I never published (revision %d, from %s): correcting", forgedRev, sender)
    if not Guild.CanPublish() then return "forged" end
    local t = Guild.Template()
    local rev = math.max(serverTime(), forgedRev + 1)
    store("guildTemplates")[key] = { rev = rev, from = ns.PlayerName(), at = serverTime(),
        rules = copyRules(t and t.rules), use = t and t.use }
    published(key)[rev] = true
    ns.Print(string.format("%s passed on a guild template in your name that you never published. Your guild "
        .. "got your real one again.", sender))
    Guild.Broadcast("correction", true)
    return "forged"
end

--- Take a complete template copy from `sender`, written by `author`: newer than ours, by a guild
--- master or officer in our roster (the sender just has to be in it); a rule for someone not in
--- the guild is left out. A name the roster doesn't know yet waits for GUILD_ROSTER_UPDATE.
--- Returns "taken", "pending", or why not.
function Guild.Offer(sender, author, rev, rules)
    local key = guildKey()
    if not key then return "no guild" end
    local current = store("guildTemplates")[key]
    if type(current) == "table" and (tonumber(current.rev) or 0) >= rev then return "not newer" end
    if rev > serverTime() + Guild.FUTURE then
        ns.Log.Add("guild", "template from %s dropped: revision in the future", sender)
        return "future"
    end
    local me = lower(ns.PlayerName())
    local authorRank = lower(author) == me and select(2, Guild.Mine()) or Guild.RankOf(author)
    if Guild.RankOf(sender) == nil or authorRank == nil then
        pending[lower(sender)] = { sender = sender, author = author, rev = rev, rules = rules }
        ns.Routes.RequestRoster()
        return "pending"
    end
    pending[lower(sender)] = nil
    if authorRank > Guild.PUBLISHER_RANK then
        ns.Log.Add("guild", "template by %s (from %s) dropped: rank %d can't publish", author, sender, authorRank)
        return "rank"
    end
    if lower(author) == me and not published(key)[rev] then
        -- Our own record of what we published decides; with none at all (SavedVariables lost or
        -- reset), the copy is taken back as ours rather than "corrected" to nothing.
        if next(published(key)) ~= nil then return correct(key, rev, sender) end
        published(key)[rev] = true
    end
    local kept = {}
    for _, r in ipairs(rules) do
        if Guild.RankOf(r.to) ~= nil or lower(r.to) == me then
            kept[#kept + 1] = r
        else
            ns.Log.Add("guild", "rule %s to %s left out: not in the guild", tostring(r.profession), tostring(r.to))
        end
    end
    local use = type(current) == "table" and current.use or nil
    kept = sorted(copyRules(kept))
    local via = lower(sender) ~= lower(author) and sender or nil
    store("guildTemplates")[key] = { rev = rev, from = author, via = via, at = serverTime(), rules = kept, use = use }
    ns.Log.Add("guild", "template by %s (from %s) taken: %s", author, sender, Guild.RulesText(kept))
    local copy = via and (" (copy from " .. via .. ")") or ""
    if use == true then
        ns.Print(string.format("Guild rules updated by %s%s: %s. Turn them off any time with /mw guild.", author, copy,
            Guild.RulesText(kept)))
    elseif use == nil then
        ns.Print(string.format("%s shared a guild template%s (%s). Open Guild in Mailworthy settings (/mw guild) to use it.", author, copy,
            Guild.RulesText(kept)))
    end
    refreshWindows()
    return "taken"
end

--- A decoded "template" or "templateAsk" message from `sender` on `channel` (Comms.Hear).
function Guild.Hear(sender, msg, channel)
    if not Guild.On() or channel ~= "GUILD" then return nil end
    if msg.kind == "templateAsk" then
        local theirs, mine = tonumber(msg.rev) or 0, myRev()
        if mine > theirs then answerSoon(sender) end
        if theirs > mine then Guild.Ask("newer copy at " .. sender) end
        return nil
    end
    local part = msg.part
    if part.rev >= myRev() then answering = false end -- someone else is sending one as new: no need
    local p = partial[lower(sender)]
    if not p or p.rev ~= part.rev or p.count ~= part.count or p.author ~= part.author then
        p = { rev = part.rev, author = part.author, count = part.count, rules = {}, got = 0 }
        partial[lower(sender)] = p
    end
    if part.rule and not p.rules[part.index] then
        p.rules[part.index] = part.rule
        p.got = p.got + 1
    end
    if p.got < p.count then return nil end
    partial[lower(sender)] = nil
    local rules, seen = {}, {}
    for i = 1, p.count do
        local r = p.rules[i]
        if not seen[r.profession] then -- one rule per profession: the first wins
            seen[r.profession] = true
            rules[#rules + 1] = r
        end
    end
    return Guild.Offer(sender, p.author, p.rev, rules)
end

-- Editing (guild master / officers) -----------------------------------------------------------

--- The rules being edited: a copy of the template until published. Nil outside a guild.
function Guild.Draft()
    local key = guildKey()
    if not key then return nil end
    local drafts = store("guildDrafts")
    if type(drafts[key]) ~= "table" then
        local t = Guild.Template()
        drafts[key] = { rules = t and copyRules(t.rules) or {} }
    end
    return drafts[key].rules
end

--- The draft differs from the published template.
function Guild.DraftChanged()
    local key = guildKey()
    local drafts = key and store("guildDrafts")[key]
    if type(drafts) ~= "table" then return false end
    local t = Guild.Template()
    local a, b = sorted(copyRules(drafts.rules)), sorted(copyRules(t and t.rules))
    if not t then return #a > 0 end
    if #a ~= #b then return true end
    for i = 1, #a do
        if a[i].profession ~= b[i].profession or lower(a[i].to) ~= lower(b[i].to) or a[i].cap ~= b[i].cap then return true end
    end
    return false
end

--- Add a rule (a profession's materials to a guild member); a rule for the same profession
--- is replaced. Returns the rule and the name it replaced, or nil and why.
function Guild.DraftAdd(name, profession)
    if not Guild.CanPublish() then return nil, "only the guild master and officers can" end
    name = ns.Routes.Clean(name)
    profession = tonumber(profession)
    if not name then return nil, "no name" end
    if #name > ns.Comms.MAX_NAME or name:find("[%c=;|:]") then return nil, "not a player name" end
    if not ns.Routes.ProfessionName(profession) then return nil, "not a crafting profession" end
    local rules = Guild.Draft()
    for i, r in ipairs(rules) do
        if tonumber(r.profession) == profession then
            local was = r.to
            rules[i] = { profession = profession, to = name, cap = r.cap }
            return rules[i], was
        end
    end
    if #rules >= Guild.MAX_RULES then return nil, "too many rules" end
    local rule = { profession = profession, to = name, cap = ns.Routes.DEFAULT_CAP }
    rules[#rules + 1] = rule
    sorted(rules)
    return rule
end

function Guild.DraftRemove(profession)
    local rules = Guild.Draft() or {}
    for i, r in ipairs(rules) do
        if tonumber(r.profession) == tonumber(profession) then
            table.remove(rules, i)
            return true
        end
    end
    return false
end

function Guild.DraftStepCap(profession, dir)
    for _, r in ipairs(Guild.Draft() or {}) do
        if tonumber(r.profession) == tonumber(profession) then r.cap = ns.Routes.NextCap(r.cap, dir) end
    end
end

--- Publish the draft to the guild: a new revision, sent at once; this character's own copy
--- turns on (they made it; one press turns it off). Returns true, or nil and why.
function Guild.Publish()
    if not Guild.On() then return nil, "the guild template is switched off (/mw feature guildTemplate)" end
    if not Guild.CanPublish() then return nil, "only the guild master and officers can" end
    local key = guildKey()
    local rules = sorted(copyRules(Guild.Draft()))
    local current = Guild.Template()
    local rev = math.max(serverTime(), current and (tonumber(current.rev) or 0) + 1 or 0)
    store("guildTemplates")[key] = { rev = rev, from = ns.PlayerName(), at = serverTime(), rules = rules,
        use = current == nil and true or current.use }
    store("guildDrafts")[key] = nil
    published(key)[rev] = true
    ns.Log.Add("guild", "published: %s", Guild.RulesText(rules))
    Guild.Broadcast("published", true)
    refreshWindows()
    return true
end

--- Lines for /mw report.
function Guild.ReportLines()
    local guild, rank = Guild.Mine()
    if not guild then return { "guild template: not in a guild (or the guild isn't known yet)" } end
    local lines = { string.format("guild: %s, rank %s%s", guild, tostring(rank), Guild.CanPublish() and ", can publish" or "") }
    local t = Guild.Template()
    if not t then
        lines[#lines + 1] = "guild template: none heard"
    else
        lines[#lines + 1] = string.format("guild template: from %s%s (%s), %s; in use: %s", tostring(t.from),
            t.via and (", copy from " .. tostring(t.via)) or "", date("%b %d %H:%M", tonumber(t.rev) or 0),
            Guild.RulesText(t.rules),
            t.use == true and "yes" or (t.use == false and "no" or "not chosen yet"))
        local personal = {}
        for _, r in ipairs(ns.Routes.List()) do if r.scope ~= "guild" then personal[#personal + 1] = r end end
        for _, r in ipairs(t.rules or {}) do
            local why = Guild.Why(r, personal, ns.Characters.Professions(), ns.PlayerName())
            if why then lines[#lines + 1] = string.format("guild rule left out: %s to %s (%s)",
                tostring(ns.Routes.ProfessionName(r.profession)), tostring(r.to), why) end
        end
    end
    if Guild.CanPublish() and Guild.DraftChanged() then lines[#lines + 1] = "guild template: unpublished changes" end
    return lines
end

ns.On("GUILD_ROSTER_UPDATE", function()
    for name, p in pairs(pending) do
        pending[name] = nil
        pcall(Guild.Offer, p.sender, p.author, p.rev, p.rules)
    end
end)

-- At login everyone asks with the revision they hold: whoever online has a newer copy answers,
-- and whoever has an older one asks back, so the newest copy spreads both ways.
ns.On("PLAYER_LOGIN", function()
    if not Guild.On() or not (C_Timer and type(C_Timer.After) == "function") then return end
    C_Timer.After(Guild.ASK_DELAY, function() pcall(Guild.Ask, "login") end)
end)
