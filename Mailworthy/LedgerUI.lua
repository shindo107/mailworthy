-- The ledger window (/mw ledger; Settings > More; the Mailworthy window's "pay back" line;
-- the friends window): the players this account received more from than it mailed back, one
-- row each with what they sent and "Mark paid" (two presses), then "Export log..." (the whole
-- mail log in the copy box). Only the player's own side: nobody is ever shown as owing them
-- (operator, 2026-11-07). Every control is a button (Nav + PadKey "settings" set); nothing to type.
local _, ns = ...

local UI = {}
ns.LedgerUI = UI

UI.ROWS = 5
local WIDTH, ROW, TOP = 520, 44, -78

local W = ns.Widgets
local frame, sub, empty, pageButton, exportButton, doneButton, hint, legend
local rows = {}
local page, armed = 1, nil
local debts = {}

function UI.Frame() return frame end
function UI.Debts() return debts end
--- The footer (the Mailworthy mark's key, the controller legend), for specs.
function UI.Footer() return legend and legend:GetText() end
--- A row's first line, for specs.
function UI.RowLine(i) return rows[i] and rows[i].text:IsShown() and rows[i].text:GetText() or nil end

local function at(widget, x, y, point)
    widget:ClearAllPoints()
    widget:SetPoint(point or "TOPLEFT", frame, point or "TOPLEFT", x, y)
end

local function setHint(text) if hint then hint:SetText(text or "") end end

--- Pure: a row's two lines for one debt ({ name, net, items, gold }). `nameText` shows in place of
--- the name (with the Mailworthy mark, Comms.Mark).
function UI.RowText(d, nameText)
    local got = d.items ~= "" and d.items or ""
    if (d.gold or 0) > 0 then got = got ~= "" and (got .. " and " .. ns.Valuation.Money(d.gold)) or ns.Valuation.Money(d.gold) end
    return string.format("|cffffd100%s|r: %s more than you've sent back", nameText or d.name, ns.Valuation.Money(d.net)),
        got ~= "" and ("|cffaaaaaareceived " .. got .. "|r") or ""
end

local function markPaid(i)
    local d = debts[(page - 1) * UI.ROWS + i]
    if not d then return end
    if armed ~= d.name then
        armed = d.name
        setHint("Press Mark paid again if you paid " .. d.name .. " back another way (a trade, gold in person).")
        UI.Refresh()
        return
    end
    armed = nil
    if ns.Ledger.MarkPaid(d.name) then setHint(d.name .. ": marked paid. The log keeps the record.") end
    UI.Refresh()
end

function UI.Create()
    if frame then return frame end
    frame = W.Window("MailworthyLedgerFrame", WIDTH, 300)
    frame:SetFrameStrata("FULLSCREEN_DIALOG")
    frame:SetPoint("CENTER")
    local title = W.Label(frame, "GameFontNormalLarge")
    title:SetPoint("TOP", 0, -18)
    title:SetText("Mail ledger")
    sub = W.Label(frame, "GameFontHighlightSmall")
    sub:SetPoint("TOPLEFT", 28, -44)
    sub:SetWidth(WIDTH - 56)
    sub:SetJustifyH("LEFT")
    sub:SetText("What other players mailed you beyond what you've mailed them back, valued when it was sent. "
        .. "Pay back by mail, in materials or gold: it counts when it goes.")
    for i = 1, UI.ROWS do
        local row = {}
        row.text = W.Label(frame, "GameFontHighlight")
        row.text:SetWidth(WIDTH - 56 - 120)
        row.text:SetJustifyH("LEFT")
        row.detail = W.Label(frame, "GameFontHighlightSmall")
        row.detail:SetWidth(WIDTH - 56 - 120)
        row.detail:SetJustifyH("LEFT")
        row.paid = W.Button(frame, "Mark paid", 100, function() markPaid(i) end, "MailworthyLedgerPaid" .. i)
        row.widgets = { row.text, row.detail, row.paid }
        rows[i] = row
    end
    empty = W.Label(frame, "GameFontHighlightSmall")
    empty:SetWidth(WIDTH - 56)
    empty:SetJustifyH("LEFT")
    empty:SetText("Nothing to pay back: you've mailed every player at least as much as they mailed you.")
    pageButton = W.Button(frame, "", 70, function()
        page, armed = page + 1, nil
        UI.Refresh()
    end, "MailworthyLedgerPage")
    exportButton = W.Button(frame, "Export log...", 130, function() UI.Export() end, "MailworthyLedgerExport")
    doneButton = W.Button(frame, "Done", 100, function() frame:Hide() end, "MailworthyLedgerDone")
    hint = W.Label(frame, "GameFontHighlightSmall")
    hint:SetJustifyH("LEFT")
    hint:SetWidth(WIDTH - 56 - 250)
    legend = W.Label(frame, "GameFontHighlightSmall")
    legend:SetPoint("BOTTOM", 0, 14)
    ns.Nav.Attach(frame)
    ns.Log.Add("ui", "ledger window created")
    return frame
end

function UI.Refresh()
    if not frame then return end
    debts = ns.Ledger.Debts()
    local pages = math.max(1, math.ceil(#debts / UI.ROWS))
    if page > pages then page = 1 end
    local first, shown = (page - 1) * UI.ROWS, 0
    local marked = false
    for i, row in ipairs(rows) do
        local d = debts[first + i]
        for _, w in ipairs(row.widgets) do w:Hide() end
        if d then
            local y = TOP - shown * ROW
            local nameText, m = ns.Comms.Mark(d.name)
            marked = marked or m
            local text, detail = UI.RowText(d, nameText)
            row.text:SetText(text)
            row.detail:SetText(detail)
            row.paid:SetText(armed == d.name and "Sure?" or "Mark paid")
            at(row.text, 28, y - 4)
            at(row.detail, 28, y - 22)
            at(row.paid, -24, y, "TOPRIGHT")
            for _, w in ipairs(row.widgets) do w:Show() end
            shown = shown + 1
        end
    end
    local y = TOP - shown * ROW
    if #debts == 0 then
        at(empty, 28, y - 4)
        empty:Show()
        y = y - 30
    else
        empty:Hide()
    end
    if pages > 1 then
        pageButton:SetText(string.format("%d/%d  >", page, pages))
        at(pageButton, -24, TOP + 22, "TOPRIGHT")
        pageButton:Show()
    else
        pageButton:Hide()
    end
    at(exportButton, 24, y - 10)
    at(hint, 164, y - 14)
    at(doneButton, -24, y - 10, "TOPRIGHT")
    frame:SetHeight(-(y - 10) + 22 + 40)
    legend:SetText(W.Footer(ns.MailButton.GamepadUI(), marked))
    ns.Nav.Revalidate()
end

--- The whole mail log in the copy box (sent and received, oldest first).
function UI.Export()
    ns.Report.Show(ns.Ledger.ExportText(), "Mailworthy mail log")
    local f = ns.Report.Frame()
    if f then W.PlaceBeside(f, frame) end
    ns.Log.Add("ui", "mail log exported")
end

--- `opener`: the Mailworthy window whose button opened it, or nil (centred).
function UI.Show(opener)
    if not frame then UI.Create() end
    W.PlaceBeside(frame, opener)
    page, armed = 1, nil
    setHint("")
    UI.Refresh()
    frame:Show()
    frame:Raise()
    ns.Log.Add("ui", "ledger window shown")
end

function UI.RefreshIfShown()
    if frame and frame:IsShown() then UI.Refresh() end
end

ns.On("PLAYER_LOGIN", function()
    UI.Create()
    ns.Ledger.OnChanged(UI.RefreshIfShown)
end)
-- A new Mailworthy user can be a name on screen (Comms.Mark): redraw.
ns.Comms.OnMarksChanged(function() UI.RefreshIfShown() end)
