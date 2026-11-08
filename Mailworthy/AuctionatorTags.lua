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
-- every such button. The tag is drawn by Border.RefreshButton like a bag button's (a texture and
-- a font string kept in BankAlt's weak table; the lock glow too): no Lua field is written on
-- Auctionator's (or Blizzard's) frames, and no frame is created. The tags show exactly
-- when the bag tags do (BankAlt.Active: the bank alt, no bank alt, tags everywhere, V after a
-- send) and are redrawn with them (BankAlt.OnRedraw). Hovering is never needed; Auctionator's
-- tooltip is GameTooltip:SetHyperlink, so Mailworthy's tooltip lines are there too.
-- Nothing happens without Auctionator. Switch: /mw feature auctionatorTags off (then /reload).
-- Unverified in game: README "Beta unknowns".
local _, ns = ...

local AuctionatorTags = {}
ns.AuctionatorTags = AuctionatorTags

AuctionatorTags.MIXIN = "AuctionatorGroupsViewItemMixin"

local places = setmetatable({}, { __mode = "k" }) -- Auctionator's button -> what it shows now, or false
local tagged = setmetatable({}, { __mode = "k" }) -- Auctionator's button -> its last draw had a tag
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

local function idOf(link)
    return type(link) == "string" and tonumber(link:match("item:(%d+)")) or nil
end

--- What to draw for a button: bag, slot (the first of its stacks still holding its item: the bags
--- may have changed since Auctionator last drew, Codex review) and its link (while Auctionator
--- counts some in the bags; a favourite that isn't there gets nothing). All nil: no tag.
--- A stack counts only when the slot provably holds the button's item: the same item ID, or, for a
--- link with none (a battle pet, a keystone), the same link; no link, no stack (Codex review).
function AuctionatorTags.Pick(where)
    if not where then return nil, nil, nil end
    local id = idOf(where.link)
    local link = where.count > 0 and where.link or nil
    if where.link == nil then return nil, nil, nil end
    for _, s in ipairs(where.slots) do
        local now = ns.Locks.ItemAt(s[1], s[2])
        local same = now and (id ~= nil and tonumber(now.itemID) == id or id == nil and now.hyperlink == where.link)
        if same then return s[1], s[2], link end
    end
    return nil, nil, link
end

--- Draw (or clear) the tag on one of Auctionator's buttons for what it shows now, through the
--- bag buttons' own drawing (Border.RefreshButton: the lock glow and BankAlt's tag, textures in
--- their weak tables; shared with the bag addons' buttons). The link is for the item-by-link
--- fallback when no stack is readable.
function AuctionatorTags.Draw(button)
    local bag, slot, link
    if ns.Features.On("auctionatorTags") then bag, slot, link = AuctionatorTags.Pick(places[button] or nil) end
    -- counted by its stack only: the link fallback draws once Border.RefreshButton takes a link
    tagged[button] = bag ~= nil and ns.Features.On("bankAltTags") and ns.BankAlt.TagAt(bag, slot, nil) ~= nil
    ns.Border.RefreshButton(button, bag, slot, nil, nil, link)
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

--- For specs and /mw report: how many buttons on screen show a tag now (a released pooled button,
--- or the closed auction house, hides them: IsVisible, Codex review).
function AuctionatorTags.Shown()
    local n = 0
    for button, has in pairs(tagged) do
        local ok, visible = pcall(button.IsVisible, button)
        if has and ok and visible then n = n + 1 end
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
