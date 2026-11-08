-- Bindings: "send my Enchanting materials to Bob" (operator, 2026-10-26). A binding
-- ties one crafting profession to one player (a guild member, a party member or
-- one of the player's own characters): every trade good that profession uses
-- (Valuation.PROFESSION_MATS) is mailed to that player instead of being valued
-- for the auction house, until the binding is removed. Saved for all the
-- account's characters on this realm + faction (MailworthyDB.routes) or for this
-- character only (MailworthyCharDB.routes); this character's bindings win.
--
-- A profession binding also takes its profession's recipes (item class 9, Valuation.RecipeProfession;
-- operator, 2026-11-08: "recipes should go to their respective profession mappings"), cap included.
--
-- Safety: locks, soulbound / quest / in-use items and profession tools still
-- stay; a binding never mails what the normal rule wouldn't touch. The price
-- cap ("to my alt above 5g each", a stepper on the binding) keeps a material
-- the market suddenly wants: at or above the cap the normal rule applies and
-- the item goes to the bank alt. "Skip once" drops a binding for this mailbox
-- visit (cleared at MAIL_CLOSED). The recipient is always shown in the window.
-- When the bound player runs Mailworthy, its hello (Comms) lists their
-- characters' crafting professions, and the mail goes to the one that has the
-- bound profession: the player themself when they do, their crafter when they
-- don't, the player when nothing is known (operator, 2026-10-26: the goal is
-- the friend who actually has the profession, never their alt for the AH).
--
-- A class binding (operator, 2026-11-08: "this is a mage only item, id like to be able to friend
-- mail these types of items too"): { to, class = "MAGE" } instead of a profession. It takes
-- items only that class may use (the tooltip's "Classes: Mage", Classes.lua) and this character
-- can't, with the same hard keeps and price cap; the mail goes to the player named.
--
-- Who can be bound: the party / raid (unit tokens), the guild (C_Club member
-- info, which carries each member's two professions and presence, as Blizzard's
-- Communities roster reads it on Forever; GetGuildRosterInfo as the fallback),
-- the account's known characters, and whoever Comms heard from. Every game call
-- is guarded; a missing API just means a shorter list.
local _, ns = ...

local Routes = {}
ns.Routes = Routes

Routes.CAP_STEPS = { 5000, 10000, 20000, 50000, 100000, 250000, 500000, 1000000 } -- copper per unit; nil = no cap
Routes.DEFAULT_CAP = 50000  -- 5g each: "an insane market high" while levelling (operator, 2026-10-26)
Routes.MAX = 12             -- bindings per scope
Routes.SCOPES = { account = "All my characters", character = "This character" }
Routes.SCOPE_REPORT = { account = "all my characters", character = "this character", guild = "guild template" }
Routes.ROUTE = "friend"     -- the verdict route of a diverted item

-- Verdicts a binding never overrides (AGENTS safety: never a locked item, and
-- nothing the game wouldn't let us attach).
Routes.HARD_KEEPS = {
    locked = true, soulbound = true, ["quest item"] = true, ["a quest needs it"] = true, ["in use"] = true,
    ["profession tool"] = true, ["item info not loaded yet"] = true,
}

-- Verdicts a class binding doesn't override either: AGENTS safety keeps anything but white items
-- (without a price source) in the bags (Codex review, 2026-11-08), and an item with no auction
-- price goes to the bank alt, not a class binding (operator, 2026-11-08: the price cap can't be
-- checked without a price).
function Routes.PriceKeep(verdict)
    if verdict and verdict.action == "mail" and verdict.route == ns.Valuation.NO_PRICE then return true end
    if not (verdict and verdict.action == "keep") then return false end
    local reason = tostring(verdict.reason)
    return reason == "no price" or reason == "uncommon or better (no price data)"
        or reason == "junk (no price data)" or reason:find("^price too old") ~= nil
end

local skipped = {} -- route key -> true for this mailbox visit

local function call(fn, ...)
    if type(fn) ~= "function" then return nil end
    local results = { pcall(fn, ...) }
    if not results[1] then return nil end
    return unpack(results, 2, table.maxn(results))
end

local function realmKey()
    local _, realm, faction = ns.Characters.Current()
    return tostring(realm) .. "|" .. tostring(faction)
end

local function accountList()
    MailworthyDB.routes = type(MailworthyDB.routes) == "table" and MailworthyDB.routes or {}
    local key = realmKey()
    MailworthyDB.routes[key] = type(MailworthyDB.routes[key]) == "table" and MailworthyDB.routes[key] or {}
    return MailworthyDB.routes[key]
end

local function charList()
    MailworthyCharDB.routes = type(MailworthyCharDB.routes) == "table" and MailworthyCharDB.routes or {}
    return MailworthyCharDB.routes
end

local function listFor(scope)
    return scope == "character" and charList() or accountList()
end

--- Pure: a player name as mail wants it: spaces collapsed, any "-Realm" suffix dropped
--- (guild rosters and addon messages carry one; a Forever name never has a hyphen).
function Routes.Clean(name)
    name = ns.Config.Clean(name)
    if not name then return nil end
    name = name:match("^([^%-]+)") or name
    return ns.Config.Clean(name)
end

-- An Enchanting binding also takes green and blue weapons and armor (operator, 2026-11-06:
-- "the enchanter binding ... should also include green or blue items that can be used for
-- disenchanting"): what the friend disenchants. The binding's price cap still sends a piece
-- the auction house pays well for to the bank alt; soulbound gear never leaves (a hard keep).
Routes.ENCHANTING = 333
Routes.GEAR_QUALITIES = { [2] = true, [3] = true } -- uncommon (green), rare (blue)
-- What a binding takes, when it differs from the profession's own list (primary materials only).
Routes.BINDING_MATS = { [333] = "dust, essences, shards, green and blue gear", [129] = "cloth" }

--- The crafting professions a binding can name: { { id, name, mats }, ... } by name.
function Routes.Professions()
    local list = {}
    for id, p in pairs(ns.Valuation.PROFESSION_MATS) do
        list[#list + 1] = { id = id, name = p.name, mats = (Routes.BINDING_MATS[id] or p.mats) .. ", recipes" }
    end
    table.sort(list, function(a, b) return a.name < b.name end)
    return list
end

function Routes.ProfessionName(id)
    local p = ns.Valuation.PROFESSION_MATS[tonumber(id) or -1]
    return p and p.name or nil
end

--- Pure: "Enchanting materials" (the profession's materials, for rows and subjects), or
--- "Mage items" for a class binding.
function Routes.What(route)
    if route.class then return (ns.Classes.Name(route.class) or tostring(route.class)) .. " items" end
    return (Routes.ProfessionName(route.profession) or "?") .. " materials"
end

function Routes.Key(profession, to)
    return tostring(profession) .. "|" .. tostring(to):lower()
end

--- A saved binding's key: "333|bob" for a profession, "class:MAGE|bob" for a class.
function Routes.KeyOf(r)
    return Routes.Key(r.class and ("class:" .. tostring(r.class)) or r.profession, r.to)
end

--- Pure: the item is one of the binding's profession's primary materials: a trade good of its
--- own subclasses (cloth for Tailoring, herbs for Alchemy), or, for Enchanting, a green or
--- blue weapon or armor piece to disenchant; or a recipe the profession learns. What a profession uses on the side (Tiers.KEEP:
--- an engineer's Linen Cloth, a blacksmith's gems) isn't mailed to a binding (2026-11-07: "only
--- focus on the primary materials ... they can ask or acquire some minor pieces"); it follows
--- the normal rule. A material the bound player's skill (`route.skill`, Routes.Skill) is past
--- (Tiers) doesn't match, unless `tiers` is false or converting it still pays
--- (Tiers.WorthConverting with `priceOf`: the friend converts it); the second return is then true.
function Routes.Matches(route, item, tiers, priceOf)
    if route.class then -- a class binding: what only that class may use, and this character can't
        return ns.Classes.ForOther(item.classes, route.class, item.myClass) == true
    end
    if tonumber(route.profession) == Routes.ENCHANTING and Routes.GEAR_QUALITIES[tonumber(item.quality) or -1]
        and ns.Valuation.CanDisenchant(item) then
        return true
    end
    -- A recipe its profession learns (operator, 2026-11-08: "recipes should go to their respective
    -- profession mappings"); the cap still sends a recipe the auction house pays well for to the bank alt.
    local recipeFor = ns.Valuation.RecipeProfession(item)
    if recipeFor then return recipeFor == tonumber(route.profession) end
    local p = ns.Valuation.PROFESSION_MATS[tonumber(route.profession) or -1]
    if not (p and item.classID == ns.Valuation.TRADE_GOODS and p.subclasses[item.subclassID] == true) then
        return false
    end
    if tiers ~= false and ns.Tiers.Outgrown(route.profession, item.itemID, route.skill)
        and not ns.Tiers.WorthConverting(route.profession, item.itemID, priceOf) then
        return false, true
    end
    return true
end

local function has(ids, profession)
    for _, id in ipairs(ids or {}) do
        if tonumber(id) == tonumber(profession) then return true end
    end
    return false
end

--- Pure: who gets a binding's mail given what the bound player's Mailworthy said (`peer`,
--- or nil): the player when they have the profession or nothing is known, else the first
--- of their characters that has it. Second return: true when it's another character.
function Routes.Crafter(route, peer)
    if route.class then return route.to, false end -- the player named: they're the class
    if not peer or has(peer.professions, route.profession) then return route.to, false end
    for _, c in ipairs(peer.characters or {}) do
        if has(c.professions, route.profession) then return c.name, true end
    end
    return route.to, false
end

--- Where a binding's mail goes right now (Routes.Crafter with the peer heard from).
function Routes.Recipient(route)
    return Routes.Crafter(route, ns.Comms and ns.Comms.Peer(route.to) or nil)
end

-- The guild roster's rank for a member's primary profession (C_Club member info carries
-- profession1ID / profession1Rank, as Blizzard's Communities roster sorts by them).
local function guildSkill(name, profession)
    if call(IsInGuild) ~= true then return nil end
    local club = rawget(_G, "C_Club")
    local clubId = type(club) == "table" and call(club.GetGuildClubId) or nil
    local members = clubId and call(club.GetClubMembers, clubId) or nil
    for _, memberId in ipairs(type(members) == "table" and members or {}) do
        local info = call(club.GetMemberInfo, clubId, memberId)
        if type(info) == "table" and info.name and tostring(Routes.Clean(info.name)):lower() == name:lower() then
            if tonumber(info.profession1ID) == profession then return tonumber(info.profession1Rank) end
            if tonumber(info.profession2ID) == profession then return tonumber(info.profession2Rank) end
            return nil
        end
    end
    return nil
end

local function ownSkill(name, profession)
    for _, entry in ipairs(ns.Characters.Mailable()) do
        if tostring(entry.name):lower() == name:lower() then
            for _, p in ipairs(entry.professions or {}) do
                if tonumber(p.skillLine) == profession then return tonumber(p.rank) end
            end
        end
    end
    return nil
end

--- The skill in a binding's profession of the character that gets its mail, or nil when
--- unknown: the highest of what their Mailworthy said (Comms "S2"), this account's own
--- character's last login, and the guild roster (primary professions only). Skill only
--- grows, so the highest is the latest.
function Routes.Skill(route)
    if route.class then return nil end
    local to = Routes.Recipient(route)
    local profession = tonumber(route.profession)
    local best
    for _, skill in ipairs({ ns.Comms and ns.Comms.Skill(to, profession) or false, ownSkill(to, profession) or false,
        guildSkill(to, profession) or false }) do
        if skill and (not best or skill > best) then best = skill end
    end
    return best
end

--- Pure: divert an item to a binding. `verdict` is Valuation.Evaluate's result for the
--- item, `routes` the active bindings (Routes.Active()). Returns the new verdict, or nil
--- when no binding applies; a second return names the binding whose cap kept the item on
--- the normal rule, a third the binding whose player's skill is past the material (Tiers).
local GROUP = { character = 1, account = 2, guild = 3 }

--- Pure: of two bindings that both take an item, `a` goes first: this character's, then the
--- account's, then the guild's (this character's win, personal wins), then within one of those
--- the recipient with the lower skill in their profession (`skill`, Routes.Active; operator,
--- 2026-11-07, Blacksmithing and Engineering both taking metal and stone: "Lowest skill first",
--- so both crafters keep levelling), a known skill before an unknown one; else the list's order.
function Routes.Before(a, b)
    local ga, gb = GROUP[a.scope] or 2, GROUP[b.scope] or 2
    if ga ~= gb then return ga < gb end
    local sa, sb = tonumber(a.skill), tonumber(b.skill)
    if sa and sb then return sa < sb end
    return sa ~= nil and sb == nil
end

--- Pure: divert an item to a binding. `verdict` is Valuation.Evaluate's result for the
--- item, `routes` the active bindings (Routes.Active()). Returns the new verdict, or nil
--- when no binding applies; a second return names the binding whose cap kept the item on
--- the normal rule, a third the binding whose player's skill is past the material (Tiers).
--- Several bindings taking the item (metal and stone: Blacksmithing and Engineering): the first
--- by Routes.Before; its cap decides, as if it were the only one.
function Routes.Divert(item, verdict, price, settings, routes)
    if verdict and verdict.action == "keep" and Routes.HARD_KEEPS[verdict.reason] then return nil end
    local outgrown, route
    for _, r in ipairs(routes or {}) do
        local matches, past = Routes.Matches(r, item, settings and settings.tiers, settings and settings.priceOf)
        if r.class and Routes.PriceKeep(verdict) then matches = false end
        if past then outgrown = outgrown or r end
        if matches and (not route or Routes.Before(r, route)) then route = r end
    end
    if not route then return nil, nil, outgrown end
    local unit
    if type(price) == "table" and price.ah ~= nil
        and (price.age == nil or price.age <= (settings and settings.maxAgeDays or math.huge)) then
        unit = ns.Valuation.SmoothedPrice(price)
    end
    if route.cap and unit and unit >= route.cap then return nil, route end
    local to, crafter = Routes.Recipient(route)
    local n = item.count or 1
    return {
        action = "mail", route = Routes.ROUTE, to = to, crafter = crafter, key = route.key, what = Routes.What(route),
        reason = ns.Valuation.RecipeProfession(item) and (Routes.ProfessionName(route.profession) .. " recipe goes to "
            .. tostring(to)) or (Routes.What(route) .. " go to " .. tostring(to)),
        vendor = (item.vendor or 0) * n, postage = (settings and settings.postage or 30) * (item.stacks or 1),
        ahUnit = unit,
    }
end

-- Saved bindings ----------------------------------------------------------------

local function withKeys(list, scope)
    local out = {}
    for _, r in ipairs(list) do
        if type(r) == "table" and r.to and (r.profession or r.class) then
            local copy = {}
            for k, v in pairs(r) do copy[k] = v end
            copy.scope, copy.key = scope, Routes.KeyOf(r)
            out[#out + 1] = copy
        end
    end
    return out
end

--- The player's own bindings (the friends window's): this character's, then the account's.
function Routes.Personal()
    local list = withKeys(charList(), "character")
    for _, r in ipairs(withKeys(accountList(), "account")) do list[#list + 1] = r end
    return list
end

--- Every binding that applies to this character: this character's first, then the
--- account's for this realm + faction, then the guild template's rules while the player has
--- them on (Guild.Rules: personal bindings and this character's professions come first).
--- Each carries `scope` ("character" / "account" / "guild") and `key`.
function Routes.List()
    local list = Routes.Personal()
    if ns.Guild then
        for _, r in ipairs(ns.Guild.Rules(list)) do list[#list + 1] = r end
    end
    return list
end

function Routes.Count() return #Routes.List() end

--- The bindings in force for this mailbox visit (not skipped once), each with the
--- recipient's `skill` (Routes.Skill) for the material tiers.
function Routes.Active()
    local list = {}
    for _, r in ipairs(Routes.List()) do
        if not skipped[r.key] then
            r.skill = Routes.Skill(r)
            list[#list + 1] = r
        end
    end
    return list
end

local function find(key)
    for _, scope in ipairs({ "character", "account" }) do
        local list = listFor(scope)
        for i, r in ipairs(list) do
            if type(r) == "table" and Routes.KeyOf(r) == key then return list, i, r, scope end
        end
    end
    return nil
end

function Routes.Get(key)
    local _, _, r, scope = find(key)
    if not r then return nil end
    local copy = {}
    for k, v in pairs(r) do copy[k] = v end
    copy.scope, copy.key = scope, key
    return copy
end

--- Add a binding. `what`: a crafting profession's skill line ID, or a class token ("MAGE") for
--- a class binding. opts: scope ("account" default / "character"), cap (copper; false = none).
--- Returns the binding, or nil and why.
function Routes.Add(name, what, opts)
    opts = opts or {}
    name = Routes.Clean(name)
    if not name then return nil, "no name" end
    if name:lower() == tostring(ns.PlayerName()):lower() then return nil, "that's this character" end
    local profession, class = tonumber(what), nil
    if not profession then
        class = type(what) == "string" and ns.Classes.Token(what) or nil
        if not class then return nil, "not a crafting profession or a class" end
    elseif not Routes.ProfessionName(profession) then
        return nil, "not a crafting profession"
    end
    local route = { to = name, profession = profession, class = class,
        cap = opts.cap == nil and Routes.DEFAULT_CAP or (opts.cap or nil), at = call(GetServerTime) or time() }
    local key = Routes.KeyOf(route)
    if find(key) then return nil, "already bound" end
    local scope = opts.scope == "character" and "character" or "account"
    local list = listFor(scope)
    if #list >= Routes.MAX then return nil, "too many bindings" end
    list[#list + 1] = route
    ns.Log.Add("routes", "bound %s to %s (%s)", Routes.What(route), name, scope)
    return Routes.Get(key)
end

function Routes.Remove(key)
    local list, i, r = find(key)
    if not list then return false end
    table.remove(list, i)
    skipped[key] = nil
    ns.Log.Add("routes", "unbound %s to %s", Routes.What(r), r.to)
    return true
end

--- Move a binding between "account" and "character".
function Routes.SetScope(key, scope)
    local list, i, r, current = find(key)
    if not list or current == scope or not Routes.SCOPES[scope] then return false end
    local target = listFor(scope)
    if #target >= Routes.MAX then return false end
    table.remove(list, i)
    target[#target + 1] = r
    ns.Log.Add("routes", "%s to %s now %s", Routes.What(r), r.to, scope)
    return true
end

function Routes.ToggleScope(key)
    local r = Routes.Get(key)
    if not r then return false end
    return Routes.SetScope(key, r.scope == "account" and "character" or "account")
end

--- Pure: the next cap in direction +1 / -1; past the top step the cap goes (nil = none).
function Routes.NextCap(cap, dir)
    local steps = Routes.CAP_STEPS
    if cap == nil then
        if dir > 0 then return nil end
        return steps[#steps]
    end
    local i, nearest = 1, math.huge
    for j, v in ipairs(steps) do
        if math.abs(v - cap) < nearest then i, nearest = j, math.abs(v - cap) end
    end
    if dir > 0 then return steps[i + 1] end -- nil past the last step: no cap
    return steps[math.max(1, i - 1)]
end

function Routes.StepCap(key, dir)
    local _, _, r = find(key)
    if not r then return end
    r.cap = Routes.NextCap(r.cap, dir)
    ns.Log.Add("routes", "%s to %s: cap %s", Routes.What(r), r.to, r.cap and ns.Valuation.Money(r.cap) or "none")
end

--- Pure: "to my alt above 5g each" / "no price cap".
function Routes.CapText(route)
    if not route.cap then return "no price cap" end
    return "to my alt at " .. ns.Valuation.Money(route.cap) .. " each or more"
end

--- Pure: "Enchanting materials to Bob Surname".
function Routes.Describe(route)
    return Routes.What(route) .. " to " .. tostring(route.to)
end

-- Skip once (this mailbox visit) --------------------------------------------------

function Routes.SkipOnce(key)
    for _, r in ipairs(Routes.List()) do
        if r.key == key then skipped[key] = true end
    end
end

function Routes.Unskip(key) skipped[key] = nil end
function Routes.Skipped(key) return skipped[key] == true end
function Routes.ClearSkips() skipped = {} end

ns.On("MAIL_CLOSED", function() Routes.ClearSkips() end)

-- Candidates: who can be bound ------------------------------------------------------

local function presenceOnline(presence)
    local enum = rawget(_G, "Enum")
    local p = type(enum) == "table" and enum.ClubMemberPresence or {}
    local offline, unknown = p.Offline or 3, p.Unknown or 0
    return presence ~= nil and presence ~= offline and presence ~= unknown
end

local function addCandidate(list, byName, c)
    c.name = Routes.Clean(c.name)
    if not c.name or c.name:lower() == tostring(ns.PlayerName()):lower() then return end
    local entry = byName[c.name:lower()]
    if not entry then
        entry = { name = c.name, sources = {}, professions = {}, professionSet = {}, online = false }
        byName[c.name:lower()] = entry
        list[#list + 1] = entry
    end
    entry.sources[c.source] = true
    entry.online = entry.online or c.online == true
    entry.class, entry.level = entry.class or ns.Classes.Token(c.class), entry.level or c.level
    for _, id in ipairs(c.professions or {}) do
        id = tonumber(id)
        if Routes.ProfessionName(id) and not entry.professionSet[id] then
            entry.professionSet[id] = true
            entry.professions[#entry.professions + 1] = id
        end
    end
end

local function groupCandidates(list, byName)
    local n = tonumber((call(GetNumGroupMembers))) or 0
    if n == 0 then return end
    local raid = call(IsInRaid) == true
    for i = 1, n do
        local unit = raid and ("raid" .. i) or ("party" .. (i - 1))
        if unit ~= "party0" then
            local name = call(GetUnitName, unit, true) or call(UnitName, unit)
            if name then
                local _, class = call(UnitClass, unit)
                addCandidate(list, byName, { name = name, source = "party", online = call(UnitIsConnected, unit) ~= false,
                    class = class, level = call(UnitLevel, unit) })
            end
        end
    end
end

local function guildCandidates(list, byName)
    if call(IsInGuild) ~= true then return end
    local club = rawget(_G, "C_Club")
    local clubId = type(club) == "table" and call(club.GetGuildClubId) or nil
    local members = clubId and call(club.GetClubMembers, clubId) or nil
    if type(members) == "table" and #members > 0 then
        for _, memberId in ipairs(members) do
            local info = call(club.GetMemberInfo, clubId, memberId)
            if type(info) == "table" and info.name and not info.isSelf then
                addCandidate(list, byName, { name = info.name, source = "guild", online = presenceOnline(info.presence),
                    level = info.level, class = ns.Classes.Token(info.classID),
                    professions = { info.profession1ID, info.profession2ID } })
            end
        end
        return
    end
    for i = 1, tonumber((call(GetNumGuildMembers))) or 0 do
        local name, _, _, level, _, _, _, _, online, _, class = call(GetGuildRosterInfo, i)
        if name then
            addCandidate(list, byName, { name = name, source = "guild", online = online == true, level = level, class = class })
        end
    end
end

local function altCandidates(list, byName)
    for _, entry in ipairs(ns.Characters.Mailable()) do
        local ids = {}
        for _, p in ipairs(entry.professions or {}) do ids[#ids + 1] = p.skillLine end
        addCandidate(list, byName, { name = entry.name, source = "alt", class = entry.class, level = entry.level,
            professions = ids })
    end
end

local function peerCandidates(list, byName)
    if not ns.Comms then return end
    for _, peer in pairs(ns.Comms.Peers()) do
        addCandidate(list, byName, { name = peer.name, source = "mailworthy", professions = peer.professions })
        local entry = byName[tostring(Routes.Clean(peer.name) or ""):lower()]
        if entry then entry.peer = peer end
    end
end

--- Pure: a candidate's professions Mailworthy can bind, by name: { { id, name }, ... }.
function Routes.Suggested(candidate)
    local list = {}
    for _, id in ipairs(candidate.professions or {}) do list[#list + 1] = { id = id, name = Routes.ProfessionName(id) } end
    table.sort(list, function(a, b) return a.name < b.name end)
    return list
end

--- Pure: "Bob Surname - Enchanting, Tailoring - online - guild, Mailworthy". `nameText` shows in
--- place of the name (the friends window's: the name with the Mailworthy mark, Comms.Mark).
function Routes.CandidateText(c, nameText)
    local parts = { nameText or c.name }
    local profs = {}
    for _, p in ipairs(Routes.Suggested(c)) do profs[#profs + 1] = p.name end
    if #profs > 0 then parts[#parts + 1] = table.concat(profs, ", ") end
    if c.online then parts[#parts + 1] = "online" end
    local where = {}
    if c.sources.me then where[#where + 1] = "you" end
    for _, s in ipairs({ "party", "guild", "alt" }) do
        if c.sources[s] then where[#where + 1] = s == "alt" and "my character" or s end
    end
    if c.sources.mailworthy or c.peer then where[#where + 1] = "Mailworthy" end
    if #where > 0 then parts[#parts + 1] = table.concat(where, ", ") end
    return table.concat(parts, " - ")
end

--- Everyone this character could bind: online players first, then the account's own
--- characters, then Mailworthy users, then party before guild, by name. Each: { name, sources = { party / guild / alt /
--- mailworthy }, online, class, level, professions = { ids... }, peer }.
function Routes.Candidates()
    local list, byName = {}, {}
    groupCandidates(list, byName)
    guildCandidates(list, byName)
    altCandidates(list, byName)
    peerCandidates(list, byName)
    local rank = { party = 1, guild = 2, alt = 3 }
    local function best(c)
        local r = 9
        for s, n in pairs(rank) do if c.sources[s] and n < r then r = n end end
        return r
    end
    table.sort(list, function(a, b)
        if a.online ~= b.online then return a.online end
        local aa, ab = a.sources.alt == true, b.sources.alt == true -- own characters: mail always arrives
        if aa ~= ab then return aa end
        local pa, pb = a.peer ~= nil, b.peer ~= nil
        if pa ~= pb then return pa end
        local ra, rb = best(a), best(b)
        if ra ~= rb then return ra < rb end
        return a.name < b.name
    end)
    return list
end

--- This character as a candidate, for a guild template rule naming its author (2026-11-07: "I
--- should be able to set routing to me in the guild template as well"): a binding to yourself
--- means nothing, but the guild's other members (and this account's other characters) mail you.
function Routes.Me()
    local name = Routes.Clean(ns.PlayerName())
    if not name then return nil end
    local ids = {}
    for _, p in ipairs(ns.Characters.Professions()) do
        local id = tonumber(p.skillLine)
        if Routes.ProfessionName(id) then ids[#ids + 1] = id end
    end
    return { name = name, sources = { me = true, guild = true }, professions = ids, professionSet = {}, online = true }
end

local lastRosterRequest = -math.huge
--- Ask the game for a fresh guild roster (what Blizzard's mail window does when the
--- auto-complete list is empty), at most every 10 s.
function Routes.RequestRoster()
    local now = call(GetTime) or 0
    if now - lastRosterRequest < 10 then return end
    lastRosterRequest = now
    local guild = rawget(_G, "C_GuildInfo")
    if call(IsInGuild) == true and type(guild) == "table" then call(guild.GuildRoster) end
end

--- One line per binding for /mw report.
function Routes.ReportLines()
    local lines = {}
    for _, r in ipairs(Routes.List()) do
        local to, crafter = Routes.Recipient(r)
        local skill = Routes.Skill(r)
        local past = skill and ns.Tiers.PastText(r.profession, skill) or ""
        lines[#lines + 1] = string.format("binding: %s (%s, %s%s, skill %s%s%s)", Routes.Describe(r),
            Routes.SCOPE_REPORT[r.scope] or tostring(r.scope), Routes.CapText(r),
            crafter and (", delivered to their crafter " .. to) or "", skill and tostring(skill) or "unknown",
            past ~= "" and (": past " .. past) or "",
            skipped[r.key] and ", skipped this visit" or "")
    end
    return lines
end
