-- Blue glow on locked items in the bags: the quest-item border, tinted blue. A bank-pinned item
-- (Pins.lua) glows the same way in the pin's green (Pins.COLOR; a lock wins on an item that is both).
-- Textures are created on the game's bag item buttons (CreateTexture isn't
-- hooked by smart navigation and
-- textures aren't returned by GetChildren, so its button scan never sees them)
-- and kept in our own weak table: no field is ever written on a Blizzard frame.
-- Buttons are pooled, so every refresh recomputes from GetBagID / GetID.
-- Refreshed by a post-hook on each container frame's UpdateItems (combined bags
-- and the individual bag frames; the bag addons' buttons through BagAddons.lua and
-- Border.AddRefresher), whenever a lock changes, and when the Mailworthy
-- window shows or hides: the glow shows only while that window is open at the
-- mailbox (operator, 2026-11-07: "only when looking at the mailbox with the addon
-- open"; before, any open mailbox lit it, and a CurseForge user, 2026-10-21, found
-- the blue hue all the time noise), unless the "glow everywhere" setting is on.
-- Elsewhere a fresh lock (Alt+click, L3) still glows for FLASH seconds on every
-- stack of that item, so the player sees it worked (operator, 2026-10-21).
-- Hovering a glowing item says why it is blue: a tooltip line through
-- TooltipDataProcessor (like the bank alt lines), only while the glow shows.
local _, ns = ...

local Border = {}
ns.Border = Border

-- The quest-item border Blizzard draws on bag slots (TEXTURE_ITEM_QUEST_BORDER),
-- desaturated and tinted blue, plus an additive copy for the glow.
Border.TEXTURE = "Interface\\ContainerFrame\\UI-Icon-QuestBorder"
Border.COLOR = { 0.3, 0.65, 1 }
Border.GLOW_ALPHA = 0.7
Border.FLASH = 3 -- seconds a fresh lock glows away from the mailbox

local borders = setmetatable({}, { __mode = "k" }) -- button -> { textures }
local frames = {}
local flashes = {} -- itemID -> GetTime() until which a fresh lock glows anyway
local decorators = {} -- fn(button, bag, slot): more per-slot drawing (bank alt tags)

--- Draw more on every bag button after each refresh (same hooks, same rules).
function Border.AddDecorator(fn) table.insert(decorators, fn) end

--- Pin a texture or font string of ours on someone else's button at `alpha` (default 1): a skin
--- that fades every region of an item button it doesn't know (EllesmereUI through Baganator's
--- "Ellesmere UI" theme: SetAlpha(0) when it skins the button, again on every restrip; issue #89)
--- leaves it alone. The field is written on our own region, never on the button.
function Border.HoldAlpha(region, alpha)
    region:SetAlpha(alpha or 1)
    region.SetAlpha = function() end
    return region
end

--- The lock glow for any button (ours or the game's bag buttons), created once,
--- kept in our own weak table.
function Border.Glow(button)
    local set = borders[button]
    if set then return set end
    set = {}
    for i, blend in ipairs({ "BLEND", "ADD" }) do
        local tex = button:CreateTexture(nil, "OVERLAY", nil, 6 + i - 1)
        tex:SetTexture(Border.TEXTURE)
        tex:SetAllPoints()
        tex:SetDesaturated(true)
        tex:SetBlendMode(blend)
        Border.HoldAlpha(tex, blend == "ADD" and Border.GLOW_ALPHA or 1)
        tex:Hide()
        set[i] = tex
    end
    borders[button] = set
    return set
end

--- Show the glow in `color` (default the lock's blue), or hide it.
function Border.Show(button, shown, color)
    if not shown and not borders[button] then return end
    color = color or Border.COLOR
    for _, tex in ipairs(Border.Glow(button)) do
        if shown then
            tex:SetVertexColor(color[1], color[2], color[3])
            tex:Show()
        else
            tex:Hide()
        end
    end
end

--- Is this item bank-pinned (Pins.lua)?
local function pinned(itemID)
    return itemID ~= nil and ns.Pins ~= nil and ns.Pins.Kind(itemID) == ns.Pins.BANK
end

--- Is the Mailworthy window open? It lives under the mail frame's tabs, so it is visible only
--- at a mailbox (IsVisible: hidden with its tab or with the mailbox, its own shown flag stays).
function Border.WindowOpen()
    local window = ns.MailWindow and ns.MailWindow.Frame and ns.MailWindow.Frame()
    if type(window) ~= "table" or type(window.IsVisible) ~= "function" then return false end
    local ok, visible = pcall(window.IsVisible, window)
    return ok and visible == true
end

--- Should locked items glow in the bags right now?
function Border.Wanted()
    return ns.Features.On("slotBorder") and (Border.WindowOpen() or ns.Config.Flag("glowEverywhere"))
end

local function now()
    local ok, t = pcall(GetTime)
    return ok and tonumber(t) or 0
end

--- Is this item in its feedback flash (locked moments ago, away from the mailbox)?
function Border.Flashing(itemID)
    local until_ = itemID ~= nil and flashes[itemID]
    return until_ ~= nil and now() < until_
end

--- A lock changed: a new lock away from the mailbox flashes for FLASH seconds. A new pin too
--- (Border.OnPinChanged).
function Border.OnLockChanged(itemID, locked)
    if itemID == nil then return end
    flashes[itemID] = nil
    if locked and ns.Features.On("slotBorder") and not Border.Wanted() then
        flashes[itemID] = now() + Border.FLASH
        local after = C_Timer and C_Timer.After
        if type(after) == "function" then
            pcall(after, Border.FLASH, function()
                if flashes[itemID] ~= nil and now() >= flashes[itemID] then
                    flashes[itemID] = nil
                    Border.RefreshAll()
                end
            end)
        end
    end
    Border.RefreshAll()
end

--- A pin changed (Pins.OnChanged): a new pin flashes green like a new lock flashes blue.
function Border.OnPinChanged(itemID, kind)
    Border.OnLockChanged(itemID, kind == (ns.Pins and ns.Pins.BANK))
end

--- Why an item glows. The controller's key is the game's own icon for the left stick press, so
--- it reads L3 on a PlayStation controller and LS on an Xbox one (Gamepad.Glyph).
function Border.Tooltip()
    return "Locked in Mailworthy: it stays in your bags and is never mailed. "
        .. "Alt+click it (" .. ns.Gamepad.Glyph(ns.Gamepad.STICK_LEFT_PRESS, 14) .. " on a controller) to unlock."
end

--- Why a pinned item glows green (R3 / RS by the player's controller, like the lock's line).
function Border.PinTooltip()
    return "Pinned in Mailworthy: Send mails it to your bank alt every time, unless it can never be mailed"
        .. " (soulbound, locked, a quest's). Ctrl+Alt+click it (" .. ns.Gamepad.Glyph(ns.Gamepad.STICK_RIGHT_PRESS, 14)
        .. " on a controller) to unpin."
end

--- The tooltip line that says why an item glows and its colour, or nil when it doesn't glow.
function Border.TooltipLine(itemID)
    if itemID == nil or not ns.Features.On("slotBorder") then return nil end
    if not (Border.Wanted() or Border.Flashing(itemID)) then return nil end
    if ns.Locks.IsItemLocked(itemID) then return Border.Tooltip(), Border.COLOR end
    if pinned(itemID) then return Border.PinTooltip(), ns.Pins.COLOR end
    return nil
end

local function onTooltip(tooltip, data)
    if tooltip ~= rawget(_G, "GameTooltip") then return end
    local id = type(data) == "table" and tonumber(data.id) or nil
    -- A row of the Mailworthy window says it itself ("Click to unlock": MailWindow.TooltipLines).
    if id and ns.MailWindow and ns.MailWindow.TooltipItem(tooltip) == id then return end
    local line, color = Border.TooltipLine(id)
    if not line then return end
    tooltip:AddLine(line, color[1], color[2], color[3], true)
end

function Border.InstallTooltip()
    local processor, enum = rawget(_G, "TooltipDataProcessor"), rawget(_G, "Enum")
    local itemType = type(enum) == "table" and type(enum.TooltipDataType) == "table" and enum.TooltipDataType.Item
    if type(processor) ~= "table" or type(processor.AddTooltipPostCall) ~= "function" or itemType == nil then
        ns.Log.Add("border", "TooltipDataProcessor missing: no lock tooltip line")
        return false
    end
    local ok, err = pcall(processor.AddTooltipPostCall, itemType, function(tooltip, data)
        local okLine, errLine = pcall(onTooltip, tooltip, data)
        if not okLine then ns.Log.Add("border", "tooltip error: %s", tostring(errLine)) end
    end)
    ns.Log.Add("border", "lock tooltip line %s", ok and "installed" or ("failed: " .. tostring(err)))
    return ok
end

--- Every button of one container frame. Forever's EnumerateValidItems (BaseContainerFrameMixin)
--- runs to GetBagSize() and yields `index, Items[index]` even when that button is nil: the
--- combined bags' size counts every bag's slots, Items only the buttons laid out so far (v0.22.0
--- logged "Border.lua:113: attempt to index local 'button'" at every login). Missing buttons are
--- skipped; the ones after them are still drawn.
function Border.RefreshFrame(frame)
    if type(frame) ~= "table" or type(frame.EnumerateValidItems) ~= "function" then return end
    local ok, iter, state, start = pcall(frame.EnumerateValidItems, frame)
    if not ok or type(iter) ~= "function" then return end
    local wanted = Border.Wanted()
    for _, button in iter, state, start do
        if type(button) == "table" then
            local okBag, bag = pcall(button.GetBagID, button)
            local okSlot, slot = pcall(button.GetID, button)
            Border.RefreshButton(button, okBag and okSlot and bag or nil, okBag and okSlot and slot or nil, nil,
                wanted)
        end
    end
end

--- The one drawing helper for any item button (Blizzard's bags, the bag addons in BagAddons.lua,
--- Auctionator's views): the lock glow (by `itemID`, else the item at bag / slot) and the
--- decorators (BankAlt's AH / B / DE / V tag), all kept in our own weak tables keyed by button.
--- `bag` / `slot` may be nil (a view with no bag slot): decorators then find the item by `link`,
--- then `itemID`. Called with only `button`, it clears everything we drew on that button.
function Border.RefreshButton(button, bag, slot, itemID, wanted, link)
    if wanted == nil then wanted = Border.Wanted() end
    if ns.Features.On("slotBorder") then
        if itemID == nil and bag ~= nil and slot ~= nil then
            local info = ns.Locks.ItemAt(bag, slot)
            itemID = info and info.itemID
        end
        local locked = itemID ~= nil and ns.Locks.IsItemLocked(itemID)
        local pin = not locked and pinned(itemID)
        Border.Show(button, (locked or pin) and (wanted or Border.Flashing(itemID)),
            pin and ns.Pins.COLOR or Border.COLOR)
    end
    for _, fn in ipairs(decorators) do
        local okDecorate, err = pcall(fn, button, bag, slot, itemID, link)
        if not okDecorate then ns.Log.Add("border", "decorator error: %s", tostring(err)) end
    end
end

--- Clear the glow and every decorator on a button (an empty slot, another character's bags).
function Border.Clear(button)
    Border.RefreshButton(button, nil, nil, nil, false, nil)
end

--- Pure: the item ID in an item link, or nil.
function Border.LinkID(link)
    return type(link) == "string" and tonumber(link:match("item:(%d+)")) or nil
end

--- A bag addon's button for a live bag slot: draw what is in that slot now. `shownID` is the item
--- the addon says the button shows (nil when it didn't say): when the slot holds something else
--- (a recycled button drawn before the addon caught up, another character's bags laid over the
--- same slot numbers) or nothing, the button is cleared instead. Returns the drawn item's ID.
function Border.DrawBagSlot(button, bag, slot, shownID, wanted)
    local info = bag ~= nil and slot ~= nil and ns.Locks.ItemAt(bag, slot) or nil
    local itemID = info and tonumber(info.itemID)
    if itemID == nil or (shownID ~= nil and shownID ~= itemID) then
        Border.Clear(button)
        return nil
    end
    Border.RefreshButton(button, bag, slot, itemID, wanted, info.hyperlink)
    return itemID
end

local refreshers = {} -- fn(wanted): redraw the buttons another bag view keeps (BagAddons)

--- Run `fn(wanted)` on every RefreshAll, after the game's bags.
function Border.AddRefresher(fn) table.insert(refreshers, fn) end

--- Whether a container frame is closed: nothing on it to redraw. Opening one redraws it anyway:
--- ContainerFrame_GenerateFrame -> Update -> AddItemsForRefresh -> UpdateItems (Forever's
--- ContainerFrame.lua), which our hook follows.
local function closed(frame)
    if type(frame.IsShown) ~= "function" then return false end
    local ok, shown = pcall(frame.IsShown, frame)
    return ok and shown == false
end

--- Redraw every open bag frame. Closed ones are skipped: on the bank alt each redraw re-reads
--- every slot and its tags re-evaluate the bags, and it runs at every bag update and every
--- Auctionator database update during a scan (BugGrabber via rl-companion, 2026-11-07: 37 calls
--- from Auctionator's incremental scan in one session).
function Border.RefreshAll()
    for _, frame in ipairs(frames) do
        if not closed(frame) then Border.RefreshFrame(frame) end
    end
    local wanted
    for _, fn in ipairs(refreshers) do
        if wanted == nil then wanted = Border.Wanted() end
        local ok, err = pcall(fn, wanted)
        if not ok then ns.Log.Add("border", "refresher error: %s", tostring(err)) end
    end
end

local function containerFrames()
    local list = {}
    local combined = rawget(_G, "ContainerFrameCombinedBags")
    if type(combined) == "table" then list[#list + 1] = combined end
    local container = rawget(_G, "ContainerFrameContainer")
    for _, frame in ipairs(type(container) == "table" and type(container.ContainerFrames) == "table"
        and container.ContainerFrames or {}) do
        list[#list + 1] = frame
    end
    return list
end

function Border.Install()
    -- The hooks serve the lock glow and the bank alt tags: either switch keeps them.
    if not ns.Features.On("slotBorder") and not ns.Features.On("bankAltTags") then
        ns.Log.Add("border", "slot border and bank alt tags off (/mw feature slotBorder on, then /reload)")
        return
    end
    local hooked = 0
    for _, frame in ipairs(containerFrames()) do
        if type(frame.UpdateItems) == "function" then
            local ok = pcall(hooksecurefunc, frame, "UpdateItems", function(self)
                local okRefresh, err = pcall(Border.RefreshFrame, self)
                if not okRefresh then ns.Log.Add("border", "refresh error: %s", tostring(err)) end
            end)
            if ok then
                hooked = hooked + 1
                frames[#frames + 1] = frame
            end
        end
    end
    if ns.Features.On("slotBorder") then Border.InstallTooltip() end
    ns.Locks.OnChanged(Border.OnLockChanged)
    ns.Pins.OnChanged(Border.OnPinChanged)
    ns.Log.Add("border", "UpdateItems hooked on %d container frames", hooked)
end

ns.On("PLAYER_LOGIN", function() Border.Install() end)
-- MailWindow refreshes the glow when its window shows or hides; the mailbox closing hides it.
ns.On("MAIL_CLOSED", function() Border.RefreshAll() end)
