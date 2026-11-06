# Mailworthy

A WoW Forever addon. Open a mailbox, press the **Mailworthy** button, and
every bag item worth more on the auction house (after fees) or disenchanted
than at the vendor goes to your bank alt. The rest stays in your bags to vendor.

- **Prices** come from Auctionator (optional, recommended). **Disenchant values** of
  green, blue and purple gear come from Siz DisenchantValue (optional; learned from your
  own disenchants) or from the era disenchant tables priced with Auctionator, the same
  number Disenchantry's tooltip shows; either addon installed switches the disenchant
  comparison on. Without Auctionator, Mailworthy mails every unlocked, tradeable white
  (common) item.
- **Preview first:** it shows the recipient, what goes and why, what stays and
  why, and a **Settings** button to fix anything before you press Send.
- **Keyboard/mouse first, controller too:** everything works with keyboard and mouse, and with a gamepad alone.
- **Lock items** you never want mailed: Alt+click (mouse) or L3 in your bags (controller); the lock follows the item.
- **Every bag counts:** backpack, bags 1-4 (profession bags too) and the reagent bag.

## Using it

- **At a mailbox:** click **Mailworthy** under the mail window (controller: Send Mail
  tab with R1, then Triangle). The window shows who gets the mail, what goes and why,
  what stays and why, and the total gain. **Send** mails it all in one press, 12 stacks
  per mail. Pressing an item locks it, so it stays.
- **Lock items** you never want mailed: Alt+click (mouse), L3 in your bags (controller),
  or press the item in the Mailworthy window. Locked items glow blue while a mailbox is
  open (a setting keeps the glow on everywhere); away from one a new lock glows for a
  moment so you see it took. Locks stay wherever the item moves.
- **On your bank alt:** bag slots carry **AH / B / DE / V** tags (list it, bank it for a
  later phase, disenchant it, vendor it now) recomputed with that character's own prices;
  tooltips show today's verdict and why the item was mailed; the Mailworthy button (or
  `/mw summary`) sums it up.
- **Bank alt on a second WoW account** (played on another monitor): mail crosses accounts,
  saved settings don't. On your main, press **Change...** in `/mw` and type the alt's name under
  "Or type a name" (press **Use name** twice: Mailworthy hasn't seen that character). On the alt's account
  install Auctionator and Mailworthy, run an Auctionator scan there, open `/mw` and press
  **This character is my bank alt**: the tags, tooltips and summary come on. Each account
  keeps its own price scans, and the "Mailed for" tooltip line stays on the sending account.
- **No math needed:** prices are the 3-day median of Auctionator's scans (one undercut
  can't flip a verdict), half the deposit counts (the game refunds it on a sale), a flooded
  market is valued at its floor, and the rule knows the realm's launch day: in launch week
  unpriced white trade goods are mailed, before the first raids enchanting materials, herbs
  and elementals are tagged **B** (bank them, they sell higher later), and later the
  minimum gain grows with the gold supply. Details: `docs/PLAN.md` "Decision rule".
- **After sending:** your main's bags tag what's left for the vendor with **V** (grey
  junk too) for the rest of the session. Lock an item to keep it and its V goes.
- **Send a profession's materials to a friend** (`/mw friends`, or the settings' "Send
  materials to friends" button): pick a guild member, party member or one of your own
  characters (online players first; their professions are shown and suggested), then the
  profession. From then on everything that profession uses (dust, essences and shards for
  an enchanter, cloth for a tailor, ...) is mailed to them, every time, for all your
  characters on that realm and faction (or this character only). Each binding has a
  **price cap** (default 5g each): a material the market suddenly wants goes to your bank
  alt instead. The Mailworthy window lists the bindings with **Skip once** (this mailbox
  visit only) and **Remove**. Locked items still stay. If the friend runs Mailworthy too,
  it tells yours which of their characters craft what (addon messages to guild and group;
  `/mw feature comms off` stops them), and the mail goes to **whichever of their characters
  has the profession**: the friend when they do, their crafter alt when they don't, and the
  friend when nothing is known. Never their bank alt. The window names the recipient.
- **Stale auction prices** get a nudge at the mailbox: once your Auctionator prices are over
  3 days old, the Mailworthy button gets a **!** and the window says so (past 7 days
  Mailworthy stops trusting them, and those items stay in your bags). When another Mailworthy user in
  your guild or group has scanned in the last 2 days, it says who, and one chat line tells
  you at the mailbox. Only the day of each player's scan is shared (with the addon messages
  above), never prices, and it never changes what gets mailed. `/mw feature staleNudge off`
  hides it.
- Profession tools (fishing poles, Mining Pick, Blacksmith Hammer, Skinning Knife, ...)
  always stay. Gold is never attached.
- **Your professions' materials stay** (on by default, a setting turns it off): cloth for
  a tailor or first-aider, leather for a leatherworker, metal and stone for a blacksmith
  or engineer (plus parts, explosives and devices), herbs for an alchemist, dust, essences
  and shards for an enchanter, meat and fish for a cook. Gathering professions keep
  nothing: what they gather is what gets sold. Elemental materials are still mailed
  (lock them to keep them).
- **Sell what I gather** (off by default, a setting turns it on): for a gatherer who also
  crafts with the same materials (a miner-blacksmith, an herbalist-alchemist, a
  skinner-leatherworker, a fisher-cook), what the gathering profession brings in is mailed
  to be sold instead of kept for the craft. Mining counts all metal and stone (ore, stone
  and the bars its smelting makes).

```
/mw                   settings: bank alt (pick, type, or "This character is my bank alt"), minimum gain, disenchant, listing length, tags, lock glow, profession materials, friends, minimap button
/mw scan              what Mailworthy would mail and why, with the numbers (sends nothing)
/mw friends           send a profession's materials to a guild member, party member or one of your characters (bindings)
/mw summary           on your bank alt: what to list, disenchant or vendor
/mw locks             this character's locked items
/mw report            a copyable report for bug reports
/mw feature <name> on|off   turn one piece off to isolate a problem (then /reload); /mw feature lists them
/mw help              all commands
```

The design, decision rule and phases are in [docs/PLAN.md](docs/PLAN.md).

## Beta unknowns (check in game)

Everything unverified is wrapped defensively (pcall / nil checks). Results of
each in-game round are in [docs/DISCOVERY-SESSION-2.md](docs/DISCOVERY-SESSION-2.md).

| API / behaviour | What to check | Status |
|---|---|---|
| `## Interface: 16001` | addon loads without "out of date" | confirmed for LedgerLink (build 1.60.1.70205) |
| Auctionator `API.v1` on Forever | S5 | **confirmed** (Auctionator 340; price, age, exactness, disenchant calls) |
| Real AH prices for bag items | `/mw scan` after an Auctionator scan | **seen** (v0.2.0 scan: Copper Ore 1s 74c, Fishing Pole 9s, all age 0); per unit still to confirm against the tooltip; Mailworthy assumes `GetAuctionPriceByItemLink` is per unit and `GetAuctionAgeByItemLink` is in days (Auctionator's convention; S5 saw age 0) |
| Auctionator's history: `Auctionator.Database:GetPriceHistory(key)` rows `{ rawDay, minSeen, maxSeen, available }` and `Auctionator.Utilities.BasicDBKeyFromLink(link)` (not its stable API; guarded, nil = last scan's price only) | `/mw scan` workings show "(3-day median; last scan ...)" and "market: N listed" | open |
| `GetServerTime()` as the launch-day anchor (`Valuation.LAUNCH_EPOCH` = Nov 4, 2026 15:00 PST) | `/mw report` "server: launch day N" | open |
| Trade-goods subclass numbers on Forever (`GetItemInfoInstant`: 7 metal, 9 herb, 10 elemental, 12 enchanting) | a Strange Dust / Bruiseweed stack shows **B** before Dec 9 | open |
| Controller in the settings window away from the mailbox (our own D-pad / Cross / Circle bindings with no Blizzard window focused) | v0.4.0 report | **works**, no blocked actions |
| Tooltip lines through `TooltipDataProcessor.AddTooltipPostCall` (item tooltips, bags and controller) | Phase 4c check | open |
| Disenchantry installed | `C_AddOns.IsAddOnLoaded("Disenchantry")` (in Forever's API docs), else `DisenchantryDB` exists | open (its CurseForge project, 1704637, is back since 2026-10-22; it has no API, so Mailworthy recomputes its "Expected disenchant value") |
| Disenchant tables (`Disenchant.lua`, ported from Disenchantry 1.1.5): a green item's `/mw scan` line "disenchant Xs each (Disenchantry)" equals Disenchantry's tooltip "Expected disenchant value"; materials priced by `Auctionator.API.v1.GetAuctionPriceByItemID` (else the `item:ID` link form); item level from `GetItemInfo`'s 4th return | a green weapon and a green armor piece with both addons installed | open (2026-10-26) |
| Profession materials: `GetProfessionInfo` 7th return is the skill line ID (Tailoring 197, Enchanting 333, ...; gathering for "Sell what I gather": Mining 186, Herbalism 182, Skinning 393, Fishing 356) and trade goods use the modern subclass numbering (cloth 5, leather 6, metal & stone 7, meat 8, herb 9, enchanting 12) | a tailor's cloth or an enchanter's dust in `/mw scan`: "KEEP ... your Tailoring needs it"; the settings window names the profession with its materials | open (2026-10-22; the subclass numbers match the decision rule's, seen for ore / herbs / enchanting materials) |
| Siz DisenchantValue: `DisenchantValueAPI.GetValue(link)` returns copper per item for a green or blue weapon / armor piece (its documented API for addons) | a green item in the bags with Siz DisenchantValue and Auctionator installed: `/mw scan` shows "disenchant Xc each" and a DE verdict matching the item's tooltip | open (2026-10-22; the addon folder name `DisenchantValue` in `## OptionalDeps` is a guess from its zip name and only affects load order) |
| Adding "Lock slot" to the bag item menu (Triangle) | alpha1 + alpha2 | **taints controller input even unclicked**: removed; Alt+click, L3 and the Mailworthy window's rows instead |
| Our own Triangle binding at the mailbox | alpha3/alpha4 self-test | **works**, no blocked actions |
| D-pad to buttons under SendMailFrame (smart navigation) | alpha3/alpha4 self-test | **no**; Mailworthy's own D-pad / Cross / Circle bindings instead, **work** (alpha5) |
| L3 lock in the bags, item locks that follow the item, blue glow | alpha5 self-test | **work** |
| Attach / send / chain mails from addon code | alpha2 self-test | **works**, including from a timer (no button press) |
| `SendMail` to a two-part "First Surname" name | alpha2 send test | **works** |
| Several mails in a row from one press | alpha2 send test | **works** (mail 2 sent after `MAIL_SEND_SUCCESS`, no press) |
| Writing into Forever's controller UI (footer bindings, FrameControlsManager) | alpha1 self-test | **never do it**: tainted gamepad input game-wide (2026-10-13) |
| Postage / AH deposit | alpha1 self-test, LedgerLink S8 | **30c per item**; deposit floor(vendor x 5%) x 1 / 4 / 12 (2h / 8h / 24h) |
| AH cut | an AH sale mail (`GetInboxInvoiceInfo`) | open (5% assumed) |
| Disenchant prices for green items | Auctionator with a green item in bags | open |
| SavedVariables survive `/reload` and relog | self-test marker, v0.4.0 settings | **work** (login, character switch, `/reload`) |
| One-press sending from the Mailworthy window (no money, no COD) | v0.4.0 | **works** (operator, 2026-10-14) |
| Reagent bag (bag 5, `NUM_TOTAL_EQUIPPED_BAG_SLOTS`) scanned, locked (Alt+click, L3) and mailed like bags 0-4 | a white item in the reagent bag: `/mw scan` lists it, Send mails it | open (CurseForge user report, 2026-10-21; source-backed: `Enum.BagIndex.ReagentBag` = 5 in `Blizzard_FrameXMLBase/Constants.lua`) |
| Guild members through `C_Club.GetGuildClubId` / `GetClubMembers` / `GetMemberInfo` (`name`, `presence`, `profession1ID` / `profession2ID` as skill line IDs, as Blizzard's Communities roster reads them on Forever; `GetGuildRosterInfo` fallback), party through `GetNumGroupMembers` / `GetUnitName(unit, true)` / `UnitIsConnected`, the roster asked for with `C_GuildInfo.GuildRoster()` | `/mw friends` lists guild and party members with "online" and their professions; a two-part name without a realm suffix lands in the binding and the mail arrives | open (2026-10-26) |
| Addon messages between Mailworthys: `C_ChatInfo.RegisterAddonMessagePrefix("Mailworthy")`, `SendAddonMessage(prefix, text, "GUILD" / "PARTY" / "RAID")`, `CHAT_MSG_ADDON` (sender possibly "Name-Realm") | two guild members with Mailworthy: `/mw report` shows "mailworthy peer: <name> (<professions>; other characters: ...)" on each, `/mw friends` marks them "Mailworthy", and a binding for a profession only an alt of theirs has says "delivered to their ... character" | open (2026-10-26) |
| "Open the Send Mail tab" on the Inbox: a `SecureActionButtonTemplate` button, `type` "click", `clickbutton` `MailFrameTab2` (Blizzard's `SECURE_ACTIONS.click` in `SecureTemplates.lua`), registered for `AnyUp` / `AnyDown` | open the Mailworthy window on the Inbox with the mouse, press "Open the Send Mail tab": the Send Mail tab opens, the window follows, Send works; `/mw report` shows no blocked actions; then the controller still jumps / targets / uses items | open (2026-11-06) |
| Scan freshness: `Auctionator.API.v1.GetAuctionAgeByItemID(caller, itemID)` (read in Auctionator's source: days since seen, nil past 21 days; else the `item:ID` link form) over 12 everyday trade goods; the scan day sent as `F2\|<server day>` after each hello | a character that hasn't scanned for a week, in a guild with a Mailworthy user who just scanned: `/mw report` "price stamp: <name> scanned 0 day(s) ago", a **!** on the Mailworthy button and the chat line at the mailbox | open (2026-11-06) |
| Lock glow only while a mailbox is open (`MAIL_SHOW` / `MAIL_CLOSED`, `MailFrame:IsShown()`), "always" setting; a new lock flashes 3 s anywhere | lock an item away from a mailbox: a 3 s glow on every stack, then nothing; open a mailbox: glow; close it: gone | open (CurseForge user report + operator, 2026-10-21) |

## Picking up the work

Start with [docs/HANDOFF.md](docs/HANDOFF.md): state, decisions, pitfalls (taint!)
and what's left. Agent rules: [AGENTS.md](AGENTS.md).

## Release

CurseForge setup, assets and the first-release checklist: [docs/CURSEFORGE.md](docs/CURSEFORGE.md).
Icon and screenshot sources are in `media/`; `tools/build-icons.sh` rebuilds them.

## Development

```bash
eval "$(luarocks --lua-version=5.1 path)"
busted --lua=luajit
luacheck .
```

Rules for changes (and for coding agents) are in [AGENTS.md](AGENTS.md).
Releases: push a `v*` tag; the BigWigs packager builds `Mailworthy-<tag>.zip`.
