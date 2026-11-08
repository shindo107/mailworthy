-- Guild contributions (Contributions.lua; Raid Ledger ROK-2148, operator rulings 2026-11-08): only
-- mail a guild template rule routed counts, in stack units, per sending character, never to this
-- account's own characters; the counters outlive the mail log's pruning; older SavedVariables load;
-- MailworthyAPI.v1.GetGuildExport returns exactly Raid Ledger's shape and caps, fresh tables, never
-- an error.
local loadAddon = require("spec.support.load_addon")

local ENCHANTING, TAILORING = 333, 197
local GM, BOB, CARA, ME = "Guild Master", "Bob Surname", "Cara Friend", "Rettana Quilwrit"
local BANK_ALT = "Roknua Themicrulah"
local GUILD = "Bank Of Azeroth"
local KEY = "Classic Beta PvP|Alliance|" .. GUILD
local NOW = 1791900000
local TODAY = math.floor(NOW / 86400)
local REV = NOW - 60

--- Every key of `t` is one of `allowed` (the contract's objects are strict).
local function onlyKeys(t, allowed, what)
    local set = {}
    for _, k in ipairs(allowed) do set[k] = true end
    for k in pairs(t) do assert.is_true(set[k] == true, what .. " has an unknown key: " .. tostring(k)) end
end

--- The whole export checked against Raid Ledger's AddonMailworthySchema (spec ROK-2148 A.2).
local function assertContract(e)
    local function int(x) return type(x) == "number" and x == math.floor(x) end
    local function unix(x) return int(x) and x >= 1 and x <= 4102444800 end
    local function count(x) return int(x) and x >= 0 and x <= 2147483647 end
    local function name(x) return type(x) == "string" and #x >= 1 and #x <= 48 end
    onlyKeys(e, { "generatedAt", "template", "peers", "givers" }, "the export")
    assert.is_true(unix(e.generatedAt))
    if e.template ~= nil then
        onlyKeys(e.template, { "rev", "author", "rules" }, "the template")
        assert.is_true(unix(e.template.rev))
        assert.is_true(name(e.template.author))
        assert.is_true(#e.template.rules <= 8)
        for _, r in ipairs(e.template.rules) do
            onlyKeys(r, { "professionSkillLineId", "recipientName" }, "a rule")
            assert.is_true(int(r.professionSkillLineId) and r.professionSkillLineId > 0)
            assert.is_true(name(r.recipientName))
        end
    end
    if e.peers ~= nil then
        assert.is_true(#e.peers >= 1 and #e.peers <= 1000, "peers: none is nil, never empty")
        for _, p in ipairs(e.peers) do
            onlyKeys(p, { "name", "lastSeenAt" }, "a peer")
            assert.is_true(name(p.name))
            assert.is_true(unix(p.lastSeenAt))
        end
    end
    if e.givers ~= nil then
        assert.is_true(#e.givers >= 1 and #e.givers <= 50, "givers: none is nil, never empty")
        for _, g in ipairs(e.givers) do
            onlyKeys(g, { "characterName", "itemsAllTime", "countingSince", "days" }, "a giver")
            assert.is_true(name(g.characterName))
            assert.is_true(count(g.itemsAllTime))
            assert.is_true(unix(g.countingSince))
            assert.is_true(#g.days <= 35)
            local last, sum = -1, 0
            for _, d in ipairs(g.days) do
                onlyKeys(d, { "day", "items" }, "a day")
                assert.is_true(int(d.day) and d.day >= 0 and d.day <= 47482)
                assert.is_true(count(d.items) and d.items > 0, "days: non-zero only")
                assert.is_true(d.day > last, "days: ascending, unique")
                last, sum = d.day, sum + d.items
            end
            assert.is_true(g.itemsAllTime >= sum)
        end
    end
end

describe("guild contributions", function()
    local ns, prices

    local function dust(count) return WowStub.item(10940, "Strange Dust", { count = count or 20, sell = 2, class = 7, subclass = 12 }) end
    local function cloth(count) return WowStub.item(2592, "Wool Cloth", { count = count or 20, sell = 33, class = 7, subclass = 5 }) end

    local function hear(sender, text) ns.Fire("CHAT_MSG_ADDON", "Mailworthy", text, "GUILD", sender) end
    local function publish(rules, rev)
        for _, m in ipairs(ns.Guild.Encode(rev or REV, GM, rules)) do hear(BOB, m) end
    end

    --- One mailbox visit: everything Bags would mail, sent and answered by the server.
    local function send()
        MailFrame:Show()
        SendMailFrame:Show()
        local result = ns.Bags.Evaluate()
        assert.is_true(ns.Mailer.Start(result.mail, ns.Config.BankAlt()))
        for _ = 1, 20 do
            WowStub.runTimers()
            if not ns.Mailer.Busy() then return result end
            ns.Fire("MAIL_SEND_SUCCESS")
        end
        error("the mailer never finished")
    end

    local function sentEntries()
        local out = {}
        for _, e in ipairs(ns.Ledger.Store().log) do if e.dir == "sent" then out[e.other] = e end end
        return out
    end

    before_each(function()
        ns = loadAddon()
        WowStub.state.guild = { clubId = 7, name = GUILD, rank = 3, members = {
            { name = GM, rank = 0, online = true }, { name = BOB, rank = 3, online = true },
            { name = CARA, rank = 3, online = true }, { name = ME, rank = 3, online = true } } }
        ns.Fire("PLAYER_LOGIN")
        ns.Config.SetBankAlt(BANK_ALT)
        prices = {}
        _G.Auctionator = { API = { v1 = {
            GetAuctionPriceByItemLink = function(_, l) return prices[l] end,
            GetAuctionAgeByItemLink = function() return 0 end,
        } } }
    end)
    after_each(function()
        _G.Auctionator = nil
        for _, line in ipairs(ns.Log.Lines()) do assert.is_nil(line:find("error", 1, true), line) end
    end)

    describe("tagging and counting", function()
        it("a guild rule's mail is tagged in the log and counted in stack units; the bank alt's and a binding's aren't", function()
            publish({ { profession = ENCHANTING, to = BOB } })
            ns.Guild.SetUse(true)
            ns.Routes.Add(CARA, TAILORING) -- a personal binding: never counted
            WowStub.setBag(0, 1, dust(20))
            WowStub.setBag(0, 2, dust(7))
            WowStub.setBag(0, 3, cloth(20))
            WowStub.setBag(0, 4, WowStub.item(3001, "Ore 1", { count = 5, sell = 5, class = 7, subclass = 7 }))
            prices[WowStub.link(3001, "Ore 1")] = 500
            send()
            local logged = sentEntries()
            assert.equal("guild", logged[BOB].scope)
            assert.same({ key = KEY, profession = ENCHANTING, rev = REV }, logged[BOB].guild)
            assert.truthy(ns.Ledger.LineText(logged[BOB]):find("guild rule: Enchanting", 1, true))
            for _, other in ipairs({ CARA, BANK_ALT }) do
                assert.is_nil(logged[other].scope, other)
                assert.is_nil(logged[other].guild, other)
            end
            local c = MailworthyDB.guildGiven[KEY][ME:lower()]
            assert.same({ name = ME, total = 27, since = NOW, days = { [TODAY] = 27 } }, c)
        end)

        it("a guild rule naming one of this account's characters: mailed and tagged, never counted", function()
            local ALT = "Alty Alterson"
            table.insert(WowStub.state.guild.members, { name = ALT, rank = 3 })
            MailworthyDB.characters["Alty Alterson|Classic Beta PvP|Alliance"] = { name = ALT,
                realm = "Classic Beta PvP", faction = "Alliance" }
            publish({ { profession = ENCHANTING, to = ALT } })
            ns.Guild.SetUse(true)
            WowStub.setBag(0, 1, dust(20))
            send()
            assert.equal("guild", sentEntries()[ALT].scope)
            assert.is_nil(MailworthyDB.guildGiven[KEY])
            assert.is_nil(MailworthyAPI.v1.GetGuildExport().givers)
        end)

        it("Blizzard's Send button never carries a guild tag", function()
            local entry = ns.Ledger.RecordSent({ to = BOB, items = {}, guild = { key = KEY, profession = ENCHANTING, rev = REV } }, "mail")
            assert.is_nil(entry.scope)
            assert.is_nil(entry.guild)
        end)

        it("Tag counts only the stacks a guild rule routed", function()
            local function stack(count, guild) return { count = count, item = { result = { guild = guild } } } end
            local g = { key = KEY, profession = ENCHANTING, rev = REV }
            assert.same({ key = KEY, profession = ENCHANTING, rev = REV, units = 27 },
                ns.Contributions.Tag({ attached = { stack(20, g), stack(5), stack(7, g) } }))
            assert.is_nil(ns.Contributions.Tag({ attached = { stack(5) } }))
            assert.is_nil(ns.Contributions.Tag({}))
            assert.is_nil(ns.Contributions.Tag(nil))
        end)

        it("day buckets roll: older than 35 days are dropped, the all-time total and countingSince stay", function()
            local tag = { key = KEY, profession = ENCHANTING, rev = REV, units = 10 }
            assert.is_true(ns.Contributions.Count(BOB, tag, NOW - 40 * 86400))
            assert.is_true(ns.Contributions.Count(BOB, tag, NOW - 34 * 86400))
            assert.is_true(ns.Contributions.Count(BOB, tag, NOW))
            assert.is_true(ns.Contributions.Count(BOB, tag, NOW + 60)) -- the same UTC day
            local c = MailworthyDB.guildGiven[KEY][ME:lower()]
            assert.equal(40, c.total)
            assert.equal(NOW - 40 * 86400, c.since)
            assert.same({ [TODAY - 34] = 10, [TODAY] = 20 }, c.days)
            assert.same({ false, "nothing attached" }, { ns.Contributions.Count(BOB, { key = KEY, units = 0 }) })
            assert.same({ false, "no guild rule" }, { ns.Contributions.Count(BOB, nil) })
            assert.same({ false, "own character" }, { ns.Contributions.Count(BANK_ALT, tag) })
        end)

        it("the counters outlive the mail log's pruning", function()
            publish({ { profession = ENCHANTING, to = BOB } })
            ns.Guild.SetUse(true)
            WowStub.setBag(0, 1, dust(20))
            send()
            for i = 1, ns.Ledger.LOG_MAX + 5 do
                ns.Ledger.Add({ dir = "received", other = "Someone Else", subject = "x" .. i, items = {} })
            end
            local log = ns.Ledger.Store().log
            assert.equal(ns.Ledger.LOG_MAX, #log)
            for _, e in ipairs(log) do assert.is_nil(e.guild, "the tagged entry should be pruned") end
            local g = MailworthyAPI.v1.GetGuildExport().givers
            assert.same({ { characterName = ME, itemsAllTime = 20, countingSince = NOW, days = { { day = TODAY, items = 20 } } } }, g)
        end)
    end)

    describe("older SavedVariables", function()
        it("v0.30.0's tables (no counters, untagged log entries) load and export without error", function()
            ns = loadAddon({ db = {
                guildTemplates = { [KEY] = { rev = REV, from = GM, at = REV, use = true,
                    rules = { { profession = ENCHANTING, to = BOB, cap = 50000 } } } },
                ledger = { ["Classic Beta PvP|Alliance"] = { log = { { id = 1, at = REV, dir = "sent", char = ME,
                    other = BOB, subject = "old", items = { { itemID = 10940, count = 3 } }, via = "Mailworthy" } } } },
                peers = { ["Classic Beta PvP|Alliance"] = { [BOB:lower()] = { name = BOB, professions = { ENCHANTING },
                    characters = {}, version = 2, at = NOW - 3600 } } },
            }, charDB = {} })
            WowStub.state.guild = { clubId = 7, name = GUILD, rank = 3, members = {
                { name = GM, rank = 0 }, { name = BOB, rank = 3 }, { name = ME, rank = 3 } } }
            ns.Fire("ADDON_LOADED", "Mailworthy")
            ns.Fire("PLAYER_LOGIN")
            assert.same({}, MailworthyDB.guildGiven)
            local e = MailworthyAPI.v1.GetGuildExport()
            assertContract(e)
            assert.same({ generatedAt = NOW, template = { rev = REV, author = GM,
                rules = { { professionSkillLineId = ENCHANTING, recipientName = BOB } } },
                peers = { { name = BOB, lastSeenAt = NOW - 3600 } } }, e)
            local report = ns.Report.Build()
            assert.truthy(report:find("guild contributions: this guild, 0 character(s)", 1, true))
            assert.truthy(report:find("guild export: template rev " .. REV .. ", 1 rule(s), 1 peer(s), 0 giver(s)", 1, true))
        end)

        it("damaged counters are cleaned at login", function()
            ns = loadAddon({ db = { guildGiven = {
                [KEY] = {
                    [ME:lower()] = { name = ME, total = "12", since = NOW - 100,
                        days = { [TODAY] = 5, [TODAY - 40] = 7, [TODAY - 1] = -3, junk = 4 } },
                    ["nobody"] = "junk",
                    ["mismatch"] = { name = "Someone", total = 4, since = NOW, days = {} },
                    ["zero"] = { name = "Zero", total = 0, since = NOW, days = {} },
                },
                [1] = { x = 1 },
                ["Classic Beta PvP|Alliance|Empty"] = "junk",
            } }, charDB = {} })
            ns.Fire("ADDON_LOADED", "Mailworthy")
            ns.Fire("PLAYER_LOGIN")
            assert.same({ [KEY] = { [ME:lower()] = { name = ME, total = 12, since = NOW - 100, days = { [TODAY] = 5 } } } },
                MailworthyDB.guildGiven)
        end)
    end)

    describe("MailworthyAPI.v1.GetGuildExport", function()
        local function seedPeers(n, at)
            local peers = ns.Comms.Peers()
            for i = 1, n do
                local name = "Peer " .. i
                peers[name:lower()] = { name = name, professions = {}, characters = {}, at = at(i) }
                table.insert(WowStub.state.guild.members, { name = name, rank = 3 })
            end
        end

        -- Raid Ledger's golden fixture `char-mailworthy` (packages/contract/ledgerlink/v1/fixtures, branch
        -- feat/rok-2148-guild-contributions): the same state in Mailworthy's tables gives the same block.
        it("matches Raid Ledger's char-mailworthy fixture for the same state", function()
            local fixture = {
                generatedAt = 1789999940,
                template = { rev = 1789568000, author = "Member1", rules = {
                    { professionSkillLineId = 333, recipientName = "Member2" },
                    { professionSkillLineId = 171, recipientName = "Member3" },
                    { professionSkillLineId = 164, recipientName = "Ana Forever" } } },
                peers = {
                    { name = "Member1", lastSeenAt = 1789996340 }, { name = "Member2", lastSeenAt = 1789992740 },
                    { name = "Member3", lastSeenAt = 1789989140 }, { name = "Member4", lastSeenAt = 1789985540 } },
                givers = {
                    { characterName = "Ana Forever", itemsAllTime = 140, countingSince = 1782224000, days = {
                        { day = 20686, items = 20 }, { day = 20688, items = 12 }, { day = 20717, items = 8 } } },
                    { characterName = "Anabelle Forever", itemsAllTime = 20, countingSince = 1789136000, days = {
                        { day = 20715, items = 20 } } } },
            }
            local peers, roster = {}, { ["ana forever"] = true }
            for i = 4, 1, -1 do -- stored by name, in no order; one more Mailworthy user outside the guild
                local p = fixture.peers[i]
                peers[p.name:lower()] = { name = p.name, professions = {}, characters = {}, version = 2, at = p.lastSeenAt }
                roster[p.name:lower()] = true
            end
            peers["stranger"] = { name = "Stran Ger", at = 1789999000 }
            local e = ns.Contributions.Build({
                now = 1789999940,
                template = { rev = 1789568000, from = "Member1", at = 1789568000, use = true, via = "Member2", rules = {
                    { profession = 333, to = "Member2", cap = 50000 }, { profession = 171, to = "Member3" },
                    { profession = 164, to = "Ana Forever", cap = 10000 } } },
                peers = peers, roster = roster,
                givers = {
                    ["anabelle forever"] = { name = "Anabelle Forever", total = 20, since = 1789136000, days = { [20715] = 20 } },
                    ["ana forever"] = { name = "Ana Forever", total = 140, since = 1782224000,
                        days = { [20717] = 8, [20686] = 20, [20688] = 12, [20682] = 5 } }, -- 20682: out of the 35 days
                },
            })
            assertContract(e)
            assert.same(fixture, e)
        end)

        it("nil outside a guild, or with nothing known", function()
            WowStub.state.guild = nil
            assert.is_nil(MailworthyAPI.v1.GetGuildExport())
            WowStub.state.guild = { clubId = 7, name = GUILD, members = { { name = ME } } }
            assert.is_nil(MailworthyAPI.v1.GetGuildExport())
        end)

        it("the template: rev, author, rules by skill line and recipient; never caps, use, via or at", function()
            publish({ { profession = ENCHANTING, to = BOB, cap = 50000 }, { profession = TAILORING, to = CARA } })
            local e = MailworthyAPI.v1.GetGuildExport()
            assertContract(e)
            assert.same({ rev = REV, author = GM, rules = {
                { professionSkillLineId = ENCHANTING, recipientName = BOB },
                { professionSkillLineId = TAILORING, recipientName = CARA } } }, e.template)
        end)

        it("an empty template keeps its empty rules list (Raid Ledger clears the masters)", function()
            publish({})
            assert.same({ rev = REV, author = GM, rules = {} }, MailworthyAPI.v1.GetGuildExport().template)
        end)

        it("peers: only this guild's roster, heard in 60 days, newest first, at most 1000", function()
            local peers = ns.Comms.Peers()
            peers["stranger"] = { name = "Stran Ger", at = NOW - 10 } -- a party member, not in the guild
            peers[CARA:lower()] = { name = CARA, at = NOW - 61 * 86400 } -- older than 60 days
            peers[BOB:lower()] = { name = BOB, at = NOW - 5 }
            seedPeers(1005, function(i) return NOW - 100 - i end)
            ns.Contributions.Roster(GUILD, true)
            local e = MailworthyAPI.v1.GetGuildExport()
            assertContract(e)
            assert.equal(1000, #e.peers)
            assert.same({ name = BOB, lastSeenAt = NOW - 5 }, e.peers[1])
            assert.same({ name = "Peer 1", lastSeenAt = NOW - 101 }, e.peers[2])
            assert.same({ name = "Peer 999", lastSeenAt = NOW - 1099 }, e.peers[1000])
            for _, p in ipairs(e.peers) do
                assert.is_true(p.name ~= "Stran Ger" and p.name ~= CARA, p.name)
            end
        end)

        it("peers need the roster: at logout the last read of this session stands in; another guild gets none", function()
            ns.Comms.Peers()[BOB:lower()] = { name = BOB, at = NOW - 5 }
            ns.Fire("GUILD_ROSTER_UPDATE")
            WowStub.state.guild = nil -- logging out: the guild is gone, LedgerLink passes the name it cached
            assert.same({ { name = BOB, lastSeenAt = NOW - 5 } }, MailworthyAPI.v1.GetGuildExport(GUILD).peers)
            assert.is_nil(MailworthyAPI.v1.GetGuildExport("Another Guild"))
            assert.is_nil(MailworthyAPI.v1.GetGuildExport())
        end)

        it("givers: total above zero, most first, at most 50; days ascending, the last 35, non-zero", function()
            local given = {}
            for i = 1, 55 do
                local days = {}
                for d = 0, 39 do days[TODAY - d] = 1 end
                days[TODAY - 2] = 0
                given[("giver " .. i):lower()] = { name = "Giver " .. i, total = 100 + i, since = NOW - 50 * 86400, days = days }
            end
            given["nothing"] = { name = "Nothing", total = 0, since = NOW, days = {} }
            given["long"] = { name = string.rep("L", 49), total = 999, since = NOW, days = {} }
            MailworthyDB.guildGiven = { [KEY] = given }
            local e = MailworthyAPI.v1.GetGuildExport()
            assertContract(e)
            assert.equal(50, #e.givers)
            assert.equal("Giver 55", e.givers[1].characterName)
            assert.equal(155, e.givers[1].itemsAllTime)
            assert.equal("Giver 6", e.givers[50].characterName)
            local days = e.givers[1].days
            assert.equal(34, #days) -- 35 days in the window, one of them zero
            assert.same({ day = TODAY - 34, items = 1 }, days[1])
            assert.same({ day = TODAY, items = 1 }, days[34])
        end)

        it("all-time is never below the days' sum, and names longer than 48 are dropped, never shortened", function()
            MailworthyDB.guildGiven = { [KEY] = { me = { name = ME, total = 2, since = NOW, days = { [TODAY] = 9 } } } }
            assert.equal(9, MailworthyAPI.v1.GetGuildExport().givers[1].itemsAllTime)
            publish({ { profession = ENCHANTING, to = BOB } })
            MailworthyDB.guildTemplates[KEY].rules[1].to = string.rep("N", 49)
            assert.same({}, MailworthyAPI.v1.GetGuildExport().template.rules)
            MailworthyDB.guildTemplates[KEY].from = string.rep("A", 49)
            assert.is_nil(MailworthyAPI.v1.GetGuildExport().template)
        end)

        it("returns fresh tables: changing the result changes nothing saved, and each call is new", function()
            publish({ { profession = ENCHANTING, to = BOB } })
            ns.Comms.Peers()[BOB:lower()] = { name = BOB, at = NOW - 5 }
            MailworthyDB.guildGiven = { [KEY] = { [ME:lower()] = { name = ME, total = 3, since = NOW, days = { [TODAY] = 3 } } } }
            local before = MailworthyAPI.v1.GetGuildExport()
            local e = MailworthyAPI.v1.GetGuildExport()
            assert.are_not.equal(before, e)
            assert.same(before, e)
            e.template.rules[1].recipientName, e.template.author = "X", "Y"
            e.peers[1].name, e.givers[1].days[1].items, e.givers[1].itemsAllTime = "X", 99, 99
            assert.same(before, MailworthyAPI.v1.GetGuildExport())
            assert.equal(BOB, MailworthyDB.guildTemplates[KEY].rules[1].to)
            assert.equal(3, MailworthyDB.guildGiven[KEY][ME:lower()].days[TODAY])
        end)

        it("reads only: an export writes nothing into MailworthyDB", function()
            MailworthyDB.peers, MailworthyDB.guildGiven = nil, nil
            assert.is_nil(MailworthyAPI.v1.GetGuildExport())
            assert.is_nil(MailworthyDB.peers)
            assert.is_nil(MailworthyDB.guildGiven)
        end)

        it("never errors: no SavedVariables yet, damaged tables, a failing game call", function()
            MailworthyDB.guildTemplates = { [KEY] = "junk" }
            MailworthyDB.peers = { ["Classic Beta PvP|Alliance"] = { x = "junk", y = { name = 5, at = "x" } } }
            MailworthyDB.guildGiven = { [KEY] = { x = { name = ME, total = 1, since = "never", days = "junk" } } }
            assert.is_nil(MailworthyAPI.v1.GetGuildExport())
            local saved = _G.GetServerTime
            _G.GetServerTime = function() error("boom") end
            assert.has_no.errors(function() MailworthyAPI.v1.GetGuildExport() end)
            _G.GetServerTime = saved
            local db = MailworthyDB
            _G.MailworthyDB = nil
            assert.is_nil(MailworthyAPI.v1.GetGuildExport(GUILD))
            _G.MailworthyDB = db
            assert.is_nil(MailworthyAPI.v1.GetGuildExport({}))
            local key = ns.Guild.Key
            ns.Guild.Key = function() error("boom") end
            assert.is_nil(MailworthyAPI.v1.GetGuildExport())
            ns.Guild.Key = key
            assert.truthy(table.concat(ns.Log.Lines(), "\n"):find("export error", 1, true), "an error is logged")
            MailworthyDB.log = {} -- the one error line this case caused on purpose
        end)
    end)
end)
