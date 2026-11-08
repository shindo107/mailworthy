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

Widgets.PAD = 16 -- the button art's edges: text stays inside them

local FONTS = {
    { normal = "GameFontNormal", highlight = "GameFontHighlight", disabled = "GameFontDisable" },
    { normal = "GameFontNormalSmall", highlight = "GameFontHighlightSmall", disabled = "GameFontDisableSmall" },
}

local function setFonts(b, set)
    for _, part in ipairs({ { "SetNormalFontObject", set.normal }, { "SetHighlightFontObject", set.highlight },
        { "SetDisabledFontObject", set.disabled } }) do
        local font = rawget(_G, part[2])
        if font and type(b[part[1]]) == "function" then pcall(b[part[1]], b, font) end
    end
end

local function textWidth(fs)
    local measure = fs.GetUnboundedStringWidth or fs.GetStringWidth
    local ok, w = pcall(measure, fs)
    return ok and tonumber(w) or nil
end

--- Pure: which font a label of `normalWidth` takes on a button of `width`: 1 (normal) when it
--- fits, else 2 (small); the second return is true when even the small one doesn't (the
--- label is then cut with "..." at the button's edge). `smallWidth` is its width in the small font.
function Widgets.FitFont(width, normalWidth, smallWidth)
    local room = width - Widgets.PAD
    if not normalWidth or normalWidth <= room then return 1, false end
    return 2, (smallWidth or normalWidth) > room
end

--- Keep a button's label inside its border (2026-11-07: "button text commonly runs over the
--- button borders"): the normal font when it fits, the small one when it doesn't, and past that
--- the label stops at the edge. Runs after every SetText on our own buttons.
function Widgets.Fit(b)
    local fs = type(b.GetFontString) == "function" and b:GetFontString() or nil
    local width = type(b.GetWidth) == "function" and tonumber((b:GetWidth())) or nil
    if not fs or not width or width <= 0 then return end
    setFonts(b, FONTS[1])
    if type(fs.SetWidth) == "function" then pcall(fs.SetWidth, fs, 0) end
    local normal = textWidth(fs)
    local font = Widgets.FitFont(width, normal)
    if font == 1 then return end
    setFonts(b, FONTS[2])
    local _, cut = Widgets.FitFont(width, normal, textWidth(fs))
    if cut and type(fs.SetWidth) == "function" then pcall(fs.SetWidth, fs, width - Widgets.PAD) end
end

-- Toggled-on look (operator, 2026-11-08: "make sure this button has a highlight when toggled
-- on. same with any other toggled button"): a green fill inside the button's border, under its
-- text, kept in our own table. Made with the button (at login), so nothing is created later.
Widgets.TOGGLED_COLOR = { 0.2, 0.8, 0.35, 0.45 }
local toggles = setmetatable({}, { __mode = "k" }) -- button -> { glow = texture, on = bool }

function Widgets.Button(parent, text, width, onClick, name)
    local b = CreateFrame("Button", name, parent, "UIPanelButtonTemplate")
    b:SetSize(width, 22)
    b:SetText(text)
    b:SetScript("OnClick", onClick)
    if type(hooksecurefunc) == "function" then
        pcall(hooksecurefunc, b, "SetText", function(self) Widgets.Fit(self) end)
    end
    Widgets.Fit(b)
    local glow = b:CreateTexture(nil, "BORDER")
    glow:SetPoint("TOPLEFT", b, "TOPLEFT", 3, -3)
    glow:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -3, 3)
    local c = Widgets.TOGGLED_COLOR
    glow:SetColorTexture(c[1], c[2], c[3], c[4])
    glow:Hide()
    toggles[b] = { glow = glow, on = false }
    return b
end

--- Show a toggle button (one of ours, made by Widgets.Button) as on or off.
function Widgets.SetToggled(b, on)
    local t = toggles[b]
    if not t then return end
    t.on = on == true
    if t.on then t.glow:Show() else t.glow:Hide() end
end

--- Is this button shown as toggled on? (specs, /mw report)
function Widgets.IsToggled(b)
    local t = toggles[b]
    return t ~= nil and t.on and t.glow:IsShown() == true
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
