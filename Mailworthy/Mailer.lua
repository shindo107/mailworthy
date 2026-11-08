-- Sending: the scan's mail list goes to the saved bank alt, 12 stacks per mail,
-- after one press of Send; items a binding diverts (Routes) go to that player in
-- their own mails, after the bank alt's. Every recipient is shown in the window. Each mail: clear the send tab, re-check every slot
-- right before attaching it (same item, same count, not locked by the game or by
-- Mailworthy, not bound; anything that changed is skipped), attach with
-- UseContainerItem, zero money and COD (as Blizzard's Send button does), then
-- SendMail. The next mail follows MAIL_SEND_SUCCESS without another press
-- (measured: alpha2 send test). It stops on MAIL_FAILED, a closed mailbox,
-- combat, the Send Mail tab going away, or no answer within 10 s.
local _, ns = ...

local Mailer = {}
ns.Mailer = Mailer

Mailer.PER_MAIL = 12
Mailer.DELAY = 0.5
Mailer.TIMEOUT = 10
Mailer.SUBJECT = "Mailworthy %d/%d"
Mailer.FRIEND_SUBJECT = "Mailworthy %d/%d: %s"
Mailer.FRIEND_BODY = "Your %s, sent by %s with Mailworthy."
Mailer.KEEP_DAYS = 30

local state = { busy = false, run = 0 }
Mailer.state = state
local listeners = {}

local function call(fn, ...)
    if type(fn) ~= "function" then return nil end
    local results = { pcall(fn, ...) }
    if not results[1] then return nil end
    return unpack(results, 2, table.maxn(results))
end

-- Timers belong to one send run: once that run stops (combat, mailbox closed,
-- failure) or a new one starts, its pending timers do nothing.
local function after(delay, fn)
    local myRun = state.run
    local function run()
        if not state.busy or state.run ~= myRun then return end
        local ok, err = pcall(fn)
        if not ok then
            ns.Log.Add("mailer", "error: %s", tostring(err))
            Mailer.Stop("error: " .. tostring(err))
        end
    end
    if C_Timer and type(C_Timer.After) == "function" then C_Timer.After(delay, run) else run() end
end

function Mailer.OnChanged(fn) table.insert(listeners, fn) end

local sentListeners = {}
--- fn(mailsSent) once a send run has mailed everything it planned.
function Mailer.OnSent(fn) table.insert(sentListeners, fn) end
local function notify()
    for _, fn in ipairs(listeners) do pcall(fn) end
end

local function setStatus(text, ...)
    state.status = string.format(text, ...)
    ns.Log.Add("mailer", "%s", state.status)
    notify()
end

function Mailer.Status() return state.status end
function Mailer.Busy() return state.busy end

--- Pure: split the items to mail into mails of PER_MAIL stacks each, per recipient: the
--- bank alt's mails first, then one run per binding (an item's result.to and what) in the
--- order they appear. Returns { { to, what, stacks = { {bag, slot, count, itemID, link,
--- item} ... } }, ... }; `to` is nil for the bank alt's mails when no bank alt is given,
--- `what` ("Enchanting materials") only for a binding's.
function Mailer.Plan(items, bankAlt)
    local groups, order = {}, {}
    for _, item in ipairs(items) do
        local r = item.result or {}
        local key = r.to and (r.to .. "|" .. tostring(r.what)) or ""
        if not groups[key] then
            groups[key] = { to = r.to or bankAlt, what = r.to and r.what or nil, items = {} }
            if key == "" then table.insert(order, 1, key) else order[#order + 1] = key end
        end
        table.insert(groups[key].items, item)
    end
    local mails = {}
    for _, key in ipairs(order) do
        local group, currentMail = groups[key], nil
        for _, item in ipairs(group.items) do
            for _, s in ipairs(item.slots) do
                if not currentMail or #currentMail.stacks >= Mailer.PER_MAIL then
                    currentMail = { to = group.to, what = group.what, stacks = {} }
                    mails[#mails + 1] = currentMail
                end
                currentMail.stacks[#currentMail.stacks + 1] = { bag = s.bag, slot = s.slot, count = s.count,
                    itemID = item.itemID, link = item.link, item = item }
            end
        end
    end
    return mails
end

local function sendTabShown()
    local frame = rawget(_G, "SendMailFrame")
    return type(frame) == "table" and call(frame.IsShown, frame) == true
end

--- Why sending can't start right now, or nil when it can. Every mail needs a recipient
--- that isn't this character: the bank alt for the bank alt's mails, the bound player
--- for a binding's. Without a bank alt (optional since 2026-11-08) only bindings' mails go.
function Mailer.Blocker(bankAlt, mails)
    if state.busy then return "already sending" end
    local me = tostring(ns.PlayerName()):lower()
    local anyToAlt = not mails or #mails == 0
    for _, mail in ipairs(mails or {}) do
        if not mail.what then anyToAlt = true end
        if mail.what and mail.to and tostring(mail.to):lower() == me then
            return "a binding points at this character: remove it"
        end
    end
    if anyToAlt then
        -- A mail for the bank alt with none set (Bags holds that share, so only a stale plan).
        if not bankAlt and mails and #mails > 0 then return "no bank alt set: press Settings" end
        if tostring(bankAlt):lower() == me then return "this character is the bank alt" end
    end
    if InCombatLockdown() then return "not in combat" end
    if not sendTabShown() then return "switch to the Send Mail tab first" end
    if not mails or #mails == 0 then return "nothing to mail" end
    return nil
end

--- Is this bag slot still exactly what the preview showed?
function Mailer.StillThere(stack)
    local info = call(C_Container and C_Container.GetContainerItemInfo, stack.bag, stack.slot)
    if type(info) ~= "table" then return false, "gone" end
    if info.itemID ~= stack.itemID or info.hyperlink ~= stack.link then return false, "a different item" end
    if (tonumber(info.stackCount) or 1) ~= stack.count then return false, "count changed" end
    if info.isLocked then return false, "in use" end
    if info.isBound then return false, "soulbound" end
    if ns.Locks.IsItemLocked(info.itemID) then return false, "locked" end
    return true
end

local function attachedCount()
    local n = 0
    for i = 1, tonumber(ATTACHMENTS_MAX_SEND) or Mailer.PER_MAIL do
        if call(GetSendMailItem, i) then n = n + 1 end
    end
    return n
end

local function record(mail)
    MailworthyDB.mailed = type(MailworthyDB.mailed) == "table" and MailworthyDB.mailed or {}
    local now = call(GetServerTime) or time()
    for _, stack in ipairs(mail.attached or {}) do
        local r = stack.item.result or {}
        MailworthyDB.mailed[stack.itemID] = { route = r.route, listRoute = r.listRoute, reason = r.reason, gain = r.gain, at = now,
            from = ns.PlayerName(), to = mail.to }
    end
end

--- Drop records older than KEEP_DAYS.
function Mailer.Prune(now)
    now = now or call(GetServerTime) or time()
    for itemID, entry in pairs(type(MailworthyDB.mailed) == "table" and MailworthyDB.mailed or {}) do
        if type(entry) ~= "table" or (tonumber(entry.at) or 0) < now - Mailer.KEEP_DAYS * 86400 then
            MailworthyDB.mailed[itemID] = nil
        end
    end
end

local sendNext

local function waitFor(index)
    after(Mailer.TIMEOUT, function()
        if state.busy and state.waiting == index then
            Mailer.Stop(string.format("no answer from the game for mail %d", index))
        end
    end)
end

local function sendMail(index)
    local mail = state.mails[index]
    if not sendTabShown() then return Mailer.Stop("the Send Mail tab closed") end
    local n = attachedCount()
    if n == 0 then
        -- Everything in this mail changed since the preview: skip it.
        ns.Log.Add("mailer", "mail %d: nothing attached, skipped", index)
        return sendNext(index + 1)
    end
    if n ~= #mail.attached then
        pcall(ClearSendMail)
        return Mailer.Stop(string.format("mail %d: %d attached, expected %d; nothing sent", index, n, #mail.attached))
    end
    pcall(SetSendMailCOD, 0)
    pcall(SetSendMailMoney, 0)
    state.waiting = index
    ns.lastCommand = string.format("Mailworthy send %d/%d", index, #state.mails)
    local subject, body = string.format(Mailer.SUBJECT, index, #state.mails), ""
    if mail.what then
        subject = string.format(Mailer.FRIEND_SUBJECT, index, #state.mails, mail.what)
        body = string.format(Mailer.FRIEND_BODY, mail.what:lower(), tostring(ns.PlayerName()))
    end
    mail.subject = subject
    local ok, err = pcall(SendMail, mail.to, subject, body)
    ns.Log.Add("mailer", "SendMail %q to %s with %d stacks: %s", subject, tostring(mail.to), n, ok and "called" or tostring(err))
    if not ok then return Mailer.Stop("SendMail failed: " .. tostring(err)) end
    setStatus("Sending mail %d of %d to %s...", index, #state.mails, tostring(mail.to))
    waitFor(index)
end

sendNext = function(index)
    if not state.busy then return end
    if index > #state.mails then
        state.busy = false
        setStatus("Sent %d mail(s), %d stacks, to %s.", state.sent, state.stacks, Mailer.Recipients(state.mails, true))
        for _, fn in ipairs(sentListeners) do pcall(fn, state.sent) end
        return
    end
    if InCombatLockdown() then return Mailer.Stop("combat") end
    if not sendTabShown() then return Mailer.Stop("the Send Mail tab closed") end
    local mail = state.mails[index]
    pcall(ClearSendMail)
    mail.attached = {}
    for _, stack in ipairs(mail.stacks) do
        local ok, why = Mailer.StillThere(stack)
        if ok then
            local okUse, err = pcall(C_Container.UseContainerItem, stack.bag, stack.slot)
            if okUse then
                mail.attached[#mail.attached + 1] = stack
            else
                ns.Log.Add("mailer", "attach %s failed: %s", tostring(stack.link), tostring(err))
            end
        else
            state.skipped = state.skipped + 1
            ns.Log.Add("mailer", "skipped %s (bag %d slot %d): %s", tostring(stack.link), stack.bag, stack.slot, why)
        end
    end
    after(Mailer.DELAY, function() sendMail(index) end)
end

--- Pure: "Roknua Themicrulah and Bob Surname" (the distinct recipients of `mails`, in order;
--- `sentOnly` counts only mails that went).
function Mailer.Recipients(mails, sentOnly)
    local names, seen = {}, {}
    for _, mail in ipairs(mails or {}) do
        local to = tostring(mail.to)
        if (not sentOnly or mail.attached and mail.sent) and not seen[to:lower()] then
            seen[to:lower()] = true
            names[#names + 1] = to
        end
    end
    if #names == 0 then return "nobody" end
    if #names == 1 then return names[1] end
    return table.concat(names, ", ", 1, #names - 1) .. " and " .. names[#names]
end

--- One press: send every mail in the plan: the bank alt's, then each binding's.
function Mailer.Start(items, bankAlt)
    local mails = Mailer.Plan(items or {}, bankAlt)
    local blocker = Mailer.Blocker(bankAlt, mails)
    if blocker then
        setStatus("Can't send: %s.", blocker)
        return false
    end
    state.run = state.run + 1
    state.busy, state.mails, state.bankAlt = true, mails, bankAlt
    state.sent, state.stacks, state.skipped, state.waiting = 0, 0, 0, nil
    ns.Log.Add("mailer", "start: %d mail(s) to %s", #mails, Mailer.Recipients(mails))
    sendNext(1)
    return true
end

function Mailer.Stop(reason)
    if not state.busy then return end
    -- Give back what this run attached, unless a mail is already on its way.
    if not state.waiting and sendTabShown() then pcall(ClearSendMail) end
    state.busy, state.waiting = false, nil
    setStatus("Stopped after %d of %d mail(s): %s.", state.sent, #(state.mails or {}), tostring(reason))
end

ns.On("MAIL_SEND_SUCCESS", function()
    if not state.busy or not state.waiting then return end
    local index = state.waiting
    local mail = state.mails[index]
    state.waiting = nil
    state.sent = state.sent + 1
    state.stacks = state.stacks + #mail.attached
    mail.sent = true
    record(mail)
    if ns.Ledger then -- the mail log and the balance with a friend (Ledger.lua): exactly what was attached
        local items = {}
        for _, stack in ipairs(mail.attached) do
            items[#items + 1] = { itemID = stack.itemID, link = stack.link, count = stack.count }
        end
        local okLog, err = pcall(ns.Ledger.RecordSent, { to = mail.to, subject = mail.subject, items = items }, "Mailworthy")
        if not okLog then ns.Log.Add("mailer", "ledger error: %s", tostring(err)) end
    end
    ns.Log.Add("mailer", "MAIL_SEND_SUCCESS for mail %d", index)
    notify()
    after(Mailer.DELAY, function() sendNext(index + 1) end)
end)
ns.On("MAIL_FAILED", function()
    if state.busy then
        pcall(ClearSendMail)
        Mailer.Stop("the game refused the mail (MAIL_FAILED)")
    end
end)
ns.On("UI_ERROR_MESSAGE", function(_, message)
    if state.busy then ns.Log.Add("mailer", "UI error: %s", tostring(message)) end
end)
ns.On("MAIL_CLOSED", function() Mailer.Stop("the mailbox closed") end)
ns.On("PLAYER_REGEN_DISABLED", function() Mailer.Stop("combat") end)
ns.On("PLAYER_LOGIN", function() Mailer.Prune() end)
ns.On("MAIL_SHOW", function()
    if not state.busy then state.status = nil end
end)
