-- Minimap button (keyboard/mouse; the controller can't reach minimap buttons,
-- tested with LedgerLink's): click opens the settings window, drag moves it
-- around the minimap edge (angle saved in MailworthyDB.minimap). Hidden from the
-- settings window; /mw feature minimapButton off removes it. LedgerLink's
-- pattern: a plain child of Minimap, no library, nothing written into Blizzard
-- tables.
local _, ns = ...

local MinimapButton = {}
ns.MinimapButton = MinimapButton

MinimapButton.ICON = "Interface\\AddOns\\Mailworthy\\Textures\\Icon"
MinimapButton.DEFAULT_ANGLE = 200

local button

local function saved()
    MailworthyDB.minimap = type(MailworthyDB.minimap) == "table" and MailworthyDB.minimap or {}
    local s = MailworthyDB.minimap
    if type(s.angle) ~= "number" then s.angle = MinimapButton.DEFAULT_ANGLE end
    return s
end

local function place()
    local angle = math.rad(saved().angle)
    local radius = (Minimap:GetWidth() or 140) / 2 + 10
    button:ClearAllPoints()
    button:SetPoint("CENTER", Minimap, "CENTER", math.cos(angle) * radius, math.sin(angle) * radius)
end

local function followCursor()
    local mx, my = Minimap:GetCenter()
    local cx, cy = GetCursorPosition()
    local scale = UIParent:GetEffectiveScale()
    saved().angle = math.deg(math.atan2(cy / scale - my, cx / scale - mx)) % 360
    place()
end

local function showTooltip(self)
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:AddLine("Mailworthy")
    GameTooltip:AddLine("Click: settings. Drag: move this button.", 1, 1, 1)
    GameTooltip:AddLine("Bank alt: " .. tostring(ns.Config.BankAlt() or "none"), 1, 1, 1)
    local trip = ns.Trip.TooltipText() -- bags nearly full and something would be mailed (Trip.lua)
    if trip then GameTooltip:AddLine(trip, 0.4, 1, 0.4) end
    GameTooltip:Show()
end

function MinimapButton.Create()
    if button or type(rawget(_G, "Minimap")) ~= "table" then return button end
    if not ns.Features.On("minimapButton") then
        ns.Log.Add("minimap", "off (/mw feature minimapButton on, then /reload)")
        return nil
    end
    button = CreateFrame("Button", "MailworthyMinimapButton", UIParent)
    button:SetParent(Minimap)
    button:SetSize(31, 31)
    button:SetFrameStrata("MEDIUM")
    button:SetFrameLevel(8)
    button:RegisterForClicks("AnyUp")
    button:RegisterForDrag("LeftButton")
    button:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
    local background = button:CreateTexture(nil, "BACKGROUND")
    background:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
    background:SetSize(20, 20)
    background:SetPoint("CENTER")
    local icon = button:CreateTexture(nil, "ARTWORK")
    icon:SetTexture(MinimapButton.ICON)
    icon:SetSize(20, 20)
    icon:SetPoint("CENTER")
    local border = button:CreateTexture(nil, "OVERLAY")
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    border:SetSize(53, 53)
    border:SetPoint("TOPLEFT")
    button:SetScript("OnClick", function()
        ns.lastCommand = "minimap button"
        ns.SettingsUI.Toggle()
    end)
    button:SetScript("OnEnter", showTooltip)
    button:SetScript("OnLeave", function() GameTooltip:Hide() end)
    button:SetScript("OnDragStart", function(self)
        GameTooltip:Hide()
        self:SetScript("OnUpdate", followCursor)
    end)
    button:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
    MinimapButton.Refresh()
    ns.Log.Add("minimap", "button created")
    return button
end

--- Show or hide per the saved setting.
function MinimapButton.Refresh()
    if not button then return end
    place()
    if ns.Config.MinimapShown() then button:Show() else button:Hide() end
end

function MinimapButton.Button() return button end

ns.On("PLAYER_LOGIN", function() MinimapButton.Create() end)
