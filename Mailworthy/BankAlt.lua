-- The bank alt view (media/bank-alt-prototype.png): what each item is for,
-- recomputed with this character's own, fresh Auctionator prices.
--
--   * tags on bag slots: AH (list it), B (bank it: it sells higher later, or this character's
--     own crafting needs it, Valuation.BankForCraft), DE (disenchant it), V (vendor now);
--   * tooltip lines: today's verdict with the price and its age, and why it was
--     mailed ("Mailed for: Auction +8s 21c, Oct 14, from <main>", recorded by
--     Mailer in MailworthyDB.mailed);
--   * a summary window: stacks to list, items to disenchant, items now better
--     at a vendor (and how many of those were mailed for the auction house).
--
-- Shown on the bank alt (the character this realm + faction mails to), on a character
-- with no bank alt (it sells its own: the bank alt is optional, operator 2026-11-08), or
-- on every character with the "tags everywhere" setting. Postage doesn't count there:
-- nothing is being mailed.
--
-- The tooltip also says why an item stays (operator, 2026-11-08: Sharp Claw and Jade showed
-- nothing, read as "missing data": they were kept for a profession, and a kept item had no
-- line), and, while the Mailworthy window is open, what the window does with it.
--
-- On a main, after Send has mailed everything (operator, 2026-10-14): V tags
-- only, on what the Mailworthy window kept because a vendor pays more, for the
-- rest of the session, so the trip to the vendor is easy. Same settings as the
-- window (postage included), so the tags match what it showed.
--
-- Grey junk with a vendor price is V too (the AH has no price for it). Without
-- Auctionator: only that, plus the "Mailed for" line.
--
-- Taint: tags are textures and font strings on the game's bag buttons (and the bag
-- addons' buttons, BagAddons.lua), kept in our own weak table (the lock glow's
-- technique, via Border's hooks and Border.RefreshButton); tooltip
-- lines go through TooltipDataProcessor, which runs addon callbacks insecurely
-- by design (forceinsecure behind an attribute delegate). Switches:
-- /mw feature bankAltTags off, /mw feature tooltipLines off.
local _, ns = ...

local BankAlt = {}
ns.BankAlt = BankAlt

BankAlt.TAGS = {
    ah = { text = "AH", label = "Auction", color = { 0.2, 0.4, 0.75 } },
    b = { text = "B", label = "Bank", color = { 0.15, 0.5, 0.45 } },
    -- Kept for this character's own crafting: in the bank, not the bags (operator, 2026-11-11). The
    -- same B for the player; its own key so the summary ("what to sell") leaves it out.
    craft = { text = "B", label = "Bank", color = { 0.15, 0.5, 0.45 } },
    de = { text = "DE", label = "Disenchant", color = { 0.45, 0.25, 0.65 } },
    v = { text = "V", label = "Vendor now", color = { 0.45, 0.38, 0.2 } },
    -- A bank-pinned item (Pins.lua): still B, in the pin's green, like its glow (operator, 2026-11-13).
    pin = { text = "B", label = "Pinned", color = ns.Pins.COLOR },
}

local money = function(c) return ns.Valuation.Money(c) end
local tags = setmetatable({}, { __mode = "k" }) -- bag button -> { bg, text }
local cache = { dirty = true, bySlot = {}, byLink = {}, byItemID = {} }
local frame, rows, header, legend

local function call(fn, ...)
    if type(fn) ~= "function" then return nil end
    local results = { pcall(fn, ...) }
    if not results[1] then return nil end
    return unpack(results, 2, table.maxn(results))
end

--- The character this realm + faction mails to: picked from a main on the same
--- account, or declared here ("This character is my bank alt" in the settings
--- window) when the bank alt lives on a second WoW account.
function BankAlt.IsBankAlt()
    return ns.Config.IsBankAltHere()
end

local vendorMode = false -- this session, on this character, after a send

--- "bankalt" (AH / DE / V), "everywhere" (the setting), "self" (no bank alt on this realm and
--- faction: this character sells its own), "vendor" (a main after Send: V only), or nil.
function BankAlt.Mode()
    if BankAlt.IsBankAlt() then return "bankalt" end
    if ns.Config.Flag("tagsEverywhere") then return "everywhere" end
    if not ns.Config.BankAlt() then return "self" end
    if vendorMode then return "vendor" end
    return nil
end

function BankAlt.Active()
    return BankAlt.Mode() ~= nil
end

--- Mailer: everything was mailed. Tag what's left for the vendor (mains only).
function BankAlt.AfterSend()
    if vendorMode or BankAlt.IsBankAlt() then return end
    vendorMode = true
    ns.Log.Add("bankalt", "vendor tags on after sending")
    BankAlt.Redraw()
end

--- Pure: the tag for a valued item: "ah" / "de" when the auction house or
--- disenchanting beats the vendor by the minimum gain, "b" when it should be banked
--- for a later phase instead of listed, "craft" when this character's own profession needs
--- it (bank it until then), "v" when the vendor wins, nil when there's nothing to say
--- (locked, soulbound, tool, no price...).
function BankAlt.Verdict(item)
    local r = item.result
    if not r then return nil end
    if ns.Valuation.BankForCraft(r) then return "craft" end
    if r.action == "mail" then
        if r.route == "bank" then return "b" end
        return (r.route == "ah" or r.route == "de") and r.route or nil
    end
    if r.reason == "not worth it" and (r.vendor or 0) > 0 then return "v" end
    -- Grey junk: no auction price, but a vendor buys it.
    local unpriced = r.reason == "no price" or r.reason == "junk (no price data)"
    if item.quality == 0 and unpriced and (item.vendor or 0) > 0 then return "v" end
    return nil
end

--- Settings for the verdicts: on the bank alt (and with "tags everywhere") no postage,
--- since nothing is mailed from there; after a send on a main, the window's own settings.
function BankAlt.Settings()
    local s = ns.Config.Values()
    if BankAlt.Mode() ~= "vendor" then s.postage = 0 end
    s.routes = {} -- tags say what the market says; bindings (Routes) only apply when mailing
    s.forTags = true -- ... and so do the send switches (Bags.ApplySendSwitches)
    return s
end

function BankAlt.Invalidate()
    cache.dirty = true
end

function BankAlt.Refresh()
    cache.dirty = false
    cache.bySlot, cache.byLink, cache.byItemID = {}, {}, {}
    cache.result = ns.Bags.Evaluate(BankAlt.Settings())
    for _, list in ipairs({ cache.result.mail, cache.result.keep }) do
        for _, item in ipairs(list) do
            item.advice = BankAlt.Verdict(item) -- the tooltip's, in every mode
            item.verdict = item.advice -- the bag tag's: after a send on a main, V only
            if BankAlt.Mode() == "vendor" and item.verdict ~= "v" then item.verdict = nil end
            cache.byLink[item.link] = item
            cache.byItemID[item.itemID] = cache.byItemID[item.itemID] or item
            for _, s in ipairs(item.slots) do cache.bySlot[s.bag .. ":" .. s.slot] = item end
        end
    end
    return cache.result
end

local function current()
    if cache.dirty then BankAlt.Refresh() end
    return cache
end

-- Tags on bag buttons --------------------------------------------------------------

local function tagFor(button)
    local t = tags[button]
    if t then return t end
    t = {}
    t.bg = button:CreateTexture(nil, "OVERLAY", nil, 6)
    t.bg:SetSize(18, 11)
    t.bg:SetPoint("TOPLEFT", 2, -2)
    t.text = button:CreateFontString(nil, "OVERLAY", "SystemFont_Tiny")
    t.text:SetPoint("CENTER", t.bg, "CENTER", 0, 0)
    t.text:SetTextColor(1, 1, 1)
    -- A bag skin that fades the button's other regions (EllesmereUI; issue #89) leaves the tag alone.
    ns.Border.HoldAlpha(t.bg)
    ns.Border.HoldAlpha(t.text)
    tags[button] = t
    return t
end

--- Border decorator: show the item's tag, or hide ours if there's none. The item is the one in
--- bag / slot; a view without bag slots (Auctionator's) passes nil for them and its item's link,
--- else its item ID (Border.RefreshButton).
function BankAlt.Decorate(button, bag, slot, itemID, link)
    local want = ns.Features.On("bankAltTags") and BankAlt.Active()
    local item
    if want then
        local c = current()
        if bag ~= nil then
            item = c.bySlot[bag .. ":" .. tostring(slot)]
        else
            item = (link and c.byLink[link]) or (itemID and c.byItemID[itemID]) or nil
        end
    end
    local tag = item and item.verdict
        and (item.verdict == "b" and item.result and item.result.pinned and BankAlt.TAGS.pin or BankAlt.TAGS[item.verdict])
    if not tag then
        local t = tags[button]
        if t then t.bg:Hide() t.text:Hide() end
        return
    end
    local t = tagFor(button)
    t.bg:SetColorTexture(tag.color[1], tag.color[2], tag.color[3], 0.95)
    t.text:SetText(tag.text)
    t.bg:Show()
    t.text:Show()
end

--- Does this button show one of our tags right now? (Baganator: our corner widget holds its corner
--- while it does.)
function BankAlt.TagShown(button)
    local t = tags[button]
    return t ~= nil and t.bg:IsShown() == true
end

--- Place a button's tag on `region` (Baganator: our corner widget, wherever the player put it), or
--- back in the top-left corner with nil.
function BankAlt.AnchorTag(button, region)
    local t = tags[button]
    if not t then return end
    t.bg:ClearAllPoints()
    if region then t.bg:SetAllPoints(region) else t.bg:SetPoint("TOPLEFT", 2, -2) end
end

--- The legend under the bags ("" while no tags show), shared by Blizzard's bags and the bag addons.
function BankAlt.LegendText()
    local mode = ns.Features.On("bankAltTags") and BankAlt.Mode()
    if mode == "vendor" then return "Mailworthy: |cffd0b070V|r sell to a vendor" end
    if not mode then return "" end
    return "Mailworthy: |cff6f9fffAH|r auction   |cff40b0a0B|r bank   |cffb080e0DE|r disenchant"
        .. "   |cffd0b070V|r vendor now"
end

local function redraw()
    BankAlt.Invalidate()
    ns.Border.RefreshAll()
    if legend then legend:SetText(BankAlt.LegendText()) end
    if frame and frame:IsShown() then BankAlt.RefreshWindow() end
end
BankAlt.Redraw = redraw

-- Tooltip --------------------------------------------------------------------------

local function ageText(age)
    if age == nil then return "" end
    if age <= 0 then return " (scanned today)" end
    return string.format(" (scanned %d day%s ago)", age, age == 1 and "" or "s")
end

-- Kept for a reason the tooltip doesn't repeat: the game's own lines (soulbound, quest item,
-- conjured item), the lock glow's line (Border), or nothing to say yet.
BankAlt.QUIET_KEEPS = { soulbound = true, ["quest item"] = true, ["conjured item"] = true, locked = true,
    ["in use"] = true, ["item info not loaded yet"] = true }

--- Pure: the label and the line for an item with no verdict tag: where the Mailworthy window
--- mails it, or why it stays in the bags. nil when there's nothing to add. `noBankAlt`: the bank
--- alt's share stays (true = none is set, or Bags.HoldReason's text: "this is your bank alt",
--- "bank alt skipped"), so nothing goes to one (Codex review).
function BankAlt.OtherLine(item, noBankAlt)
    local r = item and item.result
    if type(r) ~= "table" then return nil end
    if r.action == "mail" then
        if r.to then
            return "Mail", string.format("Goes to %s at the mailbox: %s.", tostring(r.to),
                r.what and (tostring(r.what) .. " binding") or "a binding")
        end
        if noBankAlt then
            return "Keep", string.format("Stays in your bags: %s (%s).", type(noBankAlt) == "string" and noBankAlt
                or "no bank alt", tostring(r.reason))
        end
        return "Mail", "Goes to your bank alt at the mailbox: " .. tostring(r.reason) .. "."
    end
    if r.action ~= "keep" or BankAlt.QUIET_KEEPS[r.reason] then return nil end
    return "Keep", "Stays in your bags: " .. ns.MailWindow.StayReason(r) .. "."
end

--- Pure: the tooltip lines for one item: { { text, r, g, b }, ... }.
--- `item` is the valued bag item (or nil when it isn't in the bags), `record` the
--- MailworthyDB.mailed entry (or nil).
function BankAlt.TooltipLines(item, record, settings)
    local lines = {}
    local verdict = item and (item.advice or item.verdict)
    local pinned = verdict == "b" and item.result and item.result.pinned
    local tag = verdict and (pinned and BankAlt.TAGS.pin or BankAlt.TAGS[verdict])
    local otherLabel, otherText
    if not tag then otherLabel, otherText = BankAlt.OtherLine(item, ns.Bags.HoldReason() or false) end
    local label = tag and tag.label or otherLabel
    if not label and not record then return lines end
    lines[1] = { "Mailworthy" .. (label and ("  |cffffffff[" .. label .. "]|r") or ""), 1, 0.82, 0 }
    if otherText then lines[#lines + 1] = { otherText, 1, 1, 1 } end
    if tag then
        local r, p = item.result, item.price or {}
        local unit = r.ahUnit or p.ah
        local basis = (r.scans or 1) > 1 and string.format(" (%d-day median)", r.scans) or ""
        local text
        if verdict == "ah" then
            text = string.format("Auction price today: %s each%s%s. After the %d%% cut and the %dh deposit: %s more than a vendor.",
                money(unit), basis, ageText(p.age), math.floor(settings.cut * 100 + 0.5),
                ns.Valuation.DURATION_HOURS[settings.duration], money(r.gain))
        elseif verdict == "b" and r.pinned then
            text = "Bank it: you pinned this item for your bank alt (/mw pins lists them). Ctrl+Alt+click it again to unpin."
        elseif verdict == "b" then
            local why = tostring(r.reason):gsub("^bank: ", "")
            text = "Bank it, don't list it yet: " .. why .. ". " .. (r.gain
                and string.format("Listed today it would bring %s%s more than a vendor.", unit and (money(unit) .. " each, ") or "",
                    money(r.gain))
                or "No auction price yet, so the gain is unknown.")
        elseif verdict == "craft" then
            text = "Bank it: " .. ns.MailWindow.WhyKept(r) .. ". It waits in your bank, not your bags, until you craft."
        elseif verdict == "de" then
            text = string.format("Disenchanting today: %s, %s more than a vendor.", money(p.de), money(r.gain))
        elseif p.ah then
            text = string.format("Auction price today: %s each%s%s. After the %d%% cut and the deposit that's %s, "
                .. "so sell it to a vendor (%s).", money(unit), basis, ageText(p.age), math.floor(settings.cut * 100 + 0.5),
                (r.gain or 0) > 0 and ("under your " .. money(r.threshold) .. " minimum gain") or "less than a vendor pays",
                money(r.vendor))
        else
            text = string.format("Worth no more than a vendor today: sell it (%s).", money(r.vendor))
        end
        local c = pinned and ns.Pins.COLOR or { 1, 1, 1 } -- a pin's line in its green, like its glow and tag
        lines[#lines + 1] = { text, c[1], c[2], c[3] }
    end
    if record then
        local was = BankAlt.TAGS[record.route] and BankAlt.TAGS[record.route].label
            or (record.route == "bank" and "Bank") or (record.route == "common" and "Common item")
            or (record.route == ns.Valuation.VENDOR and "Vendor")
            or (record.route == ns.Valuation.NO_PRICE and "No auction price yet") or tostring(record.reason)
        lines[#lines + 1] = { string.format("Mailed for: %s%s, %s, from %s", was,
            record.gain and (" +" .. money(record.gain)) or "", date("%b %d", record.at or 0), tostring(record.from)),
            0.55, 0.75, 1 }
    end
    return lines
end

--- While the Mailworthy window shows, the item as the window has it (its settings: postage and
--- bindings), so the tooltip says what the window does; nil otherwise.
local function windowItem(link, itemID)
    local window = ns.MailWindow.Frame()
    local result = window and window:IsVisible() and ns.MailWindow.Result()
    if not result then return nil end
    local byID
    for _, list in ipairs({ result.mail, result.keep }) do
        for _, it in ipairs(list) do
            if link and it.link == link then return it, result end
            if itemID and it.itemID == itemID then byID = byID or it end
        end
    end
    return byID, byID and result or nil
end

local function onTooltip(tooltip, data)
    if not ns.Features.On("tooltipLines") then return end
    if tooltip ~= rawget(_G, "GameTooltip") then return end
    local link = select(2, call(rawget(_G, "TooltipUtil") and TooltipUtil.GetDisplayedItem, tooltip))
    local itemID = type(data) == "table" and tonumber(data.id) or nil
    local shown, shownResult = windowItem(link, itemID)
    if not shown and not BankAlt.Active() then return end
    local c = shown and { result = shownResult } or current()
    local item = shown and { result = shown.result, price = shown.price, advice = BankAlt.Verdict(shown) }
        or (link and c.byLink[link]) or (itemID and c.byItemID[itemID]) or nil
    itemID = itemID or (shown and shown.itemID) or (item and item.itemID)
    -- On a main after sending, only the vendor verdict: "Mailed for" belongs on the bank alt.
    local mode = BankAlt.Mode()
    local record = mode and mode ~= "vendor" and itemID and type(MailworthyDB.mailed) == "table"
        and MailworthyDB.mailed[itemID] or nil
    if type(record) ~= "table" then record = nil end
    local lines = BankAlt.TooltipLines(item, record, c.result and c.result.settings or BankAlt.Settings())
    if #lines == 0 then return end
    tooltip:AddLine(" ")
    for _, l in ipairs(lines) do tooltip:AddLine(l[1], l[2], l[3], l[4], true) end
end

function BankAlt.InstallTooltip()
    if not ns.Features.On("tooltipLines") then
        ns.Log.Add("bankalt", "tooltip lines off (/mw feature tooltipLines on, then /reload)")
        return false
    end
    local processor, enum = rawget(_G, "TooltipDataProcessor"), rawget(_G, "Enum")
    local itemType = type(enum) == "table" and type(enum.TooltipDataType) == "table" and enum.TooltipDataType.Item
    if type(processor) ~= "table" or type(processor.AddTooltipPostCall) ~= "function" or itemType == nil then
        ns.Log.Add("bankalt", "TooltipDataProcessor missing: no tooltip lines")
        return false
    end
    local ok, err = pcall(processor.AddTooltipPostCall, itemType, function(tooltip, data)
        local okLines, errLines = pcall(onTooltip, tooltip, data)
        if not okLines then ns.Log.Add("bankalt", "tooltip error: %s", tostring(errLines)) end
    end)
    ns.Log.Add("bankalt", "tooltip lines %s", ok and "installed" or ("failed: " .. tostring(err)))
    return ok
end

-- Summary --------------------------------------------------------------------------

--- Pure: totals per verdict for the summary window.
function BankAlt.Summary(result)
    local s = { ah = { stacks = 0, items = 0, gain = 0 }, b = { stacks = 0, items = 0, gain = 0 },
        de = { stacks = 0, items = 0, gain = 0 }, v = { stacks = 0, items = 0, vendor = 0, wasAuction = 0 } }
    local mailed = type(MailworthyDB.mailed) == "table" and MailworthyDB.mailed or {}
    for _, list in ipairs({ result.mail, result.keep }) do
        for _, item in ipairs(list) do
            local v = item.verdict
            local t = v and s[v]
            if t then
                t.stacks, t.items = t.stacks + item.stacks, t.items + item.count
                if v == "v" then
                    t.vendor = t.vendor + (item.result.vendor or 0)
                    local record = mailed[item.itemID]
                    if type(record) == "table" and (record.route == "ah" or record.listRoute == "ah") then
                        t.wasAuction = t.wasAuction + 1
                    end
                else
                    t.gain = t.gain + (item.result.gain or 0)
                end
            end
        end
    end
    return s
end

local ROW_TEXT = {
    ah = function(t) return string.format("%d stack%s to list", t.stacks, t.stacks == 1 and "" or "s"), "+" .. money(t.gain) end,
    b = function(t)
        return string.format("%d stack%s to bank for a later phase", t.stacks, t.stacks == 1 and "" or "s"), "+" .. money(t.gain)
    end,
    de = function(t) return string.format("%d item%s to disenchant", t.items, t.items == 1 and "" or "s"), "+" .. money(t.gain) end,
    v = function(t)
        return string.format("%d stack%s to sell to a vendor%s", t.stacks, t.stacks == 1 and "" or "s",
            t.wasAuction > 0 and string.format(" (%d mailed for the auction house)", t.wasAuction) or ""), money(t.vendor)
    end,
}

function BankAlt.CreateWindow()
    if frame then return frame end
    local W = ns.Widgets
    frame = W.Window("MailworthySummaryFrame", 440, 258)
    frame:SetPoint("CENTER")
    local title = W.Label(frame, "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 22, -18)
    title:SetText("Mailworthy: what to sell")
    header = W.Label(frame, "GameFontNormal")
    header:SetPoint("TOPLEFT", 24, -50)
    rows = {}
    for i, key in ipairs({ "ah", "b", "de", "v" }) do
        local row = {}
        local y = -74 - (i - 1) * 28
        row.chipBg = frame:CreateTexture(nil, "BORDER")
        row.chipBg:SetSize(84, 16)
        row.chipBg:SetPoint("TOPLEFT", 26, y)
        local c = BankAlt.TAGS[key].color
        row.chipBg:SetColorTexture(c[1], c[2], c[3], 0.9)
        local chip = W.Label(frame, "GameFontHighlightSmall")
        chip:SetPoint("CENTER", row.chipBg, "CENTER")
        chip:SetText(BankAlt.TAGS[key].label)
        row.text = W.Label(frame, "GameFontHighlight")
        row.text:SetPoint("TOPLEFT", 120, y - 1)
        row.value = W.Label(frame, "GameFontHighlight")
        row.value:SetPoint("TOPRIGHT", -26, y - 1)
        rows[key] = row
    end
    W.Button(frame, "Close", 100, function() frame:Hide() end, "MailworthySummaryClose"):SetPoint("BOTTOMRIGHT", -20, 40)
    W.Button(frame, "Scan details", 120, function() ns.Bags.Scan() end, "MailworthySummaryScan")
        :SetPoint("BOTTOMLEFT", 20, 40)
    ns.Nav.Attach(frame)
    return frame
end

function BankAlt.RefreshWindow()
    if not frame then return end
    local c = current()
    local summary = BankAlt.Summary(c.result)
    header:SetText(c.result.priced and "With today's prices" or "No auction prices here: install Auctionator or TSM")
    for key, row in pairs(rows) do
        local text, value = ROW_TEXT[key](summary[key])
        row.text:SetText(text)
        row.value:SetText(value)
    end
end

--- `opener`: the Mailworthy window whose button opened it (placed beside that), or nil (centred).
function BankAlt.ShowWindow(opener)
    if not frame then BankAlt.CreateWindow() end
    ns.Widgets.PlaceBeside(frame, opener)
    BankAlt.Invalidate()
    BankAlt.RefreshWindow()
    frame:Show()
    frame:Raise()
    ns.Log.Add("bankalt", "summary shown")
end

function BankAlt.Frame() return frame end

ns.Border.AddDecorator(BankAlt.Decorate)

ns.On("PLAYER_LOGIN", function()
    BankAlt.CreateWindow()
    BankAlt.InstallTooltip()
    -- Legend under the combined bags (a font string: not seen by smart navigation).
    local bags = rawget(_G, "ContainerFrameCombinedBags")
    if type(bags) == "table" and ns.Features.On("bankAltTags") then
        legend = bags:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        legend:SetPoint("TOPRIGHT", bags, "BOTTOMRIGHT", -10, -4)
    end
    ns.Locks.OnChanged(redraw)
    ns.Pins.OnChanged(redraw)
    ns.Mailer.OnSent(function() BankAlt.AfterSend() end)
    local settings = ns.SettingsUI.Frame()
    if settings then settings:HookScript("OnHide", redraw) end
    local api = ns.Prices.Auctionator()
    if api and type(api.RegisterForDBUpdate) == "function" then
        pcall(api.RegisterForDBUpdate, ns.Prices.CALLER, redraw)
    end
    redraw()
end)
ns.On("BAG_UPDATE_DELAYED", function() redraw() end)
