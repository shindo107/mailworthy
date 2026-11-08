-- The way in at the mailbox. Mouse / keyboard first; controller too.
--
-- A plain "Mailworthy" Button just below the mail window on each tab: one
-- parented to InboxFrame, one to SendMailFrame (only the showing tab's is
-- visible). A click opens the Mailworthy window beside the mail window on that
-- tab. With the controller UI, the mail window's smart navigation only searches
-- the active tab's group ("Inbox" / "Send Mail"), so the D-pad reaches the
-- button on either tab and the window on Send Mail; on the Inbox the controller
-- gets a hint to press R1. We never switch tabs ourselves (see Activate).
--
-- Everything is created at login: creating frames while a gamepad panel is open
-- trips SmartNavigation's CreateFrame hook in our context. Nothing is written
-- into Blizzard's tables, and no smart-navigation key is set on our buttons.
local _, ns = ...

local MailButton = {}
ns.MailButton = MailButton

local sendButton, inboxButton, inboxHint

local function shown(name)
    local frame = rawget(_G, name)
    return type(frame) == "table" and frame:IsShown()
end

--- True when the game's controller UI is active (read-only; Blizzard's own test).
function MailButton.GamepadUI()
    local util = rawget(_G, "InputUtil")
    if type(util) ~= "table" or type(util.IsGamepadUIEnabled) ~= "function" then return false end
    local ok, on = pcall(util.IsGamepadUIEnabled)
    return ok and on == true
end

--- Mail button click or Triangle: toggle the Mailworthy window. A bank alt is optional
--- (operator, 2026-11-08): without one the window shows what would go and keeps it in the
--- bags, and bindings still mail.
--- Mouse / keyboard: on whichever tab is showing. Controller: on the Send Mail tab
--- only (the D-pad reaches the window there); on the Inbox, a hint to press R1.
--- We never switch tabs ourselves: MailFrameTab_OnClick would write
--- MailFrame.activeSubFrame from our code, which the controller focus code reads.
function MailButton.Activate(source)
    ns.lastCommand = tostring(source)
    local tab = shown("SendMailFrame") and "send" or "inbox"
    if ns.BankAlt and ns.BankAlt.IsBankAlt() then
        -- On the bank alt there's nothing to mail: the summary of what to do with it all.
        local summary = ns.BankAlt.Frame()
        if summary and summary:IsShown() then summary:Hide() else ns.BankAlt.ShowWindow() end
        ns.Log.Add("mailbutton", "%s on the bank alt: summary", tostring(source))
        return
    end
    if tab == "inbox" and MailButton.GamepadUI() then
        ns.Log.Add("mailbutton", "%s on the Inbox (controller UI): hint shown", tostring(source))
        ns.Print(ns.Features.On("autoOpen") and "Switch to the Send Mail tab (R1): Mailworthy opens there."
            or "Switch to the Send Mail tab (R1), then press Triangle or the Mailworthy button.")
        return
    end
    ns.Log.Add("mailbutton", "%s on the %s tab (%s UI)", tostring(source), tab,
        MailButton.GamepadUI() and "controller" or "mouse/keyboard")
    ns.MailWindow.Toggle(tab)
end

local function makeButton(name, parent, mail)
    -- Created on UIParent, then parented: the CreateFrame hook only reacts to frames under an open panel.
    local b = CreateFrame("Button", name, UIParent, "UIPanelButtonTemplate")
    b:SetParent(parent)
    b:SetSize(140, 24)
    b:SetText("Mailworthy")
    b:SetPoint("TOPRIGHT", mail, "BOTTOMRIGHT", -7, -2)
    b:SetScript("OnClick", function() MailButton.Activate("mail button") end)
    return b
end

function MailButton.Create()
    if sendButton then return sendButton end
    local send, inbox, mail = rawget(_G, "SendMailFrame"), rawget(_G, "InboxFrame"), rawget(_G, "MailFrame")
    if type(send) ~= "table" or type(inbox) ~= "table" or type(mail) ~= "table" or InCombatLockdown() then return nil end
    if not ns.Features.On("mailButton") then
        ns.Log.Add("mailbutton", "off (/mw feature mailButton on, then /reload)")
        return nil
    end
    -- One button per tab, same place under the mail window; only the active tab's shows.
    sendButton = makeButton("MailworthyMailButton", send, mail)
    inboxButton = makeButton("MailworthyInboxButton", inbox, mail)
    inboxHint = inbox:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    inboxHint:SetPoint("RIGHT", inboxButton, "LEFT", -6, 0)
    ns.Log.Add("mailbutton", "created under SendMailFrame and InboxFrame (below the mail window)")
    return sendButton
end

--- Controller players get the Triangle symbol and the R1 hint; mouse players a plain button.
function MailButton.Refresh()
    if not sendButton then return end
    local pad = MailButton.GamepadUI()
    local glyph = ns.Gamepad.Glyph(ns.Gamepad.FACE_TOP, 14)
    -- Stale auction prices (Stale.lua): a "!" on our own button; the window says why.
    local ok, nudge = pcall(ns.Stale.Current)
    local mark = (ok and nudge) and (nudge.level == "peer" and " |cffff8040!|r" or " |cffaaaaaa!|r") or ""
    sendButton:SetText((pad and ("Mailworthy " .. glyph) or "Mailworthy") .. mark)
    inboxButton:SetText("Mailworthy" .. mark)
    inboxHint:SetText(pad and ("R1 to Send Mail, then " .. glyph) or "")
end

ns.On("PLAYER_LOGIN", function() MailButton.Create() end)
ns.On("ADDON_LOADED", function(name)
    if name == "Blizzard_MailFrame" then MailButton.Create() end
end)
ns.On("MAIL_SHOW", function() MailButton.Refresh() end)
