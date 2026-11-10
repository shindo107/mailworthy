-- The locked items window (/mw locks; Settings > More > "Locked items (N)..."; QoL pass D,
-- 2026-11-09, media/qol-prototype.png): this character's locked items, one row each with how
-- many the bags hold ("x9 in your bags" / "not in your bags") and Unlock. The only place a lock
-- on an item that is no longer in the bags (banked, used up) can be removed: Alt+click and the
-- controller's lock key need the item in a bag slot. An unlocked row stays until the window
-- closes, its button now "Lock", so a wrong press is undone with a second one.
-- Every control is a button (Nav + PadKey "settings" set); nothing to type, nothing on hover.
local _, ns = ...

local UI = {}
ns.LocksUI = UI

UI.ROWS = 6
local WIDTH, ROW, TOP = 460, 28, -80

local W = ns.Widgets
local frame, empty, pageButton, doneButton, hint, legend
local rows = {}
local page = 1
local list = {}
local unlocked = {} -- itemID -> link (or false): unlocked here since the window opened
local busyNote = false -- a press came during a send: the hint says why nothing changed

function UI.Frame() return frame end
--- The rows as listed (every page), for specs: Locks.List entries.
function UI.List() return list end
--- A row's line as drawn (nil when the row is hidden), for specs.
function UI.RowLine(i) return rows[i] and rows[i].text:IsShown() and rows[i].text:GetText() or nil end
function UI.Hint() return hint and hint:GetText() end

local function at(widget, x, y, point)
    widget:ClearAllPoints()
    widget:SetPoint(point or "TOPLEFT", frame, point or "TOPLEFT", x, y)
end

--- Pure: a row's line for a Locks.List entry.
function UI.RowText(e)
    local where
    if not e.locked then
        where = "|cffaaaaaaunlocked|r"
    elseif (e.count or 0) > 0 then
        where = string.format("|cffaaaaaax%d in your bags|r", e.count)
    else
        where = "|cffff8040not in your bags|r"
    end
    return (e.link or e.name) .. "  " .. where
end

--- Pure: the line under the rows: how an item gets locked (the window only unlocks).
function UI.HowText(pad)
    local key = ns.Gamepad.STICK_LEFT_PRESS
    return "Lock from your bags: Alt+click, or "
        .. (pad and ns.Gamepad.Glyph(key, 14) or (ns.Gamepad.Name(key) .. " on a controller")) .. "."
end

--- Pure: the Settings button's text.
function UI.ButtonText(n)
    return (n or 0) > 0 and string.format("Locked items (%d)...", n) or "Locked items..."
end

local function press(i)
    local e = list[(page - 1) * UI.ROWS + i]
    if not e then return end
    if ns.Mailer.Busy() then -- like the Mailworthy window's rows: no lock changes mid-send
        busyNote = true
        return UI.Refresh()
    end
    -- Locks.ToggleItem flips whatever the lock is now; the row may be a moment old.
    if ns.Locks.IsItemLocked(e.itemID) == e.locked then
        if e.locked then unlocked[e.itemID] = e.link or false end
        ns.Locks.ToggleItem(e.itemID, e.link, "locked items window")
    end
    UI.Refresh()
end

function UI.Create()
    if frame then return frame end
    frame = W.Window("MailworthyLocksFrame", WIDTH, 300)
    frame:SetFrameStrata("FULLSCREEN_DIALOG")
    frame:SetPoint("CENTER")
    local title = W.Label(frame, "GameFontNormalLarge")
    title:SetPoint("TOP", 0, -18)
    title:SetText("Locked items")
    local sub = W.Label(frame, "GameFontHighlightSmall")
    sub:SetPoint("TOPLEFT", 28, -44)
    sub:SetWidth(WIDTH - 56)
    sub:SetJustifyH("LEFT")
    sub:SetText("Mailworthy never mails these from this character. Unlock one and it follows the normal rule again.")
    for i = 1, UI.ROWS do
        local row = {}
        row.text = W.Label(frame, "GameFontHighlight")
        row.text:SetWidth(WIDTH - 56 - 100)
        row.text:SetJustifyH("LEFT")
        if type(row.text.SetWordWrap) == "function" then pcall(row.text.SetWordWrap, row.text, false) end
        row.button = W.Button(frame, "Unlock", 90, function() press(i) end, "MailworthyLocksUnlock" .. i)
        rows[i] = row
    end
    empty = W.Label(frame, "GameFontHighlightSmall")
    empty:SetWidth(WIDTH - 56)
    empty:SetJustifyH("LEFT")
    empty:SetText("No locked items on this character.")
    hint = W.Label(frame, "GameFontHighlightSmall")
    hint:SetWidth(WIDTH - 56)
    hint:SetJustifyH("LEFT")
    pageButton = W.Button(frame, "", 70, function()
        page = page + 1
        UI.Refresh()
    end, "MailworthyLocksPage")
    W.PagerBack(frame, pageButton, "MailworthyLocksPageBack", function()
        page = page - 1
        UI.Refresh()
    end)
    doneButton = W.Button(frame, "Done", 100, function() frame:Hide() end, "MailworthyLocksDone")
    legend = W.Label(frame, "GameFontHighlightSmall")
    legend:SetPoint("BOTTOM", 0, 14)
    ns.Nav.Attach(frame)
    ns.Log.Add("ui", "locked items window created")
    return frame
end

function UI.Refresh()
    if not frame then return end
    list = ns.Locks.List(unlocked)
    local pages = math.max(1, math.ceil(#list / UI.ROWS))
    if page > pages then page = 1 end
    if page < 1 then page = pages end -- back from the first page: the last
    local first, shown = (page - 1) * UI.ROWS, 0
    for i, row in ipairs(rows) do
        local e = list[first + i]
        if e then
            local y = TOP - shown * ROW
            row.text:SetText(UI.RowText(e))
            row.button:SetText(e.locked and "Unlock" or "Lock")
            at(row.text, 28, y - 5)
            at(row.button, -24, y, "TOPRIGHT")
            row.text:Show()
            row.button:Show()
            shown = shown + 1
        else
            row.text:Hide()
            row.button:Hide()
        end
    end
    local y = TOP - shown * ROW
    if #list == 0 then
        at(empty, 28, y - 4)
        empty:Show()
        y = y - 24
    else
        empty:Hide()
    end
    busyNote = busyNote and ns.Mailer.Busy()
    hint:SetText(busyNote and (ns.MailWindow and ns.MailWindow.BUSY_LINE or "Sending: locks can't change until it's done.")
        or UI.HowText(ns.MailButton.GamepadUI()))
    at(hint, 28, y - 6)
    y = y - 30
    if pages > 1 then
        pageButton:SetText(string.format("%d/%d  >", page, pages))
        at(pageButton, -24 - 100 - 8, y, "TOPRIGHT")
        pageButton:Show()
    else
        pageButton:Hide()
    end
    at(doneButton, -24, y, "TOPRIGHT")
    frame:SetHeight(-y + 22 + 40)
    legend:SetText(W.Footer(ns.MailButton.GamepadUI(), false))
    ns.Nav.Revalidate()
end

--- `opener`: the Mailworthy window whose button opened it, or nil (centred).
function UI.Show(opener)
    if not frame then UI.Create() end
    W.PlaceBeside(frame, opener)
    page, unlocked, busyNote = 1, {}, false
    UI.Refresh()
    frame:Show()
    frame:Raise()
    ns.Log.Add("ui", "locked items window shown (%d)", #list)
end

function UI.RefreshIfShown()
    if frame and frame:IsShown() then UI.Refresh() end
end

ns.On("PLAYER_LOGIN", function()
    UI.Create()
    ns.Locks.OnChanged(UI.RefreshIfShown)
end)
-- The counts follow the bags (an item banked, looted or used while the window is open).
ns.On("BAG_UPDATE_DELAYED", UI.RefreshIfShown)
