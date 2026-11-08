-- The bag tags (AH / B / DE / V, BankAlt.lua) on Auctionator's own item buttons too: its
-- Selling tab's bag list and the item being posted (operator, 2026-11-08: "can the item badges
-- we show on the bag also be shown in the Auctionator ah menus too?").
--
-- Read from Auctionator 340's source (the version measured on Forever; its 16001 build loads
-- Source/Groups and Source_ModernAH):
--   * every icon in the Selling tab's bag list is a button from the template
--     AuctionatorGroupsViewItemTemplate (mixin AuctionatorGroupsViewItemMixin), taken from a
--     frame pool (CreateFramePool) by AuctionatorGroupsViewMixin:UpdateFromExisting, which
--     releases them all and calls button:SetItemInfo(info) on each one it takes back, after
--     every bag change, group toggle or selection. Scrolling moves one tall frame (a ScrollBox),
--     so a button changes item only through SetItemInfo; a released button is hidden, and our
--     textures with it;
--   * the posting panel's icon (SaleItem.xml, mixin AuctionatorBagItemSelectedMixin) calls
--     AuctionatorGroupsViewItemMixin.SetItemInfo(self, info) through the global table, and gets
--     nil when it is cleared;
--   * info: itemLink, locations (ItemLocations, one per stack; a favourite not in the bags has
--     none), or location for the posting panel's item;
--   * Auctionator creates these frames when the auction house first opens, after PLAYER_LOGIN,
--     and the XML mixin copies the mixin's functions into each button then.
-- So one hooksecurefunc post-hook on AuctionatorGroupsViewItemMixin.SetItemInfo, at login, reaches
-- every such button. The tag is a texture and a font string on Auctionator's button, kept in our
-- own weak table: no Lua field is written on Auctionator's (or Blizzard's) frames, and no frame is
-- created (textures only, like the bag tags and Baganator's lock glow). The tags show exactly
-- when the bag tags do (BankAlt.Active: the bank alt, no bank alt, tags everywhere, V after a
-- send) and are redrawn with them (BankAlt.OnRedraw). Hovering is never needed; Auctionator's
-- tooltip is GameTooltip:SetHyperlink, so Mailworthy's tooltip lines are there too.
-- Nothing happens without Auctionator. Switch: /mw feature auctionatorTags off (then /reload).
-- Unverified in game: README "Beta unknowns".
local _, ns = ...

local AuctionatorTags = {}
ns.AuctionatorTags = AuctionatorTags

AuctionatorTags.MIXIN = "AuctionatorGroupsViewItemMixin"

local tags = setmetatable({}, { __mode = "k" }) -- Auctionator's button -> { bg, text }
local places = setmetatable({}, { __mode = "k" }) -- Auctionator's button -> what it shows now, or false
local state = { hooked = false, why = "not installed yet", calls = 0, errors = 0 }

--- Pure: where an Auctionator item info is in the bags: { link = itemLink, count = how many it
--- says the bags hold, slots = { { bag, slot }, ... } }, or nil for none (a cleared button).
--- Locations are ItemLocations (GetBagAndSlot); any that errors is skipped.
function AuctionatorTags.Where(info)
    if type(info) ~= "table" then return nil end
    local where = { link = type(info.itemLink) == "string" and info.itemLink or nil, slots = {},
        count = tonumber(info.itemCount) or tonumber(info.count) or 0 }
    local list = type(info.locations) == "table" and info.locations or { info.location }
    for _, location in ipairs(list) do
        if type(location) == "table" and type(location.GetBagAndSlot) == "function" then
            local ok, bag, slot = pcall(location.GetBagAndSlot, location)
            if ok and bag ~= nil and slot ~= nil then where.slots[#where.slots + 1] = { bag, slot } end
        end
    end
    return where
end

--- The tag key ("ah", "b", "de", "v") for what a button shows, or nil: the first of its stacks
--- that has one (stacks of one item share a verdict); with no readable stack, the item by its
--- link while Auctionator counts some in the bags (a favourite that isn't there gets none).
function AuctionatorTags.TagFor(where)
    if not where then return nil end
    for _, s in ipairs(where.slots) do
        local verdict = ns.BankAlt.TagAt(s[1], s[2], nil)
        if verdict then return verdict end
    end
    if #where.slots > 0 or where.count <= 0 or not where.link then return nil end
    return ns.BankAlt.TagAt(nil, nil, where.link)
end

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
    tags[button] = t
    return t
end

--- Draw (or clear) the tag on one of Auctionator's buttons for what it shows now.
function AuctionatorTags.Draw(button)
    local key = ns.Features.On("auctionatorTags") and AuctionatorTags.TagFor(places[button] or nil)
    local tag = key and ns.BankAlt.TAGS[key]
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

--- The post-hook: Auctionator gave `button` a new item (or nil).
function AuctionatorTags.OnSetItemInfo(button, info)
    state.calls = state.calls + 1
    if type(button) ~= "table" then return end
    places[button] = AuctionatorTags.Where(info) or false
    AuctionatorTags.Draw(button)
end

--- Redraw every button Auctionator has handed us (verdicts changed: bags, prices, locks, settings).
function AuctionatorTags.RefreshAll()
    for button in pairs(places) do AuctionatorTags.Draw(button) end
end

--- Pure-ish for specs and /mw report: how many buttons show a tag now.
function AuctionatorTags.Shown()
    local n = 0
    for _, t in pairs(tags) do
        local ok, shown = pcall(t.bg.IsShown, t.bg)
        if ok and shown then n = n + 1 end
    end
    return n
end

function AuctionatorTags.Install()
    if state.hooked then return true end
    if not ns.Features.On("auctionatorTags") then
        state.why = "off (/mw feature auctionatorTags on, then /reload)"
        ns.Log.Add("atrtags", "Auctionator tags %s", state.why)
        return false
    end
    local mixin = rawget(_G, AuctionatorTags.MIXIN)
    if type(mixin) ~= "table" or type(mixin.SetItemInfo) ~= "function" then
        state.why = rawget(_G, "Auctionator") and "Auctionator loaded, but no " .. AuctionatorTags.MIXIN .. ".SetItemInfo"
            or "Auctionator not loaded"
        ns.Log.Add("atrtags", "no Auctionator tags: %s", state.why)
        return false
    end
    local ok, err = pcall(hooksecurefunc, mixin, "SetItemInfo", function(button, info)
        local okDraw, errDraw = pcall(AuctionatorTags.OnSetItemInfo, button, info)
        if not okDraw then
            state.errors = state.errors + 1
            ns.Log.Add("atrtags", "tag error: %s", tostring(errDraw))
        end
    end)
    if not ok then
        state.why = "hook failed: " .. tostring(err)
        ns.Log.Add("atrtags", "Auctionator tags %s", state.why)
        return false
    end
    state.hooked, state.why = true, "hooked"
    ns.BankAlt.OnRedraw(AuctionatorTags.RefreshAll)
    ns.Log.Add("atrtags", "Auctionator tags: %s.SetItemInfo hooked", AuctionatorTags.MIXIN)
    return true
end

--- /mw report: what to look for in game.
function AuctionatorTags.ReportLines()
    local seen = 0
    for _ in pairs(places) do seen = seen + 1 end
    return { string.format("auctionator tags: %s; %d Auctionator button(s) seen, %d tagged now, %d SetItemInfo call(s), "
        .. "%d error(s); bag tags here: %s (check: at the auction house, Auctionator's Selling tab shows the same "
        .. "AH / B / DE / V tags as the bags, after scrolling and after a bag change)", state.why, seen,
        AuctionatorTags.Shown(), state.calls, state.errors, ns.BankAlt.Active() and (ns.BankAlt.Mode() or "?") or "none") }
end

ns.On("PLAYER_LOGIN", function() AuctionatorTags.Install() end)
