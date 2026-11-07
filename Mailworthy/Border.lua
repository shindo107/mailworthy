-- Blue glow on locked items in the bags: the quest-item border, tinted blue.
-- Textures are created on the game's bag item buttons (CreateTexture isn't
-- hooked by smart navigation and
-- textures aren't returned by GetChildren, so its button scan never sees them)
-- and kept in our own weak table: no field is ever written on a Blizzard frame.
-- Buttons are pooled, so every refresh recomputes from GetBagID / GetID.
-- Refreshed by a post-hook on each container frame's UpdateItems (combined bags
-- and the individual bag frames), whenever a lock changes, and when the Mailworthy
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
        tex:SetVertexColor(unpack(Border.COLOR))
        tex:SetBlendMode(blend)
        if blend == "ADD" then tex:SetAlpha(Border.GLOW_ALPHA) end
        tex:Hide()
        set[i] = tex
    end
    borders[button] = set
    return set
end

function Border.Show(button, shown)
    if not shown and not borders[button] then return end
    for _, tex in ipairs(Border.Glow(button)) do
        if shown then tex:Show() else tex:Hide() end
    end
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

--- A lock changed: a new lock away from the mailbox flashes for FLASH seconds.
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

Border.TOOLTIP = "Locked in Mailworthy: it stays in your bags and is never mailed. "
    .. "Alt+click it (L3 on a controller) to unlock."

--- Pure: the tooltip line that says why an item glows, or nil when it doesn't glow.
function Border.TooltipLine(itemID)
    if itemID == nil or not ns.Features.On("slotBorder") or not ns.Locks.IsItemLocked(itemID) then return nil end
    if not (Border.Wanted() or Border.Flashing(itemID)) then return nil end
    return Border.TOOLTIP
end

local function onTooltip(tooltip, data)
    if tooltip ~= rawget(_G, "GameTooltip") then return end
    local line = Border.TooltipLine(type(data) == "table" and tonumber(data.id) or nil)
    if not line then return end
    tooltip:AddLine(line, Border.COLOR[1], Border.COLOR[2], Border.COLOR[3], true)
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

--- One bag button: the lock glow (by `itemID`, else the item at bag / slot) and the decorators.
function Border.RefreshButton(button, bag, slot, itemID, wanted)
    if wanted == nil then wanted = Border.Wanted() end
    if ns.Features.On("slotBorder") then
        if itemID == nil and bag ~= nil and slot ~= nil then
            local info = ns.Locks.ItemAt(bag, slot)
            itemID = info and info.itemID
        end
        local locked = itemID ~= nil and ns.Locks.IsItemLocked(itemID)
        Border.Show(button, locked and (wanted or Border.Flashing(itemID)))
    end
    for _, fn in ipairs(decorators) do
        local okDecorate, err = pcall(fn, button, bag, slot)
        if not okDecorate then ns.Log.Add("border", "decorator error: %s", tostring(err)) end
    end
end

-- Baganator (2026-11-07: "I'm not seeing the icon borders anymore on my bag menu": Baganator
-- replaces the game's bags, so the UpdateItems hooks never see its buttons). Its public API,
-- read from Baganator's source (API/Main.lua, ItemViewCommon/ItemButton.lua): a "corner
-- widget" (RegisterCornerWidget(label, id, onUpdate, onInit, defaultPosition)) is built once
-- per item button by onInit(itemButton) and updated by onUpdate(widget, details) with the
-- button's item details (details.itemID, details.itemLink); RequestItemButtonsRefresh() redraws
-- every button. Our widget is an empty texture (never shown: onUpdate returns false, so the
-- corner stays free for other widgets); its onUpdate draws the lock glow on the whole button,
-- in our own weak table like the game's bags. Baganator's buttons are its own, not Blizzard's.
-- All pcall'd (README "Beta unknowns").
Border.BAGANATOR_ID = "mailworthy_lock"
local baganatorOwners = setmetatable({}, { __mode = "k" }) -- widget -> its item button
local baganatorReady = false

local function baganatorAPI()
    local b = rawget(_G, "Baganator")
    local api = type(b) == "table" and b.API or nil
    if type(api) == "table" and type(api.RegisterCornerWidget) == "function" then return api end
    return nil
end

--- Baganator's onInit: an empty, never-shown texture that remembers its button. A texture,
--- not a frame: Baganator may build buttons while a gamepad panel is open, and AGENTS.md
--- allows no CreateFrame then (textures are fine, like the glow itself).
function Border.BaganatorInit(itemButton)
    local widget = itemButton:CreateTexture(nil, "OVERLAY")
    widget:SetSize(1, 1)
    widget:Hide()
    baganatorOwners[widget] = itemButton
    return widget
end

--- Baganator's onUpdate: the glow for the button's item; false keeps the widget hidden.
function Border.BaganatorUpdate(widget, details)
    local button = baganatorOwners[widget]
    if not button then return false end
    local itemID = type(details) == "table" and tonumber(details.itemID) or nil
    local bag, slot
    local okParent, parent = pcall(button.GetParent, button)
    if okParent and type(parent) == "table" and type(parent.GetID) == "function" then
        local okBag, b = pcall(parent.GetID, parent)
        local okSlot, sl = pcall(button.GetID, button)
        if okBag and okSlot then bag, slot = b, sl end
    end
    local ok, err = pcall(Border.RefreshButton, button, bag, slot, itemID)
    if not ok then ns.Log.Add("border", "Baganator refresh error: %s", tostring(err)) end
    return false
end

function Border.InstallBaganator()
    if baganatorReady then return true end
    local api = baganatorAPI()
    if not api then return false end
    -- Created at login (no CreateFrame while a gamepad panel is open): Baganator builds the
    -- widgets for its buttons, and our onInit only runs from its item button setup.
    local ok, err = pcall(api.RegisterCornerWidget, "Mailworthy lock glow", Border.BAGANATOR_ID,
        Border.BaganatorUpdate, Border.BaganatorInit, { corner = "top_left", priority = 1 })
    if not ok then
        ns.Log.Add("border", "Baganator corner widget failed: %s", tostring(err))
        return false
    end
    baganatorReady = true
    ns.Log.Add("border", "Baganator: lock glow registered (Baganator settings, Icons, top left corner)")
    return true
end

function Border.RefreshAll()
    for _, frame in ipairs(frames) do Border.RefreshFrame(frame) end
    local api = baganatorReady and baganatorAPI()
    if api and type(api.RequestItemButtonsRefresh) == "function" then pcall(api.RequestItemButtonsRefresh) end
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
    Border.InstallBaganator()
    if ns.Features.On("slotBorder") then Border.InstallTooltip() end
    ns.Locks.OnChanged(Border.OnLockChanged)
    ns.Log.Add("border", "UpdateItems hooked on %d container frames", hooked)
end

ns.On("PLAYER_LOGIN", function() Border.Install() end)
-- MailWindow refreshes the glow when its window shows or hides; the mailbox closing hides it.
ns.On("MAIL_CLOSED", function() Border.RefreshAll() end)
