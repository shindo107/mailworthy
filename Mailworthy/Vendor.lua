-- Sell the V items at a vendor. The bank alt view tags what a vendor pays more for with V
-- (BankAlt.Verdict: "not worth it" items and grey junk), and a main gets the same tags after a
-- Send, "so the trip to the vendor is easy". This is the last step of that trip: at a merchant,
-- one button lists the V items in the bags with what the vendor pays, and Sell sells them.
--
-- Safety, in the order a player would worry about it:
--   * nothing is sold without the window: the list first, then Sell;
--   * only V verdicts are listed, valued as the tags are (BankAlt.Settings), so what is sold is
--     what is tagged: never a locked item, a soulbound or quest item, a tool, an item a quest or
--     a profession of this character needs, or one the auction house or disenchanting pays more
--     for (none of those has a V verdict);
--   * at most BATCH (12) stacks a press, the size of the merchant's buyback list, so one press
--     can always be undone at the same merchant; the window says how many are left for the next;
--   * each slot is re-read right before it is sold (same item, same count, not locked by the
--     game); anything that changed is skipped;
--   * selling stops when the merchant closes or combat starts.
--
-- The way in: a "Mailworthy: sell V (n)" button under the merchant window (created at login on
-- UIParent, then parented, like the mail button), or Triangle with a controller while the
-- merchant window has focus (PadKey "merchant" set); /mw vendor too. The window is one of
-- Mailworthy's own (Nav + PadKey "settings" set): every control is a button.
-- Selling is C_Container.UseContainerItem on a bag slot with a merchant open, what a right-click
-- does. Switches: /mw feature vendorButton off, /mw feature padVendor off.
local _, ns = ...

local Vendor = {}
ns.Vendor = Vendor

Vendor.BATCH = 12       -- stacks per press: the merchant's buyback list holds this many
Vendor.INTERVAL = 0.25  -- seconds between two sales
Vendor.ROWS = Vendor.BATCH

local W = ns.Widgets
local WIDTH = 420
local button, frame, sub, listText, sellButton, closeButton, legend
local open = false      -- a merchant window is open (MERCHANT_SHOW .. MERCHANT_CLOSED)
local selling = false
local batch = {}        -- the stacks the window lists: what Sell sells
local status            -- the line under the list after a run

local function money(c) return ns.Valuation.Money(c) end

function Vendor.Frame() return frame end
function Vendor.Button() return button end
function Vendor.Busy() return selling end
--- The stacks the window lists right now (what Sell would sell), for specs.
function Vendor.Batch() return batch end

--- True while a merchant window is open (the event pair, and the frame when the game has one).
function Vendor.AtMerchant()
    if not open then return false end
    local merchant = rawget(_G, "MerchantFrame")
    return type(merchant) ~= "table" or type(merchant.IsShown) ~= "function" or merchant:IsShown() == true
end

--- Every bag stack with a V verdict, in bag order: { bag, slot, itemID, link, count, price }
--- (price = what the vendor pays for the stack). Valued as the bag tags are.
function Vendor.Stacks()
    local stacks = {}
    local result = ns.Bags.Evaluate(ns.BankAlt.Settings())
    for _, list in ipairs({ result.keep, result.mail }) do
        for _, item in ipairs(list) do
            if ns.BankAlt.Verdict(item) == "v" and not item.locked and not item.noValue and (item.vendor or 0) > 0 then
                for _, s in ipairs(item.slots) do
                    stacks[#stacks + 1] = { bag = s.bag, slot = s.slot, itemID = item.itemID, link = item.link,
                        count = s.count, price = item.vendor * s.count }
                end
            end
        end
    end
    table.sort(stacks, function(a, b)
        if a.bag ~= b.bag then return a.bag < b.bag end
        return a.slot < b.slot
    end)
    return stacks
end

--- Pure: the first `n` stacks, their total, and how many are left for the next press.
function Vendor.Take(stacks, n)
    local taken, total = {}, 0
    for i = 1, math.min(#stacks, n or Vendor.BATCH) do
        taken[i] = stacks[i]
        total = total + stacks[i].price
    end
    return taken, total, #stacks - #taken
end

--- Is this stack still what was listed? (the bag slot re-read right before the sale)
function Vendor.StillThere(stack)
    local info = ns.Locks.ItemAt(stack.bag, stack.slot)
    if not info or not info.itemID then return false, "the slot is empty" end
    if info.itemID ~= stack.itemID then return false, "a different item is there now" end
    if (tonumber(info.stackCount) or 1) ~= stack.count then return false, "the stack changed" end
    if info.isLocked then return false, "in use" end
    if info.hasNoValue then return false, "no vendor buys it" end
    if ns.Locks.IsItemLocked(info.itemID) then return false, "locked" end
    return true
end

--- Pure: the line after a run.
function Vendor.StatusText(sold, total, skipped, why)
    local text = string.format("Sold %d stack%s for %s.", sold, sold == 1 and "" or "s", money(total))
    if skipped > 0 then text = text .. string.format(" Skipped %d that changed.", skipped) end
    if why then text = text .. " Stopped: " .. why .. "." end
    if sold > 0 then text = text .. " The merchant's Buyback tab has them if you change your mind." end
    return text
end

--- Sell these stacks, one every INTERVAL seconds. Stops when the merchant closes or combat starts.
function Vendor.Sell(stacks)
    if selling or #stacks == 0 then return false end
    selling = true
    local i, sold, total, skipped = 0, 0, 0, 0
    local function finish(why)
        selling = false
        status = Vendor.StatusText(sold, total, skipped, why)
        ns.Log.Add("vendor", "%s", status)
        ns.Print(status)
        Vendor.Refresh()
    end
    local function step()
        if not Vendor.AtMerchant() then return finish("the merchant closed") end
        if InCombatLockdown() then return finish("combat") end
        i = i + 1
        local stack = stacks[i]
        if not stack then return finish() end
        local ok, why = Vendor.StillThere(stack)
        if ok then
            local okUse, err = pcall(C_Container.UseContainerItem, stack.bag, stack.slot)
            if okUse then
                sold, total = sold + 1, total + stack.price
            else
                skipped = skipped + 1
                ns.Log.Add("vendor", "selling %s failed: %s", tostring(stack.link), tostring(err))
            end
        else
            skipped = skipped + 1
            ns.Log.Add("vendor", "skipped %s (bag %d slot %d): %s", tostring(stack.link), stack.bag, stack.slot, why)
        end
        C_Timer.After(Vendor.INTERVAL, step)
    end
    ns.Log.Add("vendor", "selling %d stack(s)", #stacks)
    step()
    return true
end

--- Pure: one stack's line in the window.
function Vendor.RowText(stack)
    return string.format("%s%s  |cffaaaaaa%s|r", tostring(stack.link), stack.count > 1 and (" x" .. stack.count) or "",
        money(stack.price))
end

--- Pure: the merchant button's text.
function Vendor.ButtonText(n, pad)
    local text = n > 0 and string.format("Mailworthy: sell V (%d)", n) or "Mailworthy: no V items"
    return pad and (text .. " " .. ns.Gamepad.Glyph(ns.Gamepad.FACE_TOP, 14)) or text
end

function Vendor.Create()
    if frame then return frame end
    frame = W.Window("MailworthyVendorFrame", WIDTH, 200)
    frame:SetFrameStrata("FULLSCREEN_DIALOG")
    frame:SetPoint("CENTER")
    local title = W.Label(frame, "GameFontNormalLarge")
    title:SetPoint("TOP", 0, -18)
    title:SetText("Sell to this vendor")
    sub = W.Label(frame, "GameFontHighlightSmall")
    sub:SetPoint("TOPLEFT", 28, -44)
    sub:SetWidth(WIDTH - 56)
    sub:SetJustifyH("LEFT")
    listText = W.Label(frame, "GameFontHighlight")
    listText:SetPoint("TOPLEFT", 28, -78)
    listText:SetWidth(WIDTH - 56)
    listText:SetJustifyH("LEFT")
    sellButton = W.Button(frame, "", 220, function()
        if #batch > 0 and Vendor.Sell(batch) then Vendor.Refresh() end
    end, "MailworthyVendorSell")
    closeButton = W.Button(frame, "Close", 100, function() frame:Hide() end, "MailworthyVendorClose")
    legend = W.Label(frame, "GameFontHighlightSmall")
    legend:SetPoint("BOTTOM", 0, 14)
    ns.Nav.Attach(frame)
    -- The way in at the merchant: created on UIParent, then parented (MailButton's reason).
    local merchant = rawget(_G, "MerchantFrame")
    if type(merchant) == "table" and ns.Features.On("vendorButton") and not InCombatLockdown() then
        button = CreateFrame("Button", "MailworthyVendorButton", UIParent, "UIPanelButtonTemplate")
        button:SetParent(merchant)
        button:SetSize(190, 22)
        -- Under the merchant window on the right: its own tabs hang from the bottom-left corner.
        button:SetPoint("TOPRIGHT", merchant, "BOTTOMRIGHT", -6, -3)
        button:SetScript("OnClick", function() Vendor.Toggle("vendor button") end)
        ns.Log.Add("vendor", "button created under MerchantFrame")
    else
        ns.Log.Add("vendor", "no merchant button (%s)", ns.Features.On("vendorButton") and "no MerchantFrame, or combat"
            or "/mw feature vendorButton on, then /reload")
    end
    ns.Log.Add("ui", "vendor window created")
    return frame
end

function Vendor.Refresh()
    if button then
        local n = Vendor.AtMerchant() and #Vendor.Stacks() or 0
        button:SetText(Vendor.ButtonText(n, ns.MailButton.GamepadUI()))
    end
    if not frame or not frame:IsShown() then return end
    local stacks = (Vendor.AtMerchant() and not selling) and Vendor.Stacks() or (selling and batch or {})
    local total, left
    batch, total, left = Vendor.Take(stacks, Vendor.BATCH)
    local lines = {}
    for i, stack in ipairs(batch) do lines[i] = Vendor.RowText(stack) end
    if #batch == 0 then
        lines[1] = Vendor.AtMerchant() and "|cffaaaaaaNothing in your bags is tagged V.|r"
            or "|cffaaaaaaOpen a merchant window to sell.|r"
    end
    if left > 0 then
        lines[#lines + 1] = string.format("|cffaaaaaa%d more after these: press Sell again (the Buyback tab holds %d).|r",
            left, Vendor.BATCH)
    end
    if status then lines[#lines + 1] = "|cffffd100" .. status .. "|r" end
    sub:SetText("These are tagged V: a vendor pays more than the auction house or disenchanting would bring."
        .. " Lock an item (Alt+click) to keep it off this list.")
    listText:SetText(table.concat(lines, "\n"))
    sellButton:SetText(selling and "Selling..." or #batch > 0
        and string.format("Sell %d for %s", #batch, money(total)) or "Nothing to sell")
    local y = -78 - 16 * #lines - 14
    sellButton:ClearAllPoints()
    sellButton:SetPoint("TOPLEFT", frame, "TOPLEFT", 24, y)
    closeButton:ClearAllPoints()
    closeButton:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -24, y)
    frame:SetHeight(-y + 24 + 40)
    legend:SetText(W.Footer(ns.MailButton.GamepadUI(), false))
    ns.Nav.Revalidate()
end

--- The merchant button, Triangle at the merchant, or /mw vendor: open or close the window.
function Vendor.Toggle(source)
    ns.lastCommand = tostring(source)
    if not frame then Vendor.Create() end
    if frame:IsShown() then
        frame:Hide()
        return
    end
    status = nil
    W.PlaceBeside(frame, rawget(_G, "MerchantFrame"))
    frame:Show()
    frame:Raise()
    Vendor.Refresh()
    ns.Log.Add("ui", "vendor window shown by %s (%d listed)", tostring(source), #batch)
end

ns.On("PLAYER_LOGIN", function() Vendor.Create() end)
ns.On("MERCHANT_SHOW", function()
    open = true
    Vendor.Refresh()
end)
ns.On("MERCHANT_CLOSED", function()
    open = false
    if frame and frame:IsShown() and not selling then frame:Hide() end
    Vendor.Refresh()
end)
ns.On("BAG_UPDATE_DELAYED", function()
    if open and not selling then Vendor.Refresh() end
end)
ns.On("INPUT_DEVICE_INTERFACE_TRANSITION", function() Vendor.Refresh() end)
