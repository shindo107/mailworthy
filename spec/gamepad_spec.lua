-- Controller button names follow the player's controller (QoL pass, package C): a window or a
-- tooltip draws the game's own icon (Gamepad.Glyph), a chat line names the key by the active
-- device's label style (Gamepad.Name): "Shapes" = PlayStation, "Letters" / "Generic" = Xbox,
-- "Reverse" = Switch. A Switch controller (operator, 2026-11-09: "Use Xbox names"), no controller,
-- an unknown style and a Steam Deck get the Xbox names.
local loadAddon = require("spec.support.load_addon")

-- style (false = no mapped device) -> right shoulder, top face, left stick press, right stick press
local STYLES = {
    { style = "Shapes", shoulder = "R1", top = "Triangle", stick = "L3", rstick = "R3" },
    { style = "Letters", shoulder = "RB", top = "Y", stick = "LS", rstick = "RS" },
    { style = "Generic", shoulder = "RB", top = "Y", stick = "LS", rstick = "RS" },
    { style = "Reverse", shoulder = "RB", top = "Y", stick = "LS", rstick = "RS" },
    { style = "SomethingNew", shoulder = "RB", top = "Y", stick = "LS", rstick = "RS" },
    { style = false, shoulder = "RB", top = "Y", stick = "LS", rstick = "RS" },
}
-- Every controller word Mailworthy used to type, whatever the controller.
local TYPED = { "R1", "RB", "L3", "LS", "R3", "RS", "Triangle" }

local function word(text, name)
    return (" " .. text .. " "):find("[^%w]" .. name .. "[^%w]") ~= nil
end

describe("controller names", function()
    local ns
    before_each(function()
        ns = loadAddon()
        ns.Fire("PLAYER_LOGIN")
    end)
    after_each(function()
        _G.InputIconTextureSetUtility, _G.CreateAtlasMarkup = nil, nil
    end)

    it("uses Blizzard's key strings (GamepadConstants.lua)", function()
        assert.equal("PAD4", ns.Gamepad.FACE_TOP)
        assert.equal("PADRSHOULDER", ns.Gamepad.SHOULDER_RIGHT)
        assert.equal("PADLSTICK", ns.Gamepad.STICK_LEFT_PRESS)
        assert.equal("PADRSTICK", ns.Gamepad.STICK_RIGHT_PRESS)
    end)

    it("names the face buttons per style: a Switch controller gets the Xbox letters", function()
        assert.same({ "Cross", "Circle", "Square", "Triangle" }, { ns.Gamepad.NameFor("Shapes", "PAD1"),
            ns.Gamepad.NameFor("Shapes", "PAD2"), ns.Gamepad.NameFor("Shapes", "PAD3"), ns.Gamepad.NameFor("Shapes", "PAD4") })
        assert.same({ "A", "B", "X", "Y" }, { ns.Gamepad.NameFor("Letters", "PAD1"),
            ns.Gamepad.NameFor("Letters", "PAD2"), ns.Gamepad.NameFor("Letters", "PAD3"), ns.Gamepad.NameFor("Letters", "PAD4") })
        assert.same({ "A", "B", "X", "Y" }, { ns.Gamepad.NameFor("Reverse", "PAD1"),
            ns.Gamepad.NameFor("Reverse", "PAD2"), ns.Gamepad.NameFor("Reverse", "PAD3"), ns.Gamepad.NameFor("Reverse", "PAD4") })
        assert.equal("PADSOCIAL", ns.Gamepad.NameFor("Shapes", "PADSOCIAL"), "a key without a name: the key itself")
    end)

    it("without the controller API: the Xbox names, no error", function()
        local saved = _G.C_GamePad
        _G.C_GamePad = nil
        assert.is_nil(ns.Gamepad.LabelStyle())
        assert.equal("RB", ns.Gamepad.Name("PADRSHOULDER"))
        _G.C_GamePad = { GetActiveDeviceID = function() error("no device") end, GetDeviceMappedState = function() end }
        assert.equal("RB", ns.Gamepad.Name("PADRSHOULDER"))
        _G.C_GamePad = saved
    end)

    it("leaves a line without {KEY} marks alone, and one with an unknown mark readable", function()
        assert.equal("/mw feature <a|b> on|off", ns.Gamepad.Fill("/mw feature <a|b> on|off"))
        assert.equal("press PADSOCIAL {not a key}", ns.Gamepad.Fill("press {PADSOCIAL} {not a key}"))
    end)

    for _, case in ipairs(STYLES) do
        describe("label style " .. tostring(case.style), function()
            before_each(function() WowStub.state.labelStyle = case.style end)

            local function others(text, ...)
                local mine = {}
                for _, name in ipairs({ ... }) do mine[name] = true end
                for _, name in ipairs(TYPED) do
                    if not mine[name] then assert.is_false(word(text, name), name .. " in: " .. text) end
                end
            end

            it("names the four keys", function()
                assert.equal(case.shoulder, ns.Gamepad.Name(ns.Gamepad.SHOULDER_RIGHT))
                assert.equal(case.top, ns.Gamepad.Name(ns.Gamepad.FACE_TOP))
                assert.equal(case.stick, ns.Gamepad.Name(ns.Gamepad.STICK_LEFT_PRESS))
                assert.equal(case.rstick, ns.Gamepad.Name(ns.Gamepad.STICK_RIGHT_PRESS))
            end)

            it("chat, controller on the Inbox: the shoulder (and top) button by this controller's name", function()
                WowStub.state.gamepadUI = true
                MailFrame:Show()
                InboxFrame:Show()
                ns.MailButton.Activate("Triangle")
                local line = WowStub.printed[#WowStub.printed]
                assert.truthy(line:find("Switch to the Send Mail tab (" .. case.shoulder .. "): Mailworthy opens there.", 1, true), line)
                others(line, case.shoulder)

                ns.HandleSlash("feature autoOpen off")
                ns.MailButton.Activate("Triangle")
                line = WowStub.printed[#WowStub.printed]
                assert.truthy(line:find("Switch to the Send Mail tab (" .. case.shoulder .. "), then press " .. case.top
                    .. " or the Mailworthy button.", 1, true), line)
                others(line, case.shoulder, case.top)
                assert.is_false(ns.MailWindow.Frame():IsShown(), "still only a hint: never switches tabs")
            end)

            it("chat, /mw help: all four keys by this controller's name", function()
                ns.HandleSlash("help")
                local help = table.concat(WowStub.printed, "\n")
                assert.truthy(help:find("Controller: Send Mail tab (" .. case.shoulder .. "); " .. case.top
                    .. " closes and reopens it.", 1, true), help)
                assert.truthy(help:find("Alt+click it, or " .. case.stick .. " in your bags (controller).", 1, true), help)
                assert.truthy(help:find("Ctrl+Alt+click it, or " .. case.rstick .. " in your bags (controller).", 1, true), help)
                assert.is_nil(help:find("{", 1, true), "no mark left unfilled")
                -- "padTriangle" is a switch's name, not a button's.
                others(help:gsub("padTriangle", "padTop"), case.shoulder, case.top, case.stick, case.rstick)
            end)

            it("window and tooltip, when the game can't draw the icon: this controller's names in brackets", function()
                WowStub.state.gamepadUI = true
                ns.Fire("MAIL_SHOW")
                assert.equal("Mailworthy [" .. case.top .. "]", _G.MailworthyMailButton.text)
                assert.equal("[" .. case.shoulder .. "] to Send Mail, then [" .. case.top .. "]", ns.MailButton.InboxHint())
                assert.truthy(ns.Border.Tooltip():find("Alt+click it ([" .. case.stick .. "] on a controller) to unlock.", 1, true))
                ns.PadKey.RefreshHint()
                assert.equal("[" .. case.stick .. "] Mailworthy: lock / unlock item   [" .. case.rstick .. "] pin: bank / vendor",
                    ns.PadKey.BagHint())
            end)

            it("window and tooltip: the game's icon for the key, no typed name", function()
                local asked = {}
                _G.InputIconTextureSetUtility = { GetNormalActiveInputIconButtonTexture = function(key)
                    asked[key] = true
                    return "atlas-" .. key
                end }
                _G.CreateAtlasMarkup = function(atlas, w, h) return "|A:" .. atlas .. ":" .. h .. ":" .. w .. "|a" end
                WowStub.state.gamepadUI = true
                ns.Fire("MAIL_SHOW")
                assert.equal("Mailworthy |A:atlas-PAD4:14:14|a", _G.MailworthyMailButton.text)
                assert.equal("|A:atlas-PADRSHOULDER:14:14|a to Send Mail, then |A:atlas-PAD4:14:14|a", ns.MailButton.InboxHint())
                local tip = ns.Border.Tooltip()
                assert.truthy(tip:find("Alt+click it (|A:atlas-PADLSTICK:14:14|a on a controller) to unlock.", 1, true), tip)
                ns.PadKey.RefreshHint()
                assert.equal("|A:atlas-PADLSTICK:14:14|a Mailworthy: lock / unlock item   |A:atlas-PADRSTICK:14:14|a pin: bank / vendor",
                    ns.PadKey.BagHint())
                others(ns.MailButton.InboxHint() .. tip .. ns.PadKey.BagHint())
                assert.same({ PAD4 = true, PADRSHOULDER = true, PADLSTICK = true, PADRSTICK = true }, asked)
            end)
        end)
    end

    it("redraws the Inbox hint and the bag hint when the input device changes with the mailbox open (Codex review)", function()
        WowStub.state.gamepadUI = true
        ns.Fire("MAIL_SHOW")
        ns.PadKey.RefreshHint()
        assert.equal("[R1] to Send Mail, then [Triangle]", ns.MailButton.InboxHint())
        WowStub.state.labelStyle = "Letters"
        ns.Fire("INPUT_DEVICE_INTERFACE_TRANSITION")
        assert.equal("[RB] to Send Mail, then [Y]", ns.MailButton.InboxHint())
        assert.equal("Mailworthy [Y]", _G.MailworthyMailButton.text)
        assert.equal("[LS] Mailworthy: lock / unlock item   [RS] pin: bank / vendor", ns.PadKey.BagHint())
        WowStub.state.gamepadUI = false
        ns.Fire("INPUT_DEVICE_INTERFACE_TRANSITION")
        assert.equal("", ns.MailButton.InboxHint(), "back to the mouse: no hint")
    end)

    it("mouse / keyboard: no controller hint beside the Inbox button", function()
        ns.Fire("MAIL_SHOW")
        assert.equal("", ns.MailButton.InboxHint())
        assert.equal("Mailworthy", _G.MailworthyMailButton.text)
    end)
end)
