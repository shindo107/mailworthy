-- The friends window (/mw friends, the settings' Friends button, the Mailworthy
-- window's Friends button; media/ux-pass-prototype.png), one view at a time:
--   list: the bindings in force, each with its price cap stepper, scope (all my
--     characters / this character), where the mail goes (the friend, or the
--     character of theirs that has the profession, as their own Mailworthy
--     reported) and Remove; then "Add a binding...";
--   add, step 1: pick a player (party, guild, own characters, Mailworthy users;
--     online first; their professions shown); step 2: pick the profession (theirs
--     suggested). Binding saves and returns to the list; Back goes one step back.
-- With no bindings yet it opens straight on step 1. Every control is a button, so
-- the controller drives it (PadKey "settings" set, Nav); nothing needs typing.
local _, ns = ...

local UI = {}
ns.RoutesUI = UI

UI.BINDING_ROWS, UI.CANDIDATE_ROWS, UI.PROFESSION_ROWS = 4, 6, 8
local WIDTH = 560
local BIND_ROW, LIST_ROW = 50, 26
local BIND_TOP = -92
local LIST_TOP = -72

local W = ns.Widgets

local frame, sub, bindHead, stepLabel, chosenLabel, emptyBindings, bindPage, candPage, refreshButton
local addButton, backButton, doneButton, hint, legend
local bindingRows, candidateRows, professionRows = {}, {}, {}
local pages = { bind = 1, cand = 1 }
local candidates, picked = {}, nil
local view = "list"

function UI.Frame() return frame end
function UI.Picked() return picked end
--- "list" (the bindings) or "add" (step 1: a player; step 2, once picked: the profession).
function UI.View() return view end

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

local function at(widget, x, y, point)
    widget:ClearAllPoints()
    widget:SetPoint(point or "TOPLEFT", frame, point or "TOPLEFT", x, y)
end

local function createBindingRows()
    for i = 1, UI.BINDING_ROWS do
        local row = {}
        local y = BIND_TOP - (i - 1) * BIND_ROW
        row.text = W.Label(frame, "GameFontHighlight")
        row.text:SetPoint("TOPLEFT", 28, y - 4)
        row.text:SetWidth(420)
        row.text:SetJustifyH("LEFT")
        row.remove = W.Button(frame, "Remove", 80, function()
            if row.key and ns.Routes.Remove(row.key) then
                setHint("Binding removed.")
                UI.Refresh()
                ns.MailWindow.RefreshIfShown()
            end
        end, "MailworthyFriendsRemove" .. i)
        row.remove:SetPoint("TOPRIGHT", -24, y)
        row.cap = W.Label(frame, "GameFontHighlightSmall")
        row.cap:SetPoint("TOPLEFT", 28, y - 28)
        row.cap:SetWidth(220)
        row.cap:SetJustifyH("LEFT")
        row.capDown = W.Button(frame, "-", 26, function()
            if row.key then ns.Routes.StepCap(row.key, -1) end
            UI.Refresh()
        end, "MailworthyFriendsCapDown" .. i)
        row.capDown:SetPoint("TOPLEFT", 252, y - 24)
        row.capUp = W.Button(frame, "+", 26, function()
            if row.key then ns.Routes.StepCap(row.key, 1) end
            UI.Refresh()
        end, "MailworthyFriendsCapUp" .. i)
        row.capUp:SetPoint("TOPLEFT", 282, y - 24)
        row.scope = W.Button(frame, "", 150, function()
            if row.key then ns.Routes.ToggleScope(row.key) end
            UI.Refresh()
        end, "MailworthyFriendsScope" .. i)
        row.scope:SetPoint("TOPRIGHT", -24, y - 24)
        row.widgets = { row.text, row.remove, row.cap, row.capDown, row.capUp, row.scope }
        bindingRows[i] = row
    end
    emptyBindings = W.Label(frame, "GameFontHighlightSmall")
    emptyBindings:SetPoint("TOPLEFT", 28, BIND_TOP - 4)
    emptyBindings:SetWidth(WIDTH - 56)
    emptyBindings:SetJustifyH("LEFT")
    emptyBindings:SetText("None yet: press Add a binding to pick a player, then the profession whose materials they get.")
    bindPage = W.Button(frame, "", 70, function()
        pages.bind = pages.bind + 1
        UI.Refresh()
    end, "MailworthyFriendsBindPage")
    bindPage:SetPoint("TOPRIGHT", -24, BIND_TOP + 26)
    addButton = W.Button(frame, "Add a binding...", 140, function()
        view, picked = "add", nil
        setHint("")
        UI.Refresh()
    end, "MailworthyFriendsAdd")
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
        if picked then
            picked = nil
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
    bindHead:SetPoint("TOPLEFT", 20, BIND_TOP + 22)
    bindHead:SetText("Bindings")
    createBindingRows()
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

--- Re-read who can be bound (the roster is asked for and other Mailworthys are asked to say hello).
function UI.Reload(reason)
    ns.Routes.RequestRoster()
    if ns.Comms then ns.Comms.Ask() end
    candidates = ns.Routes.Candidates()
    ns.Log.Add("ui", "friends window: %d candidates (%s)", #candidates, tostring(reason))
end

function UI.Candidates() return candidates end

local function show(widgets, on)
    for _, w in ipairs(widgets) do
        if on then w:Show() else w:Hide() end
    end
end

--- The list view; returns the y below the last binding row.
local function fillBindings()
    local list = ns.Routes.List()
    local page, count = pageOf(list, UI.BINDING_ROWS, "bind")
    local first = (page - 1) * UI.BINDING_ROWS
    local shown = 0
    for i, row in ipairs(bindingRows) do
        local r = list[first + i]
        row.key = r and r.key or nil
        if r then
            local to, crafter = ns.Routes.Recipient(r)
            row.text:SetText(ns.Routes.What(r) .. " |cffffd100to " .. r.to .. "|r"
                .. (crafter and (" |cffaaaaaa(delivered to " .. to .. ")|r") or ""))
            row.cap:SetText(UI.CapText(r))
            row.scope:SetText(ns.Routes.SCOPES[r.scope] or r.scope)
            shown = shown + 1
        end
        show(row.widgets, r ~= nil)
    end
    if #list == 0 then emptyBindings:Show() else emptyBindings:Hide() end
    if count > 1 then
        bindPage:SetText(string.format("%d/%d  >", page, count))
        bindPage:Show()
    else
        bindPage:Hide()
    end
    return BIND_TOP - shown * BIND_ROW - (shown == 0 and 30 or 0)
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
        stepLabel:SetText("|cffaaaaaa1 of 2|r  Nobody to bind yet")
        chosenLabel:SetText("Join a group, be in a guild (the roster may take a moment), or log in on another of "
            .. "your characters once, then press Refresh list.")
        chosenLabel:Show()
        return LIST_TOP - 40
    end
    stepLabel:SetText("|cffaaaaaa1 of 2|r  |cffffd100Who should get your materials?|r")
    return LIST_TOP - shown * LIST_ROW
end

local function fillProfessions()
    local suggested = {}
    for _, p in ipairs(ns.Routes.Suggested(picked)) do suggested[p.id] = true end
    stepLabel:SetText("|cffaaaaaa2 of 2|r  |cffffd100What should " .. (tostring(picked.name):match("^(%S+)") or picked.name)
        .. " get?|r")
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
    local list = view == "list"
    show({ sub, bindHead }, list)
    show({ stepLabel }, not list)
    if list then
        for _, b in ipairs(candidateRows) do b:Hide() end
        for _, b in ipairs(professionRows) do b:Hide() end
        show({ candPage, refreshButton, chosenLabel, backButton }, false)
    else
        for _, row in ipairs(bindingRows) do show(row.widgets, false) end
        show({ emptyBindings, bindPage, addButton }, false)
    end
    local y
    if list then
        y = fillBindings()
        addButton:Show()
        at(addButton, 24, y - 10)
        at(hint, 176, y - 14)
        hint:SetWidth(WIDTH - 176 - 140)
        at(doneButton, -24, y - 10, "TOPRIGHT")
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

--- Step 2: the profession; the binding is saved for all the account's characters here.
function UI.Bind(i)
    local p = ns.Routes.Professions()[i]
    if not p or not picked then return end
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
    picked = nil
    view = ns.Routes.Count() == 0 and "add" or "list"
    pages.bind, pages.cand = 1, 1
    setHint("")
    UI.Reload("shown")
    UI.Refresh()
    frame:Show()
    frame:Raise()
    ns.Log.Add("ui", "friends window shown")
end

function UI.Toggle()
    if frame and frame:IsShown() then frame:Hide() else UI.Show() end
end

local function reloadIfShown(reason)
    if frame and frame:IsShown() and view == "add" and not picked then
        candidates = ns.Routes.Candidates()
        ns.Log.Add("ui", "friends window: %d candidates (%s)", #candidates, reason)
        UI.Refresh()
    end
end

ns.On("PLAYER_LOGIN", function() UI.Create() end)
ns.On("GUILD_ROSTER_UPDATE", function() reloadIfShown("roster") end)
ns.On("GROUP_ROSTER_UPDATE", function() reloadIfShown("group") end)
ns.On("CHAT_MSG_ADDON", function(prefix)
    if ns.Comms and prefix == ns.Comms.PREFIX then reloadIfShown("hello") end
end)
