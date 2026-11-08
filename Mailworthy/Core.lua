-- Mailworthy: namespace, saved variables, events and slash commands.
-- The design (entry points, decision rule, phases) is in docs/PLAN.md.
local addonName, ns = ...

ns.NAME = addonName
ns.VERSION = "@project-version@" -- the packager substitutes the release tag (also ## Version in the .toc)

function ns.Print(msg)
    print("|cff33ff99Mailworthy|r: " .. tostring(msg))
end

function ns.Init()
    MailworthyDB = type(MailworthyDB) == "table" and MailworthyDB or {}
    MailworthyCharDB = type(MailworthyCharDB) == "table" and MailworthyCharDB or {}
    MailworthyDB.blocked = MailworthyDB.blocked or {}
    MailworthyDB.characters = MailworthyDB.characters or {}
    MailworthyDB.selftest = nil -- discovery builds' self-test data (answers, test results, old log)
    MailworthyDB.log = type(MailworthyDB.log) == "table" and MailworthyDB.log or {}
    MailworthyCharDB.lockedItems = MailworthyCharDB.lockedItems or {} -- itemID -> { link, at }
    MailworthyCharDB.routes = MailworthyCharDB.routes or {}           -- this character's bindings (Routes.lua)
    MailworthyDB.routes = MailworthyDB.routes or {}                   -- realm|faction -> the account's bindings
    MailworthyDB.peers = MailworthyDB.peers or {}                     -- realm|faction -> Mailworthy users heard from
    MailworthyDB.features = MailworthyDB.features or {}
end

-- Kill switches for each piece that touches Blizzard UI, so a problem in game
-- can be isolated with /mw feature <name> off + /reload instead of a new build.
ns.Features = { DEFAULTS = {
    mailButton = true, padTriangle = true, padNav = true, padLock = true, altClickLock = true, slotBorder = true,
    minimapButton = true, bankAltTags = true, tooltipLines = true, comms = true, staleNudge = true,
    tiers = true, tierCheck = true, guildTemplate = true, ledger = true,
} }

function ns.Features.Describe()
    local list = {}
    for key in pairs(ns.Features.DEFAULTS) do list[#list + 1] = key .. "=" .. (ns.Features.On(key) and "on" or "off") end
    table.sort(list)
    return table.concat(list, ", ")
end

function ns.Features.On(name)
    local saved = MailworthyDB and MailworthyDB.features and MailworthyDB.features[name]
    if saved == nil then return ns.Features.DEFAULTS[name] == true end
    return saved
end

local function featureCommand(rest)
    local name, value = rest:match("^(%S+)%s+(%S+)$")
    local known
    for key in pairs(ns.Features.DEFAULTS) do
        if name and key:lower() == name:lower() then known = key end
    end
    if not known or (value ~= "on" and value ~= "off") then
        ns.Print("Usage: /mw feature <name> on|off (then /reload). Now: " .. ns.Features.Describe())
        return
    end
    MailworthyDB.features[known] = value == "on"
    ns.Log.Add("feature", "%s %s", known, value)
    ns.Print(known .. " " .. value .. ". /reload to apply.")
end

-- Event dispatch: modules register handlers with ns.On(event, fn).
local handlers = {}
local events = CreateFrame("Frame")
ns.eventFrame = events

function ns.On(event, fn)
    if not handlers[event] then
        handlers[event] = {}
        pcall(events.RegisterEvent, events, event)
    end
    table.insert(handlers[event], fn)
end

function ns.Fire(event, ...)
    for _, fn in ipairs(handlers[event] or {}) do
        local ok, err = pcall(fn, ...)
        if not ok and ns.Log then ns.Log.Add("error", "%s handler: %s", event, tostring(err)) end
    end
end

events:SetScript("OnEvent", function(_, event, ...) ns.Fire(event, ...) end)

ns.On("ADDON_LOADED", function(name)
    if name == addonName then ns.Init() end
end)

-- First handler for PLAYER_LOGIN (Core loads first): record which pieces are on,
-- so a blocked action in the log can be matched to the switches.
ns.On("PLAYER_LOGIN", function()
    if ns.Log then ns.Log.Add("feature", "at login: %s", ns.Features.Describe()) end
end)

local HELP = {
    "At a mailbox: click the Mailworthy button under the mail window. Controller: Send Mail tab (R1), then Triangle (Y).",
    "Lock an item (it stays locked wherever it moves): Alt+click it, or L3 in your bags (controller).",
    "Locked items glow blue while a mailbox is open (settings: always); a new lock glows a moment anywhere."
        .. " In the Mailworthy window, pressing an item locks or unlocks it.",
    "/mw or /mw settings - bank alt, minimum gain, disenchant, listing length, keep your professions' materials"
        .. " (also: tags, lock glow, minimap button)",
    "/mw friends - send a profession's materials to a guild member, party member or one of your characters"
        .. " (bindings; the Mailworthy window shows them with Skip once)",
    "/mw guild - your guild's template: turn the guild rules on or off; the guild master and officers edit it",
    "/mw locks - list this character's locked items",
    "/mw scan - what Mailworthy would mail and why (sends nothing)",
    "/mw ledger - what other players mailed you beyond what you sent back, and Export log (every mail sent"
        .. " and received)",
    "/mw summary - on your bank alt: what to list, disenchant or vendor",
    "/mw feature <mailButton|padTriangle|padNav|padLock|altClickLock|slotBorder|minimapButton|bankAltTags"
        .. "|tooltipLines|comms|staleNudge|tiers|tierCheck|guildTemplate|ledger> on|off"
        .. " - isolate a problem (then /reload)",
    "/mw report - a copyable report for bug reports",
    "/mw help - this list",
}

local function showHelp()
    ns.Print("v" .. ns.VERSION .. " - commands (/mw or /mailworthy):")
    for _, line in ipairs(HELP) do print("  " .. line) end
end

function ns.HandleSlash(msg)
    ns.lastCommand = "/mw " .. tostring(msg or "")
    local cmd, rest = string.match(string.lower(msg or ""), "^%s*(%S*)%s*(.-)%s*$")
    if cmd == "report" then
        ns.Report.Open()
    elseif cmd == "feature" then
        featureCommand(rest)
    elseif cmd == "locks" then
        ns.Locks.PrintList()
    elseif cmd == "friends" or cmd == "bindings" then
        ns.RoutesUI.Show()
    elseif cmd == "guild" then
        ns.RoutesUI.ShowGuild()
    elseif cmd == "scan" then
        ns.Bags.Scan()
    elseif cmd == "ledger" or cmd == "log" then
        ns.LedgerUI.Show()
    elseif cmd == "summary" then
        ns.BankAlt.ShowWindow()
    elseif cmd == "" or cmd == "settings" then
        ns.SettingsUI.Show()
    else
        showHelp()
    end
end

SLASH_MAILWORTHY1 = "/mw"
SLASH_MAILWORTHY2 = "/mailworthy"
SlashCmdList.MAILWORTHY = function(msg) ns.HandleSlash(msg) end
