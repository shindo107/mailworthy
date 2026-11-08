-- The friends window (/mw friends, the settings' Friends button, the Mailworthy
-- window's Friends button; media/ux-pass-prototype.png), one view at a time:
--   list: the player's own bindings, each with its price cap stepper, scope (all my
--     characters / this character), where the mail goes (the friend, or the
--     character of theirs that has the profession, as their own Mailworthy
--     reported) and Remove; then "Add a binding...";
--   add, step 1: pick a player (party, guild, own characters, Mailworthy users;
--     online first; their professions shown); step 2: pick the profession (theirs
--     suggested). Binding saves and returns to the list; Back goes one step back.
--     For a guild rule, step 1 lists this character and the guild's members only and
--     the rule goes to the draft, back in the guild view;
--   guild (/mw guild, the settings' Guild button; 2026-11-07: "I want a new button for
--     guild inside the mailworthy settings, seems weird its in the friends tab"): who
--     shared the guild's template, "Guild rules: on / off" in one press, and its rules
--     (why one is left out here); for the guild master and officers (Guild.lua) the
--     rules being edited, each with its cap stepper and Remove, "Add a rule...",
--     "Publish to guild".
-- With no bindings and no guild template it opens straight on step 1. Every control is a
-- button, so the controller drives it (PadKey "settings" set, Nav); nothing needs typing.
local _, ns = ...

local UI = {}
ns.RoutesUI = UI

UI.BINDING_ROWS, UI.CANDIDATE_ROWS, UI.PROFESSION_ROWS = 4, 6, 9
local WIDTH = 560
local BIND_ROW, LIST_ROW = 50, 26
local BIND_TOP = -92
local GUILD_LINE = -66   -- the guild template line in the guild view
local GUILD_HELP = -96   -- what the rules do, under it
local GUILD_TOP = -138   -- the first rule row in the guild view
local LIST_TOP = -72
UI.TITLE = { friends = "Send materials to friends", guild = "Guild materials" }

local W = ns.Widgets

local frame, title, sub, bindHead, stepLabel, chosenLabel, emptyBindings, bindPage, candPage, refreshButton
local addButton, backButton, doneButton, ledgerButton, hint, legend
local guildLabel, guildToggle, publishButton
local bindingRows, candidateRows, professionRows = {}, {}, {}
local pages = { bind = 1, cand = 1 }
local candidates, picked = {}, nil
local view = "list"
local target = "me" -- what the add view makes: "me" (a binding) or "guild" (a template rule)

function UI.Frame() return frame end
--- The line under the step label (the picked player, or the guild view's help).
function UI.ChosenLabel() return chosenLabel end
function UI.Picked() return picked end
--- "list" (the bindings), "add" (step 1: a player; step 2, once picked: the profession) or
--- "guild" (the guild template: on / off, its rules; the editor for the guild master and officers).
function UI.View() return view end
--- What the add view makes: "me" (a binding) or "guild" (a guild template rule).
function UI.Target() return target end

local function selected(text, on)
    return on and ("|cff33ff99> " .. text .. " <|r") or text
end

local function setHint(text) if hint then hint:SetText(text or "") end end

local function pageOf(list, rows, key)
    local count = math.max(1, math.ceil(#list / rows))
    if pages[key] > count then pages[key] = 1 end
    return pages[key], count
end

--- Pure: the cap as the rule it is: "5g each or more: to my bank alt", or "no price cap".
function UI.CapText(route)
    if not route.cap then return "no price cap" end
    return ns.Valuation.Money(route.cap) .. " each or more: to my bank alt"
end

--- What the bound player mailed this account beyond what it mailed back (Ledger.lua), as a
--- grey suffix for their binding row, or "" (only this side ever shows).
function UI.OwedText(name)
    if not ns.Ledger.On() then return "" end
    local net = ns.Ledger.Net(name)
    if net <= 0 then return "" end
    return " |cffaaaaaa(you've received " .. ns.Valuation.Money(net) .. " more from them)|r"
end

--- Pure: the guild template line's text and its toggle's ("Guild rules: on" / "off" / "Use guild
--- rules" before the player chose), or nil toggle when there is no template.
function UI.GuildText(template, canPublish)
    if not template then
        return canPublish and "No guild template yet: add a rule for each profession, then Publish to guild."
            or "No guild template yet: your guild master or an officer makes it here.", nil
    end
    local n = #(template.rules or {})
    local text = string.format("Guild template from %s: %d rule%s", tostring(template.from), n, n == 1 and "" or "s")
    if template.use == nil then return text .. " |cff33ff99(new)|r", "Use guild rules" end
    return text, template.use and "Guild rules: on" or "Guild rules: off"
end

local function at(widget, x, y, point)
    widget:ClearAllPoints()
    widget:SetPoint(point or "TOPLEFT", frame, point or "TOPLEFT", x, y)
end

-- A binding row's buttons act on what the row shows: row.kind "route" (a binding: Routes),
-- "draft" (a guild template rule being edited: Guild), "guild" (a guild rule in force: no buttons).
local function createBindingRows()
    for i = 1, UI.BINDING_ROWS do
        local row = {}
        row.text = W.Label(frame, "GameFontHighlight")
        row.text:SetWidth(420)
        row.text:SetJustifyH("LEFT")
        row.remove = W.Button(frame, "Remove", 80, function()
            if not row.key then return end
            if row.kind == "draft" then
                ns.Guild.DraftRemove(row.key)
                setHint("Rule removed. Publish to guild to send the change.")
                UI.Refresh()
            elseif ns.Routes.Remove(row.key) then
                setHint("Binding removed.")
                UI.Refresh()
                ns.MailWindow.RefreshIfShown()
            end
        end, "MailworthyFriendsRemove" .. i)
        row.cap = W.Label(frame, "GameFontHighlightSmall")
        row.cap:SetWidth(220)
        row.cap:SetJustifyH("LEFT")
        local function step(dir)
            if not row.key then return end
            if row.kind == "draft" then ns.Guild.DraftStepCap(row.key, dir) else ns.Routes.StepCap(row.key, dir) end
            UI.Refresh()
        end
        row.capDown = W.Button(frame, "-", 26, function() step(-1) end, "MailworthyFriendsCapDown" .. i)
        row.capUp = W.Button(frame, "+", 26, function() step(1) end, "MailworthyFriendsCapUp" .. i)
        row.scope = W.Button(frame, "", 150, function()
            if row.key and row.kind == "route" then ns.Routes.ToggleScope(row.key) end
            UI.Refresh()
        end, "MailworthyFriendsScope" .. i)
        row.widgets = { row.text, row.remove, row.cap, row.capDown, row.capUp, row.scope }
        bindingRows[i] = row
    end
    emptyBindings = W.Label(frame, "GameFontHighlightSmall")
    emptyBindings:SetWidth(WIDTH - 56)
    emptyBindings:SetJustifyH("LEFT")
    bindPage = W.Button(frame, "", 70, function()
        pages.bind = pages.bind + 1
        UI.Refresh()
    end, "MailworthyFriendsBindPage")
    addButton = W.Button(frame, "Add a binding...", 140, function()
        target = view == "guild" and "guild" or "me"
        view, picked = "add", nil
        setHint("")
        UI.Reload(target == "guild" and "guild rule" or "binding")
        UI.Refresh()
    end, "MailworthyFriendsAdd")
end

local function placeRow(row, y)
    at(row.text, 28, y - 4)
    at(row.remove, -24, y, "TOPRIGHT")
    at(row.cap, 28, y - 28)
    at(row.capDown, 252, y - 24)
    at(row.capUp, 282, y - 24)
    at(row.scope, -24, y - 24, "TOPRIGHT")
end

local function createGuild()
    guildLabel = W.Label(frame, "GameFontHighlight")
    guildLabel:SetWidth(WIDTH - 56 - 160)
    guildLabel:SetJustifyH("LEFT")
    guildToggle = W.Button(frame, "", 140, function()
        local was = ns.Guild.InUse()
        if ns.Guild.ToggleUse() then
            setHint(was and "Guild rules off: your materials no longer follow the guild template."
                or "Guild rules on: the guild's rules apply after your own bindings and professions.")
            ns.MailWindow.RefreshIfShown()
            local settings = ns.SettingsUI.Frame()
            if settings and settings:IsShown() then ns.SettingsUI.Refresh() end
        end
        UI.Refresh()
    end, "MailworthyFriendsGuildRules")
    publishButton = W.Button(frame, "Publish to guild", 150, function()
        local ok, err = ns.Guild.Publish()
        if not ok then
            setHint("|cffff8040Not published: " .. tostring(err) .. ".|r")
        else
            local text = "Guild template published: " .. ns.Guild.RulesText(ns.Guild.Template().rules) .. "."
            setHint(text)
            ns.Print(text .. " Members who turn the guild rules on mail these materials.")
        end
        UI.Refresh()
    end, "MailworthyFriendsPublish")
end

local function createAdd()
    stepLabel = W.Label(frame, "GameFontHighlight")
    stepLabel:SetPoint("TOPLEFT", 28, -46)
    stepLabel:SetWidth(WIDTH - 250)
    stepLabel:SetJustifyH("LEFT")
    refreshButton = W.Button(frame, "Refresh list", 100, function()
        UI.Reload("refresh")
        UI.Refresh()
    end, "MailworthyFriendsRefresh")
    refreshButton:SetPoint("TOPRIGHT", -24, -42)
    candPage = W.Button(frame, "", 70, function()
        pages.cand = pages.cand + 1
        UI.Refresh()
    end, "MailworthyFriendsPage")
    candPage:SetPoint("TOPRIGHT", -130, -42)
    chosenLabel = W.Label(frame, "GameFontHighlightSmall")
    chosenLabel:SetPoint("TOPLEFT", 28, LIST_TOP - 2)
    chosenLabel:SetWidth(WIDTH - 56)
    chosenLabel:SetJustifyH("LEFT")
    for i = 1, UI.CANDIDATE_ROWS do
        local b = W.Button(frame, "", WIDTH - 48, function() UI.Pick(i) end, "MailworthyFriendsPick" .. i)
        b:SetPoint("TOPLEFT", 24, LIST_TOP - (i - 1) * LIST_ROW)
        b:Hide()
        candidateRows[i] = b
    end
    for i = 1, UI.PROFESSION_ROWS do
        local b = W.Button(frame, "", WIDTH - 48, function() UI.Bind(i) end, "MailworthyFriendsProfession" .. i)
        b:SetPoint("TOPLEFT", 24, LIST_TOP - 24 - (i - 1) * LIST_ROW)
        b:Hide()
        professionRows[i] = b
    end
    backButton = W.Button(frame, "Back", 100, function()
        if view == "add" and picked then
            picked = nil
        elseif view == "add" and target == "guild" then
            view = "guild"
        else
            view = "list"
        end
        setHint("")
        UI.Refresh()
    end, "MailworthyFriendsBack")
end

function UI.Create()
    if frame then return frame end
    frame = W.Window("MailworthyFriendsFrame", WIDTH, 400)
    frame:SetFrameStrata("FULLSCREEN_DIALOG")
    frame:SetPoint("CENTER")
    title = W.Label(frame, "GameFontNormalLarge")
    title:SetPoint("TOP", 0, -18)
    title:SetText(UI.TITLE.friends)
    sub = W.Label(frame, "GameFontHighlightSmall")
    sub:SetPoint("TOPLEFT", 28, -44)
    sub:SetWidth(WIDTH - 56)
    sub:SetJustifyH("LEFT")
    sub:SetText("Each binding mails a profession's materials to one player, every time, until you remove it.")
    bindHead = W.Label(frame, "GameFontNormal")
    bindHead:SetText("Bindings")
    createBindingRows()
    createGuild()
    createAdd()
    hint = W.Label(frame, "GameFontHighlightSmall")
    hint:SetJustifyH("LEFT")
    doneButton = W.Button(frame, "Done", 100, function() frame:Hide() end, "MailworthyFriendsDone")
    ledgerButton = W.Button(frame, "Mail ledger...", 120, function() ns.LedgerUI.Show(frame) end, "MailworthyFriendsLedger")
    legend = W.Label(frame, "GameFontHighlightSmall")
    legend:SetPoint("BOTTOM", 0, 14)
    ns.Nav.Attach(frame)
    ns.Log.Add("ui", "friends window created")
    return frame
end

--- Re-read who can be bound (the roster is asked for and other Mailworthys are asked to say
--- hello). For a guild rule: this character (its author), then guild members only.
local function gather(reason)
    candidates = ns.Routes.Candidates()
    if target == "guild" then
        local members = { ns.Routes.Me() }
        for _, c in ipairs(candidates) do
            if c.sources.guild then members[#members + 1] = c end
        end
        candidates = members
    end
    ns.Log.Add("ui", "friends window: %d candidates (%s)", #candidates, tostring(reason))
end

function UI.Reload(reason)
    ns.Routes.RequestRoster()
    if ns.Comms then ns.Comms.Ask() end
    gather(reason)
end

function UI.Candidates() return candidates end

local function show(widgets, on)
    for _, w in ipairs(widgets) do
        if on then w:Show() else w:Hide() end
    end
end

--- Rows for `list` from `top`; `kindOf(r)` names each row's kind. Returns the y below the last row.
local function fillRows(list, top, kindOf, emptyText)
    local page, count = pageOf(list, UI.BINDING_ROWS, "bind")
    local first = (page - 1) * UI.BINDING_ROWS
    local shown = 0
    for i, row in ipairs(bindingRows) do
        local r = list[first + i]
        row.kind = r and kindOf(r) or nil
        row.key = r and (row.kind == "draft" and r.profession or r.key) or nil
        show(row.widgets, false)
        if r then
            placeRow(row, top - shown * BIND_ROW)
            if row.kind == "draft" then
                local me = tostring(r.to):lower() == tostring(ns.PlayerName()):lower()
                row.text:SetText(ns.Routes.What(r) .. " |cffffd100to " .. r.to .. "|r" .. (me and " |cffaaaaaa(you)|r" or ""))
            elseif row.kind == "guild" then
                local why = ns.Guild.Why(r, ns.Routes.Personal(), ns.Characters.Professions(), ns.PlayerName())
                row.text:SetText(ns.Routes.What(r) .. " |cffffd100to " .. r.to .. "|r"
                    .. (why and (" |cffaaaaaa(not here: " .. why .. ")|r") or ""))
            else
                local to, crafter = ns.Routes.Recipient(r)
                row.text:SetText(ns.Routes.What(r) .. " |cffffd100to " .. r.to .. "|r"
                    .. (crafter and (" |cffaaaaaa(delivered to " .. to .. ")|r") or "") .. UI.OwedText(r.to))
            end
            row.cap:SetText(UI.CapText(r))
            row.scope:SetText(ns.Routes.SCOPES[r.scope] or tostring(r.scope))
            show({ row.text, row.cap }, true)
            show({ row.remove, row.capDown, row.capUp }, row.kind ~= "guild")
            show({ row.scope }, row.kind == "route")
            shown = shown + 1
        end
    end
    if #list == 0 then
        emptyBindings:SetText(emptyText)
        at(emptyBindings, 28, top - 4)
        emptyBindings:Show()
    else
        emptyBindings:Hide()
    end
    if count > 1 then
        bindPage:SetText(string.format("%d/%d  >", page, count))
        at(bindPage, -24, top + 26, "TOPRIGHT")
        bindPage:Show()
    else
        bindPage:Hide()
    end
    return top - shown * BIND_ROW - (shown == 0 and 30 or 0)
end

--- Pure: what the guild view says under the template line.
function UI.GuildHelp(canPublish)
    if canPublish then
        return "Members who turn the guild rules on mail each profession's own materials to the player named "
            .. "(you too). Their own bindings and professions come first."
    end
    return "With the guild rules on, each profession's own materials go to the player named. "
        .. "Your own bindings and professions come first."
end

--- The guild view's head: the template line with its one-press toggle, then what the rules do.
local function fillGuildHead(canPublish)
    local name = ns.Guild.Mine()
    stepLabel:SetText("|cffffd100Guild template|r" .. (name and (" for " .. name) or ""))
    local text, toggle
    if not ns.Guild.On() then
        text = "The guild template is switched off (/mw feature guildTemplate on)."
    elseif not name then
        text = "Not in a guild (or the game hasn't said which yet)."
    else
        text, toggle = UI.GuildText(ns.Guild.Template(), canPublish)
    end
    guildLabel:SetText(text)
    at(guildLabel, 28, GUILD_LINE - 4)
    guildLabel:Show()
    if toggle then
        guildToggle:SetText(toggle)
        at(guildToggle, -24, GUILD_LINE, "TOPRIGHT")
        guildToggle:Show()
    else
        guildToggle:Hide()
    end
    chosenLabel:SetText(name and ns.Guild.On() and UI.GuildHelp(canPublish) or "")
    at(chosenLabel, 28, GUILD_HELP)
    chosenLabel:Show()
end

local function fillCandidates()
    local page, count = pageOf(candidates, UI.CANDIDATE_ROWS, "cand")
    local first = (page - 1) * UI.CANDIDATE_ROWS
    local shown = 0
    for i, b in ipairs(candidateRows) do
        local c = candidates[first + i]
        if c then
            b:SetText(ns.Routes.CandidateText(c))
            b:Show()
            shown = shown + 1
        else
            b:Hide()
        end
    end
    if count > 1 then
        candPage:SetText(string.format("%d/%d  >", page, count))
        candPage:Show()
    else
        candPage:Hide()
    end
    refreshButton:Show()
    if #candidates == 0 then
        stepLabel:SetText("|cffaaaaaa1 of 2|r  Nobody to " .. (target == "guild" and "name yet" or "bind yet"))
        chosenLabel:SetText(target == "guild" and "The guild roster may take a moment: press Refresh list."
            or ("Join a group, be in a guild (the roster may take a moment), or log in on another of "
            .. "your characters once, then press Refresh list."))
        chosenLabel:Show()
        return LIST_TOP - 40
    end
    stepLabel:SetText("|cffaaaaaa1 of 2|r  |cffffd100" .. (target == "guild" and "Which guild member gets them?"
        or "Who should get your materials?") .. "|r")
    return LIST_TOP - shown * LIST_ROW
end

--- Step 2's choices for the picked player: their class's items first when their class is known
--- (operator, 2026-11-08: a mage-only scroll to a mage friend; not for guild rules, which are
--- per profession), then every crafting profession. { { id, class, text, suggested }, ... }.
function UI.Options(candidate, forGuild)
    local list = {}
    local class = candidate and ns.Classes.Token(candidate.class)
    if class and not forGuild then
        local name = ns.Classes.Name(class)
        list[#list + 1] = { class = class, suggested = true,
            text = string.format("%s items (only a %s can use them)", name, name:lower()) }
    end
    local suggested = {}
    for _, p in ipairs(candidate and ns.Routes.Suggested(candidate) or {}) do suggested[p.id] = true end
    for _, p in ipairs(ns.Routes.Professions()) do
        list[#list + 1] = { id = p.id, text = p.name .. " (" .. p.mats .. ")", suggested = suggested[p.id] == true }
    end
    return list
end

local function fillProfessions()
    stepLabel:SetText("|cffaaaaaa2 of 2|r  |cffffd100What should " .. (tostring(picked.name):match("^(%S+)") or picked.name)
        .. " get" .. (target == "guild" and " from the guild" or "") .. "?|r")
    chosenLabel:SetText(ns.Routes.CandidateText(picked))
    chosenLabel:Show()
    local shown = 0
    local options = UI.Options(picked, target == "guild")
    for i, b in ipairs(professionRows) do
        local p = options[i]
        if p then
            b:SetText(selected(p.text, p.suggested))
            b:Show()
            shown = shown + 1
        else
            b:Hide()
        end
    end
    candPage:Hide()
    refreshButton:Hide()
    if hint:GetText() == nil or hint:GetText() == "" then
        setHint("Over the cap (" .. ns.Valuation.Money(ns.Routes.CAP_STEPS[1]) .. " each to start) a material goes to "
            .. "your bank alt instead.")
    end
    return LIST_TOP - 24 - shown * LIST_ROW
end

--- Show the widgets of the current view, place the footer under the last row, size the window.
function UI.Refresh()
    if not frame then return end
    local list, guild, add = view == "list", view == "guild", view == "add"
    title:SetText((guild or (add and target == "guild")) and UI.TITLE.guild or UI.TITLE.friends)
    show({ sub }, list)
    show({ stepLabel }, not list)
    show({ bindHead }, false)
    if not add then
        for _, b in ipairs(candidateRows) do b:Hide() end
        for _, b in ipairs(professionRows) do b:Hide() end
        show({ candPage, refreshButton, chosenLabel }, false)
    end
    if not guild then show({ guildLabel, guildToggle }, false) end
    if not guild then publishButton:Hide() end
    if not list then ledgerButton:Hide() end
    if add then
        for _, row in ipairs(bindingRows) do show(row.widgets, false) end
        show({ emptyBindings, bindPage, addButton }, false)
    end
    local y
    if list then
        local top = BIND_TOP
        at(bindHead, 20, top + 22)
        bindHead:Show()
        y = fillRows(ns.Routes.Personal(), top, function() return "route" end,
            "None yet: press Add a binding to pick a player, then the profession whose materials they get.")
        addButton:SetText("Add a binding...")
        addButton:Show()
        backButton:Hide()
        at(addButton, 24, y - 10)
        at(hint, 176, y - 14)
        hint:SetWidth(WIDTH - 176 - 260)
        at(ledgerButton, -134, y - 10, "TOPRIGHT")
        ledgerButton:Show()
        at(doneButton, -24, y - 10, "TOPRIGHT")
    elseif guild then
        local canPublish = ns.Guild.On() and ns.Guild.CanPublish()
        fillGuildHead(canPublish)
        local template = ns.Guild.On() and ns.Guild.Template() or nil
        if canPublish then
            y = fillRows(ns.Guild.Draft() or {}, GUILD_TOP, function() return "draft" end,
                "No rules yet: press Add a rule to pick yourself or a guild member, then the profession whose "
                .. "materials they get.")
            addButton:SetText("Add a rule...")
            addButton:Show()
            publishButton:SetText(ns.Guild.DraftChanged() and "Publish to guild" or "Send again")
            at(addButton, 24, y - 10)
            at(publishButton, 174, y - 10)
            publishButton:Show()
        else
            y = fillRows(template and template.rules or {}, GUILD_TOP, function() return "guild" end,
                template and "This template has no rules." or "")
            addButton:Hide()
            publishButton:Hide()
        end
        backButton:Hide()
        at(doneButton, -24, y - 10, "TOPRIGHT")
        y = y - 30
        at(hint, 28, y - 14)
        hint:SetWidth(WIDTH - 56)
    else
        at(chosenLabel, 28, LIST_TOP - 2) -- the guild view moves it under its template line
        if picked then
            for _, b in ipairs(candidateRows) do b:Hide() end
            y = fillProfessions()
        else
            for _, b in ipairs(professionRows) do b:Hide() end
            chosenLabel:Hide()
            y = fillCandidates()
        end
        backButton:Show()
        at(hint, 28, y - 14)
        hint:SetWidth(WIDTH - 56 - 230)
        at(backButton, -134, y - 10, "TOPRIGHT")
        at(doneButton, -24, y - 10, "TOPRIGHT")
    end
    frame:SetHeight(-(y - 10) + 22 + 40)
    legend:SetText(ns.MailButton.GamepadUI() and W.Legend() or "")
    ns.Nav.Revalidate()
end

--- Step 1: a player.
function UI.Pick(i)
    local c = candidates[(pages.cand - 1) * UI.CANDIDATE_ROWS + i]
    if not c then return end
    picked = c
    setHint("")
    UI.Refresh()
end

--- Step 2: the profession; a binding is saved for all the account's characters here, a
--- guild rule goes to the draft (published with Publish to guild).
function UI.Bind(i)
    local p = picked and UI.Options(picked, target == "guild")[i]
    if not p or not picked then return end
    if target == "guild" and not p.class then
        local rule, err = ns.Guild.DraftAdd(picked.name, p.id)
        if not rule then
            setHint("|cffff8040Not added: " .. tostring(err) .. ".|r")
            return
        end
        setHint(string.format("%s to %s%s. Publish to guild to send it.", ns.Routes.What(rule), rule.to,
            err and (" (was " .. tostring(err) .. ")") or ""))
        picked, view = nil, "guild"
        UI.Refresh()
        return
    end
    local route, err = ns.Routes.Add(picked.name, p.class or p.id)
    if not route then
        setHint("|cffff8040Not bound: " .. tostring(err) .. ".|r")
        return
    end
    local text = string.format("%s now go to %s. Remove it any time; at the mailbox, Skip once drops it for one visit.",
        ns.Routes.What(route), route.to)
    setHint(text)
    ns.Print(text)
    picked, view = nil, "list"
    UI.Refresh()
    ns.MailWindow.RefreshIfShown()
end

--- `opener`: the Mailworthy window whose button opened it (placed beside that), or nil (centred).
function UI.Show(opener)
    if not frame then UI.Create() end
    W.PlaceBeside(frame, opener)
    picked, target = nil, "me"
    view = #ns.Routes.Personal() == 0 and "add" or "list"
    pages.bind, pages.cand = 1, 1
    setHint("")
    UI.Reload("shown")
    UI.Refresh()
    frame:Show()
    frame:Raise()
    ns.Log.Add("ui", "friends window shown")
end

--- The guild view (/mw guild, the settings' Guild button): the template, on / off, and for the
--- guild master and officers its editor. `opener` as for UI.Show.
function UI.ShowGuild(opener)
    if not frame then UI.Create() end
    W.PlaceBeside(frame, opener)
    picked, target, view = nil, "guild", "guild"
    pages.bind, pages.cand = 1, 1
    setHint("")
    ns.Routes.RequestRoster()
    if ns.Guild.On() and not ns.Guild.Template() then ns.Guild.Ask("guild window") end
    UI.Refresh()
    frame:Show()
    frame:Raise()
    ns.Log.Add("ui", "guild window shown")
end

function UI.Toggle()
    if frame and frame:IsShown() then frame:Hide() else UI.Show() end
end

function UI.RefreshIfShown()
    if frame and frame:IsShown() then UI.Refresh() end
end

local function reloadIfShown(reason)
    if frame and frame:IsShown() and view == "add" and not picked then
        gather(reason)
        UI.Refresh()
    end
end

ns.On("PLAYER_LOGIN", function() UI.Create() end)
ns.On("GUILD_ROSTER_UPDATE", function() reloadIfShown("roster") end)
ns.On("GROUP_ROSTER_UPDATE", function() reloadIfShown("group") end)
ns.On("CHAT_MSG_ADDON", function(prefix)
    if ns.Comms and prefix == ns.Comms.PREFIX then reloadIfShown("hello") end
end)
