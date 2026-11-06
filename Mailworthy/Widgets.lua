-- Shared building blocks for Mailworthy's windows. Frames are created at login
-- on UIParent and parented afterwards: creating frames while a gamepad panel is
-- open trips SmartNavigation's CreateFrame hook in our context. No
-- smart-navigation keys are set on anything (controller: Nav + PadKey).
local _, ns = ...

local Widgets = {}
ns.Widgets = Widgets

Widgets.BACKDROP = {
    bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
    tile = true, tileSize = 32, edgeSize = 32,
    insets = { left = 11, right = 12, top = 12, bottom = 11 },
}

--- A dialog-style window with a close button; Escape closes it. Hidden until shown.
function Widgets.Window(name, width, height, parent)
    local ok, f = pcall(CreateFrame, "Frame", name, UIParent, "BackdropTemplate")
    if not ok then f = CreateFrame("Frame", name, UIParent) end
    if parent then f:SetParent(parent) end
    f:SetSize(width, height)
    f:SetFrameStrata("DIALOG")
    f:EnableMouse(true)
    if f.SetBackdrop then
        f:SetBackdrop(Widgets.BACKDROP)
        f:SetBackdropColor(0.05, 0.05, 0.07, 1) -- opaque: a window on top never shows the text below
    end
    f:SetClampedToScreen(true)
    f.CloseButton = CreateFrame("Button", name .. "CloseButton", f, "UIPanelCloseButton")
    f.CloseButton:SetPoint("TOPRIGHT", -6, -6)
    if type(UISpecialFrames) == "table" then table.insert(UISpecialFrames, name) end
    f:Hide()
    return f
end

--- Pure: which side of an opener a window of `width` fits on, all in one unit:
--- "right", "left" (both with `gap`), or nil when neither (the caller lays it over the opener).
function Widgets.Side(openerLeft, openerRight, width, screenWidth, gap)
    gap = gap or 8
    if not (openerLeft and openerRight and width and screenWidth) then return nil end
    if openerRight + gap + width <= screenWidth then return "right" end
    if openerLeft - gap - width >= 0 then return "left" end
    return nil
end

--- Place a window that another Mailworthy window opened (operator, 2026-11-06: popups
--- "overlap the existing menus and you cant read the new popup easily"): beside the opener
--- when it fits on screen, else squarely over it (opaque, so the opener's text never shows
--- through); centred without an opener (/mw, the minimap button). Clamped to the screen.
function Widgets.PlaceBeside(f, opener)
    f:ClearAllPoints()
    local side
    if opener and opener ~= f and opener:IsVisible() then
        local left, right = opener:GetLeft(), opener:GetRight()
        local fScale, oScale = f:GetEffectiveScale(), opener:GetEffectiveScale()
        local screen = UIParent:GetRight()
        local uiScale = UIParent:GetEffectiveScale()
        if left and right and screen and fScale and oScale and uiScale and fScale > 0 then
            local k = oScale / fScale
            side = Widgets.Side(left * k, right * k, f:GetWidth(), screen * uiScale / fScale, 8) or "over"
        else
            side = "over"
        end
    end
    if side == "right" then
        f:SetPoint("TOPLEFT", opener, "TOPRIGHT", 8, 0)
    elseif side == "left" then
        f:SetPoint("TOPRIGHT", opener, "TOPLEFT", -8, 0)
    elseif side == "over" then
        f:SetPoint("TOPLEFT", opener, "TOPLEFT", 0, 0)
    else
        f:SetPoint("CENTER")
    end
    return side or "center"
end

function Widgets.Button(parent, text, width, onClick, name)
    local b = CreateFrame("Button", name, parent, "UIPanelButtonTemplate")
    b:SetSize(width, 22)
    b:SetText(text)
    b:SetScript("OnClick", onClick)
    return b
end

function Widgets.Label(parent, font)
    return parent:CreateFontString(nil, "OVERLAY", font or "GameFontNormal")
end

--- The controller legend line: "(Cross) press   (Circle) close   D-pad move".
function Widgets.Legend(extra)
    local text = string.format("%s press    %s close    D-pad move", ns.Gamepad.Glyph(ns.Gamepad.FACE_BOTTOM),
        ns.Gamepad.Glyph(ns.Gamepad.FACE_RIGHT))
    return extra and (text .. "    " .. extra) or text
end
