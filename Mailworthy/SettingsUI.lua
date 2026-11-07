-- The settings window (media/ux-pass-prototype.png), one task at a time:
--   main view: the bank alt on one row with Change..., then "What gets mailed"
--     (minimum gain, listing length, disenchant, profession materials, sell what I
--     gather), "In your
--     bags" (tags, lock glow) and "More" (friends, bank alt summary, minimap button);
--   pick view (Change..., and straight away while no bank alt is set): the known
--     characters, "This character is my bank alt" (a main on another WoW account),
--     an optional typed name, Back. Picking saves and returns to the main view.
-- Keyboard/mouse: click. Controller: the D-pad moves Mailworthy's own highlight,
-- Cross presses, Circle closes (PadKey "settings" set, Nav); every setting is a
-- button, so nothing needs typing. The name box is an optional fallback the player
-- clicks into (the game never moves focus: no SetFocus).
--
-- Opened with /mw, the minimap button, or the Settings button in the Mailworthy
-- window at the mailbox. Not registered in Blizzard's options panel: that hands
-- our frame and category tables to a panel the controller UI navigates, the same
-- pattern that made the More-menu entry taint gamepad input (alpha2).
local _, ns = ...

local UI = {}
ns.SettingsUI = UI

UI.MAX_CHOICES = 6
local WIDTH, MAIN_HEIGHT, ROW = 420, 496, 26

local frame, nameBox, nameHint, current, emptyHint, legend, pricesLine, changeButton
local choiceRows = {}
local amountLabel, pctLabel, disenchantButton, minimapButton, tagsButton, glowButton, matsButton, hereButton, friendsButton
local gatherButton
local durationButtons = {}
local mainWidgets, pickWidgets = {}, {}
local typedLabel, useNameButton, backButton
local view = "main"
local pendingUnknown -- a typed name Mailworthy hasn't seen, waiting for a second press

local W = ns.Widgets
local money = function(c) return ns.Valuation.Money(c) end

function UI.Frame() return frame end
--- "main" (the settings) or "pick" (choosing the bank alt).
function UI.View() return view end

local function add(list, widget)
    list[#list + 1] = widget
    return widget
end

local function heading(list, text, y)
    local h = add(list, W.Label(frame, "GameFontNormal"))
    h:SetPoint("TOPLEFT", 20, y)
    h:SetText(text)
    return h
end

local function setHint(text) nameHint:SetText(text or "") end

local function setView(v)
    view = v
    pendingUnknown = nil
    if nameHint then setHint("") end
end

function UI.UseTyped()
    local text = ns.Config.Clean(nameBox:GetText())
    if not text then return setHint("Type a name first, or pick one above.") end
    if text:lower() == tostring(ns.PlayerName()):lower() then
        return setHint("That's this character. Pick the character that should receive the mail, or, if this "
            .. "character is the one receiving it, press \"This character is my bank alt\".")
    end
    local name = ns.Config.Complete(text, ns.Config.Choices())
    if not name and pendingUnknown ~= text:lower() then
        pendingUnknown = text:lower()
        return setHint("|cffff8040Mailworthy hasn't seen " .. text .. " on this realm and faction. "
            .. "Check the spelling, then press Use name again to save it.|r")
    end
    UI.Choose(name or text)
    nameBox:SetText("")
    setHint("")
end

function UI.Choose(name)
    pendingUnknown = nil
    local saved = ns.Config.SetBankAlt(name)
    if saved then
        ns.Print("Bank alt: " .. saved .. ". Mail goes only to this character.")
        setView("main")
    end
    UI.Refresh()
end

--- "This character is my bank alt": the character receiving the mail says so itself
--- (the only way when it plays on a second WoW account, whose saved settings the main
--- never sees). Pressed again, it clears the bank alt.
function UI.ToggleHere()
    pendingUnknown = nil
    if ns.Config.IsBankAltHere() then
        ns.Config.ClearBankAlt()
        ns.Print("No bank alt set on this realm and faction any more.")
    else
        local saved = ns.Config.SetBankAltHere()
        if saved then
            setView("main")
            ns.Print("Bank alt: " .. saved .. " (this character). Your bags now carry the AH / B / DE / V tags; "
                .. "on your main, type this name in Mailworthy's settings if it hasn't been picked there.")
        end
    end
    if ns.BankAlt then ns.BankAlt.Redraw() end
    UI.Refresh()
end

-- Main view: the bank alt on one row --------------------------------------------------

local function createBankAltRow()
    heading(mainWidgets, "Bank alt", -46)
    current = add(mainWidgets, W.Label(frame, "GameFontHighlight"))
    current:SetPoint("TOPLEFT", 28, -70)
    current:SetWidth(270)
    current:SetJustifyH("LEFT")
    changeButton = add(mainWidgets, W.Button(frame, "Change...", 96, function()
        setView("pick")
        UI.Refresh()
    end, "MailworthySettingsChange"))
    changeButton:SetPoint("TOPRIGHT", -24, -66)
end

-- Pick view: who gets the mail --------------------------------------------------------

local function createPicker()
    heading(pickWidgets, "Who gets your mail?", -46)
    local sub = add(pickWidgets, W.Label(frame, "GameFontHighlightSmall"))
    sub:SetPoint("TOPLEFT", 28, -66)
    sub:SetText("Mailworthy mails only to this character (same realm and faction).")
    emptyHint = add(pickWidgets, W.Label(frame, "GameFontHighlightSmall"))
    emptyHint:SetWidth(WIDTH - 56)
    emptyHint:SetJustifyH("LEFT")
    emptyHint:SetText("No other characters on this realm and faction yet: log in on your bank alt once "
        .. "with Mailworthy installed, or type its name below. If this character is the bank alt (for "
        .. "example for a main on another WoW account), press the button below instead.")
    for i = 1, UI.MAX_CHOICES do
        local row = {}
        row.button = W.Button(frame, "", 290, function()
            if row.name then UI.Choose(row.name) end
        end, "MailworthySettingsChoice" .. i)
        row.forget = W.Button(frame, "Forget", 70, function()
            if row.name then
                ns.Config.ForgetName(row.name)
                UI.Refresh()
            end
        end, "MailworthySettingsForget" .. i)
        choiceRows[i] = row
    end
    hereButton = add(pickWidgets, W.Button(frame, "", 372, function() UI.ToggleHere() end, "MailworthySettingsHere"))
    typedLabel = add(pickWidgets, W.Label(frame, "GameFontHighlightSmall"))
    typedLabel:SetText("Or type a name:")
    nameBox = add(pickWidgets, CreateFrame("EditBox", "MailworthySettingsName", frame, "InputBoxTemplate"))
    nameBox:SetSize(170, 20)
    nameBox:SetAutoFocus(false)
    nameBox:SetMaxLetters(48)
    nameBox:SetScript("OnTextChanged", function(self, userInput)
        if not userInput then return end
        pendingUnknown = nil
        local match = ns.Config.Complete(self:GetText(), ns.Config.Choices())
        setHint(match and ("Matches " .. match .. ": press Use name.") or "")
    end)
    nameBox:SetScript("OnEnterPressed", function(self)
        UI.UseTyped()
        self:ClearFocus()
    end)
    nameBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    useNameButton = add(pickWidgets, W.Button(frame, "Use name", 90, function() UI.UseTyped() end,
        "MailworthySettingsUseName"))
    nameHint = add(pickWidgets, W.Label(frame, "GameFontHighlightSmall"))
    nameHint:SetWidth(WIDTH - 56)
    nameHint:SetJustifyH("LEFT")
    backButton = add(pickWidgets, W.Button(frame, "Back", 100, function()
        setView("main")
        UI.Refresh()
    end, "MailworthySettingsBack"))
end

--- Pick view layout for the choices that show; returns the window height.
local function layoutPicker(shown)
    local function at(widget, x, y, point)
        widget:ClearAllPoints()
        widget:SetPoint(point or "TOPLEFT", frame, point or "TOPLEFT", x, y)
    end
    local y = -88
    if shown == 0 then
        at(emptyHint, 28, y)
        y = y - 56
    end
    for i, row in ipairs(choiceRows) do
        at(row.button, 24, y - (i - 1) * ROW)
        at(row.forget, 324, y - (i - 1) * ROW)
    end
    y = y - shown * ROW - 6
    at(hereButton, 24, y)
    y = y - 34
    at(typedLabel, 28, y - 4)
    at(nameBox, 132, y)
    at(useNameButton, 310, y + 1)
    y = y - 26
    at(nameHint, 28, y)
    y = y - 32
    at(backButton, -24, y, "TOPRIGHT")
    return -y + 52
end

-- Main view: what gets mailed, in your bags, more -------------------------------------

local function stepper(y, key, name)
    local text = add(mainWidgets, W.Label(frame, "GameFontHighlight"))
    text:SetPoint("TOPLEFT", 28, y - 4)
    local minus = add(mainWidgets, W.Button(frame, "-", 32, function()
        ns.Config.Step(key, -1)
        UI.Refresh()
    end, "MailworthySettings" .. name .. "Down"))
    minus:SetPoint("TOPLEFT", 302, y)
    local plus = add(mainWidgets, W.Button(frame, "+", 32, function()
        ns.Config.Step(key, 1)
        UI.Refresh()
    end, "MailworthySettings" .. name .. "Up"))
    plus:SetPoint("TOPLEFT", 340, y)
    return text
end

local function toggle(width, name, onClick)
    return add(mainWidgets, W.Button(frame, "", width, function()
        onClick()
        UI.Refresh()
    end, "MailworthySettings" .. name))
end

local function createRule()
    heading(mainWidgets, "What gets mailed", -102)
    amountLabel = stepper(-124, "minGain", "Amount")
    pctLabel = stepper(-152, "minGainPct", "Percent")
    local listing = add(mainWidgets, W.Label(frame, "GameFontHighlight"))
    listing:SetPoint("TOPLEFT", 28, -184)
    listing:SetText("Auction listing")
    for i, hours in ipairs(ns.Valuation.DURATION_HOURS) do
        local b = add(mainWidgets, W.Button(frame, hours .. "h", 56, function()
            ns.Config.Set("duration", i)
            UI.Refresh()
        end, "MailworthySettingsDuration" .. i))
        b:SetPoint("TOPLEFT", 196 + (i - 1) * 60, -180)
        durationButtons[i] = b
    end
    disenchantButton = toggle(372, "Disenchant", function()
        ns.Config.Set("disenchant", not ns.Config.Get("disenchant"))
    end)
    disenchantButton:SetPoint("TOPLEFT", 24, -210)
    matsButton = toggle(372, "Mats", function()
        ns.Config.Set("keepProfessionMats", not ns.Config.Get("keepProfessionMats"))
        if ns.BankAlt then ns.BankAlt.Redraw() end
    end)
    matsButton:SetPoint("TOPLEFT", 24, -236)
    gatherButton = toggle(372, "Gather", function()
        ns.Config.Set("sellGathered", not ns.Config.Get("sellGathered"))
        if ns.BankAlt then ns.BankAlt.Redraw() end
    end)
    gatherButton:SetPoint("TOPLEFT", 24, -262)
end

local function createBagsAndMore()
    heading(mainWidgets, "In your bags", -298)
    tagsButton = toggle(182, "Tags", function()
        ns.Config.Set("tagsEverywhere", not ns.Config.Flag("tagsEverywhere"))
        if ns.BankAlt then ns.BankAlt.Redraw() end
    end)
    tagsButton:SetPoint("TOPLEFT", 24, -320)
    glowButton = toggle(182, "Glow", function()
        ns.Config.Set("glowEverywhere", not ns.Config.Flag("glowEverywhere"))
        if ns.Border then ns.Border.RefreshAll() end
    end)
    glowButton:SetPoint("TOPLEFT", 214, -320)
    heading(mainWidgets, "More", -356)
    friendsButton = add(mainWidgets, W.Button(frame, "", 182, function() ns.RoutesUI.Show(frame) end,
        "MailworthySettingsFriends"))
    friendsButton:SetPoint("TOPLEFT", 24, -378)
    add(mainWidgets, W.Button(frame, "Bank alt summary...", 182, function()
        if ns.BankAlt then ns.BankAlt.ShowWindow(frame) end
    end, "MailworthySettingsSummary")):SetPoint("TOPLEFT", 214, -378)
    minimapButton = toggle(182, "Minimap", function()
        ns.Config.Set("minimapHidden", ns.Config.MinimapShown())
        if ns.MinimapButton then ns.MinimapButton.Refresh() end
    end)
    minimapButton:SetPoint("TOPLEFT", 24, -404)
    pricesLine = add(mainWidgets, W.Label(frame, "GameFontDisableSmall"))
    pricesLine:SetPoint("TOPLEFT", 28, -446)
    pricesLine:SetWidth(270)
    pricesLine:SetJustifyH("LEFT")
    add(mainWidgets, W.Button(frame, "Done", 100, function() frame:Hide() end, "MailworthySettingsDone"))
        :SetPoint("TOPRIGHT", -24, -440)
end

function UI.Create()
    if frame then return frame end
    frame = W.Window("MailworthySettingsFrame", WIDTH, MAIN_HEIGHT)
    frame:SetFrameStrata("FULLSCREEN_DIALOG")
    frame:SetPoint("CENTER")
    local title = W.Label(frame, "GameFontNormalLarge")
    title:SetPoint("TOP", 0, -18)
    title:SetText("Mailworthy settings")
    createBankAltRow()
    createPicker()
    createRule()
    createBagsAndMore()
    legend = W.Label(frame, "GameFontHighlightSmall")
    legend:SetPoint("BOTTOM", 0, 16)
    ns.Nav.Attach(frame)
    ns.Log.Add("ui", "settings window created")
    return frame
end

local function selected(text, on)
    return on and ("|cff33ff99> " .. text .. " <|r") or text
end

local function showAll(list, on)
    for _, w in ipairs(list) do
        if on then w:Show() else w:Hide() end
    end
end

--- Pure: the bank alt row: "Name  (class level)" or "(this character)", or none yet.
function UI.BankAltText(bankAlt, here, choices)
    if not bankAlt then return "|cffff8040None yet: Mailworthy mails nothing until you pick one.|r" end
    local detail = here and "this character" or nil
    for _, c in ipairs(choices or {}) do
        if c.name == bankAlt then
            detail = c.known and (tostring(c.class or "?"):lower() .. " " .. tostring(c.level or "?")) or "not seen yet"
        end
    end
    return "|cff33ff99" .. bankAlt .. "|r" .. (detail and ("  |cffaaaaaa" .. detail .. "|r") or "")
end

local function fillPicker(bankAlt, here, choices)
    hereButton:SetText(selected("This character is my bank alt", here))
    local shown = 0
    for i, row in ipairs(choiceRows) do
        local c = choices[i]
        row.name = c and c.name or nil
        if c then
            local detail = c.known and string.format("(%s %s)", tostring(c.class or "?"):lower(), tostring(c.level or "?"))
                or "(not seen)"
            row.button:SetText(selected(c.name .. "  " .. detail, bankAlt == c.name))
            row.button:Show()
            if c.known then row.forget:Hide() else row.forget:Show() end
            shown = shown + 1
        else
            row.button:Hide()
            row.forget:Hide()
        end
    end
    if shown == 0 then emptyHint:Show() else emptyHint:Hide() end
    return shown
end

local function hideChoices()
    for _, row in ipairs(choiceRows) do
        row.button:Hide()
        row.forget:Hide()
    end
end

local function fillMain(bankAlt, here, choices)
    current:SetText(UI.BankAltText(bankAlt, here, choices))
    changeButton:SetText(bankAlt and "Change..." or "Choose...")
    local v = ns.Config.Values()
    amountLabel:SetText("Gain at least |cffffffff" .. money(v.minGain) .. "|r")
    pctLabel:SetText(string.format("and at least |cffffffff%d%%|r over the vendor price",
        math.floor(v.minGainPct * 100 + 0.5)))
    for i, b in ipairs(durationButtons) do
        b:SetText(selected(ns.Valuation.DURATION_HOURS[i] .. "h", v.duration == i))
    end
    local deAddon = ns.Prices.DisenchantAddon()
    disenchantButton:SetText(string.format("Include disenchant value: %s (%s)", v.disenchant and "on" or "off",
        deAddon or "era tables"))
    local crafting = ns.Bags.CraftingText(ns.Characters.Professions()) -- "First Aid 80, Tailoring 130"
    matsButton:SetText(string.format("Keep my professions' materials: %s (%s)", v.keepProfessionMats and "on" or "off",
        crafting ~= "" and crafting or "no crafting profession here"))
    local gathering = {}
    for _, p in ipairs(ns.Valuation.GatheringProfessions(ns.Characters.Professions())) do gathering[#gathering + 1] = p.name end
    gatherButton:SetText(string.format("Sell what I gather: %s (%s)", v.sellGathered and "on" or "off",
        #gathering > 0 and table.concat(gathering, ", ") or "no gathering profession here"))
    tagsButton:SetText("Bag tags: " .. (ns.Config.Flag("tagsEverywhere") and "every character" or "bank alt only"))
    glowButton:SetText("Lock glow: " .. (ns.Config.Flag("glowEverywhere") and "always" or "in Mailworthy"))
    local bindings = ns.Routes.Count()
    friendsButton:SetText(bindings == 0 and "Friends..."
        or string.format("Friends (%d binding%s)...", bindings, bindings == 1 and "" or "s"))
    minimapButton:SetText("Minimap button: " .. (ns.Config.MinimapShown() and "shown" or "hidden"))
    pricesLine:SetText("Prices: " .. (ns.Prices.Auctionator() and "Auctionator"
        or "none (install Auctionator; only white items are mailed)"))
end

function UI.Refresh()
    if not frame then return end
    local bankAlt = ns.Config.BankAlt()
    local here = ns.Config.IsBankAltHere()
    local choices = ns.Config.Choices()
    showAll(mainWidgets, view == "main")
    showAll(pickWidgets, view == "pick")
    fillMain(bankAlt, here, choices)
    local shown = fillPicker(bankAlt, here, choices)
    if view == "pick" then
        frame:SetHeight(layoutPicker(shown))
    else
        hideChoices()
        frame:SetHeight(MAIN_HEIGHT)
    end
    legend:SetText(ns.MailButton.GamepadUI() and W.Legend() or "")
    ns.Nav.Revalidate()
end

--- Opens on the settings, or on the picker while no bank alt is set (there's nobody to mail yet).
--- `opener`: the Mailworthy window whose button opened it (placed beside that), or nil (centred).
function UI.Show(opener)
    if not frame then UI.Create() end
    W.PlaceBeside(frame, opener)
    setView(ns.Config.BankAlt() and "main" or "pick")
    UI.Refresh()
    frame:Show()
    frame:Raise()
    ns.Log.Add("ui", "settings shown (%s)", view)
end

function UI.Toggle()
    if frame and frame:IsShown() then frame:Hide() else UI.Show() end
end

ns.On("PLAYER_LOGIN", function() UI.Create() end)
