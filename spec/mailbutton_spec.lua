-- The Mailworthy button: created at login under SendMailFrame (the "Send Mail"
-- navigation group), below the mail window; on the Inbox a hint says R1.
local loadAddon = require("spec.support.load_addon")

describe("mail button", function()
    local ns
    before_each(function()
        ns = loadAddon()
        ns.Fire("PLAYER_LOGIN")
        ns.Config.SetBankAlt("Roknua Themicrulah")
    end)

    it("is created at login under SendMailFrame", function()
        local b = _G.MailworthyMailButton
        assert.equal(SendMailFrame, b.parent)
        assert.truthy(b.text:find("Mailworthy", 1, true))
    end)

    it("toggles the Mailworthy window on the Send Mail tab", function()
        MailFrame:Show()
        SendMailFrame:Show()
        _G.MailworthyMailButton:Click()
        assert.is_true(ns.MailWindow.Frame():IsShown())
        _G.MailworthyMailButton:Click()
        assert.is_false(ns.MailWindow.Frame():IsShown())
    end)

    it("opens the window without a bank alt too (operator, 2026-11-08: a bank alt is optional)", function()
        MailworthyDB.bankAlts = {}
        MailFrame:Show()
        SendMailFrame:Show()
        _G.MailworthyMailButton:Click()
        assert.is_true(ns.MailWindow.Frame():IsShown())
        assert.truthy(ns.MailWindow.Texts().to[1]:find("No bank alt", 1, true))
        assert.is_false(_G.MailworthyMailSkipBankAlt:IsShown(), "nothing to skip")
    end)

    it("mouse / keyboard: the Inbox has its own button, and the window opens right there", function()
        assert.equal(InboxFrame, _G.MailworthyInboxButton.parent)
        MailFrame:Show()
        InboxFrame:Show()
        _G.MailworthyInboxButton:Click()
        assert.is_true(ns.MailWindow.Frame():IsShown())
        assert.equal(InboxFrame, ns.MailWindow.Frame().parent)
        assert.falsy(table.concat(WowStub.printed, "\n"):find("R1", 1, true))
    end)

    it("controller on the Inbox: a hint to press R1 instead (the D-pad only reaches the window on Send Mail)", function()
        WowStub.state.gamepadUI = true
        MailFrame:Show()
        InboxFrame:Show()
        ns.Fire("MAIL_SHOW")
        ns.MailButton.Activate("Triangle")
        assert.is_false(ns.MailWindow.Frame():IsShown())
        assert.truthy(WowStub.printed[#WowStub.printed]:find("Send Mail tab (R1)", 1, true))
        assert.truthy(WowStub.printed[#WowStub.printed]:find("Mailworthy opens there", 1, true), "R1 alone opens it now")
    end)

    it("shows the Triangle symbol only with the controller UI", function()
        ns.Fire("MAIL_SHOW")
        assert.equal("Mailworthy", _G.MailworthyMailButton.text)
        WowStub.state.gamepadUI = true
        ns.Fire("MAIL_SHOW")
        assert.equal("Mailworthy [Triangle/Y]", _G.MailworthyMailButton.text)
    end)

    it("can be switched off", function()
        _G.MailworthyMailButton = nil
        local ns2 = loadAddon()
        ns2.HandleSlash("feature mailbutton off")
        ns2.Fire("PLAYER_LOGIN")
        assert.is_nil(_G.MailworthyMailButton)
    end)
end)
