-- Controller helpers that only read: button symbols and API presence.
--
-- Mailworthy must NOT write into Blizzard's controller UI. alpha1 added a
-- Triangle binding to the mail footer (GamepadSharedUtility prompted bindings +
-- Finalize) and registered its own window with FrameControlsManager: on the
-- beta that tainted the whole gamepad input stack from login on, and the game
-- then blocked jumping (DescendStop, RunBinding), targeting
-- (SetPreferredGamepadInteractTarget), InteractUnit, ClearTarget and item use
-- (2026-10-13 self-test). Controller access now comes from Mailworthy's own
-- bindings (PadKey) and highlight (Nav). See docs/FOREVER-UI-NOTES.md.
local _, ns = ...

local Gamepad = {}
ns.Gamepad = Gamepad

Gamepad.FACE_BOTTOM = "PAD1" -- Cross / A
Gamepad.FACE_RIGHT = "PAD2" -- Circle / B
Gamepad.FACE_LEFT = "PAD3" -- Square / X
Gamepad.FACE_TOP = "PAD4" -- Triangle / Y
Gamepad.SHOULDER_RIGHT = "PADRSHOULDER" -- R1 / RB
Gamepad.STICK_LEFT_PRESS = "PADLSTICK" -- L3 / LS
Gamepad.STICK_RIGHT_PRESS = "PADRSTICK" -- R3 / RS

-- What each controller calls a key, for chat lines (a window or tooltip draws the game's icon:
-- Gamepad.Glyph). The key strings are Blizzard's (Blizzard_SharedXML/Shared/GamepadConstants.lua:
-- GAMEPAD_FACE_*, GAMEPAD_SHOULDER_RIGHT, GAMEPAD_STICK_LEFT_PRESS); the styles are its four icon
-- sets (InputIcons/InputIconTexture.lua), which it picks by the active device's labelStyle
-- (InputDeviceIconSetManager.lua): "Shapes" = PlayStation, "Letters" / "Generic" = Xbox,
-- "Reverse" = Switch. A Switch controller gets the Xbox names in chat (operator, 2026-11-09:
-- "Use Xbox names"), though Blizzard's icons for it draw the top button as X and the right
-- shoulder as R ("gamepad-switch-128x-face-x").
local XBOX = { PAD1 = "A", PAD2 = "B", PAD3 = "X", PAD4 = "Y", PADRSHOULDER = "RB", PADLSTICK = "LS", PADRSTICK = "RS" }
local NAMES = {
    Shapes = { PAD1 = "Cross", PAD2 = "Circle", PAD3 = "Square", PAD4 = "Triangle", PADRSHOULDER = "R1", PADLSTICK = "L3",
        PADRSTICK = "R3" },
    Letters = XBOX,
    Generic = XBOX,
    Reverse = XBOX,
}

local function get(path)
    local v = _G
    for part in path:gmatch("[^.]+") do
        if type(v) ~= "table" then return nil end
        v = v[part]
    end
    return v
end
Gamepad.Get = get

--- "Shapes" = PlayStation, "Generic" / "Letters" = Xbox, "Reverse" = Switch.
function Gamepad.LabelStyle()
    local getId, getState = get("C_GamePad.GetActiveDeviceID"), get("C_GamePad.GetDeviceMappedState")
    if type(getId) ~= "function" or type(getState) ~= "function" then return nil end
    local ok, id = pcall(getId)
    if not ok then return nil end
    local ok2, state = pcall(getState, id)
    return ok2 and type(state) == "table" and state.labelStyle or nil
end

--- Pure: the name of a key on a controller with this label style. Any style Mailworthy doesn't
--- know, and no style at all (no controller, a Steam Deck, which the game gives no icon set of
--- its own), gets the Xbox names, and so does a Switch controller.
function Gamepad.NameFor(style, key)
    local names = NAMES[style] or XBOX
    return names[key] or XBOX[key] or tostring(key)
end

--- The name of a key on the player's controller, for a chat line: "R1" / "RB".
function Gamepad.Name(key)
    return Gamepad.NameFor(Gamepad.LabelStyle(), key)
end

--- Pure: a chat line with its {KEY} marks ("{PADRSHOULDER}") replaced by the controller's names.
function Gamepad.Fill(text)
    return (tostring(text):gsub("{(%u[%u%d]*)}", function(key) return Gamepad.Name(key) end))
end

--- The controller's symbol for a key as inline text (a texture markup string;
--- nothing is registered), or its name in brackets ("[Triangle]") if the game can't draw it.
function Gamepad.Glyph(key, size)
    size = size or 16
    local atlasFor = get("InputIconTextureSetUtility.GetNormalActiveInputIconButtonTexture")
    if type(atlasFor) == "function" and type(CreateAtlasMarkup) == "function" then
        local ok, atlas = pcall(atlasFor, key)
        if ok and atlas then
            local ok2, markup = pcall(CreateAtlasMarkup, atlas, size, size)
            if ok2 and markup then return markup end
        end
    end
    return "[" .. Gamepad.Name(key) .. "]"
end

Gamepad.API = {
    "Menu.ModifyMenu", "SmartNavigation", "InputIconTextureSetUtility", "CreateAtlasMarkup",
    "C_GamePad.GetDeviceMappedState", "C_InputInterfaceStyle.GetCurrentStyle", "ItemLocation", "C_Mail.IsCommandPending",
    "C_Container.UseContainerItem", "ClearSendMail", "GetInboxInvoiceInfo", "GetProfessionInfo",
    "C_AuctionHouse.CalculateItemDeposit", "C_AuctionHouse.CalculateCommodityDeposit",
}

function Gamepad.Presence()
    local parts = {}
    for _, path in ipairs(Gamepad.API) do
        local v = get(path)
        parts[#parts + 1] = path .. "=" .. (v == nil and "missing" or type(v))
    end
    return table.concat(parts, ", ")
end
