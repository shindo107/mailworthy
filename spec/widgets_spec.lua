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

    it("the settings' Guild button says where the guild rules stand", function()
        local text = ns.SettingsUI.GuildButtonText
        assert.equal("Guild...", text(false, nil))
        assert.equal("Guild...", text(true, nil))
        assert.equal("Guild (new template)...", text(true, { rules = {} }))
        assert.equal("Guild (rules on)...", text(true, { use = true }))
        assert.equal("Guild (rules off)...", text(true, { use = false }))
    end)
end)
