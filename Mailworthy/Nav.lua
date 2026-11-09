-- Mailworthy's own controller navigation for its window.
--
-- Blizzard's smart navigation didn't reach our window or button in game
-- (alpha3/alpha4), and joining it (FrameControlsManager, footers, menus) taints
-- gamepad input. So while the Mailworthy window is open at a focused mail
-- window, PadKey binds the D-pad, Cross and Circle to Mailworthy (its own
-- override bindings, the mechanism Triangle has used without a single blocked
-- action) and this module moves a highlight Mailworthy draws itself: every
-- visible button in the window is reachable, the first one included.
--
-- The direction search mirrors Blizzard's: the nearest button whose direction
-- is within 45 degrees of the pressed one (SmartNavigation.lua,
-- DEFAULT_DIRECTION_BUFFER), ties broken by the smaller angle.
local _, ns = ...

local Nav = {}
ns.Nav = Nav

Nav.CONE = 45
Nav.DIRECTIONS = { up = { 0, 1 }, down = { 0, -1 }, left = { -1, 0 }, right = { 1, 0 } }

-- Every Mailworthy window registered with Attach; the last one shown is on top
-- and is the one the D-pad navigates. Each has its own highlight.
local roots, highlights, current = {}, {}, nil
-- The window the highlight was last placed for (Nav.Follow) and, per window, the button it was
-- on there, so coming back to a window (the one above it closed) returns to that button.
local lastRoot, remembered = nil, setmetatable({}, { __mode = "k" })
Nav.stats = { follows = 0, returns = 0 } -- /mw report: window changes the highlight followed

--- The window the controller drives: the most recently shown visible one.
function Nav.Root()
    for i = #roots, 1, -1 do
        if roots[i]:IsVisible() then return roots[i] end
    end
    return nil
end

--- Pure: the candidate nearest to `from` in `dir` within the cone, or nil.
--- `from` and each candidate are { x = , y = , ... }.
function Nav.Pick(from, candidates, dir)
    local d = Nav.DIRECTIONS[dir]
    if not d or not from then return nil end
    local best, bestDistance, bestAngle
    for _, c in ipairs(candidates) do
        local vx, vy = c.x - from.x, c.y - from.y
        local distance = math.sqrt(vx * vx + vy * vy)
        if c ~= from and distance > 0 then
            local cos = (vx * d[1] + vy * d[2]) / distance
            local angle = math.deg(math.acos(math.max(-1, math.min(1, cos))))
            if angle <= Nav.CONE + 1e-9 then
                if not best or distance < bestDistance - 0.5
                    or (math.abs(distance - bestDistance) <= 0.5 and angle < bestAngle) then
                    best, bestDistance, bestAngle = c, distance, angle
                end
            end
        end
    end
    return best
end

--- Pure: the top-left candidate (highest row first, then leftmost).
function Nav.TopLeft(candidates)
    local best
    for _, c in ipairs(candidates) do
        if not best or c.y > best.y + 2 or (math.abs(c.y - best.y) <= 2 and c.x < best.x) then best = c end
    end
    return best
end

--- Visible buttons under the window, with their centres.
function Nav.Candidates()
    local list = {}
    local function walk(frame)
        for _, child in ipairs({ frame:GetChildren() }) do
            if child:IsVisible() then
                if child:IsObjectType("Button") then
                    local x, y = child:GetCenter()
                    if x and y then list[#list + 1] = { button = child, x = x, y = y } end
                end
                walk(child)
            end
        end
    end
    local root = Nav.Root()
    if root then walk(root) end
    return list
end

local function entryFor(button, candidates)
    for _, c in ipairs(candidates) do
        if c.button == button then return c end
    end
    return nil
end

local listeners = {}
--- `fn(button)` after the highlight moved (nil: it went away). A window shows what it has for
--- the highlighted button there (the mail window: an item row's tooltip).
function Nav.OnSelect(fn) listeners[#listeners + 1] = fn end

function Nav.Select(button)
    current = button
    for _, h in pairs(highlights) do h:Hide() end
    local root = Nav.Root()
    if button and root then remembered[root] = button end
    local highlight = button and highlights[root]
    if highlight then
        highlight:ClearAllPoints()
        highlight:SetPoint("TOPLEFT", button, "TOPLEFT", -4, 4)
        highlight:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", 4, -4)
        highlight:Show()
    end
    for _, fn in ipairs(listeners) do
        local ok, err = pcall(fn, button)
        if not ok then ns.Log.Add("nav", "select listener error: %s", tostring(err)) end
    end
end

function Nav.Current() return current end

--- Start (or restart) controller navigation at the top-left button.
function Nav.Reset()
    local first = Nav.TopLeft(Nav.Candidates())
    Nav.Select(first and first.button or nil)
end

function Nav.Move(dir)
    local candidates = Nav.Candidates()
    local from = current and entryFor(current, candidates)
    if not from then return Nav.Reset() end
    local nextEntry = Nav.Pick(from, candidates, dir)
    if nextEntry then Nav.Select(nextEntry.button) end
end

function Nav.Press()
    if current and current:IsVisible() and entryFor(current, Nav.Candidates()) then
        ns.Log.Add("nav", "Cross on %s", tostring(current:GetName() or "a button"))
        current:Click()
    else
        Nav.Reset()
    end
end

function Nav.Stop()
    Nav.Select(nil)
end

--- After a window changed what it shows (a view switch, rows hidden): while the
--- controller is navigating and its button went away, start again at the top-left (or, when the
--- window it was in closed, on the button the window now on top had: Nav.Resume).
function Nav.Revalidate()
    if current and not (current:IsVisible() and entryFor(current, Nav.Candidates())) then Nav.Resume() end
end

--- Put the highlight back in the window the controller drives: on the button it was on there
--- (still shown), else the top-left one; none when no window shows.
function Nav.Resume()
    local root = Nav.Root()
    lastRoot = root
    if not root then return Nav.Select(nil) end
    local back = remembered[root]
    if back and back:IsVisible() and entryFor(back, Nav.Candidates()) then
        Nav.stats.returns = Nav.stats.returns + 1
        return Nav.Select(back)
    end
    return Nav.Reset()
end

--- Keep the highlight with the window on top (PadKey's watcher, every tick while the controller
--- navigates; `force` when it starts). Another window opened over this one (Cross on Settings...,
--- Friends...): its top-left button. The top one closed by mouse, Escape or Circle: back to the
--- button the window below had. The selected button hidden by a view switch: start again. Before,
--- the highlight stayed on the window below and the first D-pad press only moved it over.
function Nav.Follow(force)
    local root = Nav.Root()
    if force or root ~= lastRoot then
        if root ~= lastRoot and root then Nav.stats.follows = Nav.stats.follows + 1 end
        return Nav.Resume()
    end
    if root and not (current and current:IsVisible()) then return Nav.Resume() end
end

--- Every window registered with Attach (specs: the D-pad reach spec walks each one).
function Nav.Windows()
    local list = {}
    for frame in pairs(highlights) do list[#list + 1] = frame end
    return list
end

--- Close the window the controller is in (Circle).
function Nav.CloseTop()
    local root = Nav.Root()
    if root then root:Hide() end
    return root
end

--- Register a window to navigate; the highlight is ours, a gold frame drawn
--- around the selected button. Call at login (it creates a frame).
function Nav.Attach(frame)
    if highlights[frame] then return end
    roots[#roots + 1] = frame
    frame:HookScript("OnShow", function(self)
        remembered[self] = nil -- a window that opens starts at its top-left button
        for i = #roots, 1, -1 do
            if roots[i] == self then table.remove(roots, i) end
        end
        roots[#roots + 1] = self
    end)
    local highlight = CreateFrame("Frame", (frame:GetName() or "Mailworthy") .. "NavHighlight", frame)
    highlights[frame] = highlight
    highlight:SetFrameLevel(frame:GetFrameLevel() + 20)
    local specs = { { "TOPLEFT", "TOPRIGHT", nil, 2 }, { "BOTTOMLEFT", "BOTTOMRIGHT", nil, 2 },
        { "TOPLEFT", "BOTTOMLEFT", 2, nil }, { "TOPRIGHT", "BOTTOMRIGHT", 2, nil } }
    for _, spec in ipairs(specs) do
        local tex = highlight:CreateTexture(nil, "OVERLAY")
        tex:SetColorTexture(1, 0.82, 0, 1)
        tex:SetPoint(spec[1])
        tex:SetPoint(spec[2])
        if spec[3] then tex:SetWidth(spec[3]) end
        if spec[4] then tex:SetHeight(spec[4]) end
    end
    highlight:Hide()
end
