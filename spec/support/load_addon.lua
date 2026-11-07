-- Load the addon the way the client does: every file listed in the .toc,
-- in order, each called with (addonName, namespace).
require("spec.support.wow_stub")

local ROOT = "Mailworthy/"

local function tocFiles()
    local files = {}
    for line in io.lines(ROOT .. "Mailworthy.toc") do
        if line ~= "" and not line:match("^##") then
            files[#files + 1] = (line:gsub("\\", "/"))
        end
    end
    return files
end

--- `saved` (optional): SavedVariables as an older build left them,
--- { db = MailworthyDB, charDB = MailworthyCharDB }, in place before the files load.
return function(saved)
    WowStub.reset()
    if saved then _G.MailworthyDB, _G.MailworthyCharDB = saved.db, saved.charDB end
    local ns = {}
    for _, file in ipairs(tocFiles()) do
        local chunk = assert(loadfile(ROOT .. file))
        chunk("Mailworthy", ns)
    end
    ns.Init()
    return ns
end
