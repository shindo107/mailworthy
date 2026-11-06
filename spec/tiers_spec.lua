-- Material tiers (operator, 2026-11-06: "I just got my first aid to 80 ... I shouldn't be
-- using linen cloth anymore. So ideally I send my linen cloth in the mail to the AH or my
-- friend's tailor ... once my friend goes past the similar threshold on tailoring or first
-- aid (if I have a binding for them) then I just keep going to the AH").
local loadAddon = require("spec.support.load_addon")

describe("material tiers", function()
    local ns, prices
    local FIRST_AID, TAILORING = 129, 197
    local BOB = "Bob Surname"
    local LINEN, WOOL = 2589, 2592

    local function linen() return WowStub.item(LINEN, "Linen Cloth", { count = 20, sell = 10, class = 7, subclass = 5 }) end
    local function wool() return WowStub.item(WOOL, "Wool Cloth", { count = 10, sell = 33, class = 7, subclass = 5 }) end
    local function withAuctionator()
        prices = {}
        _G.Auctionator = { API = { v1 = {
            GetAuctionPriceByItemLink = function(_, l) return prices[l] end,
            GetAuctionAgeByItemLink = function() return 0 end,
        } } }
    end
    local function firstAid(rank)
        WowStub.state.professions[2] = { index = 10, name = "First Aid", rank = rank, maxRank = 150, skillLine = FIRST_AID }
    end
    local function find(list, id)
        for _, item in ipairs(list) do if item.itemID == id then return item end end
    end
    local function messages()
        local out = {}
        for _, m in ipairs(WowStub.state.addonMessages) do out[#out + 1] = m.message end
        return out
    end

    before_each(function()
        ns = loadAddon()
        ns.Fire("PLAYER_LOGIN")
        ns.Config.SetBankAlt("Roknua Themicrulah")
        WowStub.state.addonMessages = {}
    end)
    after_each(function()
        _G.Auctionator = nil
        for _, line in ipairs(ns.Log.Lines()) do assert.is_nil(line:find("error", 1, true), line) end
    end)

    describe("the table (pure)", function()
        it("First Aid is done with Linen Cloth at 80 (Wool Bandage), and so on up", function()
            assert.equal(80, ns.Tiers.Threshold(FIRST_AID, LINEN))
            assert.is_false(ns.Tiers.Outgrown(FIRST_AID, LINEN, 79))
            assert.is_true(ns.Tiers.Outgrown(FIRST_AID, LINEN, 80))
            assert.is_false(ns.Tiers.Outgrown(FIRST_AID, LINEN, nil), "skill unknown: not past it")
            assert.is_false(ns.Tiers.Outgrown(FIRST_AID, 14047, 300), "Runecloth: the last tier, never done")
            assert.is_nil(ns.Tiers.Threshold(FIRST_AID, 10940), "not a First Aid material")
            assert.same({ "Linen Cloth", "Peacebloom", "Briarthorn", "Small Venom Sac", "Wool Cloth" },
                ns.Tiers.OutgrownNames(FIRST_AID, 150))
            assert.equal(0, ns.Tiers.Step(FIRST_AID, 1))
            assert.equal(1, ns.Tiers.Step(FIRST_AID, 80))
        end)

        it("Forever's First Aid also keeps its potion herbs, venom sacs and Tourniquet leather; not other herbs", function()
            local V = ns.Valuation
            local s = V.Settings({})
            s.professions = { { skillLine = FIRST_AID, rank = 100 } }
            local function reason(id, classID, subclassID)
                return V.Evaluate({ itemID = id, classID = classID, subclassID = subclassID, quality = 1, vendor = 10,
                    count = 5 }, nil, s).reason
            end
            assert.equal("your First Aid needs it", reason(2450, 7, 9), "Briarthorn: Lesser Healing Potion to 125")
            assert.equal("common item (no price data)", reason(2447, 7, 9), "Peacebloom: Minor Healing Potion grey at 95")
            assert.equal("common item (no price data)", reason(785, 7, 9), "Mageroyal: not a First Aid herb")
            assert.equal("your First Aid needs it", reason(1475, 15, 0), "Small Venom Sac, whatever its class")
            assert.equal("your First Aid needs it", reason(4304, 7, 6), "Thick Leather: Leather Tourniquet")
            assert.equal("common item (no price data)", reason(2318, 7, 6), "Light Leather: not First Aid's")
            assert.equal("your First Aid needs it", reason(13464, 7, 9), "Golden Sansam: never outgrown")
            assert.is_true(ns.Routes.Matches({ profession = FIRST_AID }, { itemID = 3357, classID = 7, subclassID = 9 }),
                "a First Aid binding takes Liferoot")
        end)

        it("other professions: where the last recipe using it goes grey, through the parts it makes", function()
            assert.equal(115, ns.Tiers.Threshold(TAILORING, LINEN))
            assert.equal(ns.Tiers.Threshold(TAILORING, LINEN), ns.Tiers.Threshold(TAILORING, 2996), "cloth and its bolt")
            assert.equal(185, ns.Tiers.Threshold(164, 2840), "Copper Bar: Sterling Silver Breastplate")
            assert.is_nil(ns.Tiers.Threshold(164, 3575), "Iron Bar: Iron Buckle into the Blessed Plate Belt (310)")
            assert.equal(155, ns.Tiers.Threshold(164, 2835), "Rough Stone through Rough Grinding Stone")
            assert.equal(270, ns.Tiers.Threshold(202, 2841), "Bronze: Bronze Tube, Accurate Scope, Goblin Bomb Dispenser")
            assert.equal(205, ns.Tiers.Threshold(333, 10940), "Strange Dust")
            assert.equal(25, ns.Tiers.Threshold(333, 247786), "Mote of Magic")
            assert.equal(135, ns.Tiers.Threshold(165, 2318), "Light Leather: its own recipes")
            assert.is_nil(ns.Tiers.Threshold(165, 8170), "Rugged Leather: the last tier")
            assert.equal(120, ns.Tiers.Threshold(171, 765), "Silverleaf")
            assert.is_nil(ns.Tiers.Threshold(171, 2452), "Swiftthistle still makes Swiftness Potions (operator: keep)")
            assert.is_nil(ns.Tiers.Threshold(171, 3818), "Fadeleaf: Shadow Oil into Greater Shadow Protection")
            assert.equal(165, ns.Tiers.Threshold(185, 6522), "Deviate Fish")
            assert.is_nil(ns.Tiers.Threshold(185, 13759), "Nightfin Snapper: used at 300+")
        end)

        it("materials outside a profession's subclasses: levelling ones only, by exact item", function()
            local V = ns.Valuation
            local function needed(id, classID, subclassID, profession, rank)
                return V.NeededBy({ itemID = id, classID = classID, subclassID = subclassID },
                    { { skillLine = profession, rank = rank } })
            end
            assert.equal("Engineering", needed(LINEN, 7, 5, 202, 150), "an engineer levels with Linen to 210")
            assert.is_nil(needed(LINEN, 7, 5, 202, 210))
            assert.equal("Blacksmithing", needed(774, 7, 11, 164, 100), "Malachite to 120")
            assert.is_nil(needed(7080, 7, 10, 164, 100), "Essence of Water (used at 300) isn't kept: AH")
            assert.is_nil(needed(12811, 7, 11, 197, 100), "nor Righteous Orb")
            assert.equal("Cooking", needed(5051, 12, 0, 185, 100), "Dig Rat, a quest-class cooking meat")
            assert.equal("Cooking", needed(13755, 0, 5, 185, 300), "Raw Winter Squid: kept for good")
            assert.equal("Alchemy", needed(6358, 7, 8, 171, 300), "Oily Blackmouth: kept for good (operator)")
            assert.equal("Cooking", needed(3818, 7, 9, 185, 200), "Fadeleaf: Triage Tea to 235")
        end)

        it("leather past its recipes: kept while converting pays, sold when selling pays", function()
            local V = ns.Valuation
            local light = { itemID = 2318, classID = 7, subclassID = 6, quality = 1, vendor = 15, count = 20 }
            local s = V.Settings({})
            s.professions = { { skillLine = 165, rank = 140 } }
            local ah = {}
            s.priceOf = function(id) return ah[id] end
            local r = V.Evaluate(light, nil, s)
            assert.equal("keep", r.action, "no prices: can't tell, keep it to convert")
            assert.same({ into = 2319, count = 4, name = "Medium Leather" }, r.convert)
            assert.equal("convert it: 4 make a Medium Leather (pays more)", ns.MailWindow.StayReason(r))
            ah[2318], ah[2319] = 20, 200
            assert.equal("keep", V.Evaluate(light, nil, s).action, "4 x 20c < 200c: convert")
            ah[2318] = 50
            r = V.Evaluate(light, nil, s)
            assert.equal("mail", r.action, "4 x 50c >= 200c: sell")
            assert.same({ name = "Leatherworking", skill = 140 }, r.outgrown)
            s.professions[1].rank = 120
            assert.equal(135, V.Evaluate(light, nil, s).untilSkill, "still levelling with it")
            assert.is_true(ns.Routes.Matches({ profession = 165, skill = 140 }, light, true,
                function(id) return ({ [2318] = 20, [2319] = 200 })[id] end), "a friend converts it too")
            assert.is_false((ns.Routes.Matches({ profession = 165, skill = 140 }, light, true,
                function(id) return ({ [2318] = 50, [2319] = 200 })[id] end)))
        end)

        it("every row is a known crafting profession, in rising order, with a name", function()
            for profession, rows in pairs(ns.Tiers.DONE) do
                assert.truthy(ns.Valuation.PROFESSION_MATS[profession], "crafting profession " .. profession)
                local seen, last = {}, 0
                for _, row in ipairs(rows) do
                    assert.truthy(row[2] >= last, "rising order: " .. row[3])
                    last = row[2]
                    assert.equal("number", type(row[1]))
                    assert.truthy(row[2] > 0 and row[2] <= 300, "skill in 1-300")
                    assert.equal("string", type(row[3]))
                    assert.is_nil(seen[row[1]], "an item once per profession")
                    seen[row[1]] = true
                end
            end
        end)
    end)

    describe("this character's own professions", function()
        it("First Aid 79 keeps linen (until 80); at 80 linen is valued like anything else, wool stays", function()
            local V = ns.Valuation
            local item = { itemID = LINEN, classID = 7, subclassID = 5, quality = 1, vendor = 10, count = 20 }
            local woolItem = { itemID = WOOL, classID = 7, subclassID = 5, quality = 1, vendor = 33, count = 10 }
            local s = V.Settings({})
            s.professions = { { skillLine = FIRST_AID, rank = 79 } }
            local r = V.Evaluate(item, nil, s)
            assert.equal("your First Aid needs it", r.reason)
            assert.equal(80, r.untilSkill)
            assert.equal("your First Aid needs it (until skill 80)", ns.MailWindow.StayReason(r))
            s.professions[1].rank = 80
            r = V.Evaluate(item, nil, s)
            assert.equal("mail", r.action, "no Auctionator: a white item is mailed")
            assert.same({ name = "First Aid", skill = 80 }, r.outgrown)
            assert.equal("your First Aid needs it", V.Evaluate(woolItem, nil, s).reason)
            s.tiers = false
            assert.equal("your First Aid needs it", V.Evaluate(item, nil, s).reason, "/mw feature tiers off: kept as before")
        end)

        it("another profession that still needs it keeps it", function()
            local s = ns.Valuation.Settings({})
            s.professions = { { skillLine = FIRST_AID, rank = 120 }, { skillLine = TAILORING, rank = 30 } }
            local r = ns.Valuation.Evaluate({ itemID = LINEN, classID = 7, subclassID = 5, quality = 1, vendor = 10, count = 20 },
                nil, s)
            assert.equal("your Tailoring needs it", r.reason)
        end)

        it("in the scan: linen to the bank alt, the settings and report say why", function()
            firstAid(85)
            WowStub.setBag(0, 1, linen())
            WowStub.setBag(0, 2, wool())
            local result = ns.Bags.Evaluate()
            assert.truthy(find(result.mail, LINEN))
            assert.truthy(find(result.keep, WOOL))
            local report = ns.Bags.Report(result)
            assert.truthy(report:find("your First Aid (85) is past it", 1, true), report)
            assert.truthy(report:find("kept until skill 150", 1, true), report)
            assert.truthy(report:find("kept for First Aid 85; First Aid 85 is past Linen Cloth (mailed)", 1, true), report)
            ns.SettingsUI.Show()
            assert.truthy(_G.MailworthySettingsMats:GetText():find("First Aid 85", 1, true))
            ns.HandleSlash("feature tiers off")
            assert.truthy(find(ns.Bags.Evaluate().keep, LINEN), "switched off: kept again")
        end)
    end)

    describe("a friend's binding", function()
        before_each(function()
            withAuctionator()
            WowStub.setBag(0, 1, linen())
            WowStub.setBag(0, 2, wool())
            prices[WowStub.link(LINEN, "Linen Cloth")] = 174
            prices[WowStub.link(WOOL, "Wool Cloth")] = 300
            WowStub.state.guild = { clubId = 3, members = {} }
        end)

        it("stops taking what the friend's skill is past (their Mailworthy said); the bank alt gets it", function()
            ns.Routes.Add(BOB, FIRST_AID)
            local result = ns.Bags.Evaluate()
            assert.equal(BOB, find(result.mail, LINEN).result.to, "skill unknown: the binding takes it")
            ns.Fire("CHAT_MSG_ADDON", "Mailworthy", "H2|129|", "GUILD", BOB)
            ns.Fire("CHAT_MSG_ADDON", "Mailworthy", "S2|129:80|", "GUILD", BOB)
            assert.equal(80, ns.Comms.Skill(BOB, FIRST_AID))
            result = ns.Bags.Evaluate()
            local l = find(result.mail, LINEN)
            assert.is_nil(l.result.to, "to the bank alt on the normal rule")
            assert.equal(BOB, l.result.pastFor.to)
            assert.equal(BOB, find(result.mail, WOOL).result.to, "wool still goes to Bob")
            local report = ns.Bags.Report(result)
            assert.truthy(report:find("not to Bob Surname: their First Aid (80) is past it", 1, true), report)
            assert.truthy(ns.Report.Build():find("skill 80: past Linen Cloth", 1, true))
        end)

        it("the next binding that still needs it gets it", function()
            ns.Routes.Add(BOB, FIRST_AID)
            ns.Routes.Add("Tay Lor", TAILORING)
            ns.Fire("CHAT_MSG_ADDON", "Mailworthy", "S2|129:200|", "GUILD", BOB)
            local result = ns.Bags.Evaluate()
            assert.equal("Tay Lor", find(result.mail, LINEN).result.to)
        end)

        it("the guild roster's rank counts for a primary profession; a stale lower one doesn't win", function()
            ns.Routes.Add(BOB, TAILORING)
            WowStub.state.guild.members = { { name = BOB, level = 30, online = true, professions = { TAILORING }, ranks = { 150 } } }
            ns.Fire("CHAT_MSG_ADDON", "Mailworthy", "S2|197:40|", "GUILD", BOB)
            local route = ns.Routes.Active()[1]
            assert.equal(150, route.skill, "the highest known")
            if ns.Tiers.Threshold(TAILORING, LINEN) then
                assert.is_nil(find(ns.Bags.Evaluate().mail, LINEN).result.to)
            end
        end)

        it("the skill of the friend's crafter, when the binding goes to their alt", function()
            ns.Routes.Add(BOB, FIRST_AID)
            ns.Fire("CHAT_MSG_ADDON", "Mailworthy", "H2||Bob Alt=129", "GUILD", BOB)
            ns.Fire("CHAT_MSG_ADDON", "Mailworthy", "S2||Bob Alt=129:150", "GUILD", BOB)
            local result = ns.Bags.Evaluate()
            assert.is_nil(find(result.mail, LINEN).result.to)
            assert.is_nil(find(result.mail, WOOL).result.to, "Bob Alt is at 150: past wool too")
        end)

        it("one of my own characters: its skill at its last login", function()
            MailworthyDB.characters[ns.Characters.Key("Alt Mine", "Classic Beta PvP", "Alliance")] = {
                name = "Alt Mine", realm = "Classic Beta PvP", faction = "Alliance",
                professions = { { name = "First Aid", skillLine = FIRST_AID, rank = 90 } },
            }
            ns.Routes.Add("Alt Mine", FIRST_AID)
            assert.is_nil(find(ns.Bags.Evaluate().mail, LINEN).result.to)
        end)

        it("/mw feature tiers off: the binding takes everything again", function()
            ns.Routes.Add(BOB, FIRST_AID)
            ns.Fire("CHAT_MSG_ADDON", "Mailworthy", "S2|129:200|", "GUILD", BOB)
            ns.HandleSlash("feature tiers off")
            assert.equal(BOB, find(ns.Bags.Evaluate().mail, LINEN).result.to)
        end)

        it("a hard keep still wins", function()
            ns.Routes.Add(BOB, FIRST_AID)
            ns.Locks.ToggleItem(WOOL, "link", "spec")
            assert.equal("locked", find(ns.Bags.Evaluate().keep, WOOL).result.reason)
        end)
    end)

    describe("between Mailworthys", function()
        it("the skills message: this character and the account's crafters, under 255 characters", function()
            local text = ns.Comms.EncodeSkills({ { skillLine = TAILORING, rank = 130 }, { skillLine = FIRST_AID, rank = 80 },
                { skillLine = 186, rank = 50 } }, { { name = "Alt Mine", professions = { { skillLine = 333, rank = 120 } } },
                { name = "No Rank", professions = { { skillLine = 165 } } } })
            assert.equal("S2|129:80,197:130|Alt Mine=333:120", text, "Mining isn't a crafting profession")
            local many = {}
            for i = 1, 30 do many[i] = { name = "Character Number" .. i, professions = { { skillLine = 165, rank = 200 } } } end
            assert.is_true(#ns.Comms.EncodeSkills({}, many) <= 255)
            local msg = ns.Comms.Decode(text)
            assert.equal("skills", msg.kind)
            assert.same({ [129] = 80, [197] = 130 }, msg.skills)
            assert.same({ { name = "Alt Mine", skills = { [333] = 120 } } }, msg.characters)
        end)

        it("drops junk: unknown professions, huge ranks, bad names", function()
            local msg = ns.Comms.Decode("S2|129:80,186:50,197:5000|=165:3;Bad|x")
            assert.is_nil(msg, "a stray separator: not a skills message")
            msg = ns.Comms.Decode("S2|129:80,186:50,197:5000|=165:3;Ok Name=999:4;Good Name=165:3")
            assert.same({ [129] = 80 }, msg.skills)
            assert.same({ { name = "Good Name", skills = { [165] = 3 } } }, msg.characters)
        end)

        it("a later hello keeps the skills; skills alone make a peer; the report shows them", function()
            ns.Fire("CHAT_MSG_ADDON", "Mailworthy", "S2|129:80,197:130|", "GUILD", BOB)
            assert.same({ 129, 197 }, ns.Comms.Peer(BOB).professions, "the hello was lost: the skills stand in")
            ns.Fire("CHAT_MSG_ADDON", "Mailworthy", "H2|129,197|", "GUILD", BOB)
            assert.equal(130, ns.Comms.Skill(BOB, TAILORING))
            assert.truthy(table.concat(ns.Comms.ReportLines(), "\n"):find("skills: First Aid 80, Tailoring 130", 1, true))
        end)

        it("crossing a tier tells peers again at the next mailbox", function()
            WowStub.state.guild = { clubId = 3, members = {} }
            firstAid(79)
            ns.Comms.Announce("login")
            assert.equal("S2|129:79|", messages()[2])
            WowStub.state.addonMessages = {}
            WowStub.state.now = WowStub.state.now + 60
            firstAid(79)
            ns.Fire("MAIL_SHOW")
            assert.equal(0, #messages(), "no new tier: quiet")
            firstAid(80)
            ns.Fire("MAIL_SHOW")
            assert.equal("S2|129:80|", messages()[2])
        end)
    end)
end)
