# Mailworthy plan

Mailworthy prices every item in your bags three ways (vendor, auction house
after fees, disenchant). At a mailbox, one button sends everything worth more
than its vendor price to your bank alt. The bank alt lists on the AH and
disenchants. Everything else stays in your bags for the vendor.

Target: WoW Forever (`## Interface: 16001`, classic-style client with modern
`C_` namespaces), played with a gamepad. Learnings carried over from
LedgerLink are listed at the end.

## Entry points

| Where | What it does |
|---|---|
| **Mailbox button (the main entry)** | Opening a mailbox shows a **Mailworthy** button on the mail window. Not set up yet: pressing it opens the settings panel right there. Set up: pressing it opens the preview; pressing **Send** in the preview mails. |
| **Minimap button** | Opens the settings panel anywhere. Keyboard/mouse only (the controller can't reach minimap buttons, U20). Same pattern as LedgerLink's minimap button. |
| Slash commands (`/mailworthy`, `/mw`) | `/mw` alone opens the settings window; `/mw scan`, `/mw help`. Not the main way in. |

## Input: controller and keyboard/mouse (every window)

Every feature works with **both** keyboard + mouse and a gamepad alone.
**Keyboard and mouse are the priority** (operator, 2026-10-13: "if mouse/kb
doesn't work for our addon no one will use it"); the controller is a bonus
that must never break the game.

**Never write into Blizzard's controller UI.** alpha1 added a Triangle binding to
the mail footer and registered its own window with the FrameControlsManager;
that tainted gamepad input game-wide (jumping, targeting and item use were
blocked from login). Details in [FOREVER-UI-NOTES.md](FOREVER-UI-NOTES.md).

What works (from Blizzard's source; alpha3 checks each in game):
- **Plain buttons in the focused panel's active group.** The mail window only
  navigates the active tab's group, so Mailworthy's button and window are
  children of **SendMailFrame** ("Send Mail"), created at login. D-pad + Cross
  reach them; the mouse clicks them.
- **Our own bindings** (override bindings on our own frame, re-applied if
  Blizzard replaces them, cleared on focus loss and combat; proven in game with
  Triangle, zero blocks): Triangle at a focused mail window; while the
  Mailworthy window is open, the D-pad moves Mailworthy's own highlight over
  every button, Cross presses, Circle closes; L3 locks in the bags. Blizzard's
  smart navigation didn't reach our window (alpha3/alpha4) and joining it
  taints, so we don't use it. L2/R2 window cycling into Mailworthy stays out
  (it needs FrameControlsManager registration, which taints; GatherLite reports
  the same).
- **No entries in the gamepad More menu** (taints by design, see FOREVER-UI-NOTES).
- **Button symbols** as texture markup only (`CreateAtlasMarkup`).

Per input:

| Task | Controller | Keyboard / mouse |
|---|---|---|
| Start at the mailbox | Send Mail tab (R1), then **Triangle**, or D-pad to the **Mailworthy** button + Cross | click **Mailworthy** under the mail window (either tab) |
| Preview: send / settings (Circle, X or Escape close it) | D-pad + Cross on its buttons; Triangle closes | click |
| Lock an item | **L3** on the item in your bags, or Cross on its row in the Mailworthy window | **Alt+click** the bag item, or click its row |
| See locked items | blue quest-style glow in your bags | same |
| Settings | the Mailworthy button (when not set up), the preview's Settings button | same, plus `/mw` and the minimap button |

Notes:
- The minimap button is keyboard/mouse only: the controller can't reach
  minimap buttons (LedgerLink's, tested 2026-10-13).
- No action needs a mouse-only gesture: no right-click, drag or hover-only
  information; what a tooltip shows also shows for the highlighted row.
- No action needs typing: names are picked from a list, numbers use steppers.
  Edit boxes exist only as an optional fallback.
- Never move keyboard focus (`SetFocus` crashed the gamepad UI in LedgerLink).
- Every piece that touches Blizzard UI has a kill switch:
  `/mw feature <name> off` + `/reload`.

## Player flow

1. **Open a mailbox.** The **Mailworthy** button is on the mail window, and a
   gamepad button is bound to it while the mailbox is open.
2. **First time:** a bank alt is optional (operator, 2026-11-08): without one the
   window opens anyway, mails only bindings, and lists what would go under Staying
   ("Auction +5s: no bank alt"). To pick one, Settings -> Choose...: the characters
   Mailworthy has seen (or type a name). Leave "Include
   disenchant value" on. Optionally lock items. Close the settings panel
   and you're back at the mailbox.
3. **Preview.** The button opens the preview:
   - **To: <bank alt>** at the top, so a wrong recipient is obvious before
     anything is sent;
   - the **mail list**: each item with its count, reason (AH or disenchant),
     price source and gain over vendoring;
   - the **kept list** (collapsed): items staying in your bags and why (locked,
     soulbound, no price, not worth it);
   - totals: "14 items in 2 mails, about 3g 20s more than vendoring, postage 4s 20c";
   - buttons: **Send**, **Settings** (opens the settings panel on top of the
     preview; the preview recalculates when it closes); the X, Escape and Circle
     close it. On the Inbox tab there is no Send button (a note says to open the
     Send Mail tab) and the window follows the player there (UX pass, 2026-11-06;
     v0.16.1's secure tab button didn't show in game and is gone, 2026-11-06).
     With more than one recipient (bindings), "To:" gets one line per recipient
     (what they get, how many mails; at most three, then "+N more") and the
     Mailing list is grouped by recipient, the bank alt's first.
4. **Send.** Mail 1 of N goes to the bank alt (12 items per mail), and each
   next mail follows on `MAIL_SEND_SUCCESS` without another press.
5. **Vendor the rest.** Whatever stays in your bags is worth more at the vendor
   (or has no price data, or is locked).

Prices come from Auctionator's own scans, or from TradeSkillMaster's AuctionDB when
Auctionator isn't installed (2026-11-08). Mailworthy never scans the AH itself.

## Settings panel

Opened from the mailbox button (when not set up), the preview's **Settings**
button (in the discovery build: the Mailworthy window's **Settings** button), the
minimap button or `/mw`. One window (`SettingsUI.lua`, data in `Config.lua`), every
control a button, so the controller reaches all of it: while it's open (out of
combat), Mailworthy's own bindings drive it anywhere, not just at the mailbox (D-pad
moves the highlight, Cross presses, Circle closes).

**Not registered in Blizzard's options panel** (`Settings.RegisterCanvasLayoutCategory`):
that hands our frame and category tables to a panel the controller UI navigates,
the same pattern that made the More-menu entry taint gamepad input (alpha2).

| Setting | Default | Scope |
|---|---|---|
| Bank alt (mail recipient) | none; the mailbox button opens settings until it's set | account, per realm + faction |
| Keep my professions' materials | **on**: trade goods this character's crafting professions use stay in the bags (cloth for Tailoring / First Aid, leather for Leatherworking, metal & stone for Blacksmithing, those plus parts / explosives / devices for Engineering, herbs for Alchemy, dust / essences / shards for Enchanting, meat and fish for Cooking; `Valuation.PROFESSION_MATS` by skill line ID and trade-goods subclass; gathering professions need nothing; elementals stay mailable). Operator, 2026-10-22 | account |
| Include disenchant value | **on if Siz DisenchantValue (or Disenchantry) is installed**, otherwise off. The default applies only until the player touches the checkbox; after that their choice persists | account |
| Minimum gain over vendor | **1s and 25%** (both must hold; operator 2026-11-07, was 5s); two steppers in the settings window (gold/silver amount, percent), changeable any time, including from the preview's Settings button | account |
| Max price age | 7 days (Auctionator `GetAuctionAgeByItemLink`, confirmed on Forever) | account |
| AH cut | 5% | account |
| Listing length, relist factor | **24h** (duration 3), 1.0 (operator, 2026-10-13). Deposit = floor(vendor value of the stack x 5%) x 1 / 4 / 12 for 2h / 8h / 24h (measured; the game labels durations 1/2/3 "2 / 8 / 24 Hours"), so the default is **x12** | account |
| Postage | **30c per attached item** (measured 2026-10-13) | account |
| Locked items | none | **per character** |
| Minimap button | shown | account |
| Bindings ("send my Enchanting materials to Bob", operator 2026-10-26) | none; `/mw friends` or the settings' "Send materials to friends" button: pick a player (party, guild, own characters, Mailworthy users; online first, their professions suggested from the guild roster's `profession1ID` / `profession2ID`, the known-character record or their Mailworthy's hello), then the profession. Each binding: price cap stepper (5g each by default; at or above it the normal rule applies and the item goes to the bank alt), scope, Remove; the mail goes to the friend, or to the character of theirs that has the profession when their Mailworthy has said so. Or a class instead of a profession (operator, 2026-11-08): "Mage items" takes what only a mage can use and this character can't (the tooltip's "Classes: Mage"), offered first when the player's class is known. The Mailworthy window shows them with Skip once (until the mailbox closes) and Remove | account (per realm + faction) or **per character**; this character's bindings win |

### Bank alt picker (no mistypes)

- The game's mail auto-complete has no "my characters" option (its flags are
  group, guild, friend, BNet, interacted-with, online), so Mailworthy keeps its
  own list.
- **Known characters:** every character that logs in with Mailworthy is
  recorded account-wide (name, realm, faction, class, level, last seen, and,
  for the enchanter check, its Enchanting skill). Only characters on the
  current realm + faction are offered, since mail can't cross either.
- **Saved names:** every name the player confirms is kept in a history list,
  so re-configuring is a pick, not a retype. The player can remove entries.
- **Pick first, type second:** the panel shows known + saved names as large
  buttons (gamepad-cursor friendly). The edit box is the fallback and
  auto-completes (prefix match, case-insensitive) from the same list.
- **Validation:** a typed name that matches no known character asks
  "Mailworthy hasn't seen this character - save anyway?" before it's stored.
- **Forever names have a space** ("First Surname", LedgerLink probe
  2026-10-05). `SendMail` takes the full two-part name (alpha2 send test, U7).
- Mailworthy never calls `SetFocus` (the LedgerLink gamepad crash); the player
  clicks the box.

## Decision rule

For each item, i.e. every stack of one item link in the bags together (count `n`,
vendor `v` per unit, AH price `a` per unit, disenchant value `d` per item), so one
item never splits into "mail 20, keep 3" (`Valuation.lua`):

```
vendor  = v * n
a       = the last scan's price, or the median of the last 3 scanned days' highest minimum
          buyout (Auctionator's history) when that is lower (a spike); -10% when inexact
deposit = floor(v * n * 0.05) * 12      -- 24h listing (x1 / x4 for 2h / 8h)
counted = deposit * relistFactor        -- 0.5: the game refunds it on a sale; a glut counts it in full
ahNet   = a * n * (1 - cut) - counted - postage
deNet   = d * n - postage               -- only when disenchant is enabled and the item can be disenchanted
postage = 30c x stacks                  -- 30c per attached stack, so no batching needed
best    = max(ahNet, deNet)
minGain = setting x (1 + max(0, day - 35) / 180), at most 2x   -- day = launch day (Nov 4, 2026 = 0)
mail    = best - vendor >= max(minGain, vendor * minGainPct)
```

Example: 20 Linen Cloth, vendor 10c, AH 40c each: vendor 2s, deposit floor(200 x 5%)
x 12 = 1s 20c (60c counted), ahNet = 7s 60c - 60c - 30c = 6s 70c, gain 4s 70c: under
the 5s minimum, so it stays. At 60c each it mails (gain 8s 50c).

**Market (research 4.3):** Auctionator's history also gives the units listed and a
trend (3-day median against the previous week). A **glut** (10x our count listed and
the price down 25% or more) is valued at the floor of the market (median of the daily
minimums) with the deposit counted lost.

**No auction price yet (operator, 2026-11-08):** "going to the bank alt on no data is
better than holding on the main". With Auctionator (or TSM) installed but no auction price
for an item, it is mailed to the bank alt to wait there for one (route `noprice`, chip "No
price", reason "no auction price yet"; no gain is shown, none is made up). Grey junk stays
for the vendor; a failed price call stays (never "no price yet"); a price past the age limit
stays; the hard keeps and the profession keep come first; without a bank alt (or with it
skipped) it stays like the rest of the bank alt's share. An item whose disenchant value alone
doesn't pay goes the same way (the auction house may still pay). Unpriced green and blue
gear goes too (`Valuation.UNPRICED_GEAR`). A class binding never takes an unpriced item
(`Routes.PriceKeep`: the cap can't be checked). Replaces the launch-days 0-13 exception for
white trade goods (research 4.2, 2026-10-20).

**Staple trade goods (the flat rules, operator, 2026-11-08):** `Valuation.STAPLES`, one table
of item IDs: cloth, leather and hides, ore, bars and stone, herbs, elemental materials and
enchanting dust, essences and shards (Classic IDs, about 110). With no auction price they are
mailed as a **common item** ("always mail", no invented copper value: a fixed price would be a
guess shown as a gain, and would go stale as the realm's market forms), so the Bank verdict
still applies on top (late-demand goods before the first raids are B). Without any price
source they are mailed too, whatever their quality (essences, shards and elemental essences
are green or blue).

**Recipes (operator, 2026-11-08):** "recipes should go to their respective profession
mappings or default to the bank alt if no AH data is found". A recipe (item class 9) is one
of its profession's things for a binding: its subclass (`Enum.ItemRecipeSubclass`, Forever's
generated API docs) names the profession (`Valuation.RECIPE_PROFESSION`; books and Fishing
have none). A profession binding takes it whatever its price, as its materials, and the price
cap works the same: a recipe priced at or above the cap goes by the normal rule (the bank alt
for the auction house when it pays, else it stays). Without a binding, a recipe follows the
normal rule: priced, the numbers decide; unpriced, the bank alt.

**Bank (research 4.4):** an item that would be mailed for the auction house (or as a
common item) is mailed as **bank** instead, meaning "hold it on the alt": before launch
day 35 (the first raids) when it is enchanting material, a herb past the six starters,
elemental material or Mithril+ metal; until day 60 when it is a glut whose previous-week
median was 1.5x today's floor. Disenchanting is never banked; the gain shown is what
listing it today would bring. The bank alt tags it **B**.

The full research, sources and ranking: [ALGORITHM-RESEARCH.md](ALGORITHM-RESEARCH.md).

"With Auctionator" in this rule and in AGENTS.md Safety means with an auction price source:
Auctionator, else TradeSkillMaster (`Prices.Source`, 2026-11-08). TSM alone follows every
price rule the same way (an item it has no price for goes to the bank alt; a failed call never
counts as "no price yet"); what it can't give is a price age, exactness or history, so with TSM alone
the age limit, the 3-day median, the glut check and the stale nudge don't apply.

**Without Auctionator** (no price source) there's nothing to compare, so the rule
is simple: mail every tradeable **white (common, quality 1)** item that isn't
locked, and the staple trade goods whatever their quality (2026-11-08); grey junk and
everything else uncommon or better stay in the bags (operator, 2026-10-13). The preview says "no price data: mailing common items".

The item stays in your bags (listed in the preview's kept list with the
reason) when any of these hold:
- it's locked (item lock; there's no separate never-mail list, operator 2026-10-13);
- it's soulbound or a quest item (never listed in the window: it can't be mailed),
  or currently locked by the game;
- an active quest's objective names it, quest item or not ("Redridge Goulash needs it":
  Crisp Spider Meat; operator 2026-11-08; `Quests.lua`, by item name);
- it's a profession tool (fishing poles, Mining Pick, Blacksmith Hammer, Skinning
  Knife, Flint and Tinder, Arclight Spanner, enchanting rods): the v0.2.0 scan put
  a Fishing Pole on the mail list;
- it is grey junk with no price, or its price call failed (with Auctionator installed an
  item with no price otherwise goes to the bank alt since 2026-11-08; without Auctionator at
  all, the common-items rule above applies);
- its price is older than the age limit;
- the player is the bank alt, or no bank alt is set, or the bank alt is skipped for this
  mailbox visit (Skip once beside its "To:" line): its share stays, bindings still go.

`hasNoValue` items have `vendor = 0`, so any AH price above the threshold mails them.

**Fees on Forever's AH.** Forever uses the modern auction house
(`C_AuctionHouse`): stackable goods are "commodities" priced per unit, other
items are listed one by one. Measured (LedgerLink S8, 2026-10-13): the deposit is
floor(vendor value of the stack x 5%) x 1 / 4 / 12 for 2h / 8h / 24h, the same for
commodities and items, so Mailworthy computes it from the vendor price; no AH
visit or sampling needed. The AH cut is assumed 5% until a sale mail confirms it
(`GetInboxInvoiceInfo`, U2).

Disenchant eligibility: armor or weapon (class 4 / 2), uncommon or better. A
later option limits it to items whose required Enchanting skill is at or below
the bank alt's recorded skill.

## Price sources (adapters, in priority order)

| Source | Calls | Status |
|---|---|---|
| Auctionator | `Auctionator.API.v1.GetAuctionPriceByItemLink(callerID, link)`, `GetAuctionAgeByItemLink`, `IsAuctionDataExactByItemLink`, `GetDisenchantPriceByItemLink`, `RegisterForDBUpdate` | **confirmed** on Forever (Auctionator 340, 2026-10-13); prices themselves still to see after a scan |
| Siz DisenchantValue | `DisenchantValueAPI.GetValue(linkOrID)` = copper per item (learned from the player's disenchants, else the era tables, priced from Auctionator), nil when not disenchantable / no price; `GetEraValue` | the disenchant price source since 2026-10-22 (Auctionator's own disenchant call is the fallback); its presence switches the disenchant checkbox on. Forever addon, CurseForge slug `siz-disenchantvalue` |
| Disenchantry | none it exports (everything lives in its private namespace, checked in its 1.1.5 source), so `Disenchant.lua` ports its era tables (MIT) and formula: expected value = sum of chance x average quantity x Auctionator material price (`GetAuctionPriceByItemID`, else the link form); nil when a material has no price | **the disenchant source since 2026-10-26** when Siz DisenchantValue isn't there (labelled "Disenchantry" with it installed, "tables" without); switches the disenchant checkbox on by default; CurseForge project 1704637 is back (relation restored) |
| TSM | `TSM_API.ToItemString(link)`, `TSM_API.GetCustomPriceValue("DBMinBuyout" / "DBMarket", itemString)` (unit = the lower of the two, else either), `TSM_API.IsCustomPriceValid(source)` | **the auction source when Auctionator isn't installed** (2026-11-08, CurseForge user Warki7); Auctionator wins when both are (its age, exactness and history feed the rule; TSM's API has none). Realm AuctionDB sources only, never region. Materials for the disenchant tables and leather conversions priced the same way (`Prices.MaterialPrice`). Read in TSM 4.x's `Core/API.lua`; not yet seen in game (README "Beta unknowns"); CurseForge slug `tradeskill-master` |
| Vendor | `C_Item.GetItemInfo` / `GetItemInfo` 11th return | **confirmed** |

Each adapter returns copper per unit or `nil`, plus its source name. The
preview shows which source priced each line.

## Bindings: a profession's materials to a friend (operator, 2026-10-26)

"Send my enchanting mats to a guild member, bind that, and it sends them that way until
cancelled." `Routes.lua` holds the bindings; `Routes.Divert` is pure: after the normal
verdict, a trade good a bound profession uses (`Valuation.PROFESSION_MATS`) becomes `mail`
with route `friend` and `to` = the bound player, whatever its value, unless the verdict is
a hard keep (locked, soulbound, quest, in use, tool, info not loaded) or the smoothed unit
price is at or above the binding's **cap** (then the normal rule applies: the item goes to
the bank alt, and the scan says why). A binding beats "your Tailoring needs it": an
explicit choice over the default keep. The bank alt's tags ignore bindings.

- **Scope:** all the account's characters on the realm + faction (`MailworthyDB.routes`)
  or this character (`MailworthyCharDB.routes`); this character's win; first match wins.
- **Skip once:** a session flag per binding, cleared at `MAIL_CLOSED`; the window row
  says "skipped this time" with Undo. **Remove** in the window and the friends window.
- **Mailer:** `Plan(items, bankAlt)` makes the bank alt's mails first, then one run per
  binding (recipient + materials) with subject "Mailworthy 2/3: Enchanting materials" and a
  one-line body naming the sender; `Blocker` needs a bank alt only for the bank alt's
  mails and refuses a binding that points at this character. Records `to` per item.
- **Who can be bound:** party / raid units, the guild through `C_Club` member info
  (`GetGuildRosterInfo` fallback; the roster is asked for with `C_GuildInfo.GuildRoster()`,
  10 s apart), the account's known characters (with their recorded professions), and
  Mailworthy users heard from. Names lose any "-Realm" suffix.
- **Hellos (`Comms.lua`, `/mw feature comms`):** `H2|<own crafting skill lines>|<Name=ids;...>`
  (the account's other characters on the realm + faction that craft, from the known-character
  list, as many as fit in 255 bytes) to GUILD and PARTY / RAID at login (8 s), on group
  changes (10 s apart), and in answer to `A2` (the friends window asks, 30 s apart). Peers
  are data: names cleaned and length-checked, professions must be known crafting skill
  lines, kept 60 days in `MailworthyDB.peers`.
- **Delivery follows the profession** (operator, 2026-10-26: "get the materials to the friend
  that actually has the profession, not their alt for the AH"): `Routes.Crafter(route, peer)`
  is pure: the bound player when they have the profession or nothing is known, else the
  first of their characters that has it, from the peer's **latest** hello. No toggle; the
  window and the scan name the actual recipient. Bank alts are never a target.
- Two presses with the controller: the friends window is all buttons (Nav / PadKey
  "settings" set).

## Guild template (operator, 2026-11-07)

"The guild master (if using Mailworthy) can set up a template for the rest of the guild members
to use ... send enchanting to this person, send herbs here, etc. ... to help distribute
materials amongst the guild." And: "the template should have a 1 click disable as well."

- **What a rule is:** a binding (above) the guild hands out: one crafting profession's
  materials to one guild member, with a per-unit price cap. One rule per profession (at most
  8). "Herbs" is Alchemy's rule, "cloth" Tailoring's.
- **Who publishes:** the guild master and the rank right below (rank index 0 and 1). The
  friends window shows them Create... / Edit...: the draft (`MailworthyDB.guildDrafts`), Add a
  rule... (guild members only, then the profession), cap steppers, Remove, Publish to guild.
- **Copies, from anyone** (operator, same day: "the guild master and officers have the original
  and can modify it, whoever is online gets the copy, and it can be copied from them by any
  member"). Wire, GUILD only: `T2|<revision>|<author>|<i>/<n>|<skill line>=<Name>:<cap copper>`
  per rule (`0/0` = empty) and `Q2|<revision held>` (ask). The revision is the author's server
  time; the newest wins, never more than 10 minutes ahead. Everyone asks at login with the
  revision they hold; whoever holds a newer copy answers after a short wait (an officer 1 s,
  anyone else 2-6 s) unless another answer as new goes out first, so one answer per ask; whoever
  hears an ask for a newer revision than theirs asks back. The receiver needs the **sender** in
  its roster and the **author** at rank 0 or 1 in it (a name not in the roster yet is re-checked
  at `GUILD_ROSTER_UPDATE`), and leaves out rules for players not in it.
- **A copy can't be signed** (no secret every member could check), so a member running a
  modified addon could pass on a copy in an officer's name. Limits: its rules can only name
  guild members; only players who turned the guild rules on are affected, with a chat line
  naming every rule and every recipient shown before Send; and the named author's Mailworthy,
  hearing a revision it never published (`MailworthyDB.guildPublished`), sends the real one
  again with a newer revision, which replaces every copy (a publisher with no record at all,
  saved data lost, takes its own copy back instead).
- **Opt-in once:** a new template prints one chat line and shows "Guild template from <name>:
  N rules (new)" with **Use guild rules** in the Guild window (`/mw guild`, the settings' Guild
  button; operator 2026-11-07: "seems weird its in the friends tab"); nothing is mailed before
  that press.
  Updates then apply on their own, each with a chat line naming the rules. Kept per account
  per realm + faction + guild (`MailworthyDB.guildTemplates`).
- **One-press off:** "Guild rules: on" in the Guild window and on the Bindings heading of the Mailworthy
  window (shown while a guild rule applies).
- **Personal wins:** `Routes.List` = this character's bindings, the account's, then the guild's
  (`Guild.Rules`) minus rules for a profession bound personally, a profession this character
  has (they keep their materials), or naming this character. Skip once works on guild rules;
  Remove doesn't (turn the rules off instead). `/mw report` lists each left-out rule and why.
- Switch `/mw feature guildTemplate off`.

## Material tiers (operator, 2026-11-06)

"I just got my first aid to 80, which is a threshold to where I shouldn't be using linen
cloth anymore. So ideally I send my linen cloth to the AH or my friend's tailor ... once my
friend goes past the similar threshold on tailoring or first aid (if I have a binding for
them) then I just keep going to the AH. Same methodology for all crafting materials."

- **The threshold** (`TierData.lua`, generated by `tools/tiers/build.py` from
  `tools/tiers/data.py`; research 2026-11-06: all of Forever's recipes for every crafting
  profession, read one by one from zockify's tables of client 1.60.1.70790, Tailoring and
  Blacksmithing also against the client's DB2 via wago.tools, item IDs on Wowhead's Forever
  tooltips): First Aid cloth, the operator's rule, the next bandage's learn skill; everything
  else, the highest grey of the non-holiday recipes using the material directly or through a
  part the profession makes (bolts, cured hides, grinding stones, blasting powders, tubes);
  one-off gear-into-gear chains (goggles) don't count. No row = never outgrown (a grey of 300+).
- **API check** (2026-11-06, Blizzard's Game Data API, namespace `static-forever-us`, build
  1.60.1.70399): every item ID, name, reachable reagent and leather conversion matches. The API
  has no recipe colours, so no threshold is confirmed by it (the in-game tier check is). Fixed
  from it: Coal has no row (it smelts into Azerothium for 300 SAF-T recipes), Small Egg drops to
  Breakfast Omelette (Egg Nog is Winter Veil), First Aid keeps Forever's poultice and Potent
  Anti-Venom reagents for good, and consumables (Accurate Scope, Rough Copper Bomb) count as
  parts in the tier check, as in the table. Left for the in-game check: Light Hide (Dark Leather
  Gloves no longer uses Cured Light Hide), Phoenix Bindings (Bolt of Woolen Cloth, learn 125),
  the Lesser essences (the API has no essence conversions), First Aid's trainer bandages.
- **Beyond the subclasses** (`Tiers.KEEP`, `Valuation.Uses`): each profession keeps the exact
  other materials it levels with (rows below 300; operator: "levelling ones only"), so
  valuables used at 300 still go to the AH. Kept for good: First Aid's 300 reagents, Oily
  Blackmouth, cooking fish filed as food. Alchemy herbs that still make level-60 potions have
  no row (operator: "keep those forever").
- **Leather conversions** (`Tiers.CONVERT`, `WorthConverting`; operator: "if the price is right
  we sell it, otherwise convert"): past its own recipes, Light / Medium / Heavy / Thick Leather
  (and Ruined Leather Scraps) stays while `count x its unit price < the product's unit price`
  (Auctionator, `Prices.MaterialPrice`), and also when a price is missing; a binding keeps
  taking it on the same test.
- **Own professions:** `Valuation.NeededBy(item, professions, tiers)` skips a profession whose
  `rank` is at or past the item's threshold, so the item is valued like anything else (or a
  binding that still needs it takes it); another of this character's professions that still
  needs it keeps it. Kept items say "until skill N"; the workings say "your First Aid (80) is
  past it".
- **Bindings take primary materials only** (operator, 2026-11-07: "only focus on the primary
  materials rather than every possible material the professions can use. they can ask or
  acquire some minor pieces"): `Routes.Matches` takes a trade good of the profession's own
  subclasses (plus Enchanting's gear), never a `Tiers.KEEP` side item (an engineer's Linen
  Cloth). That stays on the normal rule. Own professions still keep their side items.
- **Overlapping bindings** (operator, 2026-11-07: Blacksmithing and Engineering both take metal
  and stone; "Lowest skill first"): `Routes.Before` picks this character's bindings, then the
  account's, then the guild's; within one, the recipient with the lower `route.skill`, a known
  skill before an unknown one, then the list's order. The chosen binding's cap decides.
- **Bindings:** `Routes.Matches(route, item, tiers)` is false for a material the recipient's
  `route.skill` is past, so the next binding that needs it, or the normal rule (the bank alt),
  gets it; the workings say "not to Bob: their First Aid (80) is past it". `Routes.Skill(route)`
  = the highest of: their Mailworthy's `S2` message (for the bound player or the crafter alt
  the mail goes to), this account's own character's last-login rank, and the guild roster's
  `profession1Rank` / `profession2Rank` (primary professions only). Unknown = the binding takes
  everything, as before. A hard keep still wins.
- **Comms:** `S2|<id:rank,...>|<Name=id:rank,...;...>` right after each hello (older
  Mailworthys drop the unknown kind; a peer whose hello was lost is made from it), and a new
  hello at the next mailbox when a skill-up crossed a threshold since the last one
  (`Comms.Steps`). Validated: known crafting skill lines, ranks 0-999, clean names.
- First Aid on Forever also makes healing potions, Anti-Venoms and Tourniquets: it keeps those
  exact items (`PROFESSION_MATS[129].items`, `Valuation.Uses`), each until its recipe goes grey
  (Peacebloom 95, Briarthorn 125, Small Venom Sac 150, Bruiseweed 175, Liferoot 215, Sungrass
  270, Thick Leather 280; Golden Sansam, Large / Huge Venom Sac, Rugged Leather never).
- Switch: `/mw feature tiers off` (own professions and bindings keep every material again).
- **Tier check** (2026-11-06, `TierCheck.lua`; the table is a beta-client snapshot, never checked
  in game): the player's own profession window colours each recipe for the player's skill, which
  is ground truth for the tier rule. On `TRADE_SKILL_SHOW` / `TRADE_SKILL_LIST_UPDATE` /
  `TRADE_SKILL_DATA_SOURCE_CHANGED` (and Classic's `TRADE_SKILL_UPDATE` / `CRAFT_SHOW` /
  `CRAFT_UPDATE`, which Forever doesn't route), half a second after the last one, it reads every
  learned recipe (`C_TradeSkillUI`; linked, guild and NPC windows skipped) and saves
  `MailworthyDB.tierCheck[character key][skill line] = { rank, at, recipes, source, reagents }`,
  `reagents[itemID]` = the hardest non-grey recipe using it `{ recipe, difficulty, via }` or
  `false`. Through parts like the table: a reagent of a recipe whose output (a trade good, by
  `GetItemInfoInstant`) another non-grey recipe uses counts, `via` that part; a leather's own
  up-conversion doesn't. `/mw report` lists, per read, each material the table calls done at that
  rank that a non-grey recipe still uses (`TierCheck.Findings`), except First Aid cloth (its rule
  is the next bandage's learn skill). Those findings are evidence for `tools/tiers/data.py`; a
  human checks them (holiday recipes count here, not in the table). Meanwhile they are kept:
  The comparison is saved with each read too (`findings`: `{ itemID, name, doneAt, recipe,
  difficulty, color, via, text }`, plus `profession`, `skillLine` and the addon `version` whose
  table it used), so a reader of the SavedVariables file outside the game (rl-companion) needs
  neither the table nor `/mw report`; it reaches disk at `/reload` or logout.
  `Bags.Evaluate` gives this character's profession entries `stillUsed` (`TierCheck.Annotate`),
  and `Valuation.NeededBy` keeps an outgrown material listed there ("your Tailoring needs it
  (Soft-soled Linen Boots still yellow)") until a later read says only grey recipes use it.
  Bindings still use the table (the friend's window isn't ours). Read only, no frames. Switch
  `/mw feature tierCheck off`.

## Mailing

- Attach with `C_Container.UseContainerItem(bag, slot)` while the Send Mail tab
  is open (fallback: `C_Container.PickupContainerItem` + `ClickSendMailItemButton(i)`).
  Mailworthy never switches mail tabs itself (`MailFrameTab_OnClick` taints the
  controller UI): sending needs the player on the Send Mail tab.
- Before attaching, re-check that the slot still holds the previewed item
  (same link and count). Anything that changed is skipped, not guessed.
- `SendMail(bankAlt, subject, "")` with subject "Mailworthy 1/3". Never attaches
  money. The recipient is always the saved bank alt shown in the preview.
- Wait for `MAIL_SEND_SUCCESS` (next batch) or `MAIL_FAILED` (stop and say why).
  Stop on `MAIL_CLOSED` or on entering combat.
- Chaining works: mail 2 was attached and sent after `MAIL_SEND_SUCCESS` with
  no new press (alpha2, U8), so one press of **Send** sends every batch.

### Mailbox button

- The **Mailworthy** button sits under the mail window on both tabs (children of
  `InboxFrame` and `SendMailFrame`, created at login). Mouse: click it.
  Controller: on the Send Mail tab, **Triangle** (Mailworthy's own override
  binding, `PadKey.lua`); on the Inbox it shows an "R1 first" hint. Blizzard's
  smart navigation never reached these buttons (alpha3/alpha4), so the
  controller doesn't rely on it.
- On `MAIL_CLOSED`: close the preview.
- Anything the game blocks is recorded (`ADDON_ACTION_FORBIDDEN/BLOCKED`, as
  in LedgerLink) and shown by `/mw report`.
- **ForeverMail compatibility:** ForeverMail replaces the standard mailbox
  window, so a button anchored to `MailFrame` may never show for its users.
  Anchor to whichever mail window is visible (ForeverMail's frame if present,
  found via the probe) and fall back to a free-floating button near the
  mailbox UI.

## Item locks

- A lock belongs to the **item** (its item ID), not a bag slot: it follows the
  item when you move it or sort your bags, and covers every stack of it
  (operator, 2026-10-13). Saved per character; alpha3/alpha4 slot locks are
  converted at login. A non-stackable item locks every copy of it.
- **Keyboard/mouse:** Alt+click a bag item (post-hook of `HandleModifiedItemClick`;
  Alt alone matches none of Blizzard's modified-click cases for bag items).
- **Controller:** **L3** while the bags have focus: Mailworthy's own override
  binding (only while the bags are the focused window; L3 is auto-run in the
  world, untouched), reading the selected slot from
  `SmartNavigation:GetCurrentButton()` (read-only); a hint under the bags says so.
  Also the item's row in the Mailworthy window. Not the gamepad Triangle
  "More" menu: entries there taint controller input (alpha1/alpha2).
- **Visible:** locked items glow blue: Blizzard's quest-item border
  (`UI-Icon-QuestBorder`) desaturated and tinted blue, plus an additive copy.
  Only while a mailbox is open (a CurseForge user, 2026-10-21: the blue hue in
  the bags all the time was noise); the "glow everywhere" setting keeps it on.
  A fresh lock away from a mailbox glows for 3 s on every stack, as feedback
  that Alt+click / L3 worked (operator, 2026-10-21).

## Bank alt view (operator, 2026-10-13)

On the bank alt, Mailworthy shows what each item is for, **recomputed with the
bank alt's own, fresh Auctionator data** ([media/bank-alt-prototype.png](../media/bank-alt-prototype.png)):

- **Tags on bag slots:** a small corner badge, **AH** (Auction, blue), **DE**
  (Disenchant, purple) or **V** (Vendor now, grey/gold), the same colours as the
  preview's chips. Drawn like the lock border: textures and a font string on the
  game's bag buttons, refreshed by the `UpdateItems` post-hooks and on
  `AUCTIONATOR` price updates (`Auctionator.API.v1.RegisterForDBUpdate`).
- **Tooltip lines:** the fresh verdict with today's price and its age, and the
  original reason: "Mailed for: Auction +8s 21c, Oct 13, from <main>". If the
  market moved (e.g. now better at a vendor), both are visible.
- **Summary** (the Mailworthy window when opened on the bank alt): items to list
  with the expected gain, items to disenchant, items now better at a vendor.
- **Data:** when mail is sent, Mailworthy records per item ID the reason, the gain
  at send time, the date and the sender in `MailworthyDB.mailed` (account-wide,
  capped and expired after 30 days). The verdict itself is always recomputed with
  the same decision rule on the bank alt; without Auctionator there it shows
  only the original reason.
- **Where tags show:** on the bank alt by default (any character that is someone's
  configured bank alt); a setting shows them on every character.
- **Taint:** textures / font strings on bag buttons and tooltip lines only (tooltip
  lines are what Auctionator itself adds; no blocks were ever blamed on it).
  Nothing is written into Blizzard tables. Tooltip lines use
  `TooltipDataProcessor.AddTooltipPostCall`, which Forever runs insecurely by design
  (`forceinsecure` behind an attribute delegate, `TooltipDataHandler.lua`).
- **On a main after Send** (operator, 2026-10-14): **V** tags only, on what the window
  kept because a vendor pays more (grey junk too), for the rest of the session, with the
  window's own settings (postage included). Locking an item removes its V at once.
- **As built:** no postage in the bank alt's verdicts (its tags; nothing it sells is mailed);
  V = the vendor wins today; the summary: `/mw summary`, the settings' "Bank alt summary" button
  and the Mailworthy window's Summary... on the bank alt; switches `bankAltTags`, `tooltipLines`;
  setting "Bag tags: every character".
- **The bank alt mails too** (operator, 2026-11-08: "bank alt view should still allow mail
  automation"): the Mailworthy button (Triangle) opens the window there; what it would mail to a
  bank alt stays ("this is your bank alt"), bindings mail, and **Return to sender** sends back
  what other characters mailed it (below). `/mw feature bankAltMail off`: the button opens only
  the summary, as before.

## Return to sender (operator, 2026-11-08)

"A button that just allows me to 'queue up' a return to sender list. it should be a toggle so you
click it on the interface and everything that was mailed to you by someone gets put on the same
list we use for regular mailworthy evaluations to mail back to them. the button should be available
to everyone, not just bank alts. clicking it again returns it to normal mode. make sure this button
has a highlight when toggled on. same with any other toggled button."

- **The toggle** (`Returns.lua`, `MailworthyMailReturn` beside Settings): off by default, for this
  mailbox visit only (off at `MAIL_CLOSED`, like Skip once), lit green while on (`Widgets.SetToggled`,
  now on every toggle in every window). Mouse click or the controller's Cross on it.
- **Who sent what:** the mail ledger's log of takes on this character: per sender and item, what was
  received, less what this character has mailed that player since; system mail (AH, GM), COD and
  returned mail don't count. Several senders of one item: the latest first. The ledger is per
  account, so a bank alt on a second account knows its own takes; nothing taken before the ledger
  (v0.25.0) is known.
- **What goes:** whole stacks only (the mailer attaches whole slots), the biggest first, never past
  what is owed; a stack bigger than that stays and follows the usual rule. Whatever the price, never
  a hard keep (locked, soulbound, quest, a quest needs it, in use, a tool). A return beats a binding
  and the bank alt. The rest of the list is the usual one.
- **How:** shown under Mailing with a "back to <name>" chip and its own "To:" line ("Returned
  items"); Send mails them in their own mails, "Mailworthy 1/2: returned to you". The Send-time check
  (`UI.Changed`) and the slot re-check apply as for any mail.
- **B (bank)** (2026-10-20): the fourth tag and summary row, for items the rule says to
  hold for a later phase (decision rule above); the tooltip says why and what listing
  it today would bring. Tags are advice: the bank alt can list a B item any time.

## Release and CurseForge

How to publish, the assets (icon, description, screenshot) and the checklist for
the first public file: [CURSEFORGE.md](CURSEFORGE.md). Auctionator and Siz
DisenchantValue are optional dependencies (`.pkgmeta`, `## OptionalDeps`; Disenchantry
only in `## OptionalDeps`).

## Mail ledger (operator, 2026-11-07)

"A player exportable log of everything that was sent, in case someone ever needs to validate
where items went." Then: "If someone sends you materials (another player, not your alt) ...
show some desc of the debt balance between the two, captured at the time of send ... I want to
encourage players to pay back who sent them materials." And: "I dont ever want to see a list of
'who owes me' though. I think that will encourage bad behaviour."

- **The log** (`Ledger.lua`, `MailworthyDB.ledger[realm|faction].log`, newest 2000): every mail
  sent by this account's characters (Mailworthy's runs, recorded by `Mailer.lua` with exactly
  what it attached; Blizzard's Send button through a `SendMail` post-hook, the Send Mail tab
  read as it changes and in the hook) and every item or gold taken out of the mailbox
  (`TakeInboxItem` / `TakeInboxMoney` / `AutoLootMailItem` post-hooks, confirmed by
  `MAIL_SUCCESS`, dropped by `MAIL_FAILED`, unanswered ones counted at `MAIL_CLOSED`). Each
  entry: time, both names, subject, items (ID, name, count, value and its source), gold, COD,
  returned / own character / system flags. **Export log...** in the ledger window shows it in
  the copy box, oldest first. The critical path checks the log matches every mail sent.
- **The balance** per other player, kept as running totals (`players`), so pruning the log
  never changes it: items received at their value plus gold received, minus items and gold
  sent. Not counted: this account's characters (known characters and the bank alt), system
  mail (`canReply` false, GM, AH invoices), COD (a sale). A returned mail taken back undoes the
  "sent". Two Mailworthy peers count as one player only when each one's own hello lists the
  other (a hello is anyone's word); such links are followed through the whole group, named
  after its alphabetically first name (`Ledger.Groups`, built once from the peers and again
  after the next Mailworthy message).
- **Only your own side shows** (operator): the ledger window lists players you received more
  from than you sent back, with what they sent, and **Mark paid** (two presses: a trade or gold
  in person; logged); a chat line when you take a counted mail; the Mailworthy window's line at
  the mailbox (where you can pay back) with Ledger...; a grey suffix on that player's binding in
  Friends. Nothing ever lists who owes you, and `/mw report` has counts only.
- **Values, captured at the time of send** (operator, asked "if both players have mailworthy
  can the apps communicate?"): what you send is valued with your own prices when it goes
  (`Valuation.SmoothedPrice`, the decision rule's price). After a counted send, the item values
  go to the recipient's Mailworthy: `M2|<mail's sender>|<recipient>|<send time>|<mail id>|
  <itemID>:<count>:<copper>:<scan age>:<k>;...`, WHISPER only, and only to a player just heard from (any Mailworthy
  message: they're online; else `Comms.Ask` prompts hellos, and the values wait up to 30 days in
  `outbox`), to the recipient's own character, never another one their hello claims. The receiver
  keeps them in `expect` (31 days) when the recipient is one of its own characters and the
  mail's sender is the whisperer, and uses the oldest match (item, count and the character
  taking it) when the item is taken, **at most 3x its own price** (a made-up value can't run up
  a debt).
  Otherwise its own price when taken. No price: listed by count, not in gold.
- **The more up-to-date scan wins** (operator, 2026-11-07: "we should trust the more up to date
  value at time of send"): each value carries its Auctionator scan's age in days (v0.25.0's
  `V2` values carry none; they are still read, used as the sender's and never answered, and
  v0.25.0 drops `M2`, using its own price). On
  receipt, the receiver's own price as it stood the day the mail went (days counted as
  Auctionator counts them, `Ledger.ScanDay`: floor((local time - SCAN_DAY_0) / 86400); `PriceThen`: its
  last scan when that was already in, else that day in Auctionator's history, its lowest price
  seen) is compared with the sender's: the fresher scan at the time of send wins; a tie, an
  unknown age or no price of ours that day keeps the sender's (still capped at 3x ours). The
  export shows each value's source and scan age.
- **Answer back** (operator, same day, so both players see the same value): when the receiver
  settles on a value other than the sender's (its scan was fresher, or the cap), it queues
  `R2|<recipient>|<mail's sender>|<mail id>|<itemID>:<count>:<copper>:<k>;...` for the sender,
  held in `outbox` like the values (WHISPER only, sent once the mail's sender character is heard
  from, 30 days at most). **The mail id** is an account counter (`ledger[realm|faction].nextId`),
  never reused even when the log is pruned, and **k** numbers a stack among the mail's stacks of
  that item and count (unpriced ones too), so an answer names one stack of one mail (Codex
  review, 2026-11-07: send times and "the next unsettled stack" were not unique; send times stay
  real, so scan days are never moved). The sender finds that mail (id, sender, recipient,
  counted mails only) and stack, takes the value (`agreed`, the old one kept as `mine`) and
  moves its balance by the difference; an answer under a third or over 3x its own value is
  ignored, and a stack takes one answer. Until the answer arrives, the sender shows its own value.
  Still unmatched: a mail whose values never reached the receiver before it was taken (the
  receiver then used its own price and has nothing to answer to).
- **Trust** (Codex review, 2026-11-07): a hello's "my other characters" list is never evidence for
  reading or settling a mail. Values go to, and answers come from, the exact character the mail
  names; a stranger listing Bob as their alt gets none of Bob's values, can't answer for him and
  doesn't take his balance. The outbox is account-wide, but each message waits until the
  character it names as its author is the one logged in (the other side takes it only from
  them).
- **Never seen by the players** (operator: "as long as these messages back and forth are all
  obscured by the player"): values and answers are addon messages, which no chat window shows,
  and whispers, so only the two players' clients get them. A whisper to an offline player would
  print "No player named ... is currently playing", so one goes at once only to a player heard
  within `HEARD_FRESH` (60 s); otherwise Mailworthy asks for hellos (`A2`, guild and group) and
  sends when their reply proves they're online.
- Not built: face-to-face trades (Mark paid covers them), a shared "who owes whom" view (on
  purpose), merging characters of a player who doesn't run Mailworthy.
- Switch `/mw feature ledger off` (no hooks, nothing logged).

## Modules

| File | Role | Tested how |
|---|---|---|
| `Core.lua` | namespace, SavedVariables, slash commands, events | busted |
| `Blocked.lua` | records blocked actions (from LedgerLink) | busted |
| `Characters.lua` | known-character registry, saved-name history, auto-complete matching, realm/faction filter | busted (pure) |
| `Prices.lua` | price-source adapters | busted with stubbed addons |
| `Valuation.lua` | the decision rule: item facts + prices + settings -> mail-AH / mail-DE / keep + reason + gain | busted (pure, most tests live here) |
| `Bags.lua` | bag scan -> item facts, applies locks and filters | busted with stubbed `C_Container` |
| `Mailer.lua` | batch queue and state machine (attach, send, wait, next, stop); each run's timers die with it | busted with stubbed mail events |
| `MailWindow.lua` | the window at the mailbox: recipient, mail / staying lists (rows lock / unlock), totals, Send / Settings / Return to sender; fits its rows; follows Inbox -> Send Mail | busted + in game |
| `Returns.lua` | Return to sender: what other characters mailed this one (the ledger's takes) and which whole stacks go back to whom | busted (pure) + critical path |
| `MailButton.lua` | the Mailworthy button under the mail window (mouse; controller via Triangle, `PadKey.lua`; writes nothing into the controller UI) | busted + in game |
| `Nav.lua` / `PadKey.lua` | Mailworthy's own controller highlight and override bindings for its windows | busted + in game |
| `Locks.lua` / `Border.lua` | item locks (Alt+click, L3) and their blue glow | busted + in game |
| `Config.lua` | saved settings: bank alt per realm + faction, name history, steppers, sticky disenchant default | busted |
| `SettingsUI.lua` / `Widgets.lua` | the settings window (bank alt picker, steppers, toggles); shared window helpers | busted + in game |
| `MinimapButton.lua` | minimap button that opens settings (from LedgerLink) | busted |
| `Report.lua` | `/mw report`, one copyable report; AH sale mails (house cut) | busted |
| `Routes.lua` / `RoutesUI.lua` | bindings (a profession's materials to a player): store, pure divert with price cap, skip once, candidates (party, guild, own characters, peers); the friends window | busted |
| `Comms.lua` | hellos between Mailworthys (professions, skill ranks, scan day, mail values) over addon messages | busted |
| `Ledger.lua` / `LedgerUI.lua` | the mail log (every mail sent and taken, exportable), the balance per player (only your own side shows), value whispers; the ledger window | busted |
| `Tiers.lua` | material tiers: the skill at which each crafting profession is done with each material | busted (pure) |
| `TierCheck.lua` | tier check: reads the player's own profession window (recipe colours, reagents), reports and keeps materials the table calls done too early | busted (stubbed `C_TradeSkillUI`) + in game |

SavedVariables: `MailworthyDB` (account: characters, bank alt per
realm+faction, name history, settings, blocked actions) and
`MailworthyCharDB` (locked items).

## Phases

| Phase | Delivers | Done when |
|---|---|---|
| **0 - Discovery** | LedgerLink `/rl probe` S5 (ledger-link PR #28, released in v1.3.0) and S6 (PR #29); repo, CI, packaging | the S5 + S6 report is back and its answers are in README "Beta unknowns" |
| **1 - Prices + valuation** | `Prices`, `Valuation`, `Bags`; `/mw scan` shows what would be mailed and why, with the numbers (sends nothing). **Built**, in-game check pending | `/mw scan` agrees with a hand calculation on real bags |
| **2 - Settings + characters** | settings panel, minimap button, bank alt picker with history and auto-complete, disenchant checkbox default, thresholds, fees | bank alt survives `/reload` and relog (the beta's SavedVariables bug), and every settings control works with the gamepad alone. **Built**, in-game check pending |
| **3 - Mailbox + mailing** | mailbox button (opens settings when not set up), preview with recipient + Settings button, one press sends every batch (chained). **Built**, in-game check pending | 30+ items reach the bank alt in under 3 presses, with nothing locked, bound or unpriced sent; works with ForeverMail installed |
| **4 - Item locks** | **done** in alpha5 (Alt+click, L3, blue glow; rows in the Mailworthy window since Phase 3); no never-mail list (operator, 2026-10-13: locks cover it) | locked items never appear in the preview's mail list |
| **4c - Bank alt view** | tags on the bank alt's bag slots (recomputed with fresh prices), tooltip lines with the original reason, summary window | tags match a hand calculation with fresh prices; a changed verdict shows both. **Built** (`BankAlt.lua`), in-game check pending |
| **5 - Polish** | self-test removed, `/mw report` instead; blocked-action chat line once per session; tooltip lines on every character via the "tags everywhere" setting; description matches what shipped. **Built**; v1.0 check pending | tagged release installs cleanly |

## Beta unknowns

**Settled by the first report** (LedgerLink v1.3.1, build 70338, 2026-10-13):
- Auctionator 340 runs on Forever; its API has price, age, exactness,
  disenchant and DB-update calls.
- Disenchantry exposes no price data; since 2026-10-26 Mailworthy recomputes its expected value from the same tables (`Disenchant.lua`).
- `C_Container.GetContainerItemInfo` gives `isBound`, `hasNoValue`, `isLocked`,
  `quality`, `stackCount`, `itemID`, `hyperlink`; quest items via
  `GetContainerItemQuestInfo`; sell price is `GetItemInfo`'s 11th return.
- Backpack has 20 slots; `NUM_BAG_SLOTS` is 4; the reagent bag is bag 5
  (`NUM_TOTAL_EQUIPPED_BAG_SLOTS` = 5, source-backed; a user had one, 2026-10-21),
  so the scan, locks and sending cover bags 0-5. Profession bags sit in 1-4.
- `ATTACHMENTS_MAX_SEND` 12; `GetSendMailPrice()` 30 with nothing attached;
  `C_Mail.IsCommandPending` exists (useful for sending mails in a row).
- The AH is the modern `C_AuctionHouse` (commodities); no classic AH functions.
- Settings API: `Settings.RegisterCanvasLayoutCategory` (exists; Mailworthy doesn't use it, see "Settings panel").
- Mail auto-complete has no account-characters flag.
- Bag item buttons have no global names; combined bags exist; bags can be sorted.
- The controller UI is Blizzard's "smart navigation" (`gamepadFooter` tables,
  `…FooterinputLegend` frames, `smartNavigationFocusKey`, gamepad mixins,
  `C_Navigation`); pad buttons have no normal key bindings.
- The bag item "More" menu is a `Menu` with tag `MORE_CONTEXT_ACTIONS`
  (LedgerLink v1.3.2, 2026-10-13); Auctionator 341 returns prices (age 0, exact).

**Still open:** every remaining question, and how one session answers all of
it, is in [DISCOVERY-SESSION-2.md](DISCOVERY-SESSION-2.md) (U1-U20).

## Related addons (checked 2026-10-13)

| Addon | Overlap | Difference |
|---|---|---|
| [ForeverMail](https://www.curseforge.com/wow/addons/forevermail) (Forever, active) | rule-based auto-mailing with a queue | rules per item, not by value; no disenchant, slot locks or controller; replaces the mailbox window |
| [Larlen Mail Mule](https://www.curseforge.com/wow/addons/larlen-mail-mule) (Retail) | mails Auctionator-priced items to bank alts, queues mails | Retail only; no vendor/fee comparison, disenchant, locks or controller |
| [MuleMate](https://www.curseforge.com/wow/addons/mulemate) (Classic Era) | AH-after-cut vs 110% of vendor, prepares one mail for a bank alt | Classic Era only; player clicks Send per mail; no disenchant, locks or controller |
| [AuctionWorthy](https://www.curseforge.com/wow/addons/auctionworthy) (Classic Era) | vendor vs AH (deposit + cut) on tooltips | tooltips only, no mailing; similar name, `/worthy` |

## Carried over from LedgerLink

- One command for in-game checks (`/mw report`), never lists of `/dump` lines.
- Every unverified API is wrapped in `pcall` / nil checks and listed in README "Beta unknowns".
- Never call `SetFocus` (gamepad crash, 2026-10-05). Record blocked actions.
- Keep the logic pure and test it with busted on LuaJIT; `luacheck .` stays clean.
- The beta's SavedVariables reload bug: test settings persistence first.
- Branches and PRs only; CI runs busted, luacheck and a packaging dry run.
