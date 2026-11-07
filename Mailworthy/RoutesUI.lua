-- The friends window (/mw friends, the settings' Friends button, the Mailworthy
-- window's Friends button; media/ux-pass-prototype.png), one view at a time:
--   list: the guild template line (when the guild has one, or this character may
--     make one: who shared it, "Guild rules: on / off" in one press, Edit...), then
--     the bindings in force, each with its price cap stepper, scope (all my
--     characters / this character), where the mail goes (the friend, or the
--     character of theirs that has the profession, as their own Mailworthy
--     reported) and Remove; the guild's rules show as rows without buttons; then
--     "Add a binding...";
--   add, step 1: pick a player (party, guild, own characters, Mailworthy users;
--     online first; their professions shown); step 2: pick the profession (theirs
--     suggested). Binding saves and returns to the list; Back goes one step back.
--     For a guild rule, step 1 lists guild members only and the rule goes to the
--     draft, back in the guild view;
--   guild (guild master and officers, Guild.lua): the template's rules being edited,
--     each with its cap stepper and Remove; "Add a rule...", "Publish to guild", Back.
-- With no bindings and no guild template it opens straight on step 1. Every control is a
-- button, so the controller drives it (PadKey "settings" set, Nav); nothing needs typing.
local _, ns = ...

local UI = {}
ns.RoutesUI = UI

UI.BINDING_ROWS, UI.CANDIDATE_ROWS, UI.PROFESSION_ROWS = 4, 6, 8
local WIDTH = 560
local BIND_ROW, LIST_ROW = 50, 26
local BIND_TOP = -92
local GUILD_LINE = -66   -- the guild template line in the list view
local GUILD_SHIFT = 30   -- how far it pushes the bindings down
local DRAFT_TOP = -112   -- the first rule row in the guild view
local LIST_TOP = -72

local W = ns.Widgets

local frame, sub, bindHead, stepLabel, chosenLabel, emptyBindings, bindPage, candPage, refreshButton
local addButton, backButton, doneButton, hint, legend
local guildLabel, guildToggle, guildEdit, publishButton
local bindingRows, candidateRows, professionRows = {}, {}, {}
local pages = { bind = 1, cand = 1 }
local candidates, picked = {}, nil
local view = "list"
local target = "me" -- what the add view makes: "me" (a binding) or "guild" (a template rule)

function UI.Frame() return frame end
function UI.Picked() return picked end
--- "list" (the bindings), "add" (step 1: a player; step 2, once picked: the profession) or
--- "guild" (the guild template's rules, for the guild master and officers).
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

--- Pure: the guild template line's text and its toggle's ("Guild rules: on" / "off" / "Use guild
--- rules" before the player chose), or nil toggle when there is no template.
function UI.GuildText(template, canPublish)
    if not template then
        return canPublish and "No guild template yet: make one for your guild's materials." or nil, nil
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
    guildLabel:SetWidth(WIDTH - 56 - 250)
    guildLabel:SetJustifyH("LEFT")
    guildToggle = W.Button(frame, "", 140, function()
        local was = ns.Guild.InUse()
        if ns.Guild.ToggleUse() then
            setHint(was and "Guild rules off: your materials no longer follow the guild template."
                or "Guild rules on: the guild's rules apply after your own bindings and professions.")
            ns.MailWindow.RefreshIfShown()
        end
        UI.Refresh()
    end, "MailworthyFriendsGuildRules")
    guildEdit = W.Button(frame, "Edit...", 90, function()
        view, picked = "guild", nil
        pages.bind = 1
        setHint("")
        UI.Refresh()
    end, "MailworthyFriendsGuildEdit")
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
        local b = W.Button(frame, "", 250, function() UI.Bind(i) end, "MailworthyFriendsProfession" .. i)
        b:SetPoint("TOPLEFT", 24 + ((i - 1) % 2) * 262, LIST_TOP - 24 - math.floor((i - 1) / 2) * LIST_ROW)
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
    local title = W.Label(frame, "GameFontNormalLarge")
    title:SetPoint("TOP", 0, -18)
    title:SetText("Send materials to friends")
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
    legend = W.Label(frame, "GameFontHighlightSmall")
    legend:SetPoint("BOTTOM", 0, 14)
    ns.Nav.Attach(frame)
    ns.Log.Add("ui", "friends window created")
    return frame
end

--- Re-read who can be bound (the roster is asked for and other Mailworthys are asked to say
--- hello). For a guild rule: guild members only.
local function gather(reason)
    candidates = ns.Routes.Candidates()
    if target == "guild" then
        local members = {}
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
                row.text:SetText(ns.Routes.What(r) .. " |cffffd100to " .. r.to .. "|r")
            else
                local to, crafter = ns.Routes.Recipient(r)
                row.text:SetText(ns.Routes.What(r) .. " |cffffd100to " .. r.to .. "|r"
                    .. (crafter and (" |cffaaaaaa(delivered to " .. to .. ")|r") or ""))
            end
            row.cap:SetText(UI.CapText(r) .. (row.kind == "guild" and "  |cffaaaaaa(guild template)|r" or ""))
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

--- The list view's guild line; returns how far it pushes the bindings down.
local function fillGuildLine()
    local template, canPublish = ns.Guild.On() and ns.Guild.Template() or nil, ns.Guild.On() and ns.Guild.CanPublish()
    local text, toggle = UI.GuildText(template, canPublish)
    if not text then
        show({ guildLabel, guildToggle, guildEdit }, false)
        return 0
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
    if canPublish then
        guildEdit:SetText(template and "Edit..." or "Create...")
        at(guildEdit, toggle and -170 or -24, GUILD_LINE, "TOPRIGHT")
        guildEdit:Show()
    else
        guildEdit:Hide()
    end
    return GUILD_SHIFT
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

local function fillProfessions()
    local suggested = {}
    for _, p in ipairs(ns.Routes.Suggested(picked)) do suggested[p.id] = true end
    stepLabel:SetText("|cffaaaaaa2 of 2|r  |cffffd100What should " .. (tostring(picked.name):match("^(%S+)") or picked.name)
        .. " get" .. (target == "guild" and " from the guild" or "") .. "?|r")
    chosenLabel:SetText(ns.Routes.CandidateText(picked))
    chosenLabel:Show()
    local shown = 0
    for i, b in ipairs(professionRows) do
        local p = ns.Routes.Professions()[i]
        if p then
            b:SetText(selected(p.name .. " (" .. p.mats .. ")", suggested[p.id] == true))
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
    return LIST_TOP - 24 - math.ceil(shown / 2) * LIST_ROW
end

--- Show the widgets of the current view, place the footer under the last row, size the window.
function UI.Refresh()
    if not frame then return end
    if view == "guild" and not ns.Guild.CanPublish() then view = "list" end
    local list, guild, add = view == "list", view == "guild", view == "add"
    show({ sub }, list)
    show({ stepLabel }, not list)
    show({ bindHead }, false)
    if not add then
        for _, b in ipairs(candidateRows) do b:Hide() end
        for _, b in ipairs(professionRows) do b:Hide() end
        show({ candPage, refreshButton, chosenLabel }, false)
    end
    if not list then show({ guildLabel, guildToggle, guildEdit }, false) end
    if not guild then publishButton:Hide() end
    if add then
        for _, row in ipairs(bindingRows) do show(row.widgets, false) end
        show({ emptyBindings, bindPage, addButton }, false)
    end
    local y
    if list then
        local top = BIND_TOP - fillGuildLine()
        at(bindHead, 20, top + 22)
        bindHead:Show()
        y = fillRows(ns.Routes.List(), top, function(r) return r.scope == "guild" and "guild" or "route" end,
            "None yet: press Add a binding to pick a player, then the profession whose materials they get.")
        addButton:SetText("Add a binding...")
        addButton:Show()
        backButton:Hide()
        at(addButton, 24, y - 10)
        at(hint, 176, y - 14)
        hint:SetWidth(WIDTH - 176 - 140)
        at(doneButton, -24, y - 10, "TOPRIGHT")
    elseif guild then
        stepLabel:SetText("|cffffd100Guild template|r for " .. tostring((ns.Guild.Mine())))
        chosenLabel:SetText("Members who turn the guild rules on mail each profession's materials to the player named. "
            .. "Their own bindings and professions come first.")
        at(chosenLabel, 28, LIST_TOP - 2)
        chosenLabel:Show()
        y = fillRows(ns.Guild.Draft() or {}, DRAFT_TOP, function() return "draft" end,
            "No rules yet: press Add a rule to pick a guild member, then the profession whose materials they get.")
        addButton:SetText("Add a rule...")
        addButton:Show()
        publishButton:SetText(ns.Guild.DraftChanged() and "Publish to guild" or "Send again")
        at(addButton, 24, y - 10)
        at(publishButton, 174, y - 10)
        publishButton:Show()
        backButton:Show()
        at(backButton, -134, y - 10, "TOPRIGHT")
        at(doneButton, -24, y - 10, "TOPRIGHT")
        y = y - 30
        at(hint, 28, y - 14)
        hint:SetWidth(WIDTH - 56)
    else
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
    local p = ns.Routes.Professions()[i]
    if not p or not picked then return end
    if target == "guild" then
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
    local route, err = ns.Routes.Add(picked.name, p.id)
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
    local guildLine = ns.Guild.On() and (ns.Guild.Template() or ns.Guild.CanPublish())
    view = (ns.Routes.Count() == 0 and not guildLine) and "add" or "list"
    pages.bind, pages.cand = 1, 1
    setHint("")
    UI.Reload("shown")
    if ns.Guild.On() and not ns.Guild.Template() then ns.Guild.Ask("friends window") end
    UI.Refresh()
    frame:Show()
    frame:Raise()
    ns.Log.Add("ui", "friends window shown")
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
