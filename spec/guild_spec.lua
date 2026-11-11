-- Guild template (operator, 2026-11-07): the guild master (or an officer) publishes rules,
-- one per crafting profession, each sending that profession's materials to one guild
-- member; members turn the guild rules on once, and off again in one press. Personal
-- bindings and this character's own professions come first.
local loadAddon = require("spec.support.load_addon")

describe("guild template", function()
    local ns, prices
    local ENCHANTING, TAILORING, ALCHEMY = 333, 197, 171
    local GM, OFFICER, MEMBER, BOB, ANN = "Guild Master", "Offi Cer", "Plain Member", "Bob Surname", "Ann Herbal"

    local function dust(count) return WowStub.item(10940, "Strange Dust", { count = count or 20, sell = 2, class = 7, subclass = 12 }) end
    local function herb(count) return WowStub.item(2447, "Peacebloom", { count = count or 20, sell = 1, class = 7, subclass = 9 }) end
    local function withAuctionator()
        prices = {}
        _G.Auctionator = { API = { v1 = {
            GetAuctionPriceByItemLink = function(_, l) return prices[l] end,
            GetAuctionAgeByItemLink = function() return 0 end,
        } } }
    end
    local function hear(sender, text, channel)
        ns.Fire("CHAT_MSG_ADDON", "Mailworthy", text, channel or "GUILD", sender)
    end
    --- `sender` passes on a copy written by `author` (default: the sender).
    local function publishFrom(sender, rev, rules, author)
        for _, m in ipairs(ns.Guild.Encode(rev, author or sender, rules)) do hear(sender, m) end
    end
    local function printed() return table.concat(WowStub.printed, "\n") end
    local REV = 1791900000 - 60
    local RULES = { { profession = ENCHANTING, to = BOB, cap = 50000 }, { profession = ALCHEMY, to = ANN } }

    before_each(function()
        ns = loadAddon()
        WowStub.state.guild = { clubId = 7, name = "Bank Of Azeroth", rank = 3, members = {
            { name = GM, rank = 0, online = true },
            { name = OFFICER, rank = 1, online = true },
            { name = MEMBER, rank = 3, online = true },
            { name = BOB, rank = 3, online = true, professions = { ENCHANTING } },
            { name = ANN, rank = 4, online = false, professions = { ALCHEMY } },
            { name = "Rettana Quilwrit", rank = 3, online = true },
        } }
        ns.Fire("PLAYER_LOGIN")
        ns.Config.SetBankAlt("Roknua Themicrulah")
        WowStub.state.addonMessages = {}
    end)
    after_each(function()
        _G.Auctionator = nil
        for _, line in ipairs(ns.Log.Lines()) do assert.is_nil(line:find("error", 1, true), line) end
        assert.equal(0, WowStub.focusCalls)
    end)

    describe("the wire", function()
        it("one message per rule, decoded back; junk is dropped", function()
            local msgs = ns.Guild.Encode(REV, GM, RULES)
            assert.same({ "T2|" .. REV .. "|Guild Master|1/2|333=Bob Surname:50000",
                "T2|" .. REV .. "|Guild Master|2/2|171=Ann Herbal:0" }, msgs)
            assert.same({ "T2|" .. REV .. "|Guild Master|0/0|" }, ns.Guild.Encode(REV, GM, {}))
            assert.same({ kind = "template", version = 2, part = { rev = REV, author = GM, index = 2, count = 2,
                rule = { profession = ALCHEMY, to = ANN } } }, ns.Comms.Decode(msgs[2]))
            assert.same({ kind = "templateAsk", version = 2, rev = REV }, ns.Comms.Decode("Q2|" .. REV))
            assert.same({ kind = "templateAsk", version = 2, rev = 0 }, ns.Comms.Decode("Q2|0"))
            for _, junk in ipairs({ "T2|1|A|1/2|999=Bob:0", "T2|1|A|3/2|333=Bob:0", "T2|1|A|1/9|333=Bob:0",
                "T2|1|A|0/0|333=Bob:0", "T2|1|A|1/1|333=Bob|x:0", "T2|1|A|1/1|333=:0", "T2|1|A|1/1|333=Bob:abc",
                "T2|12345678901|A|1/1|333=Bob:0", "T2|1|A|1/1|333=" .. string.rep("x", 60) .. ":0", "T2|1||1/1|333=Bob:0",
                "T2|1|1/1|333=Bob:0", "T2|1|" .. string.rep("x", 60) .. "|1/1|333=Bob:0", "Q2|x", "Q2|12345678901" }) do
                assert.is_nil(ns.Comms.Decode(junk), junk)
            end
            for _, m in ipairs(ns.Guild.Encode(REV, string.rep("A", 48),
                { { profession = ENCHANTING, to = string.rep("N", 48), cap = 1000000 } })) do
                assert.is_true(#m <= 255)
            end
        end)
    end)

    describe("the Enchanting rule's Gear switch", function()
        -- operator, 2026-11-11: "guild master sets it per rule"
        local GEAR = "de"

        it("travels as an odd cap, which a Mailworthy from before the switch reads as an ordinary rule", function()
            local G = ns.Guild
            assert.equal(1001, G.WireCap({ profession = ENCHANTING, cap = 1000, gear = GEAR }))
            assert.equal(1000, G.WireCap({ profession = ENCHANTING, cap = 1000 }))
            assert.equal(999999999, G.WireCap({ profession = ENCHANTING, gear = GEAR }), "the switch, no cap")
            assert.equal(0, G.WireCap({ profession = ENCHANTING }))
            assert.equal(1000, G.WireCap({ profession = ALCHEMY, cap = 1000, gear = GEAR }), "only Enchanting has the switch")
            assert.same({ 1000, GEAR }, { G.ReadCap(ENCHANTING, 1001) })
            assert.same({ nil, GEAR }, { G.ReadCap(ENCHANTING, 999999999) })
            assert.same({ 1000 }, { G.ReadCap(ENCHANTING, 1000) })
            assert.same({}, { G.ReadCap(ENCHANTING, 0) })
            assert.same({ 1001 }, { G.ReadCap(ALCHEMY, 1001) }, "another rule's cap is taken as it is")
            for _, cap in ipairs(ns.Routes.CAP_STEPS) do
                assert.same({ cap, GEAR }, { G.ReadCap(ENCHANTING, G.WireCap({ profession = ENCHANTING, cap = cap, gear = GEAR })) })
                assert.same({ cap }, { G.ReadCap(ENCHANTING, G.WireCap({ profession = ENCHANTING, cap = cap })) })
            end
            local msgs = G.Encode(REV, GM, { { profession = ENCHANTING, to = BOB, cap = 1000, gear = GEAR },
                { profession = ALCHEMY, to = ANN, gear = GEAR } })
            assert.same({ "T2|" .. REV .. "|Guild Master|1/2|333=Bob Surname:1001",
                "T2|" .. REV .. "|Guild Master|2/2|171=Ann Herbal:0" }, msgs)
            -- what v0.x's Guild.DecodePart matched a rule with: the message is still a rule to it
            local profession, name, cap = msgs[1]:match("|(%d+)=([^:]+):(%d+)$")
            assert.same({ "333", BOB, "1001" }, { profession, name, cap })
            assert.same({ profession = ENCHANTING, to = BOB, cap = 1000, gear = GEAR }, ns.Comms.Decode(msgs[1]).part.rule)
            assert.same({ profession = ENCHANTING, to = BOB, gear = GEAR },
                ns.Comms.Decode("T2|" .. REV .. "|Guild Master|1/1|333=Bob Surname:999999999").part.rule)
            assert.same({ profession = ENCHANTING, to = BOB, cap = 50000 },
                ns.Comms.Decode("T2|" .. REV .. "|Guild Master|1/1|333=Bob Surname:50000").part.rule, "a rule from before the switch")
        end)

        it("a member takes it with the template, mails by it, and passes it on unchanged", function()
            publishFrom(GM, REV, { { profession = ENCHANTING, to = BOB, cap = 10000, gear = GEAR } })
            local t = ns.Guild.Template()
            assert.equal(GEAR, t.rules[1].gear)
            assert.equal(10000, t.rules[1].cap)
            assert.truthy(printed():find("Enchanting to Bob Surname (gear only when disenchanting pays more)", 1, true), printed())
            assert.equal("1g each or more: to my bank alt; gear only when disenchanting pays more",
                ns.RoutesUI.GuildCapText(t.rules[1]))
            assert.equal("1g each or more: to my bank alt", ns.RoutesUI.GuildCapText({ profession = ENCHANTING, to = BOB, cap = 10000 }))
            ns.Guild.SetUse(true)
            assert.equal(GEAR, ns.Routes.List()[1].gear, "the guild rule is a binding with the switch on")
            -- a member looking at the guild view has no switch to press
            ns.RoutesUI.ShowGuild()
            assert.is_false(_G.MailworthyFriendsGear1:IsShown())
            ns.RoutesUI.Frame():Hide()
            -- the scan: gloves that sell for more go the normal way, the dust still goes to Bob
            withAuctionator()
            local gloves = WowStub.item(5001, "Sentry's Gloves", { quality = 2, level = 18, class = 4, sell = 310 })
            WowStub.setBag(0, 1, gloves)
            WowStub.setBag(0, 2, dust(20))
            prices[gloves.hyperlink], prices[WowStub.link(10940, "Strange Dust")] = 4200, 3
            _G.DisenchantValueAPI = { GetValue = function(l) return tostring(l):find("item:5001", 1, true) and 900 or nil end }
            finally(function() _G.DisenchantValueAPI = nil end)
            local to = {}
            for _, item in ipairs(ns.Bags.Evaluate().mail) do to[item.itemID] = item.result.to or "bank alt" end
            assert.same({ [5001] = "bank alt", [10940] = BOB }, to)
            -- any member passes the copy on: the odd cap goes out again
            WowStub.state.addonMessages = {}
            ns.Guild.Broadcast("spec", true)
            assert.equal("T2|" .. REV .. "|Guild Master|1/1|333=Bob Surname:10001", WowStub.state.addonMessages[1].message)
        end)

        it("a copy an older Mailworthy saved (the odd cap, no switch field) reads as the switch on after the update", function()
            -- Codex review, 2026-11-11: before the update the member's Mailworthy stored the rule as it
            -- travelled; the same revision must mean the same thing on every member's side afterwards
            local key = "Classic Beta PvP|Alliance|Bank Of Azeroth"
            MailworthyDB.guildTemplates = { [key] = { rev = REV, from = GM, at = REV, use = true, rules = {
                { profession = ENCHANTING, to = BOB, cap = 10001 }, { profession = ALCHEMY, to = ANN, cap = 5001 } } } }
            MailworthyDB.guildDrafts = { [key] = { rules = { { profession = ENCHANTING, to = BOB, cap = 999999999 } } } }
            local t = ns.Guild.Template()
            assert.same({ profession = ENCHANTING, to = BOB, cap = 10000, gear = GEAR }, t.rules[1])
            assert.same({ profession = ALCHEMY, to = ANN, cap = 5001 }, t.rules[2], "another profession's cap is left alone")
            assert.equal(GEAR, ns.Routes.List()[1].gear, "the guild rule applies with the switch on")
            WowStub.state.addonMessages = {}
            ns.Guild.Broadcast("spec", true)
            assert.equal("T2|" .. REV .. "|Guild Master|1/2|333=Bob Surname:10001", WowStub.state.addonMessages[1].message,
                "and goes out again as it came")
            WowStub.state.guild.rank = 0
            assert.same({ profession = ENCHANTING, to = BOB, gear = GEAR }, ns.Guild.Draft()[1], "a saved draft too: no cap, the switch on")
            -- the switch off never travels as an odd cap (a cap edited by hand)
            assert.equal(1000, ns.Guild.WireCap({ profession = ENCHANTING, cap = 1001 }))
        end)

        it("the guild master sets it in the editor: one press on the Enchanting rule, then Publish", function()
            WowStub.state.guild.rank = 0
            ns.Guild.DraftAdd(BOB, ENCHANTING)
            ns.Guild.DraftAdd(ANN, ALCHEMY)
            ns.Guild.Publish()
            assert.is_false(ns.Guild.DraftChanged())
            ns.RoutesUI.ShowGuild()
            -- the draft is sorted by profession name: Alchemy, then Enchanting
            assert.is_false(_G.MailworthyFriendsGear1:IsShown(), "the Alchemy rule has no switch")
            assert.is_true(_G.MailworthyFriendsGear2:IsShown())
            assert.equal("Gear: all green and blue", _G.MailworthyFriendsGear2:GetText())
            _G.MailworthyFriendsGear2:Click()
            assert.equal("Gear: only when disenchanting pays more", _G.MailworthyFriendsGear2:GetText())
            assert.is_true(ns.Widgets.IsToggled(_G.MailworthyFriendsGear2))
            assert.equal(GEAR, ns.Guild.Draft()[2].gear)
            assert.is_nil(ns.Guild.Template().rules[2].gear, "not published yet")
            assert.is_true(ns.Guild.DraftChanged(), "the switch alone is a change to publish")
            assert.equal("Publish to guild", _G.MailworthyFriendsPublish:GetText())
            assert.equal("Enchanting: gear only when disenchanting pays more. Publish to guild to send the change.",
                ns.RoutesUI.GearHint(ns.Guild.Draft()[2], true))
            -- a new player for the rule keeps the switch
            ns.Guild.DraftAdd(MEMBER, ENCHANTING)
            assert.equal(GEAR, ns.Guild.Draft()[2].gear)
            WowStub.state.addonMessages = {}
            _G.MailworthyFriendsPublish:Click()
            assert.equal("333=Plain Member:1001", WowStub.state.addonMessages[2].message:match("|([^|]+)$"))
            assert.equal(GEAR, ns.Guild.Template().rules[2].gear)
            assert.is_false(ns.Guild.DraftToggleGear(ALCHEMY), "no switch on another profession's rule")
            assert.is_true(ns.Guild.DraftToggleGear(ENCHANTING))
            assert.is_nil(ns.Guild.Draft()[2].gear)
        end)
    end)

    describe("receiving", function()
        it("takes the guild master's template, waits for the player's choice, and says so", function()
            publishFrom(GM, REV, RULES)
            local t = ns.Guild.Template()
            assert.equal(GM, t.from)
            assert.equal(2, #t.rules)
            assert.is_nil(t.use, "not chosen yet")
            assert.same({}, ns.Guild.Rules({}), "nothing applies until turned on")
            assert.equal(0, ns.Routes.Count())
            assert.truthy(printed():find("Guild Master shared a guild template (Alchemy to Ann Herbal, "
                .. "Enchanting to Bob Surname)", 1, true), printed())
        end)

        it("takes an officer's (rank 1), drops a member's, another channel's, and a stranger's", function()
            publishFrom(MEMBER, REV, RULES)
            assert.is_nil(ns.Guild.Template(), "a plain member can't publish")
            publishFrom(GM, REV, RULES)
            ns.Guild.Template().use = true
            for _, m in ipairs(ns.Guild.Encode(REV + 10, GM, {})) do hear(GM, m, "PARTY") end
            assert.equal(2, #ns.Guild.Template().rules, "only the GUILD channel carries templates")
            publishFrom("Not In Guild", REV + 20, {})
            assert.equal(2, #ns.Guild.Template().rules, "not in the roster: waits, not taken")
            publishFrom(OFFICER, REV + 30, { { profession = TAILORING, to = BOB } })
            assert.equal(OFFICER, ns.Guild.Template().from)
            assert.is_true(ns.Guild.Template().use, "the player's choice survives an update")
            assert.truthy(printed():find("Guild rules updated by Offi Cer: Tailoring to Bob Surname", 1, true))
            publishFrom(GM, REV + 5, RULES)
            assert.equal(OFFICER, ns.Guild.Template().from, "an older revision never replaces a newer one")
            publishFrom(GM, WowStub.state.serverTime + 1200, RULES)
            assert.equal(OFFICER, ns.Guild.Template().from, "a revision far in the future is refused")
        end)

        it("a sender the roster doesn't know yet is checked again when the roster arrives", function()
            local late = "Late Leader"
            publishFrom(late, REV, RULES)
            assert.is_nil(ns.Guild.Template())
            local before = WowStub.state.rosterRequests
            assert.is_true(before >= 1, "asked the game for the roster")
            table.insert(WowStub.state.guild.members, { name = late, rank = 0 })
            ns.Fire("GUILD_ROSTER_UPDATE")
            assert.equal(late, ns.Guild.Template().from)
        end)

        it("an empty template clears the rules", function()
            publishFrom(GM, REV, RULES)
            ns.Guild.SetUse(true)
            publishFrom(GM, REV + 1, {})
            assert.equal(0, #ns.Guild.Template().rules)
            assert.equal(0, ns.Routes.Count())
        end)

        it("any member passes a copy on: the author is checked, not the sender", function()
            publishFrom(MEMBER, REV, RULES, GM)
            local t = ns.Guild.Template()
            assert.equal(GM, t.from, "the author, not the member who passed it on")
            assert.equal(MEMBER, t.via)
            assert.truthy(printed():find("Guild Master shared a guild template (copy from Plain Member)", 1, true), printed())
            assert.truthy(ns.Report.Build():find("guild template: from Guild Master, copy from Plain Member", 1, true))
            publishFrom(MEMBER, REV + 1, {}, BOB)
            assert.equal(2, #ns.Guild.Template().rules, "a copy by a plain member is dropped, whoever passes it on")
            publishFrom("Not In Guild", REV + 2, {}, GM)
            assert.equal(2, #ns.Guild.Template().rules, "a sender outside the roster: waits, not taken")
        end)

        it("a rule for someone outside the guild is left out", function()
            publishFrom(GM, REV, { { profession = ENCHANTING, to = BOB }, { profession = TAILORING, to = "Outside Person" } })
            assert.equal(1, #ns.Guild.Template().rules)
            assert.equal(BOB, ns.Guild.Template().rules[1].to)
        end)

        it("everyone asks at login with the revision they hold; one holder of a newer copy answers", function()
            WowStub.runTimers(ns.Guild.ASK_DELAY)
            local asked
            for _, m in ipairs(WowStub.state.addonMessages) do
                if m.message:sub(1, 2) == "Q2" then asked = m end
            end
            assert.equal("Q2|0", asked.message)
            assert.equal("GUILD", asked.channel)
            publishFrom(GM, REV, RULES) -- this plain member now holds a copy
            WowStub.state.addonMessages = {}
            hear(BOB, "Q2|0")
            assert.equal(0, #WowStub.state.addonMessages, "a member waits a moment before answering")
            WowStub.runTimers(10)
            assert.equal(2, #WowStub.state.addonMessages, "then sends its copy")
            assert.equal("T2|" .. REV .. "|Guild Master|1/2|171=Ann Herbal:0", WowStub.state.addonMessages[1].message)
            WowStub.state.addonMessages = {}
            WowStub.state.now = WowStub.state.now + 31
            hear(ANN, "Q2|0")
            publishFrom(OFFICER, REV, RULES, GM) -- someone else answered first
            WowStub.runTimers(10)
            assert.equal(0, #WowStub.state.addonMessages, "one answer per ask, not the whole guild's")
            hear(ANN, "Q2|" .. REV)
            WowStub.runTimers(10)
            assert.equal(0, #WowStub.state.addonMessages, "nothing newer to give")
            WowStub.state.now = WowStub.state.now + 31
            hear(ANN, "Q2|" .. (REV + 5))
            assert.equal("Q2|" .. REV, WowStub.state.addonMessages[1].message, "a newer copy is out there: ask for it")
        end)

        it("a copy in the guild master's name they never published is corrected by their Mailworthy", function()
            WowStub.state.guild.rank = 0
            WowStub.state.name = GM
            WowStub.state.guild.members[1].name = GM
            ns.Guild.DraftAdd(BOB, ENCHANTING)
            ns.Guild.Publish()
            local real = ns.Guild.Template().rev
            WowStub.state.addonMessages = {}
            publishFrom(MEMBER, real + 100, { { profession = ENCHANTING, to = MEMBER } }, GM)
            local t = ns.Guild.Template()
            assert.equal(BOB, t.rules[1].to, "the forged copy isn't taken")
            assert.is_true(t.rev > real + 100, "the real one goes out again, newer than the forgery")
            assert.equal("T2|" .. t.rev .. "|Guild Master|1/1|333=Bob Surname:1000", WowStub.state.addonMessages[1].message)
            assert.truthy(printed():find("Plain Member passed on a guild template in your name", 1, true))
            publishFrom(MEMBER, t.rev, { { profession = ENCHANTING, to = BOB } }, GM)
            assert.equal(t.rev, ns.Guild.Template().rev, "its own real revision passed back is fine")
        end)

        it("a guild master who lost their saved data takes their own copy back", function()
            WowStub.state.guild.rank = 0
            WowStub.state.name = GM
            WowStub.state.guild.members[1].name = GM
            publishFrom(MEMBER, REV, RULES, GM)
            assert.equal(2, #ns.Guild.Template().rules)
            assert.equal(GM, ns.Guild.Template().from)
        end)

        it("/mw feature guildTemplate off: nothing is heard, asked or applied", function()
            publishFrom(GM, REV, RULES)
            ns.Guild.SetUse(true)
            MailworthyDB.features.guildTemplate = false
            assert.equal(0, ns.Routes.Count())
            publishFrom(GM, REV + 1, {})
            assert.equal(2, #ns.Guild.Template().rules)
            assert.is_false(ns.Guild.Ask("spec"))
        end)
    end)

    describe("applying", function()
        before_each(function()
            withAuctionator()
            WowStub.setBag(0, 1, dust(20))
            prices[WowStub.link(10940, "Strange Dust")] = 500
            WowStub.setBag(0, 2, herb(20))
            prices[WowStub.link(2447, "Peacebloom")] = 400
            publishFrom(GM, REV, RULES)
        end)

        it("turned on: each rule is a binding (scope guild) and the materials go to their member", function()
            ns.Guild.SetUse(true)
            local list = ns.Routes.List()
            assert.equal(2, #list)
            assert.equal("guild", list[1].scope)
            local result = ns.Bags.Evaluate()
            local to = {}
            for _, it in ipairs(result.mail) do to[it.itemID] = it.result.to end
            assert.equal(BOB, to[10940])
            assert.equal(ANN, to[2447])
            assert.truthy(table.concat(ns.Routes.ReportLines(), "\n"):find("guild template", 1, true))
            assert.truthy(ns.Report.Build():find("guild template: from Guild Master", 1, true))
        end)

        it("personal wins: own bindings, own professions and rules naming this character are left out", function()
            ns.Guild.SetUse(true)
            ns.Routes.Add("Other Enchanter", ENCHANTING)
            WowStub.state.professions[2] = { index = 9, name = "Alchemy", rank = 50, maxRank = 75, skillLine = ALCHEMY }
            local list = ns.Routes.List()
            assert.equal(1, #list, "only the personal binding")
            assert.equal("Other Enchanter", list[1].to)
            local report = ns.Report.Build()
            assert.truthy(report:find("guild rule left out: Enchanting to Bob Surname (your own binding comes first)", 1, true))
            assert.truthy(report:find("guild rule left out: Alchemy to Ann Herbal (you have Alchemy)", 1, true))
            publishFrom(GM, REV + 1, { { profession = TAILORING, to = "Rettana Quilwrit" } })
            assert.equal(1, ns.Routes.Count(), "a rule naming this character never applies")
        end)

        it("Skip once works on a guild rule; the mailbox window has no Remove for it", function()
            ns.Guild.SetUse(true)
            MailFrame:Show()
            SendMailFrame:Show()
            ns.MailWindow.Show("send")
            local key = ns.Routes.List()[1].key
            assert.is_true(_G.MailworthyMailSkip1:IsShown())
            assert.is_false(_G.MailworthyMailUnbind1:IsShown())
            _G.MailworthyMailSkip1:Click()
            assert.is_true(ns.Routes.Skipped(key))
            assert.is_false(ns.Routes.Remove(key), "a guild rule can't be removed, only turned off")
        end)

        it("one press turns the guild rules off: in the mailbox window", function()
            ns.Guild.SetUse(true)
            MailFrame:Show()
            SendMailFrame:Show()
            ns.MailWindow.Show("send")
            assert.is_true(_G.MailworthyMailGuildRules:IsShown())
            assert.equal("Guild rules: on", _G.MailworthyMailGuildRules:GetText())
            _G.MailworthyMailGuildRules:Click()
            assert.is_false(ns.Guild.InUse())
            assert.equal(0, ns.Routes.Count())
            for _, it in ipairs(ns.MailWindow.Result().mail) do assert.is_nil(it.result.to, "nothing to a guild member") end
            assert.is_false(_G.MailworthyMailGuildRules:IsShown())
        end)

        it("the settings' Guild button: Use guild rules, then one press off; Friends keeps only your own", function()
            -- 2026-11-07: "I want a new button for guild inside the mailworthy settings, seems weird its in
            -- the friends tab"
            WowStub.state.professions[2] = { index = 9, name = "Alchemy", rank = 50, maxRank = 75, skillLine = ALCHEMY }
            ns.SettingsUI.Show()
            assert.equal("Guild (new template)...", _G.MailworthySettingsGuild:GetText())
            _G.MailworthySettingsGuild:Click()
            assert.equal("guild", ns.RoutesUI.View())
            assert.equal("Use guild rules", _G.MailworthyFriendsGuildRules:GetText())
            assert.is_false(_G.MailworthyFriendsAdd:IsShown(), "a plain member can't edit")
            assert.is_false(_G.MailworthyFriendsPublish:IsShown())
            assert.is_false(_G.MailworthyFriendsBack:IsShown())
            _G.MailworthyFriendsGuildRules:Click()
            assert.is_true(ns.Guild.InUse())
            assert.equal("Guild rules: on", _G.MailworthyFriendsGuildRules:GetText())
            assert.equal("Guild (rules on)...", _G.MailworthySettingsGuild:GetText(), "the settings follow")
            assert.is_false(_G.MailworthyFriendsCapUp1:IsShown(), "a guild rule has no stepper for members")
            assert.is_false(_G.MailworthyFriendsRemove1:IsShown())
            assert.equal(1, ns.Routes.Count(), "Alchemy is left out here: this character has it")
            _G.MailworthyFriendsGuildRules:Click()
            assert.is_false(ns.Guild.InUse())
            assert.equal("Guild rules: off", _G.MailworthyFriendsGuildRules:GetText())
            assert.equal(0, ns.Routes.Count())
            ns.Guild.SetUse(true)
            ns.RoutesUI.Show()
            assert.equal("add", ns.RoutesUI.View(), "no own bindings: Friends opens on step 1; the guild's rules aren't in it")
            ns.HandleSlash("guild")
            assert.equal("guild", ns.RoutesUI.View(), "/mw guild")
        end)

        it("more guild rules than rows: the mailbox points at /mw guild, not Friends (Codex review)", function()
            publishFrom(GM, REV + 1, { { profession = ENCHANTING, to = BOB }, { profession = ALCHEMY, to = ANN },
                { profession = TAILORING, to = GM }, { profession = 164, to = MEMBER } })
            ns.Guild.SetUse(true)
            MailFrame:Show()
            SendMailFrame:Show()
            ns.MailWindow.Show("send")
            assert.equal(4, ns.Routes.Count())
            assert.truthy(_G.MailworthyMailSkip2:IsShown())
            assert.equal("|cffaaaaaa+ 2 more: guild rules, /mw guild|r", ns.MailWindow.MoreText(2, true))
            assert.equal("|cffaaaaaa+ 2 more: press Friends...|r", ns.MailWindow.MoreText(2, false))
            assert.is_false(_G.MailworthyMailSkip3:IsShown(), "the last row is the pointer")
        end)

        it("a rule naming the guild master is kept: members mail them too", function()
            publishFrom(GM, REV + 1, { { profession = TAILORING, to = GM } })
            ns.Guild.SetUse(true)
            local list = ns.Routes.List()
            assert.equal(1, #list)
            assert.equal(GM, list[1].to)
        end)
    end)

    describe("editing (guild master and officers)", function()
        before_each(function() WowStub.state.guild.rank = 0 end)

        it("the Guild window: Add a rule (yourself first, then guild members), cap, Publish to guild sends it", function()
            ns.SettingsUI.Show()
            _G.MailworthySettingsGuild:Click()
            assert.equal("guild", ns.RoutesUI.View())
            assert.is_false(_G.MailworthyFriendsGuildRules:IsShown(), "no template yet: nothing to turn on")
            assert.equal("Add a rule...", _G.MailworthyFriendsAdd:GetText())
            _G.MailworthyFriendsAdd:Click()
            assert.equal("add", ns.RoutesUI.View())
            assert.equal("guild", ns.RoutesUI.Target())
            -- 2026-11-07: "I should be able to set routing to me in the guild template as well"
            local me = ns.RoutesUI.Candidates()[1]
            assert.equal("Rettana Quilwrit", me.name)
            assert.is_true(me.sources.me)
            assert.truthy(_G.MailworthyFriendsPick1:GetText():find(" - you, guild", 1, true))
            for _, c in ipairs(ns.RoutesUI.Candidates()) do assert.is_true(c.sources.guild == true, c.name) end
            local bobAt
            for i, c in ipairs(ns.RoutesUI.Candidates()) do if c.name == BOB then bobAt = i end end
            _G["MailworthyFriendsPick" .. bobAt]:Click()
            _G.MailworthyFriendsProfession4:Click() -- Enchanting
            assert.equal("guild", ns.RoutesUI.View(), "a rule returns to the guild view")
            assert.equal(BOB, ns.Guild.Draft()[1].to)
            _G.MailworthyFriendsCapUp1:Click()
            assert.equal(2500, ns.Guild.Draft()[1].cap, "a new rule starts at 10s (2026-11-11); one step up: 25s")
            _G.MailworthyFriendsAdd:Click()
            _G.MailworthyFriendsPick1:Click() -- yourself
            _G.MailworthyFriendsProfession8:Click() -- Tailoring
            assert.equal("Rettana Quilwrit", ns.Guild.Draft()[2].to)
            assert.equal("Publish to guild", _G.MailworthyFriendsPublish:GetText())
            WowStub.state.addonMessages = {}
            _G.MailworthyFriendsPublish:Click()
            assert.equal(2, #WowStub.state.addonMessages)
            local head = "T2|" .. WowStub.state.serverTime .. "|Rettana Quilwrit|"
            assert.equal(head .. "1/2|333=Bob Surname:2500", WowStub.state.addonMessages[1].message)
            assert.equal(head .. "2/2|197=Rettana Quilwrit:1000", WowStub.state.addonMessages[2].message)
            assert.equal("GUILD", WowStub.state.addonMessages[1].channel)
            assert.is_true(ns.Guild.InUse(), "the author's own copy is on")
            assert.equal(1, ns.Routes.Count(), "the author never mails themself")
            assert.equal("Send again", _G.MailworthyFriendsPublish:GetText())
            assert.equal("Guild rules: on", _G.MailworthyFriendsGuildRules:GetText())
        end)

        it("after the guild view, the picked player's line is back above the professions (Codex review)", function()
            ns.RoutesUI.ShowGuild()
            local label = ns.RoutesUI.ChosenLabel()
            assert.equal(-96, label.point[5], "the guild view's help line")
            _G.MailworthyFriendsAdd:Click()
            _G.MailworthyFriendsPick1:Click()
            assert.equal(-74, label.point[5], "the picked player, where step 2 expects it")
            assert.equal(-96, _G.MailworthyFriendsProfession1.point[3], "the first profession, under it")
        end)

        it("one rule per profession: a second replaces it; Remove takes it out of the draft", function()
            ns.Guild.DraftAdd(BOB, ENCHANTING)
            local rule, was = ns.Guild.DraftAdd(ANN, ENCHANTING)
            assert.equal(ANN, rule.to)
            assert.equal(BOB, was)
            assert.equal(1, #ns.Guild.Draft())
            assert.is_true(ns.Guild.DraftChanged())
            ns.Guild.DraftRemove(ENCHANTING)
            assert.equal(0, #ns.Guild.Draft())
            WowStub.state.guild.rank = 2
            assert.is_nil((ns.Guild.DraftAdd(BOB, ENCHANTING)), "rank 2 can't edit")
            assert.is_nil((ns.Guild.Publish()))
        end)

        it("controller: the settings' Guild button, the editor and Publish are D-pad targets", function()
            WowStub.state.gamepadUI = true
            ns.Guild.DraftAdd(BOB, ENCHANTING)
            ns.SettingsUI.Show()
            local function reachable(button)
                for _, c in ipairs(ns.Nav.Candidates()) do if c.button == button then return true end end
                return false
            end
            _G.MailworthyPadWatcher.scripts.OnUpdate(_G.MailworthyPadWatcher, 0.2)
            assert.is_true(reachable(_G.MailworthySettingsGuild))
            ns.Nav.Select(_G.MailworthySettingsGuild)
            WowStub.state.now = WowStub.state.now + 1
            _G.MailworthyPadCross:Click()
            assert.equal("guild", ns.RoutesUI.View())
            _G.MailworthyPadWatcher.scripts.OnUpdate(_G.MailworthyPadWatcher, 0.2)
            assert.is_true(reachable(_G.MailworthyFriendsAdd))
            assert.is_true(reachable(_G.MailworthyFriendsPublish))
            assert.is_true(reachable(_G.MailworthyFriendsRemove1))
        end)
    end)
end)
