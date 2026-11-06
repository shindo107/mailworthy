-- Bindings (operator, 2026-10-26): "send my Enchanting materials to Bob". A
-- profession's materials go to a guild member, party member or own character
-- instead of being valued, until the binding is removed; a price cap sends a
-- material the market suddenly wants to the bank alt instead; Skip once drops a
-- binding for one mailbox visit; the friends window picks the player (party,
-- guild, own characters, Mailworthy users) and suggests their professions;
-- Mailworthys say hello to each other (every character's crafting professions)
-- so a binding reaches the friend's character that has the profession.
local loadAddon = require("spec.support.load_addon")

describe("bindings", function()
    local ns, prices
    local ENCHANTING, TAILORING, ALCHEMY = 333, 197, 171
    local BOB = "Bob Surname"

    local function dust(count) return WowStub.item(10940, "Strange Dust", { count = count or 20, sell = 2, class = 7, subclass = 12 }) end
    local function cloth(count) return WowStub.item(2589, "Linen Cloth", { count = count or 20, sell = 10, class = 7, subclass = 5 }) end
    local function withAuctionator()
        prices = {}
        _G.Auctionator = { API = { v1 = {
            GetAuctionPriceByItemLink = function(_, l) return prices[l] end,
            GetAuctionAgeByItemLink = function() return 0 end,
        } } }
    end
    local function log() return table.concat(ns.Log.Lines(), "\n") end

    before_each(function()
        ns = loadAddon()
        ns.Fire("PLAYER_LOGIN")
        ns.Config.SetBankAlt("Roknua Themicrulah")
        WowStub.state.addonMessages = {}
    end)
    after_each(function()
        _G.Auctionator = nil
        for _, line in ipairs(ns.Log.Lines()) do assert.is_nil(line:find("error", 1, true), line) end
        assert.equal(0, WowStub.focusCalls)
    end)

    describe("pure rules", function()
        it("cleans names like mail wants them: spaces collapsed, the realm suffix dropped", function()
            assert.equal("Bob Surname", ns.Routes.Clean("  Bob   Surname-Classic Beta PvP "))
            assert.equal("Bob Surname", ns.Routes.Clean("Bob Surname"))
            assert.is_nil(ns.Routes.Clean("  "))
            assert.is_nil(ns.Routes.Clean(nil))
        end)

        it("matches the trade goods the bound profession uses", function()
            local route = { to = BOB, profession = ENCHANTING }
            assert.is_true(ns.Routes.Matches(route, { classID = 7, subclassID = 12 }))
            assert.is_false(ns.Routes.Matches(route, { classID = 7, subclassID = 5 }), "cloth isn't enchanting material")
            assert.is_false(ns.Routes.Matches(route, { classID = 4, subclassID = 12 }), "only trade goods")
            assert.is_false(ns.Routes.Matches({ to = BOB, profession = 186 }, { classID = 7, subclassID = 7 }), "Mining binds nothing")
        end)

        it("an Enchanting binding also takes green and blue weapons and armor to disenchant", function()
            local route = { to = BOB, profession = ENCHANTING }
            assert.is_true(ns.Routes.Matches(route, { classID = 4, subclassID = 2, quality = 2 }), "green armor")
            assert.is_true(ns.Routes.Matches(route, { classID = 2, subclassID = 7, quality = 3 }), "blue weapon")
            assert.is_false(ns.Routes.Matches(route, { classID = 4, subclassID = 2, quality = 1 }), "white armor doesn't disenchant")
            assert.is_false(ns.Routes.Matches(route, { classID = 4, subclassID = 2, quality = 4 }), "epics stay on the normal rule")
            assert.is_false(ns.Routes.Matches(route, { classID = 15, quality = 2 }), "a green that isn't gear")
            assert.is_false(ns.Routes.Matches({ to = BOB, profession = TAILORING }, { classID = 4, subclassID = 1, quality = 2 }),
                "only Enchanting takes gear")
            local D = ns.Valuation.DEFAULTS
            local cloak = { classID = 4, subclassID = 1, quality = 2, count = 1, stacks = 1, vendor = 120 }
            local v = ns.Routes.Divert(cloak, { action = "mail", route = "de" }, { ah = 4900, age = 0 }, D,
                { { to = BOB, profession = ENCHANTING, key = "k", cap = 50000 } })
            assert.equal(BOB, v.to)
            assert.is_nil(ns.Routes.Divert(cloak, { action = "keep", reason = "soulbound" }, nil, D,
                { { to = BOB, profession = ENCHANTING, key = "k" } }), "soulbound gear never leaves")
            local capped
            v, capped = ns.Routes.Divert(cloak, { action = "mail", route = "ah" }, { ah = 60000, age = 0 }, D,
                { { to = BOB, profession = ENCHANTING, key = "k", cap = 50000 } })
            assert.is_nil(v, "6g on the auction house, over Bob's 5g cap: the bank alt lists it")
            assert.truthy(capped)
        end)

        it("diverts a matching item to the bound player, never a hard keep", function()
            local routes = { { to = BOB, profession = ENCHANTING, key = "333|bob surname", cap = 50000 } }
            local item = { classID = 7, subclassID = 12, count = 20, stacks = 1, vendor = 2 }
            local D = ns.Valuation.DEFAULTS
            local v = ns.Routes.Divert(item, { action = "keep", reason = "not worth it" }, nil, D, routes)
            assert.equal("mail", v.action)
            assert.equal("friend", v.route)
            assert.equal(BOB, v.to)
            assert.equal("Enchanting materials go to Bob Surname", v.reason)
            assert.equal(40, v.vendor)
            assert.equal(30, v.postage)
            local hard = { "locked", "soulbound", "quest item", "in use", "profession tool", "item info not loaded yet" }
            for _, reason in ipairs(hard) do
                assert.is_nil(ns.Routes.Divert(item, { action = "keep", reason = reason }, nil, D, routes), reason)
            end
            assert.is_nil(ns.Routes.Divert({ classID = 7, subclassID = 5 }, { action = "mail" }, nil, D, routes))
            assert.is_nil(ns.Routes.Divert(item, { action = "mail" }, nil, D, {}))
        end)

        it("a binding beats 'your profession needs it': an explicit choice over the default keep", function()
            local routes = { { to = BOB, profession = ENCHANTING, key = "k" } }
            local v = ns.Routes.Divert({ classID = 7, subclassID = 12, count = 5 },
                { action = "keep", reason = "your Enchanting needs it" }, nil, ns.Valuation.DEFAULTS, routes)
            assert.equal("mail", v.action)
        end)

        it("the price cap: at or above it the normal rule applies; unknown or stale prices don't count", function()
            local route = { to = BOB, profession = ENCHANTING, key = "k", cap = 50000 }
            local item = { classID = 7, subclassID = 12, count = 20, stacks = 1, vendor = 2 }
            local D = ns.Valuation.DEFAULTS
            local v, capped = ns.Routes.Divert(item, { action = "mail", route = "ah" }, { ah = 50000, age = 0 }, D, { route })
            assert.is_nil(v)
            assert.equal(route, capped)
            v = ns.Routes.Divert(item, { action = "mail", route = "ah" }, { ah = 49999, age = 0 }, D, { route })
            assert.equal(BOB, v.to)
            assert.equal(49999, v.ahUnit)
            v = ns.Routes.Divert(item, { action = "keep", reason = "price too old (9 days)" }, { ah = 90000, age = 9 }, D, { route })
            assert.equal(BOB, v.to, "a stale price can't cap")
            v = ns.Routes.Divert(item, { action = "keep", reason = "no price" }, { ah = nil }, D, { route })
            assert.equal(BOB, v.to)
            route.cap = nil
            v = ns.Routes.Divert(item, { action = "mail", route = "ah" }, { ah = 10000000, age = 0 }, D, { route })
            assert.equal(BOB, v.to, "no cap: everything goes")
        end)

        it("the cap stepper walks the steps and ends in 'no cap'", function()
            assert.equal(100000, ns.Routes.NextCap(50000, 1))
            assert.equal(20000, ns.Routes.NextCap(50000, -1))
            assert.is_nil(ns.Routes.NextCap(1000000, 1), "past the top: no cap")
            assert.equal(1000000, ns.Routes.NextCap(nil, -1))
            assert.is_nil(ns.Routes.NextCap(nil, 1))
            assert.equal(5000, ns.Routes.NextCap(5000, -1))
            assert.equal(100000, ns.Routes.NextCap(42000, 1), "from the nearest step (5g)")
            assert.equal("to my alt at 5g each or more", ns.Routes.CapText({ cap = 50000 }))
            assert.equal("no price cap", ns.Routes.CapText({}))
        end)
    end)

    describe("saved bindings", function()
        it("adds for all my characters by default, refuses this character, unknown professions and duplicates", function()
            local r, err = ns.Routes.Add("Bob Surname-Classic Beta PvP", ENCHANTING)
            assert.truthy(r, err)
            assert.equal(BOB, r.to)
            assert.equal("account", r.scope)
            assert.equal(50000, r.cap, "5g each by default")
            assert.equal(1, #MailworthyDB.routes["Classic Beta PvP|Alliance"])
            assert.is_nil(ns.Routes.Add("Rettana Quilwrit", TAILORING))
            local _, why = ns.Routes.Add("Rettana Quilwrit", TAILORING)
            assert.equal("that's this character", why)
            assert.is_nil(ns.Routes.Add(BOB, 186), "Mining has no materials")
            assert.is_nil(ns.Routes.Add("BOB SURNAME", ENCHANTING), "already bound")
            assert.truthy(ns.Routes.Add(BOB, TAILORING), "the same player can get another profession's materials")
            assert.equal(2, ns.Routes.Count())
        end)

        it("this character's bindings come first, move between scopes, step their cap, and go", function()
            ns.Routes.Add(BOB, ENCHANTING)
            local mine = ns.Routes.Add("Alice Other", ENCHANTING, { scope = "character" })
            assert.equal(1, #MailworthyCharDB.routes)
            local list = ns.Routes.List()
            assert.equal("Alice Other", list[1].to)
            assert.equal("character", list[1].scope)
            assert.equal(BOB, list[2].to)
            assert.is_true(ns.Routes.ToggleScope(mine.key))
            assert.equal(0, #MailworthyCharDB.routes)
            assert.equal(2, #MailworthyDB.routes["Classic Beta PvP|Alliance"])
            assert.equal("account", ns.Routes.Get(mine.key).scope)
            ns.Routes.StepCap(mine.key, 1)
            assert.equal(100000, ns.Routes.Get(mine.key).cap)
            assert.is_true(ns.Routes.Remove(mine.key))
            assert.is_false(ns.Routes.Remove(mine.key))
            assert.equal(1, ns.Routes.Count())
            assert.truthy(log():find("unbound Enchanting materials to Alice Other", 1, true))
        end)

        it("survives a relog, per realm + faction", function()
            ns.Routes.Add(BOB, ENCHANTING)
            local saved, savedChar = MailworthyDB, MailworthyCharDB
            local ns2 = loadAddon()
            _G.MailworthyDB, _G.MailworthyCharDB = saved, savedChar
            ns2.Init()
            ns2.Fire("PLAYER_LOGIN")
            assert.equal(1, ns2.Routes.Count())
            WowStub.state.faction = "Horde"
            assert.equal(0, ns2.Routes.Count(), "another faction can't mail Bob")
        end)

        it("Skip once drops a binding until the mailbox closes", function()
            local r = ns.Routes.Add(BOB, ENCHANTING)
            ns.Routes.SkipOnce(r.key)
            assert.is_true(ns.Routes.Skipped(r.key))
            assert.equal(0, #ns.Routes.Active())
            assert.equal(1, ns.Routes.Count(), "still saved")
            ns.Routes.Unskip(r.key)
            assert.equal(1, #ns.Routes.Active())
            ns.Routes.SkipOnce(r.key)
            ns.Fire("MAIL_CLOSED")
            assert.is_false(ns.Routes.Skipped(r.key))
        end)
    end)

    describe("in the scan and the mail", function()
        before_each(function()
            withAuctionator()
            WowStub.setBag(0, 1, dust(20))
            prices[WowStub.link(10940, "Strange Dust")] = 500
            WowStub.setBag(0, 2, cloth(20))
            prices[WowStub.link(2589, "Linen Cloth")] = 174
            MailFrame:Show()
            SendMailFrame:Show()
        end)

        it("a bound profession's materials are mailed to the friend whatever they're worth", function()
            prices[WowStub.link(10940, "Strange Dust")] = 3 -- the rule would keep it
            local before = ns.Bags.Evaluate()
            assert.equal(1, #before.mail, "only the cloth")
            ns.Routes.Add(BOB, ENCHANTING)
            local result = ns.Bags.Evaluate()
            assert.equal(2, #result.mail)
            local d
            for _, item in ipairs(result.mail) do if item.itemID == 10940 then d = item end end
            assert.equal("friend", d.result.route)
            assert.equal(BOB, d.result.to)
            assert.equal(1, result.totals.routed)
            assert.equal(2, result.totals.mails, "one to the bank alt, one to Bob")
            assert.same({ "", BOB }, result.totals.recipients)
            assert.equal(before.totals.gain, result.totals.gain, "a gift isn't a gain")
            local report = ns.Bags.Report(result)
            assert.truthy(report:find("binding: Enchanting materials to Bob Surname (to my alt at 5g each or more)", 1, true), report)
            assert.truthy(report:find("MAIL FRIEND [Strange Dust] x20: Enchanting materials go to Bob Surname", 1, true), report)
            assert.truthy(report:find("1 stacks to friends", 1, true), report)
        end)

        it("several recipients: one To line each with what and how many mails; the Mailing list grouped", function()
            ns.Routes.Add(BOB, ENCHANTING)
            WowStub.setBag(0, 3, WowStub.item(2592, "Wool Cloth", { count = 10, sell = 33, class = 7, subclass = 5 }))
            prices[WowStub.link(2592, "Wool Cloth")] = 9000
            ns.MailWindow.Show("send")
            local result = ns.MailWindow.Result()
            assert.same({ "", BOB }, result.totals.recipients)
            assert.equal(1, result.totals.byRecipient[BOB].mails)
            assert.same({ "Enchanting materials" }, { result.totals.byRecipient[BOB].what[1] })
            assert.is_nil(result.mail[1].result.to, "the bank alt's items first ...")
            assert.equal(BOB, result.mail[#result.mail].result.to, "... then Bob's")
            local texts = ns.MailWindow.Texts()
            assert.equal("|cffffd100To:|r Roknua Themicrulah", texts.to[1])
            assert.equal("Bob Surname | Enchanting materials · 1 mail", texts.to[2])
            assert.equal("Send to Roknua, Bob", _G.MailworthyMailSend.text)
            local lines = ns.MailWindow.Recipients(result.totals, "Roknua Themicrulah", false)
            assert.equal("your bank alt · 1 mail", lines[1].note)
        end)

        it("one recipient: the To line as before; a friend alone is named first", function()
            local lines = ns.MailWindow.Recipients({ recipients = {} }, "Roknua Themicrulah", false)
            assert.same({ { name = "Roknua Themicrulah", note = "your bank alt" } }, lines)
            lines = ns.MailWindow.Recipients({ recipients = { BOB }, byRecipient = { [BOB] = { mails = 2,
                what = { "Tailoring materials" }, crafter = true } } }, "Roknua Themicrulah", false)
            assert.same({ { name = BOB, note = "Tailoring materials (their crafter)" } }, lines)
            local many = { recipients = { "", "A", "B", "C" }, byRecipient = {} }
            for _, k in ipairs(many.recipients) do many.byRecipient[k] = { mails = 1, what = {} } end
            assert.equal(4, #ns.MailWindow.Recipients(many, "Roknua Themicrulah", false))
            assert.truthy(ns.MailWindow.Layout({ to = 2, routes = 1, mail = 3, stay = 0 })
                > ns.MailWindow.Layout({ routes = 1, mail = 3, stay = 0 }))
        end)

        it("a locked material stays, and above the cap it goes to the bank alt", function()
            ns.Routes.Add(BOB, ENCHANTING)
            ns.Locks.ToggleItem(10940, "link", "spec")
            local result = ns.Bags.Evaluate()
            assert.equal(1, #result.mail)
            assert.equal("locked", result.keep[#result.keep].result.reason)
            ns.Locks.ToggleItem(10940, "link", "spec")
            prices[WowStub.link(10940, "Strange Dust")] = 60000
            result = ns.Bags.Evaluate()
            local d
            for _, item in ipairs(result.mail) do if item.itemID == 10940 then d = item end end
            assert.equal("bank", d.result.route, "the normal rule: enchanting materials are banked before the raids")
            assert.is_nil(d.result.to)
            assert.equal(BOB, d.result.capped.to)
            assert.truthy(ns.Bags.Report(result):find("not to Bob Surname: at or above the 5g cap", 1, true))
        end)

        it("Send mails the bank alt's mail first, then the friend's, with its own subject and body", function()
            ns.Routes.Add(BOB, ENCHANTING)
            local result = ns.Bags.Evaluate()
            local plan = ns.Mailer.Plan(result.mail, ns.Config.BankAlt())
            assert.equal(2, #plan)
            assert.equal("Roknua Themicrulah", plan[1].to)
            assert.is_nil(plan[1].what)
            assert.equal(BOB, plan[2].to)
            assert.equal("Enchanting materials", plan[2].what)
            assert.is_true(ns.Mailer.Start(result.mail, ns.Config.BankAlt()))
            WowStub.runTimers()
            ns.Fire("MAIL_SEND_SUCCESS")
            WowStub.runTimers()
            ns.Fire("MAIL_SEND_SUCCESS")
            WowStub.runTimers()
            local sent = WowStub.state.sent
            assert.equal(2, #sent)
            assert.equal("Roknua Themicrulah", sent[1].name)
            assert.equal("Mailworthy 1/2", sent[1].subject)
            assert.equal(BOB, sent[2].name)
            assert.equal("Mailworthy 2/2: Enchanting materials", sent[2].subject)
            assert.equal("Your enchanting materials, sent by Rettana Quilwrit with Mailworthy.", sent[2].body)
            assert.equal(0, sent[2].money)
            assert.equal("Sent 2 mail(s), 2 stacks, to Roknua Themicrulah and Bob Surname.", ns.Mailer.Status())
            assert.equal(BOB, MailworthyDB.mailed[10940].to)
            assert.equal("friend", MailworthyDB.mailed[10940].route)
            assert.equal("Roknua Themicrulah", MailworthyDB.mailed[2589].to)
        end)

        it("friends' mails go without a bank alt; a binding to this character blocks everything", function()
            MailworthyDB.bankAlts = {}
            ns.Routes.Add(BOB, ENCHANTING)
            ns.Routes.Add(BOB, TAILORING)
            local result = ns.Bags.Evaluate()
            assert.equal(2, #result.mail)
            assert.is_true(ns.Mailer.Start(result.mail, nil))
            WowStub.runTimers()
            assert.equal(BOB, WowStub.state.sent[1].name)
            ns.Fire("MAIL_SEND_SUCCESS")
            WowStub.runTimers()
            ns.Fire("MAIL_SEND_SUCCESS")
            WowStub.runTimers()
            assert.equal(2, #WowStub.state.sent)
            -- a saved binding that points at this character (e.g. made on another character for this one)
            MailworthyDB.routes["Classic Beta PvP|Alliance"][1].to = "Rettana Quilwrit"
            WowStub.setBag(0, 1, dust(20))
            result = ns.Bags.Evaluate()
            assert.is_false(ns.Mailer.Start(result.mail, "Roknua Themicrulah"))
            assert.truthy(ns.Mailer.Status():find("a binding points at this character", 1, true))
        end)

        it("names the recipients", function()
            assert.equal("nobody", ns.Mailer.Recipients({}))
            assert.equal("A", ns.Mailer.Recipients({ { to = "A" }, { to = "a" } }))
            assert.equal("A, B and C", ns.Mailer.Recipients({ { to = "A" }, { to = "B" }, { to = "C" } }))
            assert.equal("B", ns.Mailer.Recipients({ { to = "A", attached = {} }, { to = "B", attached = {}, sent = true } }, true))
        end)

        it("the bank alt's tags ignore bindings: they say what the market says", function()
            ns.Routes.Add(BOB, ENCHANTING)
            MailworthyDB.bankAlts["Classic Beta PvP|Alliance"] = "Rettana Quilwrit"
            local result = ns.BankAlt.Refresh()
            for _, item in ipairs(result.mail) do assert.is_nil(item.result.to) end
        end)
    end)

    describe("who can be bound", function()
        it("party members, the guild (C_Club: professions, presence, realm suffix), own characters; online first", function()
            WowStub.state.group = { members = { { name = "Pal Member", level = 20, online = true, class = "Rogue" } } }
            WowStub.state.guild = { clubId = 3, members = {
                { name = "Bob Surname", realm = "Classic Beta PvP", level = 30, online = true, professions = { ENCHANTING, 186 } },
                { name = "Zed Offline", level = 60, online = false, professions = { TAILORING, ALCHEMY } },
                { name = "Rettana Quilwrit", level = 8, online = true },
            } }
            MailworthyDB.characters[ns.Characters.Key("Alt Mine", "Classic Beta PvP", "Alliance")] = {
                name = "Alt Mine", realm = "Classic Beta PvP", faction = "Alliance", class = "MAGE", level = 12,
                professions = { { name = "Tailoring", skillLine = TAILORING } },
            }
            local list = ns.Routes.Candidates()
            local names = {}
            for i, c in ipairs(list) do names[i] = c.name end
            assert.same({ "Pal Member", "Bob Surname", "Alt Mine", "Zed Offline" }, names)
            assert.is_true(list[1].sources.party)
            assert.is_true(list[2].sources.guild)
            assert.same({ ENCHANTING }, list[2].professions, "Mining isn't suggested")
            assert.equal("Bob Surname - Enchanting - online - guild", ns.Routes.CandidateText(list[2]))
            assert.equal("Alt Mine - Tailoring - my character", ns.Routes.CandidateText(list[3]))
            assert.equal("Zed Offline - Alchemy, Tailoring - guild", ns.Routes.CandidateText(list[4]))
            assert.same({ { id = ALCHEMY, name = "Alchemy" }, { id = TAILORING, name = "Tailoring" } }, ns.Routes.Suggested(list[4]))
        end)

        it("falls back to GetGuildRosterInfo when the club has no members, and asks for the roster at most every 10 s", function()
            WowStub.state.guild = { clubId = 3, club = false, members = { { name = "Old Roster", level = 40, online = true } } }
            local list = ns.Routes.Candidates()
            assert.equal(1, #list)
            assert.equal("Old Roster", list[1].name)
            assert.is_true(list[1].online)
            ns.Routes.RequestRoster()
            ns.Routes.RequestRoster()
            assert.equal(1, WowStub.state.rosterRequests)
            WowStub.state.now = WowStub.state.now + 11
            ns.Routes.RequestRoster()
            assert.equal(2, WowStub.state.rosterRequests)
        end)

        it("a raid lists everyone but this character; an empty world lists nobody", function()
            WowStub.state.group = { raid = true, members = { { name = "Rettana Quilwrit" }, { name = "Raider One", online = false } } }
            local list = ns.Routes.Candidates()
            assert.equal(1, #list)
            assert.equal("Raider One", list[1].name)
            assert.is_false(list[1].online)
            WowStub.state.group = nil
            assert.equal(0, #ns.Routes.Candidates())
        end)
    end)

    describe("hellos between Mailworthys", function()
        it("encodes this character's crafting professions and the account's crafters; decodes only what it knows", function()
            local hello = ns.Comms.Encode({ { skillLine = ENCHANTING }, { skillLine = 186 }, TAILORING }, {
                { name = "Alice Alt", professions = { { skillLine = 165 }, { skillLine = 186 } } },
                { name = "Miner Only", professions = { { skillLine = 186 } } },
                { name = "Cook Two-Realm", professions = { 185 } },
            })
            assert.equal("H2|197,333|Alice Alt=165;Cook Two=185", hello)
            assert.same({ kind = "hello", version = 2, professions = { 197, 333 },
                characters = { { name = "Alice Alt", professions = { 165 } }, { name = "Cook Two", professions = { 185 } } } },
                ns.Comms.Decode(hello))
            assert.same({ kind = "hello", version = 2, professions = {}, characters = {} }, ns.Comms.Decode("H2||"))
            assert.same({ kind = "ask", version = 2 }, ns.Comms.Decode("A2"))
            assert.is_nil(ns.Comms.Decode("hello there"))
            assert.is_nil(ns.Comms.Decode(("H2|" .. string.rep("x", 300))))
            assert.same({ 333 }, ns.Comms.Decode("H2|999,333|").professions, "unknown skill lines are dropped")
            assert.same({}, ns.Comms.Decode("H2|333|Some One=999;=165;Bad=Name").characters, "junk characters are dropped")
            assert.is_nil(ns.Comms.Decode("H2|333,abc|"), "not a number list: not a hello")
            local many = {}
            for i = 1, 20 do many[i] = { name = "Character Number" .. i, professions = { 165 } } end
            assert.is_true(#ns.Comms.Encode({}, many) <= 255, "never over the addon-message limit")
        end)

        it("says hello to the guild and group after login and when the group changes, naming the account's crafters", function()
            WowStub.state.guild = { clubId = 3, members = {} }
            WowStub.state.group = { members = { { name = "Pal Member" } } }
            WowStub.state.professions[2] = { index = 9, name = "Enchanting", rank = 1, maxRank = 75, skillLine = ENCHANTING }
            MailworthyDB.characters[ns.Characters.Key("Alt Mine", "Classic Beta PvP", "Alliance")] = {
                name = "Alt Mine", realm = "Classic Beta PvP", faction = "Alliance", class = "MAGE", level = 12,
                professions = { { name = "Leatherworking", skillLine = 165 } },
            }
            MailworthyDB.characters[ns.Characters.Key("Horde Guy", "Classic Beta PvP", "Horde")] = {
                name = "Horde Guy", realm = "Classic Beta PvP", faction = "Horde", professions = { { skillLine = 197 } },
            }
            assert.is_true(WowStub.state.prefixes.Mailworthy, "prefix registered at login")
            WowStub.runTimers(10)
            local sent = WowStub.state.addonMessages
            assert.equal(4, #sent, "a hello and the skills, on each channel")
            assert.equal("GUILD", sent[1].channel)
            assert.equal("PARTY", sent[2].channel)
            assert.equal("H2|333|Alt Mine=165", sent[1].message, "the other faction's character can't be mailed")
            assert.equal("Mailworthy", sent[1].prefix)
            assert.equal("S2|333:1|", sent[3].message, "Alt Mine's skill isn't known: left out")
            ns.Fire("GROUP_ROSTER_UPDATE")
            assert.equal(4, #sent, "throttled: 10 s between hellos")
            WowStub.state.now = WowStub.state.now + 11
            ns.Fire("GROUP_ROSTER_UPDATE")
            assert.equal(8, #sent)
        end)

        it("remembers who said hello, answers an ask, drops junk, and forgets after 60 days", function()
            WowStub.state.guild = { clubId = 3, members = {} }
            ns.Fire("CHAT_MSG_ADDON", "Mailworthy", "H2|333,197|Alice Alt=165;Bob Surname=171", "GUILD", "Bob Surname-Classic Beta PvP")
            local peer = ns.Comms.Peer("bob surname")
            assert.equal(BOB, peer.name)
            assert.same({ 333, 197 }, peer.professions)
            assert.same({ { name = "Alice Alt", professions = { 165 } } }, peer.characters, "never the sender itself")
            assert.equal(1, WowStub.state.serverTime - peer.at + 1)
            ns.Fire("CHAT_MSG_ADDON", "OtherAddon", "H2|333|", "GUILD", "Someone Else")
            assert.is_nil(ns.Comms.Peer("Someone Else"))
            ns.Fire("CHAT_MSG_ADDON", "Mailworthy", "garbage", "GUILD", "Someone Else")
            assert.is_nil(ns.Comms.Peer("Someone Else"))
            ns.Fire("CHAT_MSG_ADDON", "Mailworthy", "H2|333|", "GUILD", "Rettana Quilwrit")
            assert.is_nil(ns.Comms.Peer("Rettana Quilwrit"), "not itself")
            local before = #WowStub.state.addonMessages
            WowStub.state.now = WowStub.state.now + 11
            ns.Fire("CHAT_MSG_ADDON", "Mailworthy", "A2", "GUILD", "Bob Surname")
            assert.equal(before + 2, #WowStub.state.addonMessages, "an ask gets a hello (and the skills)")
            local candidates = ns.Routes.Candidates()
            assert.equal(BOB, candidates[1].name)
            assert.equal("Bob Surname - Enchanting, Tailoring - Mailworthy", ns.Routes.CandidateText(candidates[1]))
            local report = table.concat(ns.Comms.ReportLines(), "\n")
            assert.truthy(report:find("mailworthy peer: Bob Surname (Enchanting, Tailoring; skills: not sent; "
                .. "other characters: Alice Alt = Leatherworking", 1, true), report)
            ns.Comms.Prune(WowStub.state.serverTime + 61 * 86400)
            assert.is_nil(ns.Comms.Peer(BOB))
        end)

        it("/mw feature comms off: nothing is sent or heard", function()
            MailworthyDB.features.comms = false
            WowStub.state.guild = { clubId = 3, members = {} }
            WowStub.runTimers(10)
            assert.equal(0, #WowStub.state.addonMessages)
            ns.Fire("CHAT_MSG_ADDON", "Mailworthy", "H2|333|", "GUILD", "Bob Surname")
            assert.is_nil(ns.Comms.Peer(BOB))
        end)

        it("delivery follows the profession: the friend when they have it, else their character that does", function()
            local route = { to = BOB, profession = ENCHANTING }
            assert.same({ BOB, false }, { ns.Routes.Crafter(route, nil) }, "nothing known: the friend")
            local alice = { name = "Alice Alt", professions = { 333 } }
            assert.same({ BOB, false }, { ns.Routes.Crafter(route, { professions = { 333 }, characters = { alice } }) },
                "the friend has it: the friend, whatever their alts have")
            assert.same({ "Alice Alt", true }, { ns.Routes.Crafter(route, { professions = { 197 },
                characters = { { name = "Miner Guy", professions = { 165 } }, { name = "Alice Alt", professions = { 333 } } } }) })
            local leather = { name = "Alice Alt", professions = { 165 } }
            assert.same({ BOB, false }, { ns.Routes.Crafter(route, { professions = {}, characters = { leather } }) },
                "nobody of theirs has it: the friend, never an alt for the AH")
        end)

        it("a binding's mail goes to the friend's crafter once their Mailworthy has said who that is", function()
            withAuctionator()
            WowStub.setBag(0, 1, dust(20))
            MailFrame:Show()
            SendMailFrame:Show()
            local r = ns.Routes.Add(BOB, ENCHANTING)
            assert.equal(BOB, (ns.Routes.Recipient(ns.Routes.Get(r.key))), "nothing heard: to Bob himself")
            ns.Fire("CHAT_MSG_ADDON", "Mailworthy", "H2|165|Alice Alt=333", "GUILD", BOB)
            local to, crafter = ns.Routes.Recipient(ns.Routes.Get(r.key))
            assert.equal("Alice Alt", to)
            assert.is_true(crafter)
            local result = ns.Bags.Evaluate()
            assert.equal("Alice Alt", result.mail[1].result.to)
            assert.truthy(ns.Bags.Report(result):find("delivered to their crafter Alice Alt", 1, true))
            ns.Mailer.Start(result.mail, ns.Config.BankAlt())
            WowStub.runTimers()
            assert.equal("Alice Alt", WowStub.state.sent[1].name)
            assert.truthy(table.concat(ns.Routes.ReportLines(), "\n"):find("delivered to their crafter Alice Alt", 1, true))
            ns.Fire("CHAT_MSG_ADDON", "Mailworthy", "H2|333|Alice Alt=333", "GUILD", BOB)
            assert.equal(BOB, (ns.Routes.Recipient(ns.Routes.Get(r.key))), "Bob learned Enchanting: to Bob")
        end)
    end)

    describe("the friends window", function()
        before_each(function()
            WowStub.state.guild = { clubId = 3, members = {
                { name = "Bob Surname", level = 30, online = true, professions = { ENCHANTING } },
                { name = "Zed Offline", level = 60, online = false },
            } }
        end)

        it("opens from /mw friends and the settings; picks a player, then a profession (theirs suggested)", function()
            ns.HandleSlash("friends")
            local f = ns.RoutesUI.Frame()
            assert.is_true(f:IsShown())
            assert.equal(1, WowStub.state.rosterRequests)
            assert.equal("A2", WowStub.state.addonMessages[1].message, "asks other Mailworthys to say hello")
            assert.equal("Bob Surname - Enchanting - online - guild", _G.MailworthyFriendsPick1:GetText())
            assert.is_true(_G.MailworthyFriendsPick2:IsShown())
            assert.is_false(_G.MailworthyFriendsProfession1:IsShown())
            _G.MailworthyFriendsPick1:Click()
            assert.is_false(_G.MailworthyFriendsPick1:IsShown())
            assert.truthy(_G.MailworthyFriendsProfession4:GetText()
                :find("> Enchanting (dust, essences, shards, green and blue gear) <", 1, true))
            assert.equal("Alchemy (herbs)", _G.MailworthyFriendsProfession1:GetText())
            _G.MailworthyFriendsProfession4:Click()
            local r = ns.Routes.List()[1]
            assert.equal(BOB, r.to)
            assert.equal(ENCHANTING, r.profession)
            assert.truthy(table.concat(WowStub.printed, "\n"):find("Enchanting materials now go to Bob Surname", 1, true))
            assert.equal("list", ns.RoutesUI.View(), "a binding returns to the bindings")
            assert.is_false(_G.MailworthyFriendsPick1:IsShown())
            assert.is_true(_G.MailworthyFriendsRemove1:IsShown())
            assert.equal("5g each or more: to my bank alt", ns.RoutesUI.CapText(r))
            assert.equal("no price cap", ns.RoutesUI.CapText({}))
            f:Hide()
            ns.SettingsUI.Show()
            assert.equal("Friends (1 binding)...", _G.MailworthySettingsFriends:GetText())
            _G.MailworthySettingsFriends:Click()
            assert.is_true(f:IsShown())
        end)

        it("each binding row: cap stepper, scope, where the mail goes, and Remove", function()
            ns.RoutesUI.Show()
            _G.MailworthyFriendsPick1:Click()
            _G.MailworthyFriendsProfession4:Click()
            assert.equal("All my characters", _G.MailworthyFriendsScope1:GetText())
            assert.is_nil(_G.MailworthyFriendsVia1, "no delivery toggle: the profession decides")
            _G.MailworthyFriendsCapUp1:Click()
            _G.MailworthyFriendsCapUp1:Click()
            assert.equal(250000, ns.Routes.List()[1].cap)
            _G.MailworthyFriendsScope1:Click()
            assert.equal("This character", _G.MailworthyFriendsScope1:GetText())
            assert.equal(1, #MailworthyCharDB.routes)
            ns.Fire("CHAT_MSG_ADDON", "Mailworthy", "H2|165|Alice Alt=333", "GUILD", BOB)
            ns.MailWindow.Show("send")
            assert.truthy(_G.MailworthyMailSkip1:IsShown())
            local to = ns.Routes.Recipient(ns.Routes.List()[1])
            assert.equal("Alice Alt", to)
            _G.MailworthyFriendsRemove1:Click()
            assert.equal(0, ns.Routes.Count())
            assert.is_true(_G.MailworthyFriendsRemove1:IsShown() == false)
        end)

        it("with bindings it opens on the list; Add a binding... and Back move between the views", function()
            ns.Routes.Add(BOB, ENCHANTING)
            ns.RoutesUI.Show()
            assert.equal("list", ns.RoutesUI.View())
            assert.is_true(_G.MailworthyFriendsRemove1:IsShown())
            assert.is_true(_G.MailworthyFriendsAdd:IsShown())
            assert.is_false(_G.MailworthyFriendsPick1:IsShown(), "the player list waits behind Add a binding")
            assert.is_false(_G.MailworthyFriendsBack:IsShown())
            _G.MailworthyFriendsAdd:Click()
            assert.equal("add", ns.RoutesUI.View())
            assert.is_true(_G.MailworthyFriendsPick1:IsShown())
            assert.is_false(_G.MailworthyFriendsRemove1:IsShown())
            assert.is_false(_G.MailworthyFriendsAdd:IsShown())
            _G.MailworthyFriendsPick1:Click()
            assert.is_true(_G.MailworthyFriendsProfession1:IsShown())
            _G.MailworthyFriendsBack:Click()
            assert.is_true(_G.MailworthyFriendsPick1:IsShown(), "Back from step 2: step 1")
            _G.MailworthyFriendsBack:Click()
            assert.equal("list", ns.RoutesUI.View(), "Back from step 1: the list")
            assert.is_true(_G.MailworthyFriendsRemove1:IsShown())
        end)

        it("Back returns to the list; a second binding for the same player and profession is refused", function()
            ns.RoutesUI.Show()
            _G.MailworthyFriendsPick1:Click()
            _G.MailworthyFriendsBack:Click()
            assert.is_true(_G.MailworthyFriendsPick1:IsShown())
            ns.Routes.Add(BOB, ENCHANTING)
            _G.MailworthyFriendsPick1:Click()
            _G.MailworthyFriendsProfession4:Click()
            assert.equal(1, ns.Routes.Count())
            assert.is_false(_G.MailworthyFriendsPick1:IsShown(), "stays on the profession step after a refusal")
        end)

        it("controller: D-pad reaches the player buttons, Cross picks, Circle closes", function()
            WowStub.state.gamepadUI = true
            ns.RoutesUI.Show()
            local watcher = _G.MailworthyPadWatcher
            watcher.scripts.OnUpdate(watcher, 0.2)
            assert.equal("CLICK MailworthyPadCross:LeftButton", WowStub.state.bindings.PAD1)
            local reachable = false
            for _, c in ipairs(ns.Nav.Candidates()) do
                if c.button == _G.MailworthyFriendsPick1 then reachable = true end
            end
            assert.is_true(reachable)
            ns.Nav.Select(_G.MailworthyFriendsPick1)
            WowStub.state.now = WowStub.state.now + 1
            _G.MailworthyPadCross:Click()
            assert.equal(BOB, ns.RoutesUI.Picked().name)
            WowStub.state.now = WowStub.state.now + 1
            _G.MailworthyPadCircle:Click()
            assert.is_false(ns.RoutesUI.Frame():IsShown())
        end)
    end)

    describe("the Mailworthy window", function()
        before_each(function()
            withAuctionator()
            WowStub.setBag(0, 1, dust(20))
            prices[WowStub.link(10940, "Strange Dust")] = 500
            WowStub.setBag(0, 2, cloth(20))
            prices[WowStub.link(2589, "Linen Cloth")] = 174
            MailFrame:Show()
            SendMailFrame:Show()
        end)

        it("shows each binding with Skip once and Remove, the friend on the item's chip, and every recipient on Send", function()
            ns.MailWindow.Show("send")
            assert.is_false(_G.MailworthyMailSkip1:IsShown())
            assert.equal("Send to Roknua", _G.MailworthyMailSend:GetText())
            ns.Routes.Add(BOB, ENCHANTING)
            ns.MailWindow.Refresh()
            assert.is_true(_G.MailworthyMailSkip1:IsShown())
            assert.equal("Skip once", _G.MailworthyMailSkip1:GetText())
            assert.equal("Send to Roknua, Bob", _G.MailworthyMailSend:GetText())
            local result = ns.MailWindow.Result()
            assert.equal(2, #result.mail)
            local dustTo
            for _, item in ipairs(result.mail) do if item.itemID == 10940 then dustTo = item.result.to end end
            assert.equal(BOB, dustTo)
            _G.MailworthyMailSkip1:Click()
            assert.equal("Undo skip", _G.MailworthyMailSkip1:GetText())
            assert.equal("Send to Roknua", _G.MailworthyMailSend:GetText())
            for _, item in ipairs(ns.MailWindow.Result().mail) do assert.is_nil(item.result.to) end
            _G.MailworthyMailSkip1:Click()
            assert.equal("Send to Roknua, Bob", _G.MailworthyMailSend:GetText())
            assert.is_true(_G.MailworthyMailFriends:IsShown())
            _G.MailworthyMailFriends:Click()
            assert.is_true(ns.RoutesUI.Frame():IsShown())
            ns.RoutesUI.Frame():Hide()
            _G.MailworthyMailUnbind1:Click()
            assert.equal(0, ns.Routes.Count())
            assert.is_false(_G.MailworthyMailSkip1:IsShown())
            assert.is_false(_G.MailworthyMailFriends:IsShown(), "no bindings: no bindings block (Friends is in Settings)")
        end)

        it("Send from the window mails the friend too, and the window re-scans afterwards", function()
            ns.Routes.Add(BOB, ENCHANTING)
            ns.MailWindow.Show("send")
            _G.MailworthyMailSend:Click()
            WowStub.runTimers()
            ns.Fire("MAIL_SEND_SUCCESS")
            WowStub.runTimers()
            ns.Fire("MAIL_SEND_SUCCESS")
            WowStub.runTimers()
            assert.equal(2, #WowStub.state.sent)
            assert.equal(BOB, WowStub.state.sent[2].name)
            ns.Fire("BAG_UPDATE_DELAYED")
            assert.equal(0, #ns.MailWindow.Result().mail)
        end)

        it("/mw report lists the bindings", function()
            ns.Routes.Add(BOB, ENCHANTING)
            local text = ns.Report.Build()
            assert.truthy(text:find("binding: Enchanting materials to Bob Surname (all my characters, "
                .. "to my alt at 5g each or more, skill unknown)", 1, true), text)
            assert.truthy(text:find("comms=on", 1, true))
        end)
    end)
end)
