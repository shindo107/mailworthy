-- Stubs for the WoW API Mailworthy calls. `WowStub.reset()` restores a default
-- character, bags, mailbox and gamepad UI; tests tweak `WowStub.state` (or the
-- globals) before calling the addon. Timers queue until `WowStub.runTimers()`.
local WowStub = {}
_G.WowStub = WowStub

local printed = {}
WowStub.printed = printed

local function link(id, name) return string.format("|cffffffff|Hitem:%d::::::::8:::::|h[%s]|h|r", id, name) end
WowStub.link = link

--- A bag item: WowStub.item(2770, "Copper Ore", { count = 5, sell = 5, class = 7 })
function WowStub.item(id, name, o)
    o = o or {}
    return {
        itemID = id, hyperlink = link(id, name), stackCount = o.count or 1, quality = o.quality or 1,
        isBound = o.bound or false, hasNoValue = o.noValue or false, isLocked = false,
        sell = o.sell or 1, class = o.class or 7, subclass = o.subclass, quest = o.quest or false, level = o.level,
    }
end

local function defaultState()
    return {
        name = "Rettana Quilwrit", realm = "Classic Beta PvP", faction = "Alliance",
        class = { "Paladin", "PALADIN", 2 }, level = 8, serverTime = 1791900000, inCombat = false,
        professions = { { index = 6, name = "Mining", rank = 12, maxRank = 75, skillLine = 186 } },
        numSlots = { [0] = 20, [1] = 4, [2] = 6, [3] = 0, [4] = 0 },
        bags = { [0] = {}, [1] = {}, [2] = {} },
        attached = {}, cursor = nil, used = {}, sent = {}, sentItems = {}, sounds = {}, postage = 30, money = 0, cod = 0, moneyCalls = {},
        inbox = {}, invoices = {}, takes = {},
        quests = {}, -- the quest log: { { title, header = true?, objectives = { { text, type } } } }
        itemClasses = {}, -- itemID -> "Mage" / "Mage, Warlock": the tooltip's "Classes: ..." line
        conjured = {}, -- itemID -> true: the tooltip's "Conjured Item" line
        uncached = {}, -- itemID -> true: its data hasn't loaded (a name line alone, IsItemDataCachedByID false)
        tooltipReads = 0, -- C_TooltipInfo.GetItemByID calls
        mods = {}, bindings = {}, bindingOwners = {}, activeFrame = nil, now = 1000, gamepadUI = false,
        navButton = nil,
        -- bindings: guild = nil (not in one) or { clubId, name, rank (this character's 0-based rank index, default 3),
        --   members = { { name, level, class, online, professions, ranks, rank (0-based rank index, default 3) } } },
        -- group = nil or { raid, members = { ... } } (party: the others; raid: everyone), addon messages sent / prefixes
        guild = nil, group = nil, addonMessages = {}, prefixes = {}, rosterRequests = 0,
    }
end

local function s() return WowStub.state end

function WowStub.setBag(bag, slot, item) s().bags[bag] = s().bags[bag] or {}; s().bags[bag][slot] = item end

--- Timers queue with their delay; runTimers(upTo) runs, in order, every timer
--- (including ones queued meanwhile) whose own delay is at most `upTo` seconds (default 1),
--- so a 10-second timeout stays pending unless a test asks for it.
WowStub.timers = {}
function WowStub.runTimers(upTo)
    upTo = upTo or 1
    local guard, ran = 0, true
    while ran and guard < 100 do
        ran = false
        for i, t in ipairs(WowStub.timers) do
            if t.delay <= upTo then
                table.remove(WowStub.timers, i)
                guard, ran = guard + 1, true
                t.fn()
                break
            end
        end
    end
end

WowStub.menuModifiers = {}

function WowStub.reset()
    WowStub.state = defaultState()
    for fn, original in pairs(WowStub.originals or {}) do _G[fn] = original end
    for i = #printed, 1, -1 do printed[i] = nil end
    for i = #WowStub.timers, 1, -1 do WowStub.timers[i] = nil end
    WowStub.menuModifiers = {}
    WowStub.focusCalls = 0
    WowStub.managerCalls = {}
    _G.MailworthyDB, _G.MailworthyCharDB = nil, nil
    _G.Auctionator = nil
    _G.DisenchantValueAPI = nil
    _G.SendMailFrame = WowStub.newWidget("Frame", "SendMailFrame")
    _G.InboxFrame = WowStub.newWidget("Frame", "InboxFrame")
    _G.MailFrame = WowStub.newWidget("Frame", "MailFrame")
    _G.MerchantFrame = WowStub.newWidget("Frame", "MerchantFrame")
    -- Blizzard's Send Mail tab: Mailworthy's code must never click it (specs check tabClicks stays 0).
    _G.MailFrameTab2 = WowStub.newWidget("Button", "MailFrameTab2")
    _G.MailFrameTab2.shown = true
    _G.MailFrameTab2.scripts.OnClick = function() WowStub.tabClicks = WowStub.tabClicks + 1 end
    WowStub.tabClicks = 0
    _G.ContainerFrameCombinedBags = WowStub.containerFrame()
    _G.ContainerFrameContainer = { ContainerFrames = { WowStub.containerFrame(), WowStub.containerFrame() } }
end

--- A bag item button like Blizzard's (pooled): GetBagID / GetID, textures may be
--- created on it, but writing any Lua field on it is an error (taint guard).
function WowStub.itemButton(bag, slot)
    local b = { bag = bag, slot = slot, textures = {}, fontStrings = {}, buttonContext = "ButtonContext_ContainerFrameItemButton" }
    function b.GetBagID() return b.bag end
    function b.GetID() return b.slot end
    function b.IsVisible() return b.hidden ~= true end -- rawset(b, "hidden", true): pooled / its bags closed
    function b.CreateTexture()
        local t = WowStub.newWidget("Texture")
        table.insert(b.textures, t)
        return t
    end
    function b.CreateFontString()
        local f = WowStub.newWidget("FontString")
        table.insert(b.fontStrings, f)
        return f
    end
    return setmetatable(b, { __newindex = function(_, k) error("wrote field " .. tostring(k) .. " on a Blizzard item button") end })
end

--- A container frame: UpdateItems (hookable) and EnumerateValidItems over its pooled buttons.
--- EnumerateValidItems is Forever's (Blizzard_UIPanels_Game/Mainline/ContainerFrame.lua,
--- BaseContainerFrameMixin): it runs to GetBagSize() and yields `index, Items[index]` even when
--- that button is nil (the combined bags' size is every bag's slots; Items is only rebuilt when
--- the frame lays itself out). `size` sets the bag size; by default it is #Items.
function WowStub.containerFrame()
    local f = { Items = {} }
    function f.UpdateItems() end
    function f.CreateFontString() return WowStub.newWidget("FontString") end -- PadKey's L3 hint
    function f.GetBagSize(self) return self.size or #self.Items end
    local function iterator(container, index)
        index = index + 1
        if index <= container:GetBagSize() then return index, container.Items[index] end
    end
    function f.EnumerateValidItems(self) return iterator, self, 0 end
    return f
end

_G.unpack = _G.unpack or table.unpack -- luacheck: ignore 143
_G.time = os.time
_G.date = os.date
_G.print = function(...)
    local t = {}
    for i = 1, select("#", ...) do t[i] = tostring(select(i, ...)) end
    printed[#printed + 1] = table.concat(t, " ")
end

-- Widget stubs: any method call is accepted; the ones tests read are recorded.
-- SetFocus is counted so specs can prove the addon never calls it (gamepad crash).
local function newWidget(kind, name)
    local w = { kind = kind, name = name, scripts = {}, hooks = {}, shown = false, events = {}, children = {} }
    local function runHooks(ev)
        if w.scripts[ev] then w.scripts[ev](w) end
        for _, fn in ipairs(w.hooks[ev] or {}) do fn(w) end
    end
    return setmetatable(w, { __index = function(self, key)
        if key == "SetScript" then return function(_, ev, fn) self.scripts[ev] = fn end end
        if key == "GetScript" then return function(_, ev) return self.scripts[ev] end end
        if key == "HookScript" then
            return function(_, ev, fn) self.hooks[ev] = self.hooks[ev] or {}; table.insert(self.hooks[ev], fn) end
        end
        if key == "RegisterEvent" then return function(_, ev) self.events[ev] = true end end
        if key == "UnregisterEvent" then return function(_, ev) self.events[ev] = nil end end
        if key == "SetFocus" then return function() WowStub.focusCalls = WowStub.focusCalls + 1 end end
        if key == "Show" then return function() self.shown = true; runHooks("OnShow") end end
        if key == "Hide" then return function() self.shown = false; runHooks("OnHide") end end
        if key == "IsShown" then return function() return self.shown end end
        if key == "SetAlpha" then return function(_, a) rawset(self, "alpha", a) end end
        if key == "GetAlpha" then return function() return rawget(self, "alpha") or 1 end end
        if key == "SetVertexColor" or key == "SetColorTexture" then
            return function(_, r, g, b) rawset(self, "color", { r, g, b }) end
        end
        if key == "SetOwner" then return function(_, owner) rawset(self, "owner", owner) end end
        if key == "GetOwner" then return function() return rawget(self, "owner") end end
        if key == "SetText" then return function(_, t) self.text = t end end
        if key == "SetPoint" then
            return function(_, ...)
                rawset(self, "point", { ... })
                local points = rawget(self, "points") or {}
                rawset(self, "points", points)
                points[(...)] = { ... } -- one per anchor, as in game
            end
        end
        if key == "SetAllPoints" then
            return function(_, rel)
                rawset(self, "points", { TOPLEFT = { "TOPLEFT", rel, "TOPLEFT" },
                    BOTTOMRIGHT = { "BOTTOMRIGHT", rel, "BOTTOMRIGHT" } })
            end
        end
        if key == "ClearAllPoints" then return function() rawset(self, "point", nil) rawset(self, "points", nil) end end
        if key == "SetSize" then return function(_, width, height) rawset(self, "w", width) rawset(self, "h", height) end end
        if key == "SetWidth" then return function(_, width) rawset(self, "w", width) end end
        if key == "SetHeight" then return function(_, h) rawset(self, "h", h) end end
        -- Sizes and positions only with WowStub.state.layout (the D-pad graph specs): the others
        -- keep the old answers (nil sizes, every button at 1, 1 unless cx / cy are set).
        if key == "GetWidth" or key == "GetHeight" then
            return function()
                if not s().layout then return nil end
                return rawget(self, key == "GetWidth" and "w" or "h") or 0
            end
        end
        if key == "SetAttribute" then
            return function(_, k, v) rawset(self, "attributes", rawget(self, "attributes") or {}); self.attributes[k] = v end
        end
        if key == "GetAttribute" then return function(_, k) return (rawget(self, "attributes") or {})[k] end end
        if key == "GetText" then return function() return self.text end end
        if key == "GetName" then return function() return self.name end end
        if key == "SetParent" then
            return function(_, p)
                local old = rawget(self, "parent")
                if type(old) == "table" and old.children then
                    for i, c in ipairs(old.children) do if c == self then table.remove(old.children, i) break end end
                end
                self.parent = p
                if type(p) == "table" and p.children then table.insert(p.children, self) end
            end
        end
        if key == "GetParent" then return function() return self.parent end end
        if key == "GetChildren" then return function() return unpack(self.children) end end
        if key == "IsObjectType" then return function(_, t) return self.kind == t end end
        if key == "GetCenter" then
            return function()
                if s().layout and not rawget(self, "cx") then
                    local l, b, r, t = WowStub.rect(self)
                    if l then return (l + r) / 2, (b + t) / 2 end
                end
                return self.cx or 1, self.cy or 1
            end
        end
        if key == "GetFrameLevel" then return function() return 1 end end
        if key == "IsVisible" then
            return function()
                if not self.shown then return false end
                local p = rawget(self, "parent")
                if type(p) ~= "table" or p == _G.UIParent or type(p.IsVisible) ~= "function" then return true end
                return p:IsVisible()
            end
        end
        -- A disabled button ignores clicks, as in game.
        if key == "Click" then
            return function() if self.scripts.OnClick and rawget(self, "enabled") ~= false then self.scripts.OnClick(self) end end
        end
        if key == "Disable" then return function() rawset(self, "enabled", false) end end
        if key == "Enable" then return function() rawset(self, "enabled", true) end end
        if key == "IsEnabled" then return function() return rawget(self, "enabled") ~= false end end
        if key == "CreateFontString" or key == "CreateTexture" then
            return function() return newWidget(key == "CreateTexture" and "Texture" or "FontString") end
        end
        -- Like real frames: unset fields (lowercase, e.g. gamepadFooter) are nil; methods are no-ops.
        if type(key) == "string" and key:match("^%l") then return nil end
        return function() end
    end })
end
WowStub.newWidget = newWidget

-- A small anchor solver for the stub's widgets (WowStub.state.layout): each SetPoint pins one
-- edge or centre of the widget to a point of another (its parent by default), sizes come from
-- SetSize / SetWidth / SetHeight. Enough for Nav's direction search over real positions.
-- Returns left, bottom, right, top (y grows upwards, as in game), or nil.
local SCREEN = { 0, 0, 1920, 1080 }
local function pointOf(rect, name)
    local l, b, r, t = rect[1], rect[2], rect[3], rect[4]
    local x = name:find("LEFT") and l or name:find("RIGHT") and r or (l + r) / 2
    local y = name:find("TOP") and t or name:find("BOTTOM") and b or (b + t) / 2
    return x, y
end
function WowStub.rect(w, depth)
    depth = depth or 0
    if w == nil or w == _G.UIParent or depth > 40 then return SCREEN[1], SCREEN[2], SCREEN[3], SCREEN[4] end
    local parent = rawget(w, "parent")
    local width, height = rawget(w, "w") or 0, rawget(w, "h") or 0
    local L, R, CX, B, T, CY
    for name, p in pairs(rawget(w, "points") or {}) do
        local rel, relPoint, x, y = parent, name, 0, 0
        local a, b, c, d = p[2], p[3], p[4], p[5]
        if type(a) == "number" then
            x, y = a, b or 0
        elseif a ~= nil then
            rel = type(a) == "string" and _G[a] or a
            if type(b) == "string" then relPoint, x, y = b, c or 0, d or 0
            elseif type(b) == "number" then x, y = b, c or 0 end
        end
        local rl, rb, rr, rt = WowStub.rect(rel, depth + 1)
        local px, py = pointOf({ rl, rb, rr, rt }, relPoint)
        px, py = px + x, py + y
        if name:find("LEFT") then L = px elseif name:find("RIGHT") then R = px else CX = px end
        if name:find("TOP") then T = py elseif name:find("BOTTOM") then B = py else CY = py end
    end
    if not (L or R or CX) or not (T or B or CY) then
        local pl, pb, pr, pt = WowStub.rect(parent, depth + 1)
        CX, CY = CX or (pl + pr) / 2, CY or (pb + pt) / 2
    end
    if L and R then -- luacheck: ignore 542
    elseif L then R = L + width
    elseif R then L = R - width
    else L, R = CX - width / 2, CX + width / 2 end
    if B and T then -- luacheck: ignore 542
    elseif T then B = T - height
    elseif B then T = B + height
    else B, T = CY - height / 2, CY + height / 2 end
    return L, B, R, T
end
WowStub.frames = {}
_G.CreateFrame = function(kind, name, parent, template)
    local w = newWidget(kind, name)
    w.template = template
    w.parent = parent
    if type(parent) == "table" and parent.children then table.insert(parent.children, w) end
    if kind == "Frame" or kind == "Button" or kind == "EditBox" or kind == "ScrollFrame" then w.shown = true end
    if name then WowStub.frames[name] = w; _G[name] = w end
    return w
end
_G.UIParent = newWidget("Frame", "UIParent")
_G.UIParent.shown = true
_G.UISpecialFrames = {}
_G.ChatFontNormal = {}
_G.SlashCmdList = {}
_G.NUM_BAG_SLOTS = 4
_G.NUM_REAGENTBAG_SLOTS = 1
_G.NUM_TOTAL_EQUIPPED_BAG_SLOTS = 5 -- bags 0-4 + the reagent bag (Enum.BagIndex.ReagentBag = 5)
_G.ATTACHMENTS_MAX_SEND = 12

_G.hooksecurefunc = function(t, method, hook)
    if type(t) == "string" then t, method, hook = _G, t, method end -- global form
    local original = t[method]
    t[method] = function(...)
        local results = { original(...) }
        hook(...)
        return unpack(results)
    end
end
_G.C_Timer = { After = function(delay, fn) table.insert(WowStub.timers, { delay = delay, fn = fn }) end }
_G.GetTime = function() return s().now end

-- Modifier keys and modified item clicks
_G.IsAltKeyDown = function() return s().mods.alt == true end
_G.IsShiftKeyDown = function() return s().mods.shift == true end
_G.IsControlKeyDown = function() return s().mods.ctrl == true end
_G.HandleModifiedItemClick = function() return false end
function WowStub.itemLocation(bag, slot)
    return { IsBagAndSlot = function() return bag ~= nil end, GetBagAndSlot = function() return bag, slot end }
end

-- Override bindings: the last one set for a key wins; ClearOverrideBindings drops an owner's.
_G.SetOverrideBindingClick = function(owner, _, key, buttonName)
    s().bindings[key] = "CLICK " .. buttonName .. ":LeftButton"
    s().bindingOwners[key] = owner
end
_G.ClearOverrideBindings = function(owner)
    for key, o in pairs(s().bindingOwners) do
        if o == owner then s().bindings[key] = nil; s().bindingOwners[key] = nil end
    end
end
_G.GetBindingAction = function(key) return s().bindings[key] or "" end

-- Character, party / raid units
local function groupUnit(unit)
    local g = s().group
    if type(unit) ~= "string" or not g then return nil end
    local kind, i = unit:match("^(%a+)(%d+)$")
    if kind == "party" and not g.raid then return g.members[tonumber(i)] end
    if kind == "raid" and g.raid then return g.members[tonumber(i)] end
    return nil
end
_G.GetUnitName = function(unit)
    if unit == nil or unit == "player" then return s().name end
    local m = groupUnit(unit)
    return m and m.name or nil
end
_G.UnitName = function(unit)
    if unit == nil or unit == "player" then return (s().name:match("^(%S+)")) end
    local m = groupUnit(unit)
    return m and (m.name:match("^(%S+)")) or nil
end
_G.GetRealmName = function() return s().realm end
_G.UnitFactionGroup = function() return s().faction end
_G.UnitClass = function(unit)
    if unit == nil or unit == "player" then return unpack(s().class, 1, 3) end
    local m = groupUnit(unit)
    if m then return m.class or "Warrior", (m.class or "WARRIOR"):upper(), 1 end
end
_G.UnitLevel = function(unit)
    if unit == nil or unit == "player" then return s().level end
    local m = groupUnit(unit)
    return m and m.level or nil
end
_G.UnitIsConnected = function(unit)
    local m = groupUnit(unit)
    return m ~= nil and m.online ~= false
end
_G.GetNumGroupMembers = function()
    local g = s().group
    if not g then return 0 end
    return g.raid and #g.members or (#g.members + 1)
end
_G.IsInRaid = function() return s().group ~= nil and s().group.raid == true end

-- Guild: C_Club member info (presence 1 = online, 3 = offline, as Enum.ClubMemberPresence), the
-- GetGuildRosterInfo fallback when the club has no members, roster requests counted.
_G.IsInGuild = function() return s().guild ~= nil end
_G.GetNumGuildMembers = function() return s().guild and #s().guild.members or 0 end
_G.GetGuildRosterInfo = function(i)
    local m = s().guild and s().guild.members[i]
    if not m then return nil end
    return m.name, "Member", m.rank or 3, m.level, m.class, "Zone", "", "", m.online == true, 0, (m.class or "WARRIOR"):upper()
end
-- GetGuildInfo("player"): guild name, rank name, 0-based rank index (TabardFrame.lua reads it so).
_G.GetGuildInfo = function(unit)
    local g = s().guild
    if unit ~= "player" or not g then return nil end
    return g.name or "Stub Guild", "Rank", g.rank or 3
end
_G.C_GuildInfo = { GuildRoster = function() s().rosterRequests = s().rosterRequests + 1 end }
_G.C_Club = {
    GetGuildClubId = function() return s().guild and s().guild.clubId or nil end,
    GetClubMembers = function(clubId)
        local ids = {}
        local g = s().guild
        if g and g.clubId == clubId and g.club ~= false then
            for i in ipairs(g.members) do ids[#ids + 1] = i end
        end
        return ids
    end,
    GetMemberInfo = function(clubId, i)
        local g = s().guild
        local m = g and g.clubId == clubId and g.members[i]
        if not m then return nil end
        return { isSelf = m.name == s().name, memberId = i, name = m.name .. (m.realm and ("-" .. m.realm) or ""),
            presence = m.online and 1 or 3, level = m.level, classID = m.classID,
            profession1ID = m.professions and m.professions[1], profession2ID = m.professions and m.professions[2],
            profession1Rank = m.ranks and m.ranks[1], profession2Rank = m.ranks and m.ranks[2],
            guildRankOrder = (m.rank or 3) + 1 }
    end,
}

-- Addon messages: what Mailworthy sends is recorded; CHAT_MSG_ADDON is fired by the tests.
_G.C_ChatInfo = {
    RegisterAddonMessagePrefix = function(prefix) s().prefixes[prefix] = true; return 0 end,
    SendAddonMessage = function(prefix, message, channel, target)
        table.insert(s().addonMessages, { prefix = prefix, message = message, channel = channel, target = target })
        return 0
    end,
}
_G.GetServerTime = function() return s().serverTime end
_G.InCombatLockdown = function() return s().inCombat end
_G.GetBuildInfo = function() return "1.60.1", "70338", "Oct  9 2026", 16001 end
_G.GetProfessions = function()
    local idx = {}
    for i, p in ipairs(s().professions) do idx[i] = p.index end
    return unpack(idx)
end
_G.GetProfessionInfo = function(index)
    for _, p in ipairs(s().professions) do
        if p.index == index then return p.name, 0, p.rank, p.maxRank, 0, 0, p.skillLine end
    end
end

-- Items and bags
local function byLink(l)
    for _, bag in pairs(s().bags) do
        for _, item in pairs(bag) do
            if item.hyperlink == l or item.itemID == l then return item end
        end
    end
end
_G.GetItemInfo = function(l)
    local item = byLink(l)
    if item then
        return "name", item.hyperlink, item.quality, item.level or 1, 1, "t", "s", 20, "", 0, item.sell, item.class, item.subclass or 0
    end
end
_G.GetItemInfoInstant = function(l)
    local item = byLink(l)
    if item then return item.itemID, "t", "s", "", 0, item.class, item.subclass or 0 end
end
local function at(bag, slot) return s().bags[bag] and s().bags[bag][slot] end
local function attachItem(item)
    if not item or item.isLocked or #s().attached >= 12 then return end
    item.isLocked = true
    table.insert(s().attached, item)
end
_G.C_Container = {
    GetContainerNumSlots = function(bag) return s().numSlots[bag] or 0 end,
    -- numFreeSlots, bagFamily (0 = any item; state.bagFamily[bag] for a profession bag)
    GetContainerNumFreeSlots = function(bag)
        local used = 0
        for _ in pairs(s().bags[bag] or {}) do used = used + 1 end
        return math.max(0, (s().numSlots[bag] or 0) - used), (s().bagFamily or {})[bag] or 0
    end,
    GetContainerItemInfo = function(bag, slot) return at(bag, slot) end,
    GetContainerItemQuestInfo = function(bag, slot)
        local item = at(bag, slot)
        return { isQuestItem = item and item.quest or false }
    end,
    UseContainerItem = function(bag, slot)
        if SendMailFrame:IsShown() then
            attachItem(at(bag, slot))
        elseif _G.MerchantFrame:IsShown() and at(bag, slot) then -- a right-click at a merchant: sold
            local item = at(bag, slot)
            s().sold = s().sold or {}
            table.insert(s().sold, { bag = bag, slot = slot, itemID = item.itemID, count = item.stackCount or 1,
                bound = item.isBound == true, quest = item.quest == true })
            s().bags[bag][slot] = nil
        else
            table.insert(s().used, { bag, slot })
        end
    end,
    PickupContainerItem = function(bag, slot) s().cursor = at(bag, slot) end,
}
_G.CursorHasItem = function() return s().cursor ~= nil end
_G.ClearCursor = function() s().cursor = nil end

-- Mail
_G.ClickSendMailItemButton = function()
    if s().cursor then attachItem(s().cursor); s().cursor = nil end
end
_G.GetSendMailItem = function(i)
    local item = s().attached[i]
    if item then return item.hyperlink:match("%[(.-)%]") or "name", item.itemID, 0, item.stackCount, item.quality end
end
-- What the player has (copper); nil until a spec sets WowStub.state.gold: no postage check.
_G.GetMoney = function() return s().gold end
_G.SOUNDKIT = { IG_MAINMENU_OPTION_CHECKBOX_ON = 856 }
_G.PlaySound = function(kit) table.insert(s().sounds, kit) end
_G.GetSendMailPrice = function() return s().postage * math.max(1, #s().attached) end
_G.ClearSendMail = function()
    for _, item in ipairs(s().attached) do item.isLocked = false end
    s().attached = {}
end
_G.SetSendMailMoney = function(c) s().money = c; table.insert(s().moneyCalls, "money " .. tostring(c)) end
_G.SetSendMailCOD = function(c) s().cod = c; table.insert(s().moneyCalls, "cod " .. tostring(c)) end
_G.SendMail = function(name, subject, body)
    table.insert(s().moneyCalls, "send")
    local count, carried = #s().attached, {}
    for _, item in ipairs(s().attached) do
        -- what this mail carried, as the item was when it left (sentItems[i] goes with sent[i])
        carried[#carried + 1] = { itemID = item.itemID, count = item.stackCount, quality = item.quality,
            bound = item.isBound, quest = item.quest }
        for _, bag in pairs(s().bags) do
            for slot, x in pairs(bag) do if x == item then bag[slot] = nil end end
        end
    end
    s().attached = {}
    table.insert(s().sentItems, carried)
    table.insert(s().sent, { name = name, subject = subject, body = body, count = count, money = s().money,
        cod = s().cod })
end
_G.C_Mail = { IsCommandPending = function() return false end }
-- Item tooltip data (TooltipInfoDocumentation.lua): a name line, a "Conjured Item" line (no line
-- type of its own: None = 0) for a conjured item, and a "Classes: ..." line
-- (TooltipDataLineType.UsageRequirement = 43) for a class-only item.
_G.ITEM_CLASSES_ALLOWED = "Classes: %s"
_G.ITEM_CONJURED = "Conjured Item"
_G.C_TooltipInfo = {
    GetItemByID = function(id)
        s().tooltipReads = s().tooltipReads + 1
        local lines = { { type = 22, leftText = "Item " .. tostring(id) } }
        if s().uncached[id] then return { id = id, lines = lines } end
        if s().conjured[id] then lines[#lines + 1] = { type = 0, leftText = "Conjured Item" } end
        local classes = s().itemClasses[id]
        if classes then lines[#lines + 1] = { type = 43, leftText = "Classes: " .. classes } end
        return { id = id, lines = lines }
    end,
}
-- Item data (ItemDocumentation.lua): IsItemDataCachedByID(itemInfo) -> isCached. The item info
-- calls stay the globals (GetItemInfo, GetItemInfoInstant), as Prices.lua falls back to them.
_G.C_Item = { IsItemDataCachedByID = function(id) return s().uncached[id] ~= true end }
-- The quest log (QuestLogDocumentation.lua): numShownEntries, GetInfo -> { title, questID, isHeader },
-- GetQuestObjectives(questID) -> { { text, type, ... } }.
_G.C_QuestLog = {
    GetNumQuestLogEntries = function() return #s().quests, #s().quests end,
    GetInfo = function(i)
        local q = s().quests[i]
        return q and { title = q.title, questID = 1000 + i, isHeader = q.header == true } or nil
    end,
    GetQuestObjectives = function(id) local q = s().quests[id - 1000] return q and q.objectives or {} end,
}
_G.GetInboxNumItems = function() return #s().inbox, #s().inbox end
-- inbox[i] = { sender, subject, money, cod, daysLeft, returned, canReply (default true), isGM,
--   items = { { itemID, name, count, link } } }; takes are recorded in state.takes (the tests fire
-- MAIL_SUCCESS / MAIL_FAILED, as the server would).
_G.GetInboxHeaderInfo = function(i)
    local m = s().inbox[i]
    if m then
        return nil, nil, m.sender, m.subject, m.money or 0, m.cod or 0, m.daysLeft or 30,
            m.items and #m.items or m.hasItem or 1, false, m.returned == true, false, m.canReply ~= false, m.isGM == true
    end
end
_G.GetInboxItem = function(i, a)
    local it = s().inbox[i] and s().inbox[i].items and s().inbox[i].items[a]
    if it then return it.name, it.itemID, 0, it.count or 1, it.quality or 1, true end
end
_G.GetInboxItemLink = function(i, a)
    local it = s().inbox[i] and s().inbox[i].items and s().inbox[i].items[a]
    return it and (it.link or link(it.itemID, it.name)) or nil
end
_G.TakeInboxItem = function(i, a) table.insert(s().takes, { "item", i, a }) end
_G.TakeInboxMoney = function(i) table.insert(s().takes, { "money", i }) end
_G.AutoLootMailItem = function(i) table.insert(s().takes, { "all", i }) end
_G.GetSendMailItemLink = function(i) local item = s().attached[i]; return item and item.hyperlink end
_G.GetSendMailMoney = function() return s().money end
_G.GetSendMailCOD = function() return s().cod end
-- Mail functions the addon hooks (hooksecurefunc): put back at every reset, so one spec's
-- hooks never wrap the next spec's calls.
WowStub.originals = {}
for _, fn in ipairs({ "SendMail", "TakeInboxItem", "TakeInboxMoney", "AutoLootMailItem" }) do
    WowStub.originals[fn] = _G[fn]
end
_G.GetInboxInvoiceInfo = function(i)
    local v = s().invoices[i]
    if v then return v.type, v.item, v.player, v.bid, v.buyout, v.deposit, v.cut, 0, 0, 0, v.count end
end

-- Menu + gamepad UI
_G.Menu = { ModifyMenu = function(tag, fn) WowStub.menuModifiers[tag] = fn end }

--- A footer like Blizzard's PromptedBindingFooter, recording what's added.
function WowStub.footer()
    local f = { bindings = {}, calls = {}, finalized = 0, isShown = false }
    local function rec(name) return function(_, ...) table.insert(f.calls, name) return ... end end
    f.AddStandardSelectPrompt = rec("select")
    f.AddStandardBackPrompt = rec("back")
    f.AddStandardFrameControlManagerBindings = rec("frameControls")
    f.AddPromptedBinding = function(self, b) table.insert(self.bindings, b); table.insert(self.calls, "binding") end
    f.Finalize = function(self) self.finalized = self.finalized + 1; table.insert(self.calls, "finalize") end
    f.ShowAndActivateBindings = function(self) self.isShown = true end
    f.HideAndDeactivateBindings = function(self) self.isShown = false end
    return f
end
_G.GamepadSharedUtility = {
    CreatePromptedBinding = function(key, fn, label) return { key = key, fn = fn, label = label } end,
    CreatePromptedBindingFooter = function() return WowStub.footer() end,
}
_G.GamepadMode = { FrameControlsManager = {
    FrameShown = function(_, f) table.insert(WowStub.managerCalls, { "shown", f.name }) end,
    FrameHidden = function(_, f) table.insert(WowStub.managerCalls, { "hidden", f.name }) end,
    GetActiveFrame = function() return s().activeFrame end,
} }
_G.InputUtil = {
    IsGamepadUIEnabled = function() return s().gamepadUI end,
    IsMKBUIEnabled = function() return not s().gamepadUI end,
}
_G.GameTooltip = newWidget("GameTooltip", "GameTooltip")
_G.SmartNavigation = { GetCurrentButton = function() return s().navButton end }
_G.C_GamePad = {
    GetActiveDeviceID = function() return 5 end,
    -- state.labelStyle: "Shapes" (PlayStation, the default: the one seen in game), "Letters" /
    -- "Generic" (Xbox), "Reverse" (Switch); false = no mapped device.
    GetDeviceMappedState = function()
        local style = s().labelStyle
        if style == false then return nil end
        return { labelStyle = style or "Shapes" }
    end,
}

WowStub.reset()
return WowStub
