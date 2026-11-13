std = "lua51"
max_line_length = 140
exclude_files = { ".luarocks/**", ".install/**", "lua_modules/**", ".release/**" }

-- Globals the addon defines (SavedVariables + slash command registration).
globals = {
    "MailworthyDB", "MailworthyCharDB",
    -- the read-only API other addons call (Contributions.lua: MailworthyAPI.v1.GetGuildExport)
    "MailworthyAPI",
    "SLASH_MAILWORTHY1", "SLASH_MAILWORTHY2", "SlashCmdList",
}

-- WoW API the addon reads. Keep this list to what the code actually calls.
read_globals = {
    -- Lua extensions the client provides
    "date", "time",
    -- character
    "GetUnitName", "UnitName", "GetRealmName", "UnitFactionGroup", "UnitClass", "UnitLevel", "GetServerTime",
    "GetBuildInfo", "GetProfessions", "GetProfessionInfo", "InCombatLockdown",
    -- bindings: party / raid, guild (C_Club member info, GetGuildRosterInfo fallback), addon messages
    "GetNumGroupMembers", "IsInRaid", "UnitIsConnected", "IsInGuild", "GetNumGuildMembers", "GetGuildRosterInfo",
    "GetGuildInfo", "C_GuildInfo", "C_Club", "C_ChatInfo",
    -- bags and items
    "C_Container", "C_Item", "GetItemInfo", "GetItemInfoInstant", "NUM_BAG_SLOTS", "NUM_REAGENTBAG_SLOTS", "NUM_TOTAL_EQUIPPED_BAG_SLOTS", "CursorHasItem", "ClearCursor",
    -- mail
    "SendMailFrame", "InboxFrame", "SendMail", "ClearSendMail", "ClickSendMailItemButton", "GetSendMailItem",
    "GetSendMailPrice", "ATTACHMENTS_MAX_SEND", "C_Mail", "GetInboxNumItems", "GetInboxHeaderInfo",
    "GetInboxInvoiceInfo", "SetSendMailMoney", "SetSendMailCOD",
    "GetMoney", "PlaySound",
    -- the mail ledger (Ledger.lua): post-hooks on the take calls, the attachments being taken
    "GetInboxItem",
    -- price sources
    "Auctionator",
    -- locks (Alt+click) and the locked-slot border
    "IsAltKeyDown", "IsShiftKeyDown", "IsControlKeyDown", "HandleModifiedItemClick",
    -- Triangle at the mailbox: our own override binding; FrameControlsManager is read only
    "GamepadMode", "SetOverrideBindingClick", "ClearOverrideBindings", "GetBindingAction", "GetTime",
    -- mouse: item tooltips on the lock grid
    "GameTooltip",
    -- menus (Menu is read only for the API report), controller UI, timers
    "Menu", "hooksecurefunc", "CreateAtlasMarkup", "C_Timer",
    -- the tier check reads the player's own profession window (TierCheck.lua; Classic globals via _G)
    "C_TradeSkillUI",
    -- UI
    "CreateFrame", "UIParent", "UISpecialFrames", "ChatFontNormal",
    -- minimap button
    "Minimap", "GetCursorPosition",
    -- bank alt tooltip lines (TooltipDataProcessor is read with rawget)
    "TooltipUtil",
}

files["spec/**"] = {
    std = "+busted",
    globals = { "WowStub", "print", "unpack", "time", "date", "CreateFrame", "InboxFrame", "SendMailFrame",
        "C_Container", "Auctionator", "Menu", "MailFrame", "MerchantFrame",
        "MailworthyMailButton", "GamepadSharedUtility", "GamepadMode", "ContainerFrameCombinedBags", "ContainerFrameContainer",
        "HandleModifiedItemClick", "MailworthyPadWatcher", "DisenchantryDB", "MailworthyInboxButton", "GameTooltip", "SmartNavigation", "Minimap", "MailworthyMinimapButton", "MailworthySettingsFrame", "TooltipDataProcessor", "Enum", "TooltipUtil", "MailworthySummaryFrame", "MailworthyReportFrame",
        "MailworthyFriendsFrame", "C_Club", "C_ChatInfo", "C_GuildInfo",
        "TakeInboxItem", "TakeInboxMoney", "AutoLootMailItem" },
    allow_defined_top = true,
}
