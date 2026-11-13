-- Mailworthy's own controller bindings. They never touch Blizzard's controller UI.
--
-- Each binding is SetOverrideBindingClick(our frame, true, key, our button):
-- it writes no Blizzard Lua table. alpha1 wrote Triangle into the mail
-- window's footer and tainted gamepad input game-wide; this mechanism carried
-- Triangle through alpha3/alpha4 without one blocked action. A watcher checks
-- every 0.1 s which set is wanted, from read-only state
-- (FrameControlsManager:GetActiveFrame(), InputUtil.IsGamepadUIEnabled()):
--
--   mail    mail window focused, Mailworthy window closed:  Triangle opens it
--   window  mail window focused, Mailworthy window open:    Triangle closes,
--           D-pad moves Mailworthy's highlight (Nav), Cross presses, Circle closes
--   bags    bags focused:  L3 locks / unlocks the selected item (Locks), R3 pins / unpins it
--           for the bank (Pins); each key has its own switch (padLock, padPin)
--   merchant  merchant window focused:  Triangle opens / closes the vendor window (Vendor)
--   settings  the settings, friends, ledger, locked items, summary, vendor or report window open, anywhere (out of combat): D-pad moves,
--           Cross presses, Circle closes it. Our own window, so no Blizzard
--           panel needs focus; the bindings go as soon as it closes.
--
-- Blizzard binds unused face buttons to nothing while a window is focused and
-- re-applies its bindings on its own refreshes, so ours are re-applied when
-- GetBindingAction(key, true) shows they were replaced (the pattern
-- wow-forever-tweaks uses). Everything is cleared when no set is wanted, and
-- at the start of combat (bindings can't change in combat).
local _, ns = ...

local PadKey = {}
ns.PadKey = PadKey

PadKey.INTERVAL = 0.1
PadKey.SETS = {
    mail = { PAD4 = "MailworthyPadTriangle" },
    window = {
        PAD4 = "MailworthyPadTriangle", PAD1 = "MailworthyPadCross", PAD2 = "MailworthyPadCircle",
        PADDUP = "MailworthyPadUp", PADDDOWN = "MailworthyPadDown",
        PADDLEFT = "MailworthyPadLeft", PADDRIGHT = "MailworthyPadRight",
    },
    bags = { PADLSTICK = "MailworthyPadLock", PADRSTICK = "MailworthyPadPin" },
    merchant = { PAD4 = "MailworthyPadVendor" },
    settings = {
        PAD1 = "MailworthyPadCross", PAD2 = "MailworthyPadCircle",
        PADDUP = "MailworthyPadUp", PADDDOWN = "MailworthyPadDown",
        PADDLEFT = "MailworthyPadLeft", PADDRIGHT = "MailworthyPadRight",
    },
}

local NAVIGATES = { window = true, settings = true }
-- A key with a switch of its own (/mw feature): bound only while its feature is on.
PadKey.KEY_FEATURE = { PADLSTICK = "padLock", PADRSTICK = "padPin" }

local watcher, active, elapsed = nil, nil, 0
PadKey.stats = { applies = 0, clears = 0, presses = 0, sets = {} }

local function call(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, result = pcall(fn, ...)
    return ok and result or nil
end

local function activeFrame()
    local manager = GamepadMode and GamepadMode.FrameControlsManager
    if type(manager) ~= "table" then return nil end
    return call(manager.GetActiveFrame, manager)
end

local function isBagFrame(frame)
    if frame == nil then return false end
    if frame == rawget(_G, "ContainerFrameCombinedBags") then return true end
    local container = rawget(_G, "ContainerFrameContainer")
    for _, f in ipairs(type(container) == "table" and type(container.ContainerFrames) == "table"
        and container.ContainerFrames or {}) do
        if f == frame then return true end
    end
    return false
end

--- Which binding set is wanted right now (nil = none).
function PadKey.Wanted()
    if InCombatLockdown() or not ns.MailButton.GamepadUI() then return nil end
    -- "settings": our free-standing windows (settings, friends, ledger, locked items, bank alt summary,
    -- report), anywhere.
    local standalone = false
    for _, mod in ipairs({ ns.SettingsUI, ns.RoutesUI, ns.LedgerUI, ns.LocksUI, ns.BankAlt, ns.Vendor, ns.Report }) do
        local f = mod and mod.Frame()
        if f and f:IsShown() then standalone = true end
    end
    if standalone and ns.Features.On("padNav") then return "settings" end
    local focused = activeFrame()
    local mail = rawget(_G, "MailFrame")
    if focused ~= nil and focused == mail and mail:IsShown() then
        local window = ns.MailWindow and ns.MailWindow.Frame()
        if window and window:IsShown() and ns.Features.On("padNav") then return "window" end
        if ns.Features.On("padTriangle") then return "mail" end
    elseif isBagFrame(focused) and (ns.Features.On("padLock") or ns.Features.On("padPin")) then
        return "bags"
    elseif focused ~= nil and focused == rawget(_G, "MerchantFrame") and focused:IsShown() and ns.Features.On("padVendor")
        and ns.Features.On("vendorButton") then
        return "merchant"
    end
    return nil
end

-- `entering` = PLAYER_REGEN_DISABLED, whose handlers run before combat lockdown
-- starts: clear then even though InCombatLockdown() may already say true.
local function clear(reason, entering)
    if not active then return end
    if InCombatLockdown() and not entering then return end
    pcall(ClearOverrideBindings, watcher)
    ns.Log.Add("pad", "%s bindings cleared (%s)", active, reason)
    PadKey.stats.clears = PadKey.stats.clears + 1
    if NAVIGATES[active] then ns.Nav.Stop() end
    active = nil
end

function PadKey.Check()
    local want = PadKey.Wanted()
    if want ~= active then
        clear(want and ("now " .. want) or "nothing focused for Mailworthy")
        if want == nil then return end
        active = want
        PadKey.stats.sets[want] = (PadKey.stats.sets[want] or 0) + 1
        ns.Log.Add("pad", "%s bindings on", want)
        if NAVIGATES[want] then ns.Nav.Follow(true) end
    end
    if not active then return end -- nothing wanted and nothing bound (most of the time)
    if NAVIGATES[active] then ns.Nav.Follow() end
    for key, buttonName in pairs(PadKey.SETS[active]) do
        local expected = "CLICK " .. buttonName .. ":LeftButton"
        local feature = PadKey.KEY_FEATURE[key]
        local okAction, action = pcall(GetBindingAction, key, true)
        if feature and not ns.Features.On(feature) then -- luacheck: ignore 542
            -- this key's switch is off: Blizzard keeps it
        elseif not okAction or action ~= expected then
            local ok, err = pcall(SetOverrideBindingClick, watcher, true, key, buttonName)
            PadKey.stats.applies = PadKey.stats.applies + 1
            if PadKey.stats.applies <= 12 or PadKey.stats.applies % 50 == 0 then
                ns.Log.Add("pad", "%s -> %s (apply #%d, was %q)%s", key, buttonName, PadKey.stats.applies,
                    tostring(action), ok and "" or (": " .. tostring(err)))
            end
        end
    end
end

-- A hidden click target per action. A CLICK binding may deliver a press as
-- down, up or both depending on settings: act on the down, ignore the matching
-- up, and debounce when the state isn't given.
local function padButton(name, fn)
    local b = CreateFrame("Button", name, UIParent)
    b:Hide()
    b:RegisterForClicks("AnyDown", "AnyUp")
    local lastDown, last = -10, -10
    b:SetScript("OnClick", function(_, _, down)
        local now = GetTime()
        if down == false then
            if now - lastDown < 1 then return end
        elseif down == true then
            lastDown = now
        elseif now - last < 0.25 then
            return
        end
        last = now
        PadKey.stats.presses = PadKey.stats.presses + 1
        local ok, err = pcall(fn)
        if not ok then ns.Log.Add("pad", "%s error: %s", name, tostring(err)) end
    end)
    return b
end

function PadKey.Create()
    if watcher then return end
    watcher = CreateFrame("Frame", "MailworthyPadWatcher", UIParent)
    watcher:SetScript("OnUpdate", function(_, delta)
        elapsed = elapsed + delta
        if elapsed < PadKey.INTERVAL then return end
        elapsed = 0
        local ok, err = pcall(PadKey.Check)
        if not ok then ns.Log.Add("pad", "check error: %s", tostring(err)) end
    end)
    -- The watcher stops ticking while the interface is hidden (Alt+Z, a cinematic hides UIParent),
    -- so it can no longer see focus go: let go now, or Cross (jump) and the D-pad stay ours.
    watcher:SetScript("OnHide", function() clear("interface hidden") end)
    padButton("MailworthyPadTriangle", function() ns.MailButton.Activate("Triangle") end)
    padButton("MailworthyPadCross", function() ns.Nav.Press() end)
    padButton("MailworthyPadCircle", function()
        local closed = ns.Nav.CloseTop()
        ns.Log.Add("pad", "Circle closed %s", closed and tostring(closed:GetName()) or "nothing")
        -- Back in the window below (the Mailworthy window under the settings): on the button
        -- that opened the closed one, else its top-left.
        ns.Nav.Follow()
    end)
    for _, dir in ipairs({ "Up", "Down", "Left", "Right" }) do
        padButton("MailworthyPad" .. dir, function() ns.Nav.Move(dir:lower()) end)
    end
    padButton("MailworthyPadLock", function() ns.Locks.ToggleSelectedBagSlot() end)
    padButton("MailworthyPadPin", function() ns.Pins.ToggleSelectedBagSlot() end)
    padButton("MailworthyPadVendor", function() ns.Vendor.Toggle("Triangle") end)
    -- Hint under the combined bags (a font string: not a frame, not seen by smart navigation).
    local bags = rawget(_G, "ContainerFrameCombinedBags")
    if type(bags) == "table" and (ns.Features.On("padLock") or ns.Features.On("padPin")) then
        PadKey.bagHint = bags:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        PadKey.bagHint:SetPoint("TOPLEFT", bags, "BOTTOMLEFT", 10, -4)
        PadKey.RefreshHint()
    end
    ns.Log.Add("pad", "controller watcher ready")
end

function PadKey.RefreshHint()
    if not PadKey.bagHint then return end
    local parts = {}
    if ns.Features.On("padLock") then
        parts[#parts + 1] = ns.Gamepad.Glyph(ns.Gamepad.STICK_LEFT_PRESS, 14) .. " Mailworthy: lock / unlock item"
    end
    if ns.Features.On("padPin") then
        parts[#parts + 1] = ns.Gamepad.Glyph(ns.Gamepad.STICK_RIGHT_PRESS, 14) .. " bank pin"
    end
    PadKey.bagHint:SetText(ns.MailButton.GamepadUI() and table.concat(parts, "   ") or "")
end

--- The hint under the bags as drawn ("" for mouse / keyboard, or with padLock and padPin off).
function PadKey.BagHint()
    return PadKey.bagHint and PadKey.bagHint:GetText() or ""
end

function PadKey.Report()
    local sets = {}
    for name, n in pairs(PadKey.stats.sets) do sets[#sets + 1] = name .. " x" .. n end
    table.sort(sets)
    return string.format("controller bindings: sets %s, applies %d, clears %d, presses %d, PAD4 now %s, PADDUP now %s; "
        .. "highlight followed %d window change(s), %d back to the opener's button, %d row tooltip(s) shown",
        #sets > 0 and table.concat(sets, ", ") or "none", PadKey.stats.applies, PadKey.stats.clears,
        PadKey.stats.presses, tostring(select(2, pcall(GetBindingAction, "PAD4", true))),
        tostring(select(2, pcall(GetBindingAction, "PADDUP", true))), ns.Nav.stats.follows, ns.Nav.stats.returns,
        ns.MailWindow.stats.padTips)
end

ns.On("PLAYER_LOGIN", function() PadKey.Create() end)
ns.On("INPUT_DEVICE_INTERFACE_TRANSITION", function() PadKey.RefreshHint() end)
ns.On("PLAYER_REGEN_DISABLED", function() clear("combat", true) end)
