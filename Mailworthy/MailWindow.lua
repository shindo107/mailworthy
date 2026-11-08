-- The Mailworthy window at the mailbox (media/ux-pass-prototype.png): who the mail
-- goes to, the bindings in force (only when there are any: a profession's materials
-- to a friend, with Skip once and Remove), what goes and why, what stays and why,
-- the total gain, and Send / Settings. One press of Send mails everything (Mailer).
-- The window grows and shrinks to the rows it shows (UI.Layout); the X, Escape and
-- the controller's Circle close it.
--
-- It opens by itself when the Send Mail tab shows (operator, 2026-11-08: "when you click send
-- mail mailworthy should open"; the tab watcher sees the tab, switch autoOpen). Opened on the
-- Inbox, Send is greyed out and says "Click Send Mail"; on Send Mail it is "Send to ...".
--
-- Mouse: click. Controller: Triangle at the mail window opens it, then the D-pad
-- moves Mailworthy's own highlight, Cross presses, Circle closes (PadKey "window"
-- set, Nav). Every row is a button: pressing an item locks it (it stays in the
-- bags) or unlocks it, so the controller can change the list without a menu.
-- Everything the mouse tooltip shows is also on the row itself.
--
-- Created at login (never while a gamepad panel is open), parented to the
-- showing mail tab; nothing is written into Blizzard's frames or tables.
local _, ns = ...

local UI = {}
ns.MailWindow = UI

UI.MAIL_ROWS, UI.STAY_ROWS, UI.ROUTE_ROWS = 8, 5, 3
UI.TO_LINES = 2 -- recipient lines under "To:" (the last says "+N more" when there are more)
local WIDTH, MAIL_ROW, STAY_ROW, ROUTE_ROW = 520, 30, 20, 24

local W = ns.Widgets
local money = function(c) return ns.Valuation.Money(c) end

-- The tab the last draw was for (true: the Inbox), so the watcher redraws when it changes.
local renderedInbox
local frame, title, toName, toNote, mailHead, mailHint, mailCount, mailEmpty, stayHead, stayCount, mailPage, stayPage
local guildButton
local routesHead, totalLine, totalNote, sendButton, settingsButton, legend, staleLine, owedLine, owedButton, skipAltButton
local mailRows, stayRows, routeRows, toLines = {}, {}, {}, {}
local friendsButton
local result
local shownAlt -- the bank alt the list on screen was drawn for (UI.Send compares against it)
local pages = { mail = 1, stay = 1 }

UI.CHIPS = {
    ah = { "Auction", 0.2, 0.4, 0.75 },
    de = { "Disenchant", 0.45, 0.25, 0.65 },
    common = { "Common", 0.4, 0.4, 0.4 },
    bank = { "Bank", 0.15, 0.5, 0.45 },
    friend = { "to a friend", 0.55, 0.35, 0.12 }, -- the chip says "to <first name>"
}

function UI.Frame() return frame end
function UI.Result() return result end
--- The texts at the top ("To:" and the recipient lines) and the fees / status line, for specs and the report.
function UI.Texts()
    local to = { toName and toName:GetText() }
    for _, line in ipairs(toLines) do
        if line.name:IsShown() then to[#to + 1] = line.name:GetText() .. " | " .. line.note:GetText() end
    end
    return { to = to, note = totalNote and totalNote:GetText() }
end

--- Pure: "|cffRRGGBB" + name from an item link (no brackets), or the link as is.
function UI.ItemText(link, count, stacks)
    local color, name = tostring(link):match("|c(%x%x%x%x%x%x%x%x).-%[(.-)%]")
    local text = name and ("|c" .. color .. name .. "|r") or tostring(link)
    if count and count > 1 then text = text .. " |cffaaaaaax" .. count .. "|r" end
    if stacks and stacks > 1 then text = text .. " |cff888888(" .. stacks .. " stacks)|r" end
    return text
end

UI.LOCKED_COLOR = "|cff4da6ff" -- the bags' lock-glow blue

--- Pure: the Staying header's count, with how many of them are locked (listed first).
function UI.StayCountText(items, locked)
    local text = string.format("%d item%s", items, items == 1 and "" or "s")
    if locked > 0 then text = string.format("%s%d locked|r · %s", UI.LOCKED_COLOR, locked, text) end
    return text
end

--- Pure: a player-facing reason for an item that stays.
function UI.StayReason(r)
    if r.held then -- the bank alt's share, held (none set, or skipped this visit): Bags.HoldReason
        local chip = UI.CHIPS[r.route] or UI.CHIPS.common
        return string.format("%s%s: %s", chip[1], r.gain and (" +" .. money(r.gain)) or "", r.held)
    end
    if r.quest then return r.quest .. " needs it" end
    if r.reason == "not worth it" then
        if (r.gain or 0) <= 0 then return "sells better at a vendor" end
        return string.format("only %s more than a vendor (needs %s)", money(r.gain), money(r.threshold))
    end
    if r.reason == "no price" then return "no auction price yet" end
    if r.reason == "locked" then return "locked (press to unlock)" end
    if r.reason == "junk (no price data)" then return "junk: sell it at a vendor" end
    if r.reason == "uncommon or better (no price data)" then return "uncommon: needs Auctionator prices" end
    if r.untilSkill then return r.reason .. " (until skill " .. r.untilSkill .. ")" end
    if r.window then
        return string.format("%s (%s still %s)", r.reason, tostring(r.window.recipe),
            ns.TierCheck.COLORS[r.window.difficulty] or "in use")
    end
    if r.convert then return string.format("convert it: %d make a %s (pays more)", r.convert.count, r.convert.name) end
    return r.reason
end

local function firstName(name) return tostring(name):match("^(%S+)") or tostring(name) end

--- Pure: the Send button's text: "Send to Roknua", "Send to Roknua, Bob", "Send to Roknua +2".
--- `recipients` lists the scan's recipients ("" = the bank alt); `skipped`: the bank alt is skipped.
function UI.SendText(recipients, bankAlt, isBankAlt, skipped)
    if skipped then bankAlt = nil end
    local names = {}
    for _, to in ipairs(recipients or {}) do
        if to == "" then
            if bankAlt and not isBankAlt then names[#names + 1] = firstName(bankAlt) end
        else
            names[#names + 1] = firstName(to)
        end
    end
    if #names == 0 then return (bankAlt and not isBankAlt) and ("Send to " .. firstName(bankAlt)) or "Send" end
    if #names > 2 then return string.format("Send to %s +%d", names[1], #names - 1) end
    return "Send to " .. table.concat(names, ", ")
end

local function mailsText(n) return string.format("%d mail%s", n, n == 1 and "" or "s") end

--- Pure: who this scan mails to, one line each, the bank alt first: { { name, note, bank }, ... }.
--- `totals` from Bags.Evaluate (recipients, byRecipient). With nothing to mail: the bank alt
--- alone, as before. With more than one recipient each note says what they get and how many
--- mails (operator, 2026-11-06: "when sending to multiple people ... the receiver is made clear").
--- `skipped`: the bank alt is skipped this visit; its line stays first, so Undo skip sits beside it.
function UI.Recipients(totals, bankAlt, isBankAlt, skipped)
    local recipients = totals and totals.recipients or {}
    local several = #recipients > 1
    local lines = {}
    local function bankLine(each)
        local note = isBankAlt and "this is your bank alt" or (bankAlt and "your bank alt" or "optional: Settings")
        if skipped and bankAlt and not isBankAlt then note = "your bank alt · skipped this time" end
        if several and each and bankAlt then note = note .. " · " .. mailsText(each.mails) end
        lines[#lines + 1] = { name = bankAlt or "|cffaaaaaaNo bank alt: what's worth selling stays|r", note = note,
            bank = true }
    end
    if #recipients == 0 or (skipped and bankAlt) then bankLine() end
    for _, to in ipairs(recipients) do
        local each = totals.byRecipient and totals.byRecipient[to] or { mails = 0, what = {} }
        if to == "" then
            bankLine(each)
        else
            local what = #each.what > 0 and table.concat(each.what, ", ") or "a binding"
            lines[#lines + 1] = { name = to, note = what .. (each.crafter and " (their crafter)" or "")
                .. (several and (" · " .. mailsText(each.mails)) or "") }
        end
    end
    return lines
end

local function toggleLock(row)
    if row.item and not ns.Mailer.Busy() then
        -- A fresh lock goes to the top of Staying (locked items first): show that page.
        if not ns.Locks.IsItemLocked(row.item.itemID) then pages.stay = 1 end
        ns.Locks.ToggleItem(row.item.itemID, row.item.link, "Mailworthy window")
    end
end

local function showTooltip(row)
    if not row.item or type(GameTooltip) ~= "table" then return end
    local slot = row.item.slots and row.item.slots[1]
    GameTooltip:SetOwner(row.button, "ANCHOR_RIGHT")
    if slot then pcall(GameTooltip.SetBagItem, GameTooltip, slot.bag, slot.slot) end
    GameTooltip:Show()
end

local function rowButton(name, parent, height)
    local b = CreateFrame("Button", name, parent)
    b:SetHeight(height)
    b:SetPoint("LEFT", 16, 0)
    b:SetPoint("RIGHT", -16, 0)
    b:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
    local bg = b:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    return b, bg
end

local function createMailRows()
    for i = 1, UI.MAIL_ROWS do
        local row = {}
        local b, bg = rowButton("MailworthyMailRow" .. i, frame, MAIL_ROW - 2)
        bg:SetColorTexture(1, 1, 1, i % 2 == 0 and 0.03 or 0.06)
        row.button = b
        row.icon = b:CreateTexture(nil, "ARTWORK")
        row.icon:SetSize(22, 22)
        row.icon:SetPoint("LEFT", 8, 0)
        row.name = W.Label(b, "GameFontHighlight")
        row.name:SetPoint("LEFT", 40, 0)
        row.name:SetWidth(230)
        row.name:SetJustifyH("LEFT")
        row.chipBg = b:CreateTexture(nil, "BORDER")
        row.chipBg:SetSize(84, 16)
        row.chipBg:SetPoint("LEFT", 290, 0)
        row.chip = W.Label(b, "GameFontHighlightSmall")
        row.chip:SetPoint("CENTER", row.chipBg, "CENTER")
        row.gain = W.Label(b, "GameFontHighlight")
        row.gain:SetPoint("RIGHT", -8, 0)
        b:SetScript("OnClick", function() toggleLock(row) end)
        b:SetScript("OnEnter", function() showTooltip(row) end)
        b:SetScript("OnLeave", function() if type(GameTooltip) == "table" then GameTooltip:Hide() end end)
        b:Hide()
        mailRows[i] = row
    end
end

local function createStayRows()
    for i = 1, UI.STAY_ROWS do
        local row = {}
        local b, bg = rowButton("MailworthyStayRow" .. i, frame, STAY_ROW - 1)
        bg:SetColorTexture(1, 1, 1, i % 2 == 0 and 0.02 or 0.05)
        row.button = b
        row.name = W.Label(b, "GameFontHighlightSmall")
        row.name:SetPoint("LEFT", 8, 0)
        row.name:SetWidth(220)
        row.name:SetJustifyH("LEFT")
        row.reason = W.Label(b, "GameFontHighlightSmall")
        row.reason:SetPoint("LEFT", 236, 0)
        row.reason:SetWidth(250)
        row.reason:SetJustifyH("LEFT")
        row.reason:SetTextColor(0.55, 0.75, 1)
        b:SetScript("OnClick", function() toggleLock(row) end)
        b:SetScript("OnEnter", function() showTooltip(row) end)
        b:SetScript("OnLeave", function() if type(GameTooltip) == "table" then GameTooltip:Hide() end end)
        b:Hide()
        stayRows[i] = row
    end
end

-- Bindings (Routes): shown only while there are bindings. One row each with Skip once
-- (this mailbox visit) and Remove, under a "Bindings" heading with the way into the
-- friends window. The mail list below shows where each item goes. A guild template's
-- rules (Guild.lua) are rows too, with Skip once but no Remove; while any shows, "Guild
-- rules: on" on the heading turns them all off in one press (operator, 2026-11-07).
local function createRouteRows()
    routesHead = W.Label(frame, "GameFontNormal")
    routesHead:SetText("Bindings")
    friendsButton = W.Button(frame, "Friends...", 90, function() ns.RoutesUI.Show(frame) end, "MailworthyMailFriends")
    guildButton = W.Button(frame, "Guild rules: on", 130, function()
        if ns.Guild.SetUse(false) then
            ns.Print("Guild rules off: your materials no longer follow the guild template. Turn them back on with /mw guild.")
        end
        UI.Refresh()
    end, "MailworthyMailGuildRules")
    guildButton:Hide()
    -- Skip once for the bank alt too (operator, 2026-11-08): its share stays this visit, bindings go.
    skipAltButton = W.Button(frame, "Skip once", 84, function()
        if ns.Mailer.Busy() then return end
        ns.Bags.SkipBankAlt(not ns.Bags.BankAltSkipped())
        UI.Refresh()
    end, "MailworthyMailSkipBankAlt")
    skipAltButton:Hide()
    for i = 1, UI.ROUTE_ROWS do
        local row = {}
        row.text = W.Label(frame, "GameFontHighlightSmall")
        row.text:SetWidth(300)
        row.text:SetJustifyH("LEFT")
        row.skip = W.Button(frame, "Skip once", 84, function()
            if not row.key then return end
            if ns.Routes.Skipped(row.key) then ns.Routes.Unskip(row.key) else ns.Routes.SkipOnce(row.key) end
            UI.Refresh()
        end, "MailworthyMailSkip" .. i)
        row.remove = W.Button(frame, "Remove", 74, function()
            if row.key and ns.Routes.Remove(row.key) then
                ns.Print("Binding removed.")
                UI.Refresh()
            end
        end, "MailworthyMailUnbind" .. i)
        row.text:Hide()
        row.skip:Hide()
        row.remove:Hide()
        routeRows[i] = row
    end
end

--- Pure: the last row when more bindings apply than show. Own bindings come first in the list,
--- so when the first hidden one is a guild rule, all the hidden ones are: those are in the Guild
--- window, not Friends (2026-11-07, Codex review).
function UI.MoreText(n, guildOnly)
    return string.format("|cffaaaaaa+ %d more: %s|r", n, guildOnly and "guild rules, /mw guild" or "press Friends...")
end

--- Pure: a binding row's grey tags: "(guild, skill 120)", "(skill 120)", "(guild)" or "". The skill
--- shows why a material past it stays (2026-11-07: "i'm not sure hiphop is on linen anymore").
function UI.RouteTags(guild, skill)
    local tags = {}
    if guild then tags[#tags + 1] = "guild" end
    if skill then tags[#tags + 1] = "skill " .. tostring(skill) end
    return #tags > 0 and (" |cff888888(" .. table.concat(tags, ", ") .. ")|r") or ""
end

--- Fill the binding rows; returns how many rows show (0: the block is hidden).
local function fillRoutes()
    local list = ns.Routes.List()
    local shown = 0
    for i, row in ipairs(routeRows) do
        local r = list[i]
        row.key = r and r.key or nil
        if r and i == UI.ROUTE_ROWS and #list > UI.ROUTE_ROWS then
            row.text:SetText(UI.MoreText(#list - UI.ROUTE_ROWS + 1, r.scope == "guild"))
            row.key = nil
            row.skip:Hide()
            row.remove:Hide()
        elseif r then
            local to, crafter = ns.Routes.Recipient(r)
            local skipped = ns.Routes.Skipped(r.key)
            row.text:SetText(ns.Routes.What(r) .. " |cffffd100to " .. firstName(to) .. "|r"
                .. (crafter and (" |cff888888(" .. firstName(r.to) .. "'s crafter)|r") or "")
                .. UI.RouteTags(r.scope == "guild", ns.Routes.Skill(r))
                .. (skipped and " |cff888888skipped this time|r" or ""))
            row.skip:SetText(skipped and "Undo skip" or "Skip once")
            row.skip:Show()
            if r.scope == "guild" then row.remove:Hide() else row.remove:Show() end
        end
        if r then
            row.text:Show()
            shown = shown + 1
        else
            row.text:Hide()
            row.skip:Hide()
            row.remove:Hide()
        end
    end
    local guild = false
    for _, r in ipairs(list) do guild = guild or r.scope == "guild" end
    if shown > 0 then
        routesHead:Show()
        friendsButton:Show()
    else
        routesHead:Hide()
        friendsButton:Hide()
    end
    if guild then guildButton:Show() else guildButton:Hide() end
    return shown
end

local function pageButton(name, list)
    local b = W.Button(frame, "", 70, function()
        local rows = list == "mail" and UI.MAIL_ROWS or UI.STAY_ROWS
        local items = result and result[list == "mail" and "mail" or "keep"] or {}
        local count = math.max(1, math.ceil(#items / rows))
        pages[list] = pages[list] % count + 1
        UI.Refresh(true)
    end, name)
    b:Hide()
    return b
end

local function at(widget, x, y, point)
    widget:ClearAllPoints()
    widget:SetPoint(point or "TOPLEFT", frame, point or "TOPLEFT", x, y)
end

function UI.Create()
    if frame then return frame end
    local send = rawget(_G, "SendMailFrame")
    frame = W.Window("MailworthyMailWindow", WIDTH, 400, type(send) == "table" and send or nil)
    title = W.Label(frame, "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 22, -18)
    toName = W.Label(frame, "GameFontHighlightLarge")
    toName:SetPoint("TOPLEFT", 24, -48)
    toNote = W.Label(frame, "GameFontDisableSmall")
    toNote:SetPoint("TOPRIGHT", -26, -52)
    for i = 1, UI.TO_LINES do
        local name = W.Label(frame, "GameFontHighlight")
        local note = W.Label(frame, "GameFontDisableSmall")
        name:Hide()
        note:Hide()
        toLines[i] = { name = name, note = note }
    end
    staleLine = W.Label(frame, "GameFontHighlightSmall")
    staleLine:SetWidth(WIDTH - 48)
    staleLine:SetJustifyH("LEFT")
    staleLine:Hide()
    -- Pay back (Ledger.lua): what another player mailed this account beyond what it mailed back,
    -- here where the player can mail it back. Only this side ever shows.
    owedLine = W.Label(frame, "GameFontHighlightSmall")
    owedLine:SetWidth(WIDTH - 48 - 100)
    owedLine:SetJustifyH("LEFT")
    owedLine:Hide()
    owedButton = W.Button(frame, "Ledger...", 90, function() ns.LedgerUI.Show(frame) end, "MailworthyMailLedger")
    owedButton:Hide()
    createRouteRows()

    mailHead = W.Label(frame, "GameFontNormal")
    mailHead:SetText("Mailing")
    mailHint = W.Label(frame, "GameFontDisableSmall")
    mailHint:SetText("press an item to keep it in your bags")
    mailCount = W.Label(frame, "GameFontHighlightSmall")
    mailPage = pageButton("MailworthyMailPage", "mail")
    mailEmpty = W.Label(frame, "GameFontDisableSmall")
    mailEmpty:SetText("Nothing worth mailing in your bags right now.")
    createMailRows()

    stayHead = W.Label(frame, "GameFontNormal")
    stayHead:SetText("Staying in your bags")
    stayCount = W.Label(frame, "GameFontHighlightSmall")
    stayPage = pageButton("MailworthyStayPage", "stay")
    createStayRows()

    totalLine = W.Label(frame, "GameFontNormalLarge")
    totalLine:SetTextColor(0.6, 1, 0.5)
    totalNote = W.Label(frame, "GameFontHighlightSmall")
    totalNote:SetWidth(WIDTH - 48)
    totalNote:SetJustifyH("LEFT")

    sendButton = W.Button(frame, "Send", 190, function() UI.Send() end, "MailworthyMailSend")
    settingsButton = W.Button(frame, "Settings", 110, function() ns.SettingsUI.Show(frame) end, "MailworthyMailSettings")
    legend = W.Label(frame, "GameFontHighlightSmall")

    frame:SetScript("OnHide", function(self)
        if type(send) == "table" and self:GetParent() ~= send then self:SetParent(send) end
    end)
    -- The lock glow shows only while this window is open (Border.Wanted): redraw it on both.
    local function glow()
        local ok, err = pcall(ns.Border.RefreshAll)
        if not ok then ns.Log.Add("border", "refresh error: %s", tostring(err)) end
    end
    frame:HookScript("OnShow", glow)
    frame:HookScript("OnHide", glow)
    ns.Nav.Attach(frame)
    ns.Log.Add("ui", "mail window created%s", type(send) == "table" and " under SendMailFrame" or "")
    return frame
end

--- Fill the shown rows of a list from its page; returns how many show.
local function fillList(rows, items, page, perPage, fill)
    local first = (page - 1) * perPage
    local shown = 0
    for i, row in ipairs(rows) do
        local item = items[first + i]
        row.item = item
        if item then
            fill(row, item)
            row.button:Show()
            shown = shown + 1
        else
            row.button:Hide()
        end
    end
    return shown
end

local function fillMailRow(row, item)
    local chip = UI.CHIPS[item.result.route] or UI.CHIPS.common
    row.icon:SetTexture(item.icon)
    row.name:SetText(UI.ItemText(item.link, item.count, item.stacks))
    row.chip:SetText(item.result.to and ("to " .. firstName(item.result.to)) or chip[1])
    row.chipBg:SetColorTexture(chip[2], chip[3], chip[4], 0.9)
    row.gain:SetText(item.result.gain and ("+" .. money(item.result.gain)) or "")
end

local function fillStayRow(row, item)
    row.name:SetText(UI.ItemText(item.link, item.count))
    local reason = UI.StayReason(item.result)
    if item.result.reason == "locked" then reason = UI.LOCKED_COLOR .. reason .. "|r" end
    row.reason:SetText(reason)
end

local function pageLabel(button, list, rows)
    local count = math.ceil(#list / rows)
    if count <= 1 then
        button:Hide()
        return
    end
    button:SetText(string.format("%d/%d  >", math.min(pages[button == mailPage and "mail" or "stay"], count), count))
    button:Show()
end

--- Pure: the pay-back line for the ledger's debts (Ledger.Debts: most first), or nil.
function UI.OwedText(debts)
    local d = debts and debts[1]
    if not d then return nil end
    local text = ns.Ledger.DebtText(d.name, d.net)
    if #debts > 1 then text = text .. string.format(" |cffaaaaaa(and %d more)|r", #debts - 1) end
    return text
end

--- Place everything top to bottom for the rows that show; returns the window height.
--- `n` = { routes = , mail = , stay = } shown row counts; `n.stale` = the stale-prices line shows;
--- `n.to` = recipient lines under "To:" (more than one recipient).
function UI.Layout(n)
    local y = -76
    for i, line in ipairs(toLines) do
        if i <= (n.to or 0) then
            at(line.name, 50, y + 4)
            at(line.note, -26, y + 2, "TOPRIGHT")
            y = y - 20
        end
    end
    if (n.to or 0) > 0 then y = y - 6 end
    if n.stale then
        at(staleLine, 24, y)
        y = y - 32
    end
    if n.owed then
        at(owedLine, 24, y - 2)
        at(owedButton, -24, y + 4, "TOPRIGHT")
        y = y - 30
    end
    if n.routes > 0 then
        at(routesHead, 24, y)
        at(friendsButton, -24, y + 4, "TOPRIGHT")
        at(guildButton, -120, y + 4, "TOPRIGHT")
        y = y - 22
        for i, row in ipairs(routeRows) do
            if i <= n.routes then
                at(row.text, 28, y - 5)
                at(row.skip, -102, y, "TOPRIGHT")
                at(row.remove, -20, y, "TOPRIGHT")
                y = y - ROUTE_ROW
            end
        end
        y = y - 10
    end

    at(mailHead, 22, y)
    at(mailHint, 90, y - 2)
    at(mailCount, -24, y - 2, "TOPRIGHT")
    at(mailPage, -150, y + 4, "TOPRIGHT")
    y = y - 18
    for i, row in ipairs(mailRows) do
        row.button:SetPoint("TOP", frame, "TOP", 0, y - (i - 1) * MAIL_ROW)
    end
    if n.mail == 0 then
        at(mailEmpty, 28, y - 4)
        y = y - 22
    end
    y = y - n.mail * MAIL_ROW - 8

    if n.stay > 0 then
        at(stayHead, 22, y)
        at(stayCount, -24, y - 2, "TOPRIGHT")
        at(stayPage, -150, y + 4, "TOPRIGHT")
        y = y - 18
        for i, row in ipairs(stayRows) do
            row.button:SetPoint("TOP", frame, "TOP", 0, y - (i - 1) * STAY_ROW)
        end
        y = y - n.stay * STAY_ROW - 8
    end

    at(totalLine, 24, y - 2)
    at(totalNote, 24, y - 24)
    y = y - 50
    at(sendButton, 20, y)
    at(settingsButton, 220, y)
    at(legend, -24, y - 5, "TOPRIGHT")
    return -(y - 22) + 18
end

--- Re-scan the bags (unless only paging) and redraw.
function UI.Refresh(keepScan)
    if not frame then return end
    if not keepScan or not result then
        if not ns.Mailer.Busy() then result = ns.Bags.Evaluate() end
    end
    if not result then return end
    local pad = ns.MailButton.GamepadUI()
    title:SetText("Mailworthy  " .. (pad and ns.Gamepad.Glyph(ns.Gamepad.FACE_TOP) or ""))
    local bankAlt = ns.Config.BankAlt()
    shownAlt = bankAlt
    local isBankAlt = ns.Config.IsBankAltHere()
    local t = result.totals
    local skipped = ns.Bags.BankAltSkipped()
    local recipients = UI.Recipients(t, bankAlt, isBankAlt, skipped)
    toName:SetText("|cffffd100To:|r " .. recipients[1].name)
    toNote:SetText(recipients[1].note)
    local canSkip = recipients[1].bank and bankAlt ~= nil and not isBankAlt and not ns.Mailer.Busy()
    skipAltButton:SetText(skipped and "Undo skip" or "Skip once")
    if canSkip then skipAltButton:Show() else skipAltButton:Hide() end
    at(skipAltButton, -20, -44, "TOPRIGHT")
    at(toNote, canSkip and -112 or -26, -52, "TOPRIGHT")
    local more = 0
    for i, line in ipairs(toLines) do
        local r = recipients[i + 1]
        if r and i == UI.TO_LINES and #recipients > UI.TO_LINES + 1 then
            line.name:SetText(string.format("|cffaaaaaa+ %d more (see Mailing)|r", #recipients - UI.TO_LINES))
            line.note:SetText("")
        elseif r then
            line.name:SetText(r.name)
            line.note:SetText(r.note)
        end
        if r then
            line.name:Show()
            line.note:Show()
            more = more + 1
        else
            line.name:Hide()
            line.note:Hide()
        end
    end

    for list, n in pairs({ mail = UI.MAIL_ROWS, stay = UI.STAY_ROWS }) do
        local items = result[list == "mail" and "mail" or "keep"]
        if pages[list] > math.max(1, math.ceil(#items / n)) then pages[list] = 1 end
    end
    mailCount:SetText(string.format("%d item%s · %d mail%s", t.items, t.items == 1 and "" or "s",
        t.mails, t.mails == 1 and "" or "s"))
    stayCount:SetText(UI.StayCountText(#result.keep, result.locked or 0))
    local okStale, nudge = pcall(ns.Stale.Current)
    local staleText = okStale and ns.Stale.Text(nudge) or nil
    staleLine:SetText(staleText or "")
    if staleText then staleLine:Show() else staleLine:Hide() end
    local owedText = UI.OwedText(ns.Ledger.On() and ns.Ledger.Debts() or {})
    owedLine:SetText(owedText or "")
    for _, w in ipairs({ owedLine, owedButton }) do
        if owedText then w:Show() else w:Hide() end
    end
    local shown = {
        to = more,
        stale = staleText ~= nil,
        owed = owedText ~= nil,
        routes = fillRoutes(),
        mail = fillList(mailRows, result.mail, pages.mail, UI.MAIL_ROWS, fillMailRow),
        stay = fillList(stayRows, result.keep, pages.stay, UI.STAY_ROWS, fillStayRow),
    }
    pageLabel(mailPage, result.mail, UI.MAIL_ROWS)
    pageLabel(stayPage, result.keep, UI.STAY_ROWS)
    -- The hint gives way to the pager on a long list (they share the heading line).
    if shown.mail > 0 and not mailPage:IsShown() then mailHint:Show() else mailHint:Hide() end
    if shown.mail > 0 then mailEmpty:Hide() else mailEmpty:Show() end
    for _, w in ipairs({ stayHead, stayCount }) do
        if shown.stay > 0 then w:Show() else w:Hide() end
    end

    if result.priced then
        totalLine:SetText("+" .. money(t.gain) .. " more than vendoring")
        totalNote:SetText(string.format("after the %d%% AH cut, %dh deposits and %s postage",
            math.floor(result.settings.cut * 100 + 0.5), ns.Valuation.DURATION_HOURS[result.settings.duration],
            money(t.postage)))
    else
        totalLine:SetText(string.format("%d common item%s to mail", t.items, t.items == 1 and "" or "s"))
        totalNote:SetText("No Auctionator: only white items go. Postage " .. money(t.postage) .. ".")
    end
    -- While sending (and after), the mailer's progress or problem takes the fees line.
    local status = ns.Mailer.Status()
    if status then totalNote:SetText(status) end
    sendButton:SetText(ns.Mailer.Busy() and "Sending..." or UI.SendText(t.recipients, bankAlt, isBankAlt, skipped))
    renderedInbox = UI.OnInbox()
    sendButton:Show()
    if renderedInbox and not ns.Mailer.Busy() then
        -- Mail goes out from the Send Mail tab only, and we never switch tabs ourselves
        -- (MailFrameTab_OnClick taints the controller UI). Send is greyed out here and names the
        -- tab (operator, 2026-11-08: "the button should be greyed out with a 'click send mail'
        -- text"); on Send Mail the watcher redraws it as "Send to ..." and the list follows.
        sendButton:SetText(UI.InboxSendText(pad))
        sendButton:Disable()
    else
        sendButton:Enable()
    end
    legend:SetText(pad and W.Legend() or "")
    frame:SetHeight(UI.Layout(shown))
    ns.Nav.Revalidate()
end

--- Pure: the items of a fresh scan (`fresh`, its mail list, for bank alt `freshAlt`) going
--- somewhere the list on screen (`shown`, drawn for `previewAlt`) didn't say: an item the preview
--- sent elsewhere, or a new one (bags changed) to a player the preview didn't name; the bank alt
--- the list named is always shown ("To: ..."). Items are told apart by link (one item ID can be
--- several items: a green's random suffix), and one item may go to several shown recipients.
--- A binding's recipient can move between the preview and Send without the bags changing (a
--- crafter's skill passes a material, two bindings swap on "lowest skill first"), and so can the
--- bank alt (picked in Settings beside the list) (Codex review, 2026-11-07).
--- `stayed` (the list's Staying items): one of those now in the mail is a change too (a quest
--- abandoned after the preview; Codex review, 2026-11-08), whoever it goes to.
function UI.Changed(shown, fresh, previewAlt, freshAlt, stayed)
    if freshAlt == nil then freshAlt = previewAlt end
    local function key(it) return it.link or it.itemID end
    local kept = {}
    for _, it in ipairs(stayed or {}) do kept[key(it)] = true end
    local was, named = {}, { [tostring(previewAlt)] = true }
    for _, it in ipairs(shown or {}) do
        local to = tostring(it.result and it.result.to or previewAlt)
        local k = key(it)
        was[k] = was[k] or {}
        was[k][to] = true
        named[to] = true
    end
    local changed = {}
    for _, it in ipairs(fresh or {}) do
        local to = tostring(it.result and it.result.to or freshAlt)
        local before = was[key(it)]
        if kept[key(it)] and not before then
            changed[#changed + 1] = { item = it, was = "Staying", to = to }
        elseif (before and not before[to]) or (not before and not named[to]) then
            changed[#changed + 1] = { item = it, was = before and next(before) or nil, to = to }
        end
    end
    return changed
end

--- Pure: the greyed-out Send button's text on the Inbox (the controller reaches Send Mail with R1).
function UI.InboxSendText(pad)
    return pad and "Send Mail tab: R1" or "Click Send Mail"
end

function UI.Send()
    if not result or UI.OnInbox() then return end
    ns.lastCommand = "Mailworthy Send"
    local shown, alt, stayed = result.mail, shownAlt, result.keep
    UI.Refresh() -- the freshest scan, so the mail list is what's in the bags now
    -- AGENTS Safety: mail goes only to the recipients the player saw. If the fresh scan sends
    -- anything elsewhere, nothing goes: the list now shows where, and a second press sends it.
    local changed = UI.Changed(shown, result.mail, alt, ns.Config.BankAlt(), stayed)
    if #changed > 0 then
        local c = changed[1]
        local name = tostring(c.item.link or ""):match("%[(.-)%]") or ("item " .. tostring(c.item.itemID))
        local text = string.format("Not sent: %s now goes to %s%s. Check the list, then press Send again.", name,
            firstName(c.to), c.was == "Staying" and " instead of staying in your bags"
                or c.was and (" instead of " .. firstName(c.was)) or "")
        ns.Log.Add("mailer", "send held: %d item(s) changed recipient since the preview (%s to %s, was %s)", #changed,
            name, c.to, tostring(c.was))
        ns.Print(text)
        totalNote:SetText("|cffff8040" .. text .. "|r")
        return
    end
    ns.Mailer.Start(result.mail, ns.Config.BankAlt())
    UI.Refresh(true)
end

--- Beside the mail window, as a child of the showing tab; away from a mailbox, centred.
function UI.Show(tab)
    if not frame then UI.Create() end
    local send, inbox, mail = rawget(_G, "SendMailFrame"), rawget(_G, "InboxFrame"), rawget(_G, "MailFrame")
    local parent = (tab == "inbox") and inbox or send
    frame:ClearAllPoints()
    if type(parent) == "table" and type(mail) == "table" then
        if frame:GetParent() ~= parent then frame:SetParent(parent) end
        frame:SetPoint("TOPLEFT", mail, "TOPRIGHT", 8, 0)
    else
        frame:SetParent(UIParent)
        frame:SetPoint("CENTER")
    end
    pages.mail, pages.stay = 1, 1
    UI.Refresh()
    frame:Show()
    ns.Log.Add("ui", "mail window shown (%s tab): %d to mail, %d staying", tostring(tab), #result.mail, #result.keep)
end

--- True while the Inbox tab is what shows, where nothing can be sent. Read from what the
--- player sees (IsVisible), not from which tab the window was opened on: v0.17.1 to v0.20.1
--- tested the window's parent and the Send Mail frame's own shown flag, and in game the Send
--- button stayed hidden on the Send Mail tab (operator, 2026-11-07: "the send mail button is
--- just gone now").
function UI.OnInbox()
    local send, inbox = rawget(_G, "SendMailFrame"), rawget(_G, "InboxFrame")
    if type(send) == "table" and send:IsVisible() then return false end
    return type(inbox) == "table" and inbox:IsVisible() == true
end

--- What the tab test sees, for the log and /mw report.
function UI.TabState()
    local function state(name)
        local f = rawget(_G, name)
        if type(f) ~= "table" then return name .. " missing" end
        return string.format("%s shown %s visible %s", name, tostring(f:IsShown()), tostring(f:IsVisible()))
    end
    local parent = frame and frame:GetParent()
    local parentName = parent and parent.GetName and parent:GetName() or tostring(parent)
    return string.format("%s; %s; window on %s", state("SendMailFrame"), state("InboxFrame"), tostring(parentName))
end

--- The watcher's second job: if the tab changed since the last draw (the Send button and the
--- Inbox note follow it), redraw. Returns true when it redrew.
function UI.CheckTab()
    if not (frame and frame:IsVisible()) or ns.Mailer.Busy() then return false end
    local onInbox = UI.OnInbox()
    if onInbox == renderedInbox then return false end
    ns.Log.Add("ui", "tab changed (%s): %s", onInbox and "Inbox" or "Send Mail", UI.TabState())
    renderedInbox = onInbox -- once per change, even if the redraw fails
    UI.Refresh(true)
    return true
end

local sendWasVisible = false
--- The watcher's third job: the Send Mail tab just showed and the window is closed: open it
--- (operator, 2026-11-08). Once per showing: closed there, it stays closed until the tab shows
--- again. Returns true when it opened the window.
function UI.AutoOpen()
    local send, mail = rawget(_G, "SendMailFrame"), rawget(_G, "MailFrame")
    local visible = type(send) == "table" and send:IsVisible() == true and type(mail) == "table"
    local opened = false
    if visible and not sendWasVisible and ns.Features.On("autoOpen") and not ns.Mailer.Busy()
        and not (frame and frame:IsVisible()) then
        ns.Log.Add("ui", "Send Mail tab shown: window opened")
        UI.Show("send")
        opened = true
    end
    sendWasVisible = visible
    return opened
end

--- Opened on the Inbox and the player moved to Send Mail: move the window there too.
--- (Opened on Send Mail and back from the Inbox needs nothing: it was hidden with its tab.)
function UI.FollowTab()
    local send, inbox = rawget(_G, "SendMailFrame"), rawget(_G, "InboxFrame")
    if frame and frame:IsShown() and type(inbox) == "table" and frame:GetParent() == inbox
        and type(send) == "table" and send:IsShown() then
        ns.Log.Add("ui", "mail window follows to the Send Mail tab")
        UI.Show("send")
        return true
    end
    return false
end

function UI.Toggle(tab)
    -- IsVisible, not IsShown: opened on one tab and hidden with it, the window keeps its shown
    -- flag, and a press on the other tab's button must show it there, not "hide" it.
    if frame and frame:IsVisible() then
        frame:Hide()
    else
        UI.Show(tab)
    end
end

local function refreshIfShown()
    if frame and frame:IsShown() then UI.Refresh() end
end
UI.RefreshIfShown = refreshIfShown

ns.On("PLAYER_LOGIN", function()
    UI.Create()
    -- Our own watcher frame (created at login, on UIParent): reads which tab shows, five
    -- times a second, nothing more. Errors are logged, never raised every frame.
    local watcher = CreateFrame("Frame", "MailworthyTabWatcher", UIParent)
    local elapsed = 0
    watcher:SetScript("OnUpdate", function(_, dt)
        elapsed = elapsed + (dt or 0)
        if elapsed < 0.2 then return end
        elapsed = 0
        local ok, err = pcall(UI.FollowTab)
        if ok then ok, err = pcall(UI.AutoOpen) end
        if ok then ok, err = pcall(UI.CheckTab) end
        if not ok then ns.Log.Add("ui", "tab watcher error: %s", tostring(err)) end
    end)
    ns.Locks.OnChanged(refreshIfShown)
    -- While sending, redraw the status only; once it's done or stopped, re-scan: the bag
    -- update for the sent items may have come mid-send, when it was skipped (v0.4.0).
    ns.Mailer.OnChanged(function()
        if frame and frame:IsShown() then UI.Refresh(ns.Mailer.Busy()) end
    end)
    local settings = ns.SettingsUI.Frame()
    if settings then settings:HookScript("OnHide", refreshIfShown) end
    local friends = ns.RoutesUI.Frame()
    if friends then friends:HookScript("OnHide", refreshIfShown) end
end)
ns.On("BAG_UPDATE_DELAYED", function()
    if not ns.Mailer.Busy() then refreshIfShown() end
end)
