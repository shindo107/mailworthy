-- Tier check (2026-11-06): the material tiers were researched from a beta-client snapshot and
-- never checked in game. The player's own profession window colours each recipe for their
-- skill, so reading it verifies the table: a material the table calls done that a non-grey
-- recipe still uses shows in /mw report, and stays in the bags until the window says otherwise.
-- C_TradeSkillUI (Forever's retail-style Professions window) is stubbed here; so are the
-- Classic globals the module falls back to.
local loadAddon = require("spec.support.load_addon")

describe("tier check (the profession window against the tier table)", function()
    local ns
    local TAILORING, FIRST_AID, LEATHER, ENCHANTING = 197, 129, 165, 333
    local LINEN, BOLT_LINEN, LIGHT_LEATHER, WOOL, BOLT_WOOL, BOOTS = 2589, 2996, 2318, 2592, 2997, 4240
    local ME = "Rettana Quilwrit|Classic Beta PvP|Alliance"
    local window, savedInstant, savedCreate, created
    local CLASSES = { [BOLT_LINEN] = 7, [BOLT_WOOL] = 7, [BOOTS] = 4, [2319] = 7, [500] = 4, [501] = 4 }

    local function has(text, s) assert.truthy(text:find(s, 1, true), "missing: " .. s .. "\n" .. text) end
    local function hasNot(text, s) assert.falsy(text:find(s, 1, true), "unexpected: " .. s .. "\n" .. text) end
    local function classOf(id) return CLASSES[id] end

    -- A recipe of the stubbed window: id, name, difficulty (0 orange .. 3 grey), reagents, output.
    local function recipe(id, name, difficulty, reagents, output, extra)
        local r = { recipeID = id, name = name, relativeDifficulty = difficulty, learned = true, reagents = reagents,
            output = output }
        for k, v in pairs(extra or {}) do r[k] = v end
        return r
    end
    local function tailoringWindow(bootsDifficulty)
        return {
            base = { professionID = TAILORING, professionName = "Tailoring", skillLevel = 120 },
            recipes = {
                recipe(1, "Bolt of Linen Cloth", 3, { LINEN }, BOLT_LINEN),
                recipe(2, "Soft-soled Linen Boots", bootsDifficulty, { BOLT_LINEN, LIGHT_LEATHER }, BOOTS),
                recipe(3, "Linen Bag", 3, { BOLT_LINEN }, 4238),
                recipe(4, "Bolt of Woolen Cloth", 0, { WOOL }, BOLT_WOOL),
                recipe(5, "Gray Woolen Shirt", 1, { BOLT_WOOL }, 2587),
                recipe(6, "Brown Linen Robe (not learned)", 0, { LINEN }, 6238, { learned = false }),
            },
        }
    end
    local function professionsOf(skillLine, name, rank)
        WowStub.state.professions = { { index = 10, name = name, rank = rank, maxRank = 150, skillLine = skillLine } }
    end
    local function stubWindow()
        local function find(id) for _, r in ipairs(window.recipes) do if r.recipeID == id then return r end end end
        _G.C_TradeSkillUI = {
            IsTradeSkillLinked = function() return window.linked == true end,
            IsTradeSkillGuild = function() return window.guild == true end,
            IsTradeSkillGuildMember = function() return false end,
            IsNPCCrafting = function() return window.npc == true end,
            IsTradeSkillReady = function() return true end,
            GetBaseProfessionInfo = function() return window.base end,
            GetChildProfessionInfo = function() return { professionID = 0, skillLevel = 0 } end,
            GetFilteredRecipeIDs = function()
                local ids = {}
                for _, r in ipairs(window.recipes) do ids[#ids + 1] = r.recipeID end
                return ids
            end,
            GetRecipeInfo = function(id) return find(id) end,
            GetRecipeSchematic = function(id)
                local r = find(id)
                local slots = {}
                for i, item in ipairs(r.reagents) do slots[i] = { reagents = { { itemID = item } }, quantityRequired = 1 } end
                return { recipeID = id, outputItemID = r.output, reagentSlotSchematics = slots }
            end,
        }
    end
    local function open()
        ns.Fire("TRADE_SKILL_SHOW")
        WowStub.runTimers()
    end

    before_each(function()
        ns = loadAddon()
        ns.Fire("PLAYER_LOGIN")
        ns.Config.SetBankAlt("Roknua Themicrulah")
        professionsOf(TAILORING, "Tailoring", 120)
        window = tailoringWindow(1)
        stubWindow()
        savedInstant = _G.GetItemInfoInstant
        local bagInstant = savedInstant
        _G.GetItemInfoInstant = function(l)
            if type(l) == "number" and CLASSES[l] then return l, "t", "s", "", 0, CLASSES[l], 0 end
            return bagInstant(l)
        end
        created = 0
        savedCreate = _G.CreateFrame
        _G.CreateFrame = function(...) created = created + 1; return savedCreate(...) end
    end)
    after_each(function()
        _G.C_TradeSkillUI, _G.GetItemInfoInstant, _G.CreateFrame = nil, savedInstant, savedCreate
        for _, name in ipairs({ "GetTradeSkillLine", "GetNumTradeSkills", "GetTradeSkillInfo", "GetTradeSkillNumReagents",
            "GetTradeSkillReagentItemLink", "GetTradeSkillItemLink", "GetCraftDisplaySkillLine", "GetNumCrafts",
            "GetCraftInfo", "GetCraftNumReagents", "GetCraftReagentItemLink", "GetCraftItemLink" }) do
            _G[name] = nil
        end
        for _, line in ipairs(ns.Log.Lines()) do assert.is_nil(line:find("error", 1, true), line) end
    end)

    describe("the summary (pure)", function()
        local function recipes(list)
            local out = {}
            for _, r in ipairs(list) do
                if r.learned then
                    out[#out + 1] = { name = r.name, difficulty = r.relativeDifficulty, reagents = r.reagents, output = r.output }
                end
            end
            return out
        end

        it("records the hardest non-grey recipe using each reagent, directly or through a part; grey only = false", function()
            local s = ns.TierCheck.Summarize(recipes(tailoringWindow(1).recipes), TAILORING, classOf)
            assert.same({ recipe = "Soft-soled Linen Boots", difficulty = 1 }, s[BOLT_LINEN])
            assert.same({ recipe = "Soft-soled Linen Boots", difficulty = 1, via = "Bolt of Linen Cloth" }, s[LINEN])
            assert.same({ recipe = "Bolt of Woolen Cloth", difficulty = 0 }, s[WOOL], "orange beats the yellow shirt")
            assert.same({ recipe = "Gray Woolen Shirt", difficulty = 1 }, s[BOLT_WOOL])
            local grey = ns.TierCheck.Summarize(recipes(tailoringWindow(3).recipes), TAILORING, classOf)
            assert.is_false(grey[BOLT_LINEN])
            assert.is_false(grey[LIGHT_LEATHER])
            assert.is_false(grey[LINEN])
        end)

        it("gear made from gear is not a part (Engineering's goggles); unknown classes are", function()
            local list = {
                { name = "Goggles A", difficulty = 3, reagents = { LINEN }, output = 500 },
                { name = "Goggles B", difficulty = 1, reagents = { 500 }, output = 501 },
            }
            assert.is_false(ns.TierCheck.Summarize(list, TAILORING, classOf)[LINEN])
            assert.same({ recipe = "Goggles B", difficulty = 1, via = "Goggles A" },
                ns.TierCheck.Summarize(list, TAILORING, function() return nil end)[LINEN])
        end)

        it("a leather's own up-conversion doesn't count (past its recipes it's kept while converting pays)", function()
            local list = {
                { name = "Medium Leather", difficulty = 1, reagents = { LIGHT_LEATHER }, output = 2319 },
                { name = "Medium Leather Belt", difficulty = 1, reagents = { 2319 }, output = 4249 },
                { name = "Light Leather Pants", difficulty = 3, reagents = { LIGHT_LEATHER }, output = 7280 },
            }
            local s = ns.TierCheck.Summarize(list, LEATHER, classOf)
            assert.is_false(s[LIGHT_LEATHER])
            assert.same({ recipe = "Medium Leather Belt", difficulty = 1 }, s[2319])
        end)

        it("compares with the table: only materials it calls done; First Aid cloth follows the bandage-learn rule", function()
            local record = { rank = 120, reagents = {
                [LINEN] = { recipe = "Soft-soled Linen Boots", difficulty = 1, via = "Bolt of Linen Cloth" },
                [WOOL] = { recipe = "Bolt of Woolen Cloth", difficulty = 0 },
                [LIGHT_LEATHER] = false,
            } }
            local findings = ns.TierCheck.Findings(TAILORING, record)
            assert.equal(1, #findings, "wool (160) isn't done yet at 120")
            assert.equal("tier check: Linen Cloth still used by Soft-soled Linen Boots (yellow) at skill 120, "
                .. "table says done at 115 (via Bolt of Linen Cloth)", ns.TierCheck.FindingText(findings[1], 120))
            local bandage = { rank = 90, reagents = { [LINEN] = { recipe = "Heavy Linen Bandage", difficulty = 1 } } }
            assert.same({}, ns.TierCheck.Findings(FIRST_AID, bandage))
        end)
    end)

    describe("reading the window (C_TradeSkillUI)", function()
        it("opening Tailoring records the rank and every reagent's use for this character, creating no frames", function()
            open()
            local record = MailworthyDB.tierCheck[ME][TAILORING]
            assert.equal(120, record.rank)
            assert.equal(5, record.recipes, "the unlearned recipe is skipped")
            assert.equal("C_TradeSkillUI (filtered list)", record.source)
            assert.same({ recipe = "Soft-soled Linen Boots", difficulty = 1, via = "Bolt of Linen Cloth" },
                record.reagents[LINEN])
            assert.is_false(record.reagents[2587] or false)
            assert.equal(0, created)
            has(table.concat(ns.Log.Lines(), "\n"),
                "Tailoring 120: 5 learned recipes read (C_TradeSkillUI (filtered list)), 2 material(s) still used past the table")
        end)

        it("prefers GetAllRecipeIDs when the client has it; a burst of list updates is read once", function()
            local all = 0
            _G.C_TradeSkillUI.GetAllRecipeIDs = function() all = all + 1; return C_TradeSkillUI.GetFilteredRecipeIDs() end
            ns.Fire("TRADE_SKILL_SHOW")
            ns.Fire("TRADE_SKILL_LIST_UPDATE")
            ns.Fire("TRADE_SKILL_LIST_UPDATE")
            WowStub.runTimers()
            assert.equal(1, all)
            assert.equal("C_TradeSkillUI", MailworthyDB.tierCheck[ME][TAILORING].source)
        end)

        it("a linked, guild or NPC window is not the player's own: nothing is recorded", function()
            for _, flag in ipairs({ "linked", "guild", "npc" }) do
                window[flag] = true
                open()
                window[flag] = nil
            end
            assert.is_nil(MailworthyDB.tierCheck and MailworthyDB.tierCheck[ME])
        end)

        it("a gathering or unknown profession window is ignored", function()
            window.base = { professionID = 186, professionName = "Mining", skillLevel = 12 }
            open()
            assert.is_nil(MailworthyDB.tierCheck and MailworthyDB.tierCheck[ME])
        end)

        it("is off with /mw feature tierCheck off", function()
            ns.HandleSlash("feature tierCheck off")
            open()
            assert.is_nil(MailworthyDB.tierCheck)
            ns.HandleSlash("report")
            has(ns.Report.Text(), "tier check: off (/mw feature tierCheck on, then /reload)")
        end)
    end)

    describe("/mw report", function()
        it("says nothing was read yet, then lists each read and what's still used past the table", function()
            ns.HandleSlash("report")
            has(ns.Report.Text(), "tier check: no profession window read yet (open one of your crafting professions)")
            open()
            ns.HandleSlash("report")
            local text = ns.Report.Text()
            has(text, "tier check: Rettana Quilwrit Tailoring 120 read ")
            has(text, "(5 learned recipes, C_TradeSkillUI (filtered list)): 2 material(s) still used past the table")
            has(text, "tier check: Linen Cloth still used by Soft-soled Linen Boots (yellow) at skill 120, "
                .. "table says done at 115 (via Bolt of Linen Cloth)")
            has(text, "tier check: Bolt of Linen Cloth still used by Soft-soled Linen Boots (yellow) at skill 120, "
                .. "table says done at 115\n")
            hasNot(text, "Wool Cloth still used")
        end)

        it("matches the table when every recipe using an outgrown material is grey", function()
            window = tailoringWindow(3)
            open()
            ns.HandleSlash("report")
            has(ns.Report.Text(), "C_TradeSkillUI (filtered list)): matches the table")
        end)
    end)

    describe("keeping what the window still uses", function()
        local function linenInBags()
            WowStub.setBag(0, 1, WowStub.item(LINEN, "Linen Cloth", { count = 20, sell = 10, class = 7, subclass = 5 }))
        end
        local function find(list, id)
            for _, item in ipairs(list) do if item.itemID == id then return item end end
        end

        it("Tailoring 120 is past Linen Cloth (115), but a yellow recipe still uses it: kept until the window says otherwise",
            function()
            linenInBags()
            assert.truthy(find(ns.Bags.Evaluate().mail, LINEN), "before any read, the table decides: mailed")
            open()
            local result = ns.Bags.Evaluate()
            local linen = find(result.keep, LINEN)
            assert.truthy(linen, "kept after the read")
            assert.equal("your Tailoring needs it", linen.result.reason)
            assert.same({ recipe = "Soft-soled Linen Boots", difficulty = 1, via = "Bolt of Linen Cloth" }, linen.result.window)
            assert.equal("your Tailoring needs it (Soft-soled Linen Boots still yellow)", ns.MailWindow.StayReason(linen.result))
            hasNot(ns.Bags.Report(result), "is past Bolt of Linen Cloth, Linen Cloth")
            has(ns.Bags.Report(result),
                "KEEP [Linen Cloth] x20: your Tailoring needs it - vendor 10c each = 2s; past the table, but your profession "
                    .. "window still shows Soft-soled Linen Boots (yellow) via Bolt of Linen Cloth")
            window = tailoringWindow(3) -- skilled up: the boots turned grey
            open()
            assert.truthy(find(ns.Bags.Evaluate().mail, LINEN), "mailed again")
        end)

        it("doesn't keep anything with the tiers or the tier check off", function()
            linenInBags()
            open()
            ns.HandleSlash("feature tierCheck off")
            assert.truthy(find(ns.Bags.Evaluate().mail, LINEN))
        end)

        it("Valuation.NeededBy (pure): the entry's stillUsed keeps an outgrown material; other materials are untouched", function()
            local V = ns.Valuation
            local linen = { itemID = LINEN, classID = 7, subclassID = 5 }
            local used = { [LINEN] = { recipe = "Soft-soled Linen Boots", difficulty = 1 } }
            local name, outgrown, untilSkill, convert, window2 =
                V.NeededBy(linen, { { skillLine = TAILORING, rank = 120, stillUsed = used } }, true)
            assert.equal("Tailoring", name)
            assert.is_nil(outgrown)
            assert.is_nil(untilSkill)
            assert.is_nil(convert)
            assert.same(used[LINEN], window2)
            local _, past = V.NeededBy(linen, { { skillLine = TAILORING, rank = 120, stillUsed = {} } }, true)
            assert.same({ name = "Tailoring", skill = 120 }, past)
        end)
    end)

    describe("Classic globals (a client without C_TradeSkillUI)", function()
        it("reads the trade skill window and Enchanting's craft window", function()
            _G.C_TradeSkillUI = nil
            local link = WowStub.link
            _G.GetTradeSkillLine = function() return "Tailoring", 120, 150 end
            local rows = {
                { "Cloth", "header" },
                { "Bolt of Linen Cloth", "trivial", { link(LINEN, "Linen Cloth") }, link(BOLT_LINEN, "Bolt of Linen Cloth") },
                { "Soft-soled Linen Boots", "medium", { link(BOLT_LINEN, "Bolt of Linen Cloth") }, link(BOOTS, "Boots") },
            }
            _G.GetNumTradeSkills = function() return #rows end
            _G.GetTradeSkillInfo = function(i) return rows[i][1], rows[i][2] end
            _G.GetTradeSkillNumReagents = function(i) return #(rows[i][3] or {}) end
            _G.GetTradeSkillReagentItemLink = function(i, j) return rows[i][3][j] end
            _G.GetTradeSkillItemLink = function(i) return rows[i][4] end
            ns.Fire("TRADE_SKILL_UPDATE")
            WowStub.runTimers()
            local record = MailworthyDB.tierCheck[ME][TAILORING]
            assert.equal("classic trade skill window", record.source)
            assert.equal(2, record.recipes)
            assert.same({ recipe = "Soft-soled Linen Boots", difficulty = 1, via = "Bolt of Linen Cloth" }, record.reagents[LINEN])

            professionsOf(ENCHANTING, "Enchanting", 190)
            _G.GetCraftDisplaySkillLine = function() return "Enchanting", 190, 225 end
            local crafts = { { "Enchant Bracer - Minor Health", "easy", { link(10940, "Strange Dust") } },
                { "Runed Silver Rod", "medium", { link(6338, "Silver Rod") } } }
            _G.GetNumCrafts = function() return #crafts end
            _G.GetCraftInfo = function(i) return crafts[i][1], "", crafts[i][2] end
            _G.GetCraftNumReagents = function(i) return #crafts[i][3] end
            _G.GetCraftReagentItemLink = function(i, j) return crafts[i][3][j] end
            ns.Fire("CRAFT_SHOW")
            WowStub.runTimers()
            local craft = MailworthyDB.tierCheck[ME][ENCHANTING]
            assert.equal("classic craft window", craft.source)
            assert.equal(190, craft.rank)
            ns.HandleSlash("report")
            has(ns.Report.Text(), "tier check: Silver Rod still used by Runed Silver Rod (yellow) at skill 190, table says done at 170")
        end)
    end)
end)
