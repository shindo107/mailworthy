-- Diagnostics log for /mw report: hooks, presses, locks, sends and mail events
-- (account-wide, so a report from the bank alt holds the main's session too). Also read
-- outside the game from the SavedVariables file (rl-companion), so each line carries its date.
local _, ns = ...

local Log = {}
ns.Log = Log

Log.MAX = 300
Log.SLACK = 50 -- lines past MAX before the oldest go, in one move (not one shift per line)

--- Pure: keep the newest `max` lines of `log` (in place), once it is `slack` lines over.
function Log.Trim(log, max, slack)
    local extra = #log - max
    if extra <= (slack or 0) then return end
    for i = 1, max do log[i] = log[i + extra] end
    for i = #log, max + 1, -1 do log[i] = nil end
end

function Log.Add(area, fmt, ...)
    local log = MailworthyDB and MailworthyDB.log
    if type(log) ~= "table" then return end
    local ok, msg = pcall(string.format, fmt, ...)
    if not ok then msg = tostring(fmt) end
    log[#log + 1] = string.format("%s %s [%s] %s", date("%m-%d %H:%M:%S"), ns.PlayerName and ns.PlayerName() or "?",
        area, msg)
    Log.Trim(log, Log.MAX, Log.SLACK)
end

--- The log, newest last; at most MAX lines (what is past them waits for the next trim).
function Log.Lines()
    local log = MailworthyDB and type(MailworthyDB.log) == "table" and MailworthyDB.log or {}
    if #log > Log.MAX then Log.Trim(log, Log.MAX, 0) end
    return log
end
