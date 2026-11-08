-- Button labels stay inside their borders (2026-11-07: "button text commonly runs over the button
-- borders"), the mailbox window's binding rows name the recipient's skill, and the settings' Guild
-- button says where the guild rules stand.
local loadAddon = require("spec.support.load_addon")

describe("widgets and labels", function()
    local ns

    before_each(function()
        ns = loadAddon()
        ns.Fire("PLAYER_LOGIN")
    end)

    it("FitFont: the normal font when it fits, the small one when not, cut only when even that doesn't", function()
        local W = ns.Widgets
        assert.same({ 1, false }, { W.FitFont(182, 150) })
        assert.same({ 1, false }, { W.FitFont(182, 166) }, "exactly the room inside the border")
        assert.same({ 2, false }, { W.FitFont(182, 200, 160) })
        assert.same({ 2, true }, { W.FitFont(182, 260, 220) })
        assert.same({ 1, false }, { W.FitFont(182, nil) }, "can't measure: left as it is")
    end)

    it("a button's label switches to the small font after SetText when it runs over, and back", function()
        local widths = { GameFontNormal = 7, GameFontNormalSmall = 5 } -- pixels per character
        local font = "GameFontNormal"
        _G.GameFontNormal, _G.GameFontNormalSmall = { name = "GameFontNormal" }, { name = "GameFontNormalSmall" }
        local cut
        local fs = {
            GetUnboundedStringWidth = function() return #ns.Widgets.lastText * widths[font] end,
            SetWidth = function(_, w) cut = w > 0 and w or nil end,
        }
        local b = ns.Widgets.Button(_G.UIParent, "", 182, function() end, "MailworthyTestButton")
        rawset(b, "GetFontString", function() return fs end)
        rawset(b, "GetWidth", function() return 182 end)
        rawset(b, "SetNormalFontObject", function(_, f) font = f.name end)
        local function set(text)
            ns.Widgets.lastText = text
            b:SetText(text)
        end
        set("Friends...")
        assert.equal("GameFontNormal", font)
        set(string.rep("x", 30)) -- 210 normal, 150 small
        assert.equal("GameFontNormalSmall", font)
        assert.is_nil(cut)
        set(string.rep("x", 40)) -- 200 small: cut at the border
        assert.equal(166, cut)
        set("Done")
        assert.equal("GameFontNormal", font)
        assert.is_nil(cut)
        _G.GameFontNormal, _G.GameFontNormalSmall = nil, nil
    end)

    it("a binding row names the recipient's skill and the guild", function()
        assert.equal(" |cff888888(guild, skill 120)|r", ns.MailWindow.RouteTags(true, 120))
        assert.equal(" |cff888888(skill 40)|r", ns.MailWindow.RouteTags(false, 40))
        assert.equal(" |cff888888(guild)|r", ns.MailWindow.RouteTags(true, nil))
        assert.equal("", ns.MailWindow.RouteTags(false, nil))
    end)

    it("Send holds when a fresh scan sends an item somewhere the list didn't show (Codex review)", function()
        local function mail(itemID, to) return { itemID = itemID, result = { to = to } } end
        local changed = ns.MailWindow.Changed
        assert.same({}, changed({ mail(1, "Smith"), mail(2) }, { mail(1, "Smith"), mail(2) }, "Bank"))
        assert.same({}, changed({ mail(1, "Smith") }, { mail(1, "Smith"), mail(9) }, "Bank"), "new item, bank alt")
        assert.same({}, changed({ mail(1, "Smith") }, { mail(9, "Smith") }, "Bank"), "new item, a shown friend")
        assert.same({}, changed({ mail(1, "Smith"), mail(2) }, { mail(2) }, "Bank"), "an item gone: fewer mails")
        local c = changed({ mail(1, "Smith") }, { mail(1, "Jold") }, "Bank")
        assert.equal(1, #c)
        assert.equal("Smith", c[1].was)
        assert.equal("Jold", c[1].to)
        assert.equal(1, #changed({ mail(1, "Smith") }, { mail(1) }, "Bank"), "a friend's item now to the bank alt")
        assert.equal(1, #changed({ mail(1, "Smith") }, { mail(9, "Ann") }, "Bank"), "a new item to someone unseen")
        -- Codex re-review: the bank alt changed in Settings beside the list; one item ID, two items
        assert.equal(1, #changed({ mail(1) }, { mail(1) }, "Old Bank", "New Bank"), "the bank alt changed after the preview")
        assert.equal(1, #changed({ mail(1, "Smith") }, { mail(9) }, "Old Bank", "New Bank"), "a new item to the new bank alt")
        local function green(link, to) return { itemID = 15210, link = link, result = { to = to } } end
        local list = { green("[Raider Shortsword of the Tiger]"), green("[Raider Shortsword of the Monkey]", "Bob") }
        assert.same({}, changed(list, list, "Bank"), "two suffixes of one item ID, two recipients: unchanged")
        -- Codex review, 2026-11-08: an item the list showed under Staying, now in the mail.
        local c2 = changed({}, { mail(1081) }, "Bank", "Bank", { mail(1081) })
        assert.equal(1, #c2)
        assert.equal("Staying", c2[1].was)
        assert.equal(1, #changed(list, { green("[Raider Shortsword of the Tiger]", "Bob"),
            green("[Raider Shortsword of the Monkey]", "Bob") }, "Bank"))
        -- Codex review, 2026-11-08: Return to sender splits one item by stacks; restacked between the
        -- preview and Send, the same two recipients would get other amounts.
        local function cloth(n, to) return { itemID = 2592, link = "[Wool Cloth]", count = n, result = { to = to } } end
        local shownSplit = { cloth(20, "Bob"), cloth(10) }
        assert.same({}, changed(shownSplit, { cloth(20, "Bob"), cloth(10) }, "Bank"))
        local c3 = changed(shownSplit, { cloth(15, "Bob"), cloth(15) }, "Bank")
        assert.equal(2, #c3)
        assert.equal("Bob", c3[1].to)
        assert.equal(15, c3[1].count)
        assert.equal(20, c3[1].wasCount)
    end)

    it("the settings' Guild button says where the guild rules stand", function()
        local text = ns.SettingsUI.GuildButtonText
        assert.equal("Guild...", text(false, nil))
        assert.equal("Guild...", text(true, nil))
        assert.equal("Guild (new template)...", text(true, { rules = {} }))
        assert.equal("Guild (rules on)...", text(true, { use = true }))
        assert.equal("Guild (rules off)...", text(true, { use = false }))
    end)
end)
