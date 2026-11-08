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
-- send) and are redrawn with them (Border.AddRefresher). Hovering is never needed; Auctionator's
-- tooltip is GameTooltip:SetHyperlink, so Mailworthy's tooltip lines are there too.
-- Nothing happens without Auctionator. Switch: /mw feature auctionatorTags off (then /reload).
-- Unverified in game: README "Beta unknowns".
local _, ns = ...

local AuctionatorTags = {}
ns.AuctionatorTags = AuctionatorTags

AuctionatorTags.MIXIN = "AuctionatorGroupsViewItemMixin"

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

--- Pure: "itemID:suffixID" for an item link (field 7 of "item:...": the random suffix, "of the
--- Bear"), nil for a link with no item ID (a battle pet, a keystone). Auctionator replaces the bag's
--- hyperlink with GetItemInfo's, which may differ in other fields, so the whole link can't be compared.
function AuctionatorTags.Variant(link)
    local body = type(link) == "string" and link:match("item:([%-%d:]+)") or nil
    if not body then return nil end
    local fields = {}
    for f in (body .. ":"):gmatch("([^:]*):") do fields[#fields + 1] = f end
    local id = tonumber(fields[1])
    if not id then return nil end
    return id .. ":" .. tostring(tonumber(fields[7]) or 0)
end

--- What to draw for a button: bag, slot (the first of its stacks still holding its item: the bags
--- may have changed since Auctionator last drew, Codex review) and its link (while Auctionator
--- counts some in the bags; a favourite that isn't there gets nothing). All nil: no tag.
--- A stack counts only when the slot provably holds the button's item: the same item ID and random
--- suffix (two "of the Bear" / "of the Whale" pieces share an ID, not a price), or, for a link with
--- no item ID (a battle pet, a keystone), the same link; no link, no stack (Codex reviews).
function AuctionatorTags.Pick(where)
    if not where or where.link == nil then return nil, nil, nil end
    local variant = AuctionatorTags.Variant(where.link)
    local link = where.count > 0 and where.link or nil
    for _, s in ipairs(where.slots) do
        local now = ns.Locks.ItemAt(s[1], s[2])
        local same = now ~= nil and (variant ~= nil and AuctionatorTags.Variant(now.hyperlink) == variant
            or variant == nil and now.hyperlink == where.link)
        if same then return s[1], s[2], link end
    end
    return nil, nil, link
end

--- Draw (or clear) the tag on one of Auctionator's buttons for what it shows now, through the
--- bag buttons' own drawing (Border.RefreshButton: the lock glow and BankAlt's tag, textures in
--- their weak tables; shared with the bag addons' buttons). The link is for the item-by-link
--- fallback when no stack is readable (BankAlt.Decorate: by link when there's no slot).
function AuctionatorTags.Draw(button, wanted)
    local bag, slot, link
    if ns.Features.On("auctionatorTags") then bag, slot, link = AuctionatorTags.Pick(places[button] or nil) end
    ns.Border.RefreshButton(button, bag, slot, nil, wanted, link)
end

--- The post-hook: Auctionator gave `button` a new item (or nil).
function AuctionatorTags.OnSetItemInfo(button, info)
    state.calls = state.calls + 1
    if type(button) ~= "table" then return end
    places[button] = AuctionatorTags.Where(info) or false
    AuctionatorTags.Draw(button)
end

--- Redraw every button Auctionator has handed us: a Border refresher, run by every Border.RefreshAll
--- (verdicts changed: bags, prices, locks, settings; the Mailworthy window shown or hidden; a lock's
--- flash over, Codex review).
function AuctionatorTags.RefreshAll(wanted)
    for button in pairs(places) do AuctionatorTags.Draw(button, wanted) end
end

--- For specs and /mw report: how many buttons on screen show a tag now (a released pooled button,
--- or the closed auction house, hides them: IsVisible, Codex review).
function AuctionatorTags.Shown()
    local n = 0
    for button in pairs(places) do
        local ok, visible = pcall(button.IsVisible, button)
        if ok and visible and ns.BankAlt.TagShown(button) then n = n + 1 end
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
    ns.Border.AddRefresher(AuctionatorTags.RefreshAll)
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
