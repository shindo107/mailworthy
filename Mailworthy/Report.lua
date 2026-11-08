-- /mw report: one copyable report for bug reports (AGENTS: in-game checks go
-- into one report, not lists of /dump lines). Build, controller, switches, bank
-- alt, settings, locks, the last send, blocked actions and the log. Also the
-- copy box /mw scan uses, and the AH sale-mail reader that measures the house
-- cut (still an assumed 5%, docs/PLAN.md).
--
-- The copy box is created at login on UIParent; the player clicks the text to
-- select it (the game never moves keyboard focus: no SetFocus).
local _, ns = ...

local Report = {}
ns.Report = Report

local reportFrame, reportBox, reportText, reportHeading

local function call(fn, ...)
    if type(fn) ~= "function" then return nil end
    local results = { pcall(fn, ...) }
    if not results[1] then return nil end
    return unpack(results, 2, table.maxn(results))
end

local function strings(...)
    local out = {}
    for i = 1, select("#", ...) do out[i] = tostring((select(i, ...))) end
    return table.concat(out, ", ")
end

function Report.Create()
    if reportFrame then return reportFrame end
    local W = ns.Widgets
    reportFrame = W.Window("MailworthyReportFrame", 640, 440)
    reportFrame:SetPoint("CENTER")
    reportHeading = W.Label(reportFrame, "GameFontNormalLarge")
    reportHeading:SetPoint("TOP", 0, -18)
    local hint = W.Label(reportFrame, "GameFontHighlightSmall")
    hint:SetPoint("BOTTOM", 0, 18)
    hint:SetText("Click the text, Ctrl+C, then paste it where you report the problem")
    local scroll = CreateFrame("ScrollFrame", "MailworthyReportScroll", reportFrame, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 20, -44)
    scroll:SetPoint("BOTTOMRIGHT", -40, 40)
    reportBox = CreateFrame("EditBox", "MailworthyReportEditBox", scroll)
    reportBox:SetMultiLine(true)
    reportBox:SetMaxLetters(0)
    reportBox:SetAutoFocus(false)
    reportBox:SetFontObject(ChatFontNormal)
    reportBox:SetWidth(560)
    reportBox:SetScript("OnEscapePressed", function() reportFrame:Hide() end)
    reportBox:SetScript("OnTextChanged", function(self, userInput)
        if userInput then
            self:SetText(reportText)
            self:HighlightText()
        end
    end)
    reportBox:SetScript("OnEditFocusGained", function(self) self:HighlightText() end)
    reportBox:SetScript("OnMouseUp", function(self) self:HighlightText() end)
    scroll:SetScrollChild(reportBox)
    ns.Nav.Attach(reportFrame)
    return reportFrame
end

--- Show text in the copy box.
function Report.Show(text, heading)
    if not reportFrame then Report.Create() end
    reportText = text
    reportHeading:SetText(heading or "Mailworthy report")
    reportBox:SetText(text)
    reportFrame:Show()
    reportFrame:Raise()
end

function Report.Text() return reportText end
function Report.Frame() return reportFrame end

function Report.Build()
    local name, realm, faction = ns.Characters.Current()
    local v = ns.Config.Values()
    v.serverDay = ns.Config.ServerDay()
    local lines = {
        string.format("Mailworthy %s report at %s", ns.VERSION, date("%Y-%m-%d %H:%M")),
        "build: " .. strings(call(GetBuildInfo)),
        string.format("character: %s (%s, %s)%s", tostring(name), tostring(realm), tostring(faction),
            ns.BankAlt.IsBankAlt() and " - the bank alt" or ""),
        "bank alt: " .. tostring(ns.Config.BankAlt() or "none set"),
        string.format("server: launch day %s (realm first seen %s)", tostring(ns.Config.ServerDay()),
            date("%Y-%m-%d", ns.Config.FirstSeen())),
        string.format("settings: %dh listing, min gain %s and %d%%, disenchant %s, max price age %d days, tags %s, "
            .. "lock glow %s, bags 0-%d, profession materials %s",
            ns.Valuation.DURATION_HOURS[v.duration], ns.Bags.MinGainText(v), math.floor(v.minGainPct * 100 + 0.5),
            v.disenchant and "on" or "off", v.maxAgeDays,
            ns.Config.Flag("tagsEverywhere") and "every character" or "bank alt only",
            ns.Config.Flag("glowEverywhere") and "always" or "with the Mailworthy window open", ns.Bags.LastBag(),
            ns.Bags.ProfessionMatsText(ns.Bags.Evaluate(v).settings)),
        "prices: " .. (ns.Prices.SourceText() or "none")
            .. (ns.Prices.DisenchantAddon() and (", " .. ns.Prices.DisenchantAddon() .. " installed") or ""),
        string.format("controller: %s, labelStyle=%s", ns.MailButton.GamepadUI() and "on" or "off",
            tostring(ns.Gamepad.LabelStyle())),
        "api: " .. ns.Gamepad.Presence(),
        "features: " .. ns.Features.Describe(),
        ns.PadKey.Report(),
        "locked items (this character): " .. ns.Locks.Describe(),
        "last send: " .. tostring(ns.Mailer.Status() or "none this session"),
    }
    for _, entry in pairs(MailworthyDB.characters) do lines[#lines + 1] = "known character: " .. ns.Characters.Describe(entry) end
    for _, l in ipairs(ns.Routes.ReportLines()) do lines[#lines + 1] = l end
    for _, l in ipairs(ns.Guild.ReportLines()) do lines[#lines + 1] = l end
    for _, l in ipairs(ns.Comms.ReportLines()) do lines[#lines + 1] = l end
    for _, l in ipairs(ns.Stale.ReportLines()) do lines[#lines + 1] = l end
    for _, l in ipairs(ns.TierCheck.ReportLines()) do lines[#lines + 1] = l end
    for _, l in ipairs(ns.Ledger.ReportLines()) do lines[#lines + 1] = l end
    for _, l in ipairs(ns.Contributions.ReportLines()) do lines[#lines + 1] = l end
    for _, l in ipairs(ns.BagAddons.ReportLines()) do lines[#lines + 1] = l end
    for _, l in ipairs(ns.AuctionatorTags.ReportLines()) do lines[#lines + 1] = l end
    lines[#lines + 1] = "mail tabs: " .. ns.MailWindow.TabState() .. "; Inbox: " .. tostring(ns.MailWindow.OnInbox())
    for _, l in ipairs(ns.Blocked.Lines()) do lines[#lines + 1] = l end
    lines[#lines + 1] = "log:"
    for _, l in ipairs(ns.Log.Lines()) do lines[#lines + 1] = l end
    return table.concat(lines, "\n")
end

function Report.Open()
    Report.Show(Report.Build(), "Mailworthy report")
end

-- AH sale mails: the house cut (consignment) as a share of the sale. Never logs
-- the buyer's name. Each invoice is logged once per mailbox visit.
local seen = {}
ns.On("MAIL_SHOW", function() seen = {} end)
ns.On("MAIL_INBOX_UPDATE", function()
    for i = 1, tonumber((call(GetInboxNumItems))) or 0 do
        local invoiceType, itemName, _, bid, buyout, deposit, consignment, _, _, _, count = call(GetInboxInvoiceInfo, i)
        local key = tostring(i) .. tostring(itemName) .. tostring(buyout)
        if invoiceType and not seen[key] then
            seen[key] = true
            local base = tonumber(buyout) and tonumber(buyout) > 0 and tonumber(buyout) or tonumber(bid)
            ns.Log.Add("invoice", "%s %q x%s: bid %s, buyout %s, deposit %s, house cut %s%s", tostring(invoiceType),
                tostring(itemName), tostring(count), tostring(bid), tostring(buyout), tostring(deposit),
                tostring(consignment), (base and tonumber(consignment))
                    and string.format(" (%.2f%%)", 100 * tonumber(consignment) / base) or "")
        end
    end
end)

ns.On("PLAYER_LOGIN", function() Report.Create() end)
