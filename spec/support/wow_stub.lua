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
        attached = {}, cursor = nil, used = {}, sent = {}, postage = 30, money = 0, cod = 0, moneyCalls = {},
        inbox = {}, invoices = {},
        mods = {}, bindings = {}, bindingOwners = {}, activeFrame = nil, now = 1000, gamepadUI = false,
        navButton = nil,
        -- bindings: guild = nil (not in one) or { clubId, members = { { name, level, class, online, professions, ranks } } },
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
function WowStub.containerFrame()
    local f = { Items = {} }
    function f.UpdateItems() end
    function f.CreateFontString() return WowStub.newWidget("FontString") end -- PadKey's L3 hint
    function f.EnumerateValidItems(self)
        local i = 0
        return function()
            i = i + 1
            if self.Items[i] then return i, self.Items[i] end
        end
    end
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
        if key == "SetText" then return function(_, t) self.text = t end end
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
        if key == "GetCenter" then return function() return self.cx or 1, self.cy or 1 end end
        if key == "GetFrameLevel" then return function() return 1 end end
        if key == "IsVisible" then
            return function()
                if not self.shown then return false end
                local p = rawget(self, "parent")
                if type(p) ~= "table" or p == _G.UIParent or type(p.IsVisible) ~= "function" then return true end
                return p:IsVisible()
            end
        end
        if key == "Click" then return function() if self.scripts.OnClick then self.scripts.OnClick(self) end end end
        if key == "CreateFontString" or key == "CreateTexture" then
            return function() return newWidget(key == "CreateTexture" and "Texture" or "FontString") end
        end
        -- Like real frames: unset fields (lowercase, e.g. gamepadFooter) are nil; methods are no-ops.
        if type(key) == "string" and key:match("^%l") then return nil end
        return function() end
    end })
end
WowStub.newWidget = newWidget
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
    return m.name, "Member", 1, m.level, m.class, "Zone", "", "", m.online == true, 0, (m.class or "WARRIOR"):upper()
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
            presence = m.online and 1 or 3, level = m.level, classID = 1,
            profession1ID = m.professions and m.professions[1], profession2ID = m.professions and m.professions[2],
            profession1Rank = m.ranks and m.ranks[1], profession2Rank = m.ranks and m.ranks[2] }
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
    GetContainerItemInfo = function(bag, slot) return at(bag, slot) end,
    GetContainerItemQuestInfo = function(bag, slot)
        local item = at(bag, slot)
        return { isQuestItem = item and item.quest or false }
    end,
    UseContainerItem = function(bag, slot)
        if SendMailFrame:IsShown() then attachItem(at(bag, slot)) else table.insert(s().used, { bag, slot }) end
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
    if item then return "name", item.itemID, 0, item.stackCount, item.quality end
end
_G.GetSendMailPrice = function() return s().postage * math.max(1, #s().attached) end
_G.ClearSendMail = function()
    for _, item in ipairs(s().attached) do item.isLocked = false end
    s().attached = {}
end
_G.SetSendMailMoney = function(c) s().money = c; table.insert(s().moneyCalls, "money " .. tostring(c)) end
_G.SetSendMailCOD = function(c) s().cod = c; table.insert(s().moneyCalls, "cod " .. tostring(c)) end
_G.SendMail = function(name, subject, body)
    table.insert(s().moneyCalls, "send")
    local count = #s().attached
    for _, item in ipairs(s().attached) do
        for _, bag in pairs(s().bags) do
            for slot, x in pairs(bag) do if x == item then bag[slot] = nil end end
        end
    end
    s().attached = {}
    table.insert(s().sent, { name = name, subject = subject, body = body, count = count, money = s().money,
        cod = s().cod })
end
_G.C_Mail = { IsCommandPending = function() return false end }
_G.GetInboxNumItems = function() return #s().inbox, #s().inbox end
_G.GetInboxHeaderInfo = function(i)
    local m = s().inbox[i]
    if m then return nil, nil, m.sender, m.subject, 0, 0, m.daysLeft or 30, m.hasItem or 1 end
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
    GetDeviceMappedState = function() return { labelStyle = "Shapes" } end,
}

WowStub.reset()
return WowStub
