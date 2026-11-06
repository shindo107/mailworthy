-- Stale auction prices: a nudge at the mailbox when this character's Auctionator prices
-- are past the 7-day cutoff, louder when another Mailworthy user scanned recently
-- (their scan day arrives as "F2|<day>" after their hello). Display only.
local loadAddon = require("spec.support.load_addon")

describe("stale prices", function()
    local ns, ages
    local DAY = 86400

    local function withAuctionator()
        ages = {}
        _G.Auctionator = { API = { v1 = {
            GetAuctionPriceByItemLink = function() return nil end,
            GetAuctionAgeByItemLink = function() return nil end,
            GetAuctionAgeByItemID = function(_, id) return ages[id] end,
        } } }
    end
    local function today() return math.floor(WowStub.state.serverTime / DAY) end
    local function messages()
        local out = {}
        for _, m in ipairs(WowStub.state.addonMessages) do out[#out + 1] = m.message end
        return out
    end
    local function printed() return table.concat(WowStub.printed, "\n") end

    before_each(function()
        ns = loadAddon()
        withAuctionator()
        ns.Fire("PLAYER_LOGIN")
        ns.Config.SetBankAlt("Roknua Themicrulah")
        WowStub.state.guild = { clubId = 3, members = {} }
    end)
    after_each(function()
        _G.Auctionator = nil
        for _, line in ipairs(ns.Log.Lines()) do assert.is_nil(line:find("error", 1, true), line) end
    end)

    describe("the rule (pure)", function()
        it("no nudge while the prices count; a quiet one past the cutoff; a loud one when a peer is fresher", function()
            local N = ns.Stale.Nudge
            assert.is_nil(N(nil, nil, 100, 7), "no Auctionator: the window already says there are no prices")
            assert.is_nil(N(7, nil, 100, 7), "7 days still counts (Valuation: older than maxAgeDays)")
            assert.same({ level = "self", age = 8 }, N(8, nil, 100, 7))
            assert.same({ level = "peer", age = 9, peer = "Bob Surname", peerAgo = 1 },
                N(9, { name = "Bob Surname", day = 99 }, 100, 7))
            assert.equal("self", N(9, { name = "Bob Surname", day = 95 }, 100, 7).level, "Bob's scan is 5 days old")
            assert.equal("peer", N(math.huge, { name = "Bob Surname", day = 100 }, 100, 7).level, "never scanned")
        end)

        it("the freshest peer heard in the last two weeks", function()
            local at = 100 * DAY
            local peers = {
                bob = { name = "Bob", day = 98, at = at },
                zed = { name = "Zed", day = 99, at = at - 20 * DAY }, -- heard too long ago
                amy = { name = "Amy", day = 97, at = at },
            }
            assert.equal("Bob", ns.Stale.Freshest(peers, at).name)
            assert.is_nil(ns.Stale.Freshest({}, at))
        end)

        it("texts for people", function()
            assert.truthy(ns.Stale.Text({ level = "peer", age = 9, peer = "Bob Surname", peerAgo = 1 })
                :find("Your auction prices are 9 days old; Bob scanned yesterday.", 1, true))
            assert.truthy(ns.Stale.Text({ level = "self", age = math.huge }):find("over 3 weeks old", 1, true))
            assert.is_nil(ns.Stale.ChatText({ level = "self", age = 9 }), "no chat line without a fresher peer")
            assert.truthy(ns.Stale.ChatText({ level = "peer", age = 12, peer = "Amy Bee", peerAgo = 0 })
                :find("12 days old and Amy scanned today", 1, true))
        end)
    end)

    describe("freshness", function()
        it("is the freshest watched trade good Auctionator has seen", function()
            assert.equal(math.huge, ns.Stale.OwnAge(), "nothing seen in 21 days")
            assert.is_nil(ns.Stale.Message())
            ages[2589], ages[2770] = 9, 3
            assert.equal(3, ns.Stale.OwnAge())
            assert.equal("F2|" .. (today() - 3), ns.Stale.Message())
            _G.Auctionator = nil
            assert.is_nil(ns.Stale.OwnAge())
        end)

        it("falls back to the link call on an Auctionator without GetAuctionAgeByItemID", function()
            _G.Auctionator.API.v1.GetAuctionAgeByItemID = nil
            _G.Auctionator.API.v1.GetAuctionAgeByItemLink = function(_, link) return link == "item:10940" and 2 or nil end
            assert.equal(2, ns.Stale.OwnAge())
        end)
    end)

    describe("between Mailworthys", function()
        it("a hello is followed by the scan day; no scan day without one", function()
            ages[2770] = 1
            ns.Comms.Announce("test")
            local m = messages()
            assert.equal("H2|", m[1]:sub(1, 3))
            assert.equal("F2|" .. (today() - 1), m[2])
            WowStub.state.addonMessages = {}
            WowStub.state.now = WowStub.state.now + 60
            ages[2770] = nil
            ns.Comms.Announce("test")
            assert.equal(1, #messages(), "only the hello")
        end)

        it("records a peer's scan day; drops days in the future, too old, or malformed", function()
            ns.Fire("CHAT_MSG_ADDON", "Mailworthy", "F2|" .. (today() - 1), "GUILD", "Bob Surname-Classic Beta PvP")
            local bob = ns.Stale.Peers()["bob surname"]
            assert.equal(today() - 1, bob.day)
            assert.equal("Bob Surname", bob.name)
            assert.is_nil(ns.Comms.Peer("Bob Surname"), "a scan day isn't a hello: bindings data untouched")
            ns.Fire("CHAT_MSG_ADDON", "Mailworthy", "F2|" .. (today() + 5), "GUILD", "Zed Future")
            ns.Fire("CHAT_MSG_ADDON", "Mailworthy", "F2|" .. (today() - 400), "GUILD", "Old Timer")
            ns.Fire("CHAT_MSG_ADDON", "Mailworthy", "F2|12x", "GUILD", "Bad Data")
            ns.Fire("CHAT_MSG_ADDON", "Mailworthy", "F2|123456789", "GUILD", "Long Data")
            ns.Fire("CHAT_MSG_ADDON", "Mailworthy", "F2|1|2", "GUILD", "Extra Data")
            local count = 0
            for _ in pairs(ns.Stale.Peers()) do count = count + 1 end
            assert.equal(1, count)
        end)

        it("logging in with stale prices asks the guild to say hello (so fresh peers answer)", function()
            ns = loadAddon()
            withAuctionator()
            WowStub.state.guild = { clubId = 3, members = {} }
            ns.Fire("PLAYER_LOGIN")
            WowStub.runTimers(20)
            local asked = false
            for _, m in ipairs(messages()) do if m == "A2" then asked = true end end
            assert.is_true(asked)
        end)

        it("fresh prices: no ask at login", function()
            ns = loadAddon()
            withAuctionator()
            ages[2770] = 0
            WowStub.state.guild = { clubId = 3, members = {} }
            ns.Fire("PLAYER_LOGIN")
            WowStub.runTimers(20)
            for _, m in ipairs(messages()) do assert.not_equal("A2", m) end
        end)
    end)

    describe("at the mailbox", function()
        before_each(function()
            WowStub.setBag(0, 1, WowStub.item(2770, "Copper Ore", { count = 20, sell = 5 }))
            ages[2770] = 9
        end)

        it("a fresher peer: '!' on the button, a line in the window, one chat line", function()
            ns.Fire("CHAT_MSG_ADDON", "Mailworthy", "F2|" .. (today() - 1), "GUILD", "Bob Surname")
            MailFrame:Show()
            SendMailFrame:Show()
            ns.Fire("MAIL_SHOW")
            assert.truthy(printed():find("Your auction prices are 9 days old and Bob scanned yesterday", 1, true))
            assert.truthy(_G.MailworthyMailButton:GetText():find("!", 1, true))
            local plain = ns.MailWindow.Layout({ routes = 0, mail = 1, stay = 0 })
            ns.MailWindow.Show("send")
            assert.truthy(ns.MailWindow.Layout({ stale = true, routes = 0, mail = 1, stay = 0 }) > plain)
            assert.truthy(table.concat(ns.Report.Build and { ns.Report.Build() } or {}, "")
                :find("price stamp: Bob Surname scanned 1 day(s) ago", 1, true))
        end)

        it("stale without a fresher peer: the quiet line only, no chat", function()
            MailFrame:Show()
            SendMailFrame:Show()
            ns.Fire("MAIL_SHOW")
            assert.is_nil(printed():find("auction prices", 1, true))
            assert.equal("self", ns.Stale.Current().level)
            assert.truthy(_G.MailworthyMailButton:GetText():find("!", 1, true))
        end)

        it("fresh prices: nothing", function()
            ages[2770] = 2
            MailFrame:Show()
            SendMailFrame:Show()
            ns.Fire("MAIL_SHOW")
            assert.is_nil(ns.Stale.Current())
            assert.equal("Mailworthy", _G.MailworthyMailButton:GetText())
        end)

        it("/mw feature staleNudge off: nothing shows", function()
            ns.Fire("CHAT_MSG_ADDON", "Mailworthy", "F2|" .. today(), "GUILD", "Bob Surname")
            ns.HandleSlash("feature staleNudge off")
            MailFrame:Show()
            SendMailFrame:Show()
            ns.Fire("MAIL_SHOW")
            assert.is_nil(ns.Stale.Current())
            assert.is_nil(printed():find("auction prices", 1, true))
            assert.equal("Mailworthy", _G.MailworthyMailButton:GetText())
        end)
    end)
end)
