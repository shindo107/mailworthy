local loadAddon = require("spec.support.load_addon")

local function printed(text)
    for _, line in ipairs(WowStub.printed) do
        if line:find(text, 1, true) then return true end
    end
    return false
end

describe("core", function()
    it("creates both saved tables", function()
        loadAddon()
        assert.is_table(MailworthyDB)
        assert.is_table(MailworthyCharDB)
        assert.same({}, MailworthyDB.blocked)
    end)

    it("keeps saved tables that already exist", function()
        local ns = loadAddon()
        MailworthyDB.bankAlt = "Keep Me"
        ns.Init()
        assert.equal("Keep Me", MailworthyDB.bankAlt)
    end)

    it("registers /mw and /mailworthy: alone it opens settings, /mw help prints help", function()
        local ns = loadAddon()
        assert.equal("/mw", SLASH_MAILWORTHY1)
        assert.equal("/mailworthy", SLASH_MAILWORTHY2)
        SlashCmdList.MAILWORTHY("")
        assert.is_true(ns.SettingsUI.Frame():IsShown())
        SlashCmdList.MAILWORTHY("help")
        assert.is_true(printed("commands (/mw or /mailworthy)"))
    end)

    it("never moves keyboard focus (gamepad crash in LedgerLink)", function()
        loadAddon()
        SlashCmdList.MAILWORTHY("")
        assert.equal(0, WowStub.focusCalls)
    end)

    -- rl-companion reads the log from the SavedVariables file: lines from 01:32 and 15:25 could
    -- be one day or two (2026-11-08), so each line carries its date now.
    it("dates every log line and keeps the newest MAX lines", function()
        local ns = loadAddon()
        ns.Log.Add("test", "first %d", 1)
        assert.truthy(ns.Log.Lines()[1]:match("^%d%d%-%d%d %d%d:%d%d:%d%d .- %[test%] first 1$"), ns.Log.Lines()[1])
        for i = 2, ns.Log.MAX + ns.Log.SLACK do ns.Log.Add("test", "line %d", i) end
        assert.equal(ns.Log.MAX + ns.Log.SLACK, #MailworthyDB.log, "trimmed in one go, not one shift per line")
        ns.Log.Add("test", "one more")
        assert.equal(ns.Log.MAX, #MailworthyDB.log)
        assert.truthy(MailworthyDB.log[ns.Log.MAX]:find("one more", 1, true), "newest last")
        assert.truthy(MailworthyDB.log[1]:find("line " .. (ns.Log.SLACK + 2), 1, true), "oldest went")
        ns.Log.Add("test", "again")
        assert.equal(ns.Log.MAX, #ns.Log.Lines(), "what /mw report prints stays at MAX")
    end)
end)
