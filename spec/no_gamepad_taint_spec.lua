-- Regression guard (alpha1 + alpha2, 2026-10-13): writing into Blizzard's
-- controller UI (prompted-binding footers, FrameControlsManager registration,
-- the gamepad More menu) tainted gamepad input. Mailworthy may only READ
-- FrameControlsManager:GetActiveFrame() and SmartNavigation:GetCurrentButton().
local loadAddon = require("spec.support.load_addon")

describe("no mail tab switching from Mailworthy's code", function()
    it("never calls MailFrameTab_OnClick or clicks a mail tab (the Inbox button is a secure click)", function()
        for _, file in ipairs({ "MailWindow", "MailButton", "Mailer", "Nav", "PadKey", "Core", "SettingsUI", "RoutesUI" }) do
            local source = assert(io.open("Mailworthy/" .. file .. ".lua")):read("*a")
            local code = source:gsub("%-%-[^\n]*", "") -- comments may name it
            assert.is_nil(code:find("MailFrameTab_OnClick", 1, true), file)
            assert.is_nil(code:find("MailFrameTab%d*[:.]Click"), file)
            assert.is_nil(code:find("PanelTemplates_SetTab", 1, true), file)
        end
    end)
end)

describe("no writes into the controller UI", function()
    local saved
    before_each(function()
        saved = { util = GamepadSharedUtility, mode = GamepadMode, menu = Menu, nav = SmartNavigation }
        local function forbidden(name) return function() error("Mailworthy called " .. name) end end
        _G.GamepadSharedUtility = setmetatable({}, { __index = function(_, k) return forbidden("GamepadSharedUtility." .. k) end })
        _G.GamepadMode = { FrameControlsManager = setmetatable({ GetActiveFrame = function() return MailFrame end },
            { __index = function(_, k) return forbidden("FrameControlsManager:" .. k) end }) }
        _G.Menu = setmetatable({}, { __index = function(_, k) return forbidden("Menu." .. k) end })
        _G.SmartNavigation = setmetatable({ GetCurrentButton = function() return nil end },
            { __index = function(_, k) return forbidden("SmartNavigation:" .. k) end })
    end)
    after_each(function()
        _G.GamepadSharedUtility, _G.GamepadMode, _G.Menu, _G.SmartNavigation = saved.util, saved.mode, saved.menu, saved.nav
    end)

    it("logs in, opens the mailbox, binds Triangle, opens the window, report and settings without touching them", function()
        local ns = loadAddon()
        InboxFrame.gamepadFooter = WowStub.footer()
        ns.Fire("PLAYER_LOGIN")
        ns.Config.SetBankAlt("Roknua Themicrulah")
        WowStub.setBag(0, 1, WowStub.item(2770, "Copper Ore", { count = 20, sell = 5 }))
        MailFrame:Show()
        SendMailFrame:Show()
        ns.Fire("MAIL_SHOW")
        WowStub.state.gamepadUI = true
        MailworthyPadWatcher.scripts.OnUpdate(MailworthyPadWatcher, 0.2)
        _G.MailworthyPadTriangle:Click()
        MailworthyPadWatcher.scripts.OnUpdate(MailworthyPadWatcher, 0.2)
        _G.MailworthyPadRight:Click()
        assert.is_true(ns.MailWindow.Frame():IsShown())
        _G.MailworthyMailSend:Click() -- no Auctionator: the white Copper Ore goes
        WowStub.runTimers()
        assert.equal(1, #WowStub.state.sent)
        ns.Locks.ToggleSelectedBagSlot()
        ns.HandleSlash("report")
        -- the friends window (guild roster read through C_Club, a binding made with the controller)
        WowStub.state.guild = { clubId = 7, members = { { name = "Bob Surname", level = 30, online = true, professions = { 333 } } } }
        ns.HandleSlash("friends")
        MailworthyPadWatcher.scripts.OnUpdate(MailworthyPadWatcher, 0.2)
        _G.MailworthyFriendsPick1:Click()
        _G.MailworthyFriendsProfession4:Click() -- Enchanting (alphabetical: Alchemy, Blacksmithing, Cooking, Enchanting)
        assert.equal(1, ns.Routes.Count())
        _G.MailworthyFriendsDone:Click()
        -- settings over the window, driven by the controller; then away from the mailbox
        _G.MailworthyMailSettings:Click()
        MailworthyPadWatcher.scripts.OnUpdate(MailworthyPadWatcher, 0.2)
        _G.MailworthyPadDown:Click()
        _G.MailworthySettingsDuration2:Click()
        WowStub.state.activeFrame = nil
        MailworthyPadWatcher.scripts.OnUpdate(MailworthyPadWatcher, 0.2)
        assert.equal(0, #InboxFrame.gamepadFooter.calls)
        assert.falsy(table.concat(MailworthyDB.log, "\n"):find("Mailworthy called", 1, true))
    end)
end)
