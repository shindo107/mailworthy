-- Expected disenchant value from the era tables priced with Auctionator: the
-- number Disenchantry's tooltip shows (its tables, its formula), computed by
-- Mailworthy because Disenchantry has no API. Order of sources: Siz
-- DisenchantValue, the tables, Auctionator's own call.
local loadAddon = require("spec.support.load_addon")

describe("disenchant tables", function()
    local ns
    local STRANGE_DUST, GREATER_MAGIC, SMALL_GLIMMERING = 10940, 10939, 10978
    local materials

    local function auctionator(byID)
        materials = byID or {}
        _G.Auctionator = { API = { v1 = {
            GetAuctionPriceByItemLink = function(_, l)
                local id = tonumber(l:match("item:(%d+)"))
                return materials[id]
            end,
            GetAuctionAgeByItemLink = function() return 0 end,
        } } }
    end

    before_each(function() ns = loadAddon() end)
    after_each(function() _G.Auctionator, _G.DisenchantValueAPI, _G.DisenchantryDB = nil, nil, nil end)

    describe("outcomes (pure)", function()
        local D
        before_each(function() D = ns.Disenchant end)

        it("green armor: dust, essence and shard by item level band", function()
            local out = D.Outcomes({ quality = 2, level = 18, classID = 4 })
            assert.same({ itemID = STRANGE_DUST, chance = 75, minQuantity = 2, maxQuantity = 3 }, out[1])
            assert.same({ itemID = GREATER_MAGIC, chance = 20, minQuantity = 1, maxQuantity = 2 }, out[2])
            assert.same({ itemID = SMALL_GLIMMERING, chance = 5, minQuantity = 1, maxQuantity = 1 }, out[3])
            out = D.Outcomes({ quality = 2, level = 10, classID = 4 })
            assert.equal(2, #out, "no shard below item level 16")
            assert.equal(80, out[1].chance)
        end)

        it("green weapons favour essences; on Forever ilvl 21-30 weapons give Greater Magic Essence", function()
            local out = D.Outcomes({ quality = 2, level = 18, classID = 2 })
            assert.equal(20, out[1].chance)
            assert.equal(75, out[2].chance)
            assert.equal(GREATER_MAGIC, out[2].itemID)
            out = D.Outcomes({ quality = 2, level = 24, classID = 2 })
            assert.equal(GREATER_MAGIC, out[2].itemID, "not Lesser Astral Essence")
            assert.equal(10998, D.Outcomes({ quality = 2, level = 24, classID = 4 })[2].itemID, "armor keeps Lesser Astral")
        end)

        it("blue and purple gear: shards and crystals", function()
            assert.same({ { itemID = SMALL_GLIMMERING, chance = 100, minQuantity = 1, maxQuantity = 1 } },
                D.Outcomes({ quality = 3, level = 20, classID = 4 }))
            local out = D.Outcomes({ quality = 3, level = 60, classID = 2 })
            assert.equal(99.5, out[1].chance)
            assert.equal(20725, out[2].itemID)
            assert.same({ { itemID = 20725, chance = 100, minQuantity = 1, maxQuantity = 2 } },
                D.Outcomes({ quality = 4, level = 70, classID = 4 }))
        end)

        it("nothing for white items, trade goods, odd levels or gear the tables don't cover", function()
            assert.is_nil(D.Outcomes({ quality = 1, level = 20, classID = 4 }))
            assert.is_nil(D.Outcomes({ quality = 2, level = 20, classID = 7 }))
            assert.is_nil(D.Outcomes({ quality = 2, level = 0, classID = 4 }))
            assert.is_nil(D.Outcomes({ quality = 2, level = 90, classID = 4 }))
            assert.is_nil(D.Outcomes({ quality = 4, level = 10, classID = 4 }))
            assert.is_nil(D.Outcomes(nil))
        end)

        it("expected value = chance x average quantity x price, nil when a material has no price", function()
            local out = D.Outcomes({ quality = 2, level = 18, classID = 4 })
            local prices = { [STRANGE_DUST] = 100, [GREATER_MAGIC] = 1000, [SMALL_GLIMMERING] = 2000 }
            -- 0.75 x 2.5 x 100 + 0.20 x 1.5 x 1000 + 0.05 x 1 x 2000 = 187.5 + 300 + 100
            assert.equal(587, D.ExpectedValue(out, function(id) return prices[id] end))
            prices[SMALL_GLIMMERING] = nil
            assert.is_nil(D.ExpectedValue(out, function(id) return prices[id] end))
            assert.is_nil(D.ExpectedValue(nil, function() return 1 end))
            assert.is_nil(D.ExpectedValue({}, function() return 1 end))
        end)
    end)

    describe("as a price source", function()
        local link = WowStub.link(5000, "Green Sword")
        before_each(function()
            WowStub.setBag(0, 1, WowStub.item(5000, "Green Sword", { quality = 2, level = 18, class = 2, sell = 100 }))
        end)

        it("materials are priced by ID when Auctionator has that call, else by an item: link", function()
            auctionator({ [STRANGE_DUST] = 100 })
            assert.equal(100, ns.Prices.MaterialPrice(STRANGE_DUST))
            assert.is_nil(ns.Prices.MaterialPrice(1))
            _G.Auctionator.API.v1.GetAuctionPriceByItemID = function(_, id) return id == STRANGE_DUST and 150 or nil end
            assert.equal(150, ns.Prices.MaterialPrice(STRANGE_DUST))
            _G.Auctionator = nil
            assert.is_nil(ns.Prices.MaterialPrice(STRANGE_DUST))
        end)

        it("gives the tables' value, labelled Disenchantry when it's installed, 'tables' otherwise", function()
            auctionator({ [STRANGE_DUST] = 100, [GREATER_MAGIC] = 1000, [SMALL_GLIMMERING] = 2000 })
            -- weapon: 0.20 x 2.5 x 100 + 0.75 x 1.5 x 1000 + 0.05 x 2000 = 50 + 1125 + 100
            local de, source = ns.Prices.DisenchantValueFor(link)
            assert.equal(1275, de)
            assert.equal("tables", source)
            _G.DisenchantryDB = {}
            de, source = ns.Prices.DisenchantValueFor(link)
            assert.equal(1275, de)
            assert.equal("Disenchantry", source)
            local p = ns.Prices.Lookup(link)
            assert.equal(1275, p.de)
            assert.equal("Disenchantry", p.deSource)
        end)

        it("Siz DisenchantValue comes first, Auctionator's own call last", function()
            auctionator({ [STRANGE_DUST] = 100, [GREATER_MAGIC] = 1000, [SMALL_GLIMMERING] = 2000 })
            _G.DisenchantValueAPI = { GetValue = function() return 900 end }
            local de, source = ns.Prices.DisenchantValueFor(link)
            assert.equal(900, de)
            assert.equal("DisenchantValue", source)
            _G.DisenchantValueAPI = nil
            materials[SMALL_GLIMMERING] = nil -- a material without a price: the tables can't say
            _G.Auctionator.API.v1.GetDisenchantPriceByItemLink = function() return 300 end
            de, source = ns.Prices.DisenchantValueFor(link)
            assert.equal(300, de)
            assert.equal("Auctionator", source)
            _G.Auctionator.API.v1.GetDisenchantPriceByItemLink = nil
            assert.is_nil((ns.Prices.DisenchantValueFor(link)))
        end)

        it("end to end: with Disenchantry installed a green sword goes for disenchanting on the tables' value", function()
            ns.Fire("PLAYER_LOGIN")
            ns.Config.SetBankAlt("Roknua Themicrulah") -- without one, its share stays (Bags.HoldReason)
            _G.DisenchantryDB = {}
            auctionator({ [STRANGE_DUST] = 100, [GREATER_MAGIC] = 1000, [SMALL_GLIMMERING] = 2000 })
            local result = ns.Bags.Evaluate()
            assert.equal(1, #result.mail)
            local sword = result.mail[1]
            assert.equal("de", sword.result.route)
            assert.equal(1275 - 30, sword.result.deNet)
            assert.truthy(ns.Bags.Report(result):find("disenchant 12s 75c each (Disenchantry)", 1, true))
            assert.is_true(result.settings.disenchant, "Disenchantry switches the comparison on")
            ns.SettingsUI.Show()
            assert.equal("Include disenchant value: on (Disenchantry)", _G.MailworthySettingsDisenchant:GetText())
        end)
    end)
end)
