-- Prices.History: Auctionator's per-day price history, read from its database
-- (not the stable API), guarded so that anything odd is "no history"; the
-- disenchant value from Siz DisenchantValue's API, else Auctionator's call; TradeSkillMaster as
-- the auction source when Auctionator isn't installed (TSM_API, its public API).
local loadAddon = require("spec.support.load_addon")

describe("prices", function()
    local P, ns
    local link = WowStub.link(2589, "Linen Cloth")

    local function auctionator(history, keyFn)
        _G.Auctionator = {
            API = { v1 = {
                GetAuctionPriceByItemLink = function() return 40 end,
                GetAuctionAgeByItemLink = function() return 1 end,
                IsAuctionDataExactByItemLink = function() return false end,
                GetDisenchantPriceByItemLink = function() return nil end,
            } },
            Database = { GetPriceHistory = function(self, key)
                assert.equal(_G.Auctionator.Database, self, "called as a method")
                return history[key]
            end },
            Utilities = { BasicDBKeyFromLink = keyFn or function(l) return l:match("item:(%d+)") end },
        }
    end

    before_each(function()
        ns = loadAddon()
        P = ns.Prices
    end)
    after_each(function() _G.Auctionator, _G.DisenchantValueAPI, _G.DisenchantryDB, _G.TSM_API = nil, nil, nil, nil end)

    describe("disenchant addon", function()
        it("is Siz DisenchantValue by its API table, Disenchantry by its saved variables, else none", function()
            assert.is_nil(P.DisenchantAddon())
            assert.is_false(P.DisenchantAddonInstalled())
            _G.DisenchantValueAPI = { GetEraValue = function() end } -- no GetValue: not the API we need
            assert.is_nil(P.DisenchantAddon())
            _G.DisenchantValueAPI = { GetValue = function() return 1000 end }
            assert.equal("Siz DisenchantValue", P.DisenchantAddon())
            assert.is_true(P.DisenchantAddonInstalled())
            _G.DisenchantValueAPI = nil
            _G.DisenchantryDB = {}
            assert.equal("Disenchantry", P.DisenchantAddon())
            assert.is_true(P.DisenchantryInstalled())
        end)

        it("values an item through GetValue, as copper per item; nil, junk or an error is no value", function()
            assert.is_nil(P.DisenchantValueOf(link))
            local asked
            _G.DisenchantValueAPI = { GetValue = function(l) asked = l return 1234 end }
            assert.equal(1234, P.DisenchantValueOf(link))
            assert.equal(link, asked)
            _G.DisenchantValueAPI.GetValue = function() return nil end
            assert.is_nil(P.DisenchantValueOf(link))
            _G.DisenchantValueAPI.GetValue = function() return "junk" end
            assert.is_nil(P.DisenchantValueOf(link))
            _G.DisenchantValueAPI.GetValue = function() error("boom") end
            assert.is_nil(P.DisenchantValueOf(link))
        end)
    end)

    describe("History", function()
        it("is nil without Auctionator, without its database, or for an unknown item", function()
            assert.is_nil(P.History(link))
            _G.Auctionator = { API = { v1 = {} } }
            assert.is_nil(P.History(link))
            auctionator({})
            assert.is_nil(P.History(link))
        end)

        it("maps Auctionator's rows (rawDay, minSeen, maxSeen, available), newest first, 21 days at most", function()
            local rows = {}
            for d = 1, 30 do rows[#rows + 1] = { rawDay = d, minSeen = d, maxSeen = d + 5, available = d * 10, date = "x" } end
            auctionator({ ["2589"] = rows })
            local h = P.History(link)
            assert.equal(21, #h)
            assert.same({ day = 30, minSeen = 30, maxSeen = 35, available = 300 }, h[1])
            assert.same({ day = 10, minSeen = 10, maxSeen = 15, available = 100 }, h[21])
        end)

        it("drops rows without a day, ignores odd numbers and survives errors in Auctionator", function()
            auctionator({ ["2589"] = { { rawDay = 3, maxSeen = 9, minSeen = "abc", available = -4 }, "junk", { minSeen = 1 } } })
            assert.same({ { day = 3, minSeen = nil, maxSeen = 9, available = -4 } }, P.History(link))
            auctionator({}, function() error("boom") end)
            assert.is_nil(P.History(link))
            _G.Auctionator.Utilities.BasicDBKeyFromLink = function() return "2589" end
            _G.Auctionator.Database.GetPriceHistory = function() error("boom") end
            assert.is_nil(P.History(link))
        end)
    end)

    describe("Lookup", function()
        it("carries the history, the last day's quantity and a three-state exactness", function()
            auctionator({ ["2589"] = { { rawDay = 1, maxSeen = 50, available = 20 }, { rawDay = 2, maxSeen = 60, available = 900 } } })
            local p = P.Lookup(link)
            assert.equal(40, p.ah)
            assert.equal(false, p.exact)
            assert.equal(900, p.available)
            assert.equal(2, p.history[1].day)
            _G.Auctionator.API.v1.IsAuctionDataExactByItemLink = nil
            assert.is_nil(P.Lookup(link).exact, "unknown when Auctionator can't say")
            _G.Auctionator.API.v1.IsAuctionDataExactByItemLink = function() return true end
            assert.equal(true, P.Lookup(link).exact)
        end)

        it("takes the disenchant value from Siz DisenchantValue first, else Auctionator's call", function()
            auctionator({})
            assert.is_nil(P.Lookup(link).de)
            _G.Auctionator.API.v1.GetDisenchantPriceByItemLink = function() return 300 end
            local p = P.Lookup(link)
            assert.equal(300, p.de)
            assert.equal("Auctionator", p.deSource)
            _G.DisenchantValueAPI = { GetValue = function() return 900 end }
            p = P.Lookup(link)
            assert.equal(900, p.de)
            assert.equal("DisenchantValue", p.deSource)
            _G.DisenchantValueAPI.GetValue = function() error("boom") end
            p = P.Lookup(link)
            assert.equal(300, p.de, "an erroring GetValue falls back to Auctionator")
            assert.equal("Auctionator", p.deSource)
            _G.Auctionator.API.v1.GetDisenchantPriceByItemLink = nil
            p = P.Lookup(link)
            assert.is_nil(p.de)
            assert.is_nil(p.deSource)
        end)

        it("says when the price call itself failed, so it never counts as 'no price yet'", function()
            auctionator({})
            assert.is_nil(P.Lookup(link).failed)
            _G.Auctionator.API.v1.GetAuctionPriceByItemLink = function() error("boom") end
            local p = P.Lookup(link)
            assert.is_nil(p.ah)
            assert.is_true(p.failed)
            _G.Auctionator.API.v1.GetAuctionPriceByItemLink = nil
            assert.is_nil(P.Lookup(link), "no price call at all = no price source: the no-Auctionator rule")
        end)
    end)

    describe("TradeSkillMaster", function()
        -- TSM_API as TSM 4.x's Core/API.lua has it: GetCustomPriceValue checks its arguments and
        -- raises on a bad item string or a colon call; nil + a message for no data or a bad source.
        local values, calls
        local function tsm()
            values, calls = {}, {}
            local api = {}
            api.ToItemString = function(item)
                assert.is_true(item ~= api, "never called with a colon")
                local id = type(item) == "string" and item:match("item:(%d+)")
                return id and ("i:" .. id) or nil
            end
            api.IsCustomPriceValid = function(source)
                return source == "DBMinBuyout" or source == "DBMarket" or source == "DBRecent"
            end
            api.GetCustomPriceValue = function(source, itemString)
                assert.is_true(source ~= api, "never called with a colon")
                if type(itemString) ~= "string" or not itemString:find("^[ip]:%d+") then
                    error("Invalid 'itemString' argument type (must be a TSM item string): " .. tostring(itemString))
                end
                calls[#calls + 1] = source .. " " .. itemString
                if not api.IsCustomPriceValid(source) then return nil, "'" .. source .. "' is not a valid source." end
                local v = values[source .. " " .. itemString]
                if v == nil then return nil, "No value was returned by the custom price for the specified item." end
                return v
            end
            _G.TSM_API = api
            P.ResetTSM()
            return api
        end

        it("is the source only when Auctionator isn't installed; Auctionator wins when both are", function()
            assert.is_nil(P.Source())
            assert.is_nil(P.SourceText())
            assert.is_nil(P.Lookup(link), "no source: the no-Auctionator rule")
            _G.TSM_API = { ToItemString = function() end } -- no GetCustomPriceValue: not the API we need
            assert.is_nil(P.Source())
            tsm()
            assert.equal("TSM", P.Source())
            assert.equal("TradeSkillMaster", P.SourceText())
            auctionator({})
            assert.equal("Auctionator", P.Source())
            assert.equal("Auctionator (TSM installed, not used)", P.SourceText())
            values["DBMinBuyout i:2589"] = 9999
            local p = P.Lookup(link)
            assert.equal("Auctionator", p.source)
            assert.equal(40, p.ah, "Auctionator's price, not TSM's")
            assert.same({}, calls, "TSM isn't asked while Auctionator is the source")
        end)

        it("prices an item by its TSM item string: the lower of DBMinBuyout and DBMarket", function()
            tsm()
            values["DBMinBuyout i:2589"], values["DBMarket i:2589"] = 45, 60
            local p = P.Lookup(link)
            assert.equal("TSM", p.source)
            assert.equal(45, p.ah)
            assert.equal(45, p.minBuyout)
            assert.equal(60, p.market)
            assert.is_nil(p.failed)
            assert.is_nil(p.age, "TSM's API gives no age")
            assert.is_nil(p.exact)
            assert.is_nil(p.history)
            assert.same({ "DBMinBuyout i:2589", "DBMarket i:2589" }, calls, "realm sources only, never region")
            values["DBMarket i:2589"] = 30
            assert.equal(30, P.Lookup(link).ah, "the market value caps a high minimum buyout")
            values["DBMinBuyout i:2589"] = nil
            assert.equal(30, P.Lookup(link).ah, "nothing listed: the market value")
            values["DBMinBuyout i:2589"], values["DBMarket i:2589"] = 52.6, nil
            assert.equal(53, P.Lookup(link).ah, "whole copper")
        end)

        it("no data is 'no price yet'; an error or a source TSM doesn't know is a failed call", function()
            local api = tsm()
            local p = P.Lookup(link)
            assert.is_nil(p.ah)
            assert.is_nil(p.failed, "TSM has no data for it: no price yet")
            api.GetCustomPriceValue = function() error("boom") end
            p = P.Lookup(link)
            assert.is_nil(p.ah)
            assert.is_true(p.failed)
            tsm()
            _G.TSM_API.IsCustomPriceValid = function() return false, "not a valid source" end
            assert.is_true(P.Lookup(link).failed, "a source TSM doesn't know (no AuctionDB) is never 'no price yet'")
            _G.TSM_API.IsCustomPriceValid = function() error("boom") end
            assert.is_true(P.Lookup(link).failed)
            _G.TSM_API.IsCustomPriceValid = nil
            assert.is_true(P.Lookup(link).failed, "can't tell no data from a bad source: failed")
            tsm()
            values["DBMarket i:2589"] = 70
            _G.TSM_API.IsCustomPriceValid = function(source) return source == "DBMarket" end
            p = P.Lookup(link)
            assert.equal(70, p.ah, "one source answering is a price")
            assert.is_nil(p.failed)
            values["DBMarket i:2589"] = -5
            assert.is_nil(P.Lookup(link).ah, "a negative value is no price")
        end)

        it("one source raising: the other's price counts; with no price there it is a failed call (Codex review)", function()
            local api = tsm()
            local real = api.GetCustomPriceValue
            api.GetCustomPriceValue = function(source, itemString)
                if source == "DBMinBuyout" then error("boom") end
                return real(source, itemString)
            end
            values["DBMarket i:2589"] = 70
            local p = P.Lookup(link)
            assert.equal(70, p.ah)
            assert.is_nil(p.failed)
            values["DBMarket i:2589"] = nil
            p = P.Lookup(link)
            assert.is_nil(p.ah)
            assert.is_true(p.failed, "no data from one, an error from the other: never 'no price yet'")
        end)

        it("asks IsCustomPriceValid again until it says yes, then keeps the yes (Codex review)", function()
            local api = tsm()
            local asked, answer = 0, false
            api.IsCustomPriceValid = function() asked = asked + 1 return answer end
            api.GetCustomPriceValue = function() return nil, "No value was returned" end -- no data
            assert.is_true(P.Lookup(link).failed)
            assert.is_true(P.Lookup(link).failed)
            assert.equal(4, asked, "a no is asked again (both sources, twice)")
            answer = true
            assert.is_nil(P.Lookup(link).failed)
            assert.is_nil(P.Lookup(link).failed)
            assert.equal(6, asked, "a yes is kept")
        end)

        it("prices the disenchant tables' materials, so a green gets a disenchant value with TSM alone", function()
            local green = { quality = 2, level = 20, classID = 4 }
            assert.is_nil(ns.Disenchant.Value(green), "no source: no value")
            local api = tsm()
            api.GetCustomPriceValue = function() return 100 end
            local de = ns.Disenchant.Value(green)
            assert.is_true(type(de) == "number" and de > 0, tostring(de))
        end)

        it("falls back to i:<item ID> when ToItemString fails, and never passes a link as the item string", function()
            local api = tsm()
            values["DBMinBuyout i:2589"] = 45
            api.ToItemString = function() error("boom") end
            assert.equal("i:2589", P.TSMItemString(link))
            assert.equal(45, P.Lookup(link).ah)
            api.ToItemString = function() return "[Linen Cloth]" end
            assert.equal("i:2589", P.TSMItemString(link))
            api.ToItemString = function() return "i:2589::r5" end
            assert.equal("i:2589::r5", P.TSMItemString(link))
            api.ToItemString = function() return nil end
            assert.is_nil(P.TSMItemString("no link"))
            assert.is_nil(P.TSMItemString(nil))
            local p = P.LookupTSM("no link")
            assert.is_nil(p.ah)
            assert.is_true(p.failed, "an item TSM can't name is never 'no price yet'")
        end)

        it("prices materials by item ID for the disenchant tables and leather conversions", function()
            tsm()
            assert.is_nil(P.MaterialPrice(10940))
            values["DBMinBuyout i:10940"] = 25
            assert.equal(25, P.MaterialPrice(10940))
            assert.is_nil(P.MaterialPrice("x"))
            auctionator({})
            _G.Auctionator.API.v1.GetAuctionPriceByItemID = function() return 11 end
            assert.equal(11, P.MaterialPrice(10940), "Auctionator's while it is the source")
        end)
    end)
end)
