# Mailworthy handoff (2026-10-13)

Everything a new agent needs to continue Mailworthy from this directory. It
was built in one long session that started in the LedgerLink repo; this file
replaces that conversation. Read it fully, then `docs/PLAN.md`.

## 1. What Mailworthy is

A WoW **Forever** addon (client 1.60.1, `## Interface: 16001`; classic-style game,
retail-style UI code). At a mailbox, one button mails every bag item worth more on
the auction house (after fees) or disenchanted than at a vendor to the player's
**bank alt**; the rest stays in the bags for the vendor. The bank alt then sees
tags (AH / DE / Vendor) recomputed with fresh prices. Optional integrations:
Auctionator (prices, recommended) and Siz DisenchantValue (disenchant values; switches
on the disenchant comparison) and Disenchantry (back on CurseForge since 2026-10-22; no API,
so `Disenchant.lua` recomputes its expected value from the same era tables; a switch too).

The operator (repo owner) plays on a **Windows PC with a gamepad**, tests in
game, and pastes reports back. **Keyboard/mouse is the priority** ("if mouse/kb
doesn't work no one will use it"); the controller is a must-have bonus that
must never break the game.

## 2. Where things are

| What | Where |
|---|---|
| Repo | GitHub `sjdodge123/mailworthy` (public), default branch `main` |
| Design + phases + decision rule | [docs/PLAN.md](PLAN.md) |
| Decision-rule research (bank category, server age, competition; beta build check 2026-10-20), **built** as rule v2 | [docs/ALGORITHM-RESEARCH.md](ALGORITHM-RESEARCH.md) |
| Blizzard source findings + **taint rules** | [docs/FOREVER-UI-NOTES.md](FOREVER-UI-NOTES.md) |
| In-game discovery history (U1-U20 results, rerun scripts) | [docs/DISCOVERY-SESSION-2.md](DISCOVERY-SESSION-2.md) |
| CurseForge setup, assets, path to v1.0 | [docs/CURSEFORGE.md](CURSEFORGE.md) |
| Controller UI screenshot (reference) | [docs/img/forever-mailbox-gamepad.webp](img/forever-mailbox-gamepad.webp) |
| Logo source / avatar / in-game icon | [media/logo.svg](../media/logo.svg), [media/logo-400.png](../media/logo-400.png), [media/logo-512.png](../media/logo-512.png), [Mailworthy/Textures/Icon.tga](../Mailworthy/Textures/Icon.tga) |
| **Target release UI** (mailbox window) | [media/ui-prototype.html](../media/ui-prototype.html) -> [.png](../media/ui-prototype.png) |
| **Target bank alt view** (tags + tooltip + summary) | [media/bank-alt-prototype.html](../media/bank-alt-prototype.html) -> [.png](../media/bank-alt-prototype.png) |
| **Bindings UI** (binding rows in the mail window, the friends window) | [media/bindings-prototype.html](../media/bindings-prototype.html) -> [.png](../media/bindings-prototype.png) |
| **UX pass** (current layout of the mailbox, settings and friends windows, 2026-11-06) | [media/ux-pass-prototype.html](../media/ux-pass-prototype.html) -> [.png](../media/ux-pass-prototype.png) |
| CurseForge description (paste into the project page) | [media/curseforge-description.html](../media/curseforge-description.html) |
| Rebuild icon/avatar/TGA/screenshots | [tools/build-icons.sh](../tools/build-icons.sh) (Chrome headless + Pillow) |
| Package layout check (CI) | [tools/check-package-layout.sh](../tools/check-package-layout.sh) |
| Agent rules | [AGENTS.md](../AGENTS.md) (CLAUDE.md includes it) |
| Blizzard's Forever UI source | GitHub `Ketho/wow-ui-source-forever` (branch `forever`); read with `gh api repos/Ketho/wow-ui-source-forever/contents/<path>?ref=forever --jq .content \| base64 -d`, search with `gh search code --repo Ketho/wow-ui-source-forever "<term>"`. Snapshot of build 70205: `Bleakfiber/Blizzard-Interface-Assets---Forever-1.60.1.70205` |
| Sibling project | LedgerLink (CurseForge 1728299), a separate repo. Its `/rl probe` sections S5-S8 (v1.3.0-v1.3.3) were Mailworthy's first discovery tool: price addons, bag values, mail/AH/gamepad APIs, smart navigation dumps, the bag "More" menu recorder, AH deposits. LedgerLink's own rules (wire format owned by Raid Ledger) don't apply here |

**Same-named files trap:** LedgerLink also has `media/logo-400.png`,
`media/curseforge-description.html`, etc. Always use paths inside this repo.

## 3. Code (Mailworthy/, load order = .toc)

| File | Role |
|---|---|
| `Core.lua` | namespace, SavedVariables (`MailworthyDB` account, `MailworthyCharDB` per char), event dispatch `ns.On/ns.Fire`, slash `/mw`, **feature switches** `/mw feature <name> on|off` (mailButton, padTriangle, padNav, padLock, altClickLock, slotBorder; logged at login) |
| `Log.lua` | account-wide self-test log (400 lines) |
| `Blocked.lua` | records `ADDON_ACTION_FORBIDDEN/BLOCKED` blamed on Mailworthy, with the last command; chat line |
| `Characters.lua` | known characters (name "First Surname", realm, faction, class, level, professions); `Mailable()` = same realm+faction; SavedVariables marker per login/reload |
| `Gamepad.lua` | read-only helpers: button symbols (`labelStyle`, `CreateAtlasMarkup`), API presence |
| `Locks.lua` | **item locks** (by item ID, per character; follow the item; slot locks migrate); Alt+click via `hooksecurefunc("HandleModifiedItemClick")`; L3 via read-only `SmartNavigation:GetCurrentButton()` |
| `Border.lua` | blue glow on locked items: Blizzard's quest border texture tinted blue, on bag buttons via `hooksecurefunc(frame, "UpdateItems")` on combined + individual bag frames; shown only while a mailbox is open (`MAIL_SHOW` / `MAIL_CLOSED`, `MailFrame:IsShown()`) unless the `glowEverywhere` flag is set; a fresh lock flashes `Border.FLASH` (3 s) anywhere, via `Locks.OnChanged(itemID, locked)` |
| `MailButton.lua` | "Mailworthy" button under the mail window on both tabs (children of InboxFrame / SendMailFrame, created at login); `Activate` toggles the window; controller on the Inbox gets an "R1 first" hint (we never switch tabs) |
| `Nav.lua` | Mailworthy's **own** controller navigation for its window: nearest button within 45 degrees, top-left start, gold highlight |
| `PadKey.lua` | Mailworthy's **own override bindings** (watcher every 0.1 s, re-apply when replaced, clear on focus loss and at `PLAYER_REGEN_DISABLED`): set `mail` (Triangle), `window` (Triangle, D-pad, Cross, Circle), `bags` (L3 lock) |
| `Prices.lua` | Auctionator adapter (`Lookup`: AH price per unit, age in days, exact, disenchant; nil without Auctionator), disenchant value from Siz DisenchantValue (`DisenchantValueOf`: `DisenchantValueAPI.GetValue(link)`, else Auctionator's call; `deSource`), vendor price (`GetItemInfo` 11th return), class ID, `DisenchantAddon()` / `DisenchantAddonInstalled()` (Siz DisenchantValue by its API table, Disenchantry by `DisenchantryDB`) |
| `Disenchant.lua` | era disenchant tables ported from Disenchantry 1.1.5 (MIT; original-era rows only, Forever's ilvl 21-30 weapon essence quirk) and the pure expected value (chance x average quantity x material price, nil when a material has no price); `Value(itemFacts)` prices materials through `Prices.MaterialPrice` |
| `Valuation.lua` | **pure** decision rule: settings (defaults + saved, disenchant follows the disenchant addon, `keepProfessionMats` on), profession materials (`PROFESSION_MATS` by skill line ID x trade-goods subclass, `NeededBy`, `CraftingProfessions`; `settings.professions` filled by `Bags.Evaluate` from `Characters.Professions()`), deposit, thresholds, keep reasons, no-Auctionator rule, `Money` formatting |
| `Bags.lua` | scan bags 0-5 (`LastBag()` = `NUM_TOTAL_EQUIPPED_BAG_SLOTS`: backpack, bags 1-4, reagent bag; `IsBag()` shared with Locks) -> slots -> items (grouped per link + bound + in-use), locks, prices, verdicts, totals; `/mw scan` report in the copy box (sends nothing) |
| `Config.lua` | saved settings (`MailworthyDB.settings` only what the player touched, `bankAlts[realm|faction]` set by a pick or by the bank alt itself via `SetBankAltHere`, `names` history); flags `minimapHidden`, `tagsEverywhere`, `glowEverywhere`; choices, auto-complete, steppers |
| `Widgets.lua` | window / button / label / legend helpers shared by all windows |
| `Mailer.lua` | sending: plan 12 stacks per mail, re-check each slot, attach, zero money/COD, `SendMail`, chain on `MAIL_SEND_SUCCESS`; stops on failure / close / combat / 10 s; a run id kills a stopped run's timers; records `MailworthyDB.mailed` (30 days) |
| `MailWindow.lua` | the window at the mailbox (`media/ux-pass-prototype.png`): To, binding rows (only while there are bindings: Skip once / Remove, Friends...), Mailing rows (chip + gain), Staying rows (reason), total (its second line: fees, or the mailer's status), Send / Settings (no Close: X, Escape, Circle); `UI.Layout` sizes the window to the rows shown; rows toggle item locks; pages of 8 / 5. Opened on the Inbox, there is no Send button (a note says to open the Send Mail tab; v0.16.1's secure "click" button on `MailFrameTab2` never showed in game and was removed, operator 2026-11-06: "otherwise just don't show it"), and `MailworthyTabWatcher` moves the window to Send Mail when the player goes there (Mailworthy's code never switches tabs). Several recipients: `UI.Recipients(totals)` puts one line per recipient under "To:" (what, how many mails; `Bags` totals `byRecipient`) and the Mailing list is grouped by recipient |
| `BankAlt.lua` | bank alt view: verdicts with no postage (`Verdict`: ah / de / v), tags on bag buttons (a `Border` decorator), tooltip lines via `TooltipDataProcessor`, summary window (`/mw summary`, mail button on the bank alt); switches `bankAltTags`, `tooltipLines`; setting `tagsEverywhere` |
| `SettingsUI.lua` | settings window, two views (`UI.View`): main (bank alt row with Change..., "What gets mailed": steppers, 2/8/24h, disenchant, profession materials; "In your bags": tags, glow; "More": friends, summary, minimap; the prices source) and pick (opened by Change..., and first while no bank alt is set: known characters, "This character is my bank alt" for a second account, optional typed name with "not seen" second press, Back); a pick returns to main; controller via `PadKey` set `settings` (works away from the mailbox) |
| `MinimapButton.lua` | LedgerLink's minimap button (click: settings; drag: move); feature `minimapButton` |
| `Report.lua` | `/mw report` (one copyable report: build, controller, switches, bank alt, settings, locks, last send, bindings, peers, blocked actions, log), the copy box `/mw scan` uses, and the AH sale-mail reader (house cut). Replaced the discovery self-test in Phase 5 |
| `Routes.lua` | **bindings** (2026-10-26): a crafting profession's materials to one player (`MailworthyDB.routes[realm\|faction]` for all the account's characters, `MailworthyCharDB.routes` for this one; this character's win). Pure `Divert(item, verdict, price, settings, routes)`: route `friend`, `to`, `what`; never over a hard keep; at or above the binding's `cap` (copper per unit, `CAP_STEPS`, 5g default, nil = none) the normal verdict stands with `capped`. `SkipOnce` per mailbox visit. `Candidates()`: party / raid units, guild via `C_Club` (`GetGuildRosterInfo` fallback), known characters, peers; `Clean` drops "-Realm". Pure `Crafter(route, peer)` / `Recipient(route)`: the bound player, or the character of theirs that has the profession (from their hello) |
| `Comms.lua` | hellos between Mailworthys (`C_ChatInfo`, prefix `Mailworthy`): `H2\|<own crafting skill lines>\|<Name=ids;...>` (the account's other crafters here) / `A2`; peers in `MailworthyDB.peers[realm\|faction]` (60 days); throttled; everything received is validated data. Switch `comms` |
| `Stale.lua` | stale auction prices (2026-11-06): freshness = days since Auctionator saw the freshest of 12 everyday trade goods (`WATCH`, `GetAuctionAgeByItemID`); the scan day goes out as `F2\|<server day>` after each hello (Comms; older Mailworthys drop unknown kinds) and peers' days are kept in `MailworthyDB.fresh[realm\|faction]` (60 days; separate from `peers`, so bindings data is untouched). Pure `Nudge(ownAge, freshest, today, maxAgeDays, nudgeDays)`: nil up to `NUDGE_DAYS` (3, operator 2026-11-06), "self" past that (`ignored` past `maxAgeDays`, 7: those items stay in the bags), "peer" when someone heard in 14 days scanned within 2 days. Shown as "!" on the mail buttons, a line at the top of the Mailworthy window, and (peer only) one chat line at `MAIL_SHOW`; logging in stale sends an ask so fresh peers answer. Display only. Switch `staleNudge` |
| `RoutesUI.lua` | the friends window (`/mw friends`, settings button, Mailworthy window button), two views (`UI.View`): list (binding rows: cap stepper with `UI.CapText` "5g each or more: to my bank alt", scope, Remove; names the crafter the mail goes to; Add a binding...) and add (step 1 a player, online first; step 2 the profession, theirs suggested; Back one step); opens on add while there are no bindings; a binding returns to the list |

Tests: `spec/` (busted on LuaJIT, 207 specs) with a WoW stub in
`spec/support/wow_stub.lua` (bags, mail send tab, postage, timers with delays,
override bindings, focused frame, item buttons that **error on any field write**).
`Nav` drives the most recently shown visible window (`Nav.Root`); Circle closes only that one.
Guard spec `no_gamepad_taint_spec.lua`: Mailworthy may only *read*
`FrameControlsManager:GetActiveFrame()` and `SmartNavigation:GetCurrentButton()`.

## 4. Measured facts (in game, 2026-10-13)

- Auctionator 340/341 on Forever: `Auctionator.API.v1` has `GetAuctionPriceByItemLink`,
  `GetAuctionAgeByItemLink`, `IsAuctionDataExactByItemLink`, `GetDisenchantPriceByItemLink`,
  `GetVendorPriceByItemLink`, `RegisterForDBUpdate` (caller ID "Mailworthy"). Prices only
  after a scan. Disenchant values were never seen (no green item tested).
- Disenchantry 1.1.1: no readable price data (`DisenchantryDB` = settings only); 1.1.5 (back on
  CurseForge 2026-10-22, project 1704637) computes an "Expected disenchant value" in its tooltip
  from era tables + Auctionator, all in its private namespace: Mailworthy ports the tables. Siz
  DisenchantValue (CurseForge `siz-disenchantvalue`, Forever 1.60.1, Sep 2026) documents
  `DisenchantValueAPI.GetValue(link)` = copper or nil for other addons (Auctionator's DE
  Value column uses it); not yet seen in game (2026-10-22).
- Postage: **30c per attached item** (30c empty). 12 attachments per mail.
- AH: modern `C_AuctionHouse`; durations index 1/2/3 = **2 / 8 / 24 hours**;
  deposit = **floor(vendor value of stack x 5%) x 1 / 4 / 12**, same for commodities
  and items, computable with the AH closed (0 for uncached items).
  `GetItemCommodityStatus`: 1 = item, 2 = commodity. AH cut assumed **5%** (not yet
  verified; `GetInboxInvoiceInfo` on a sale mail gives `consignment`).
- Attaching with `C_Container.UseContainerItem` works on a press **and from a timer**;
  `ClearSendMail()` returns items; `SendMail(name, subject, "")` to "First Surname"
  works; mail 2 chained after `MAIL_SEND_SUCCESS` with no press works; mails were in
  the bank alt's inbox 89 s later.
- Bags: backpack 20 slots, `NUM_BAG_SLOTS` 4, reagent bag = bag 5 (`NUM_TOTAL_EQUIPPED_BAG_SLOTS` 5, source;
  a CurseForge user had items there that v0.5.1 ignored, 2026-10-21); `GetContainerItemInfo` gives
  `isBound, hasNoValue, isLocked, quality, stackCount, itemID, hyperlink, iconFileID`;
  quest via `GetContainerItemQuestInfo`; sell price = `GetItemInfo` 11th return.
- Settings API: `Settings.RegisterCanvasLayoutCategory` (no `InterfaceOptions_AddCategory`); not used (taint risk).
- Mail auto-complete has no "my characters" flag (own list needed).
- SavedVariables persist across login, character switch and `/reload`.
- `labelStyle` "Shapes" (PlayStation); atlas markup works. Minimap buttons are not
  reachable with the controller.
- **alpha3/alpha4/alpha5: zero blocked actions** with controller and mouse/keyboard.
  Own Triangle binding: 9 presses, Blizzard replaced it twice in 2 minutes.
- **alpha5 (all 11 questions yes):** envelope icon, Alt+click and L3 locks, locks
  follow the item through sorting, blue glow, Triangle toggles the window, D-pad
  highlight reaches every button, Cross presses, Circle closes only our window,
  bags keep their Triangle, Cross still uses items.

## 5. Pitfalls (each cost a test round)

**Taint (the big one).** Any addon write into Blizzard's gamepad UI taints gamepad
input until `/reload`; the game then blocks `SetPreferredGamepadInteractTarget`,
jumping (`DescendStop`, `RunBinding`), `InteractUnit`, `ClearTarget`, `SpellStopCasting`
and bag item use (`UNKNOWN()`). Proven unsafe:
1. Prompted bindings on Blizzard footers (`AddPromptedBinding` + `Finalize`) - alpha1, tainted at login.
2. Registering our window: `FrameControlsManager:FrameShown`, own `CreatePromptedBindingFooter` (and by source/prior art `ShowUIPanel`) - this is why **L2/R2 into our window is not possible**.
3. **`Menu.ModifyMenu("MORE_CONTEXT_ACTIONS")`** (bag item Triangle "More" menu), even unclicked - alpha2. The operator asked for it twice; the answer is L3 + Bag locks.
4. `CreateFrame` while a gamepad panel is open (SmartNavigation's CreateFrame hook runs in our context). **Create every frame at login**, on UIParent, then `SetParent`.
5. Writing any Lua field on a Blizzard frame, or any `smartNavigation*` / `OnSmartNav*` / `buttonContext` key on ours.
6. `MailFrameTab_OnClick` from addon code (writes `MailFrame.activeSubFrame`, read by focus code): **never switch mail tabs ourselves**.
7. `SetFocus` from addon code (LedgerLink: blocked `SetPreferredGamepadInteractTarget`, client crash). The player clicks edit boxes.

Safe (verified or source-backed): own override bindings on our own frame
(`SetOverrideBindingClick(ourFrame, true, key, ourButton)`; gamepad modules don't
listen to `UPDATE_BINDINGS`); `hooksecurefunc` post-hooks; textures / font strings
on Blizzard frames kept in our own weak tables; read-only `GetActiveFrame`,
`GetCurrentButton`, `InputUtil.IsGamepadUIEnabled`; mail API calls from timers;
tooltip lines (Auctionator adds them, never blamed); source-backed, not yet seen in game:
a `SecureActionButtonTemplate` button with `type` = "click" and `clickbutton` = `MailFrameTab2`
pressed by the player's **mouse** (Blizzard's `SECURE_ACTIONS.click` presses the tab, like a
`/click` macro; `MailWindow.PlaceTabButton`: out of combat, mouse UI only, never via `Nav`,
whose Cross press is addon code). `no_gamepad_taint_spec` checks no Mailworthy file calls
`MailFrameTab_OnClick`, `PanelTemplates_SetTab` or a tab's `Click`.

**Unsolved:** plain buttons under `SendMailFrame` should be in smart navigation's
"Send Mail" group (`Utility.FindButtonGroups` walks all descendants, no bounds
check), but the D-pad never reached them in alpha3/alpha4. Hence `Nav` + `PadKey`.
Blizzard ships `SmartNavigationDebug` (overlay of navigable buttons) if this needs
revisiting; showing it needs `/run`, which the operator shouldn't be asked to do lightly.

**Timers outliving their run.** A `C_Timer.After` callback queued by a send run still
fires after that run stops (combat, mailbox closed): the first Mailer draft would then
call `SendMail` anyway. Every Mailer timer checks the run id and `busy`.

**Process pitfalls.**
- The operator **merges PRs silently**. Before pushing to a PR branch, gate the push
  on `gh pr view N --json state --jq .state` == OPEN (a printed check in the same
  script is not enough: PR #6 lost two commits that way, recovered in PR #7).
- zsh doesn't word-split `$(...)` in `for` loops; pass commit lists explicitly.
- Code run from `OnUpdate` / events is wrapped in `pcall` and only *logs* errors, so a
  spec passes while the code errors every tick (alpha5: `PadKey.Check` on `pairs(nil)`
  ten times a second flooded the 400-line log). Specs for such code assert the log
  has no error lines (`spec/padkey_spec.lua` `after_each`).
- The stub's `GetCenter`, `IsVisible` and parent tracking matter for `Nav` specs.
- Reports come back as one .txt with several reports (main + bank alt); read them all.
- Ask for in-game tests only when the source research says the fix is real; the
  operator wants few iterations.

## 6. Decisions

- Keyboard/mouse first; controller everywhere too; no mouse-only gestures, no
  required typing; `SetFocus` never.
- Locks are **per item ID** (all stacks, follow moves), per character; Alt+click
  (mouse), L3 in bags (controller), Bag locks page; blue quest-style glow.
  **No never-mail list** (operator, 2026-10-13: locks cover it).
- After a send, the main's bags get **V** tags (vendor items, grey junk) for the session;
  locks re-evaluate tags at once (operator, 2026-10-14). `BankAlt.Mode()` = "vendor".
- Settings: our own window, not Blizzard's options panel (registering there hands our
  tables to a controller-navigated panel; same taint pattern as the More menu).
  Valuation defaults apply until the player touches a setting.
- Mailbox entry: "Mailworthy" button under the mail window (both tabs); controller:
  R1 then Triangle; Mailworthy's own D-pad / Cross / Circle while its window is
  open; no L2/R2 cycling into it; no More-menu entry.
- Decision rule (PLAN): AH net = price x count x 0.95 - deposit - 30c postage vs
  vendor; deposit for the **24h listing** (operator, 2026-10-13) = floor(vendor x
  count x 5%) x 12, half counted (relist factor 0.5 since 2026-10-20; a glut counts it in full);
  mail when gain >= **5s and 25%** (defaults, steppers in settings);
  disenchant compared when enabled (default on if Siz DisenchantValue or Disenchantry is
  installed; the value from Siz DisenchantValue, else Auctionator, since 2026-10-22).
  **Without Auctionator: mail every unlocked, tradeable white (common) item**;
  greys and uncommon+ stay. Soulbound / quest items can't be mailed (don't list them).
- Decision rule v2 (operator, 2026-10-20: "most gold while levelling, no math for the
  player"; built from ALGORITHM-RESEARCH.md steps 1-5): the price is the 3-day median of
  Auctionator's history (its database, not the stable API: guarded); launch day from
  `GetServerTime()` against Nov 4, 2026 (`Valuation.LAUNCH_EPOCH`), or the realm's first
  sight when earlier; days 0-13 mail unpriced white trade goods; a glut (10x our count
  listed, -25%) is valued at the floor; **Bank** verdict (B tag) for late-demand trade
  goods before day 35 and gluts until day 60; the minimum gain grows 1/180 a day after
  day 35, capped at 2x. No new settings.
- Bank alt picked from known characters (same realm + faction), never typed by default.
- **Bank alt on a second WoW account** (Reddit r/wowaddons, 2026-10-24): SavedVariables are
  per account, so the main's pick never reaches the alt. The alt declares itself with the
  settings button "This character is my bank alt" (`Config.SetBankAltHere`, `ClearBankAlt`,
  `IsBankAltHere`); it writes the **same** `bankAlts[realm|faction]` slot a pick uses (one
  bank alt per realm + faction per account, so the account's other characters mail to it),
  and `BankAlt.IsBankAlt()` reads it. The typed path still refuses the character's own name
  and points at the button. Not crossing accounts: price scans (Auctionator per account) and
  the "Mailed for" history (`MailworthyDB.mailed`, written by the sender); the tooltip and
  summary skip the line when there's no record. The history is not carried in the mail
  body or subject (decided against in that PR).
- Bank alt view: AH / DE / V tags on bag slots recomputed with the bank alt's own
  prices; tooltip shows fresh verdict + "Mailed for: ..." (recorded at send time,
  `MailworthyDB.mailed`, 30-day expiry); summary window.
- Releases: **every tag publishes to CurseForge** (project **1743661**, `CF_API_KEY`
  set, `.toc` has the ID). Operator asked for plain release tags `vX.Y.Z` going
  forward; alpha tags upload as alpha files (v0.1.0-alpha5 did). **Check `git ls-remote
  --tags origin` for the latest tag before tagging** (the operator asked for "v0.6.0" on
  2026-10-21 when v0.8.0 already existed; v0.9.0 was agreed instead). Tag only when the
  operator says "tag X"; then watch the release run and report the CurseForge "Success!"
  line: the packager's later "Uploading ...zip... Success!" lines are the GitHub release,
  not CurseForge, and the run can fail after them.
- CurseForge feedback (user cursebandit, 2026-10-21, built the same day): every equipped bag
  is scanned, lockable and mailed (bags 0-5: the reagent bag was missing); the lock glow
  shows only while a mailbox is open, with a settings button ("Locked items glow blue:
  at the mailbox only / always", flag `glowEverywhere`) for the old behaviour; a new lock
  (Alt+click, L3) still glows 3 s away from a mailbox so the player sees it worked.
- Profession materials (operator, 2026-10-22: "factor in the player's own professions"): a
  setting, on by default ("Keep my professions' materials", `keepProfessionMats`), keeps trade
  goods the character's crafting professions use, as the keep reason "your Tailoring needs
  it", before any pricing. Mapping by `GetProfessionInfo` skill line ID and item subclass
  (`Valuation.PROFESSION_MATS`); gathering professions need nothing; elementals stay mailable.
- Enchanting bindings take green and blue gear (operator, 2026-11-06: "the enchanter binding
  for friend sending should also include green or blue items that can be used for
  disenchanting"): `Routes.Matches` also takes uncommon / rare weapons and armor
  (`Valuation.CanDisenchant`, `Routes.GEAR_QUALITIES`; epics stay on the normal rule) for a
  binding on Enchanting 333. Soulbound gear is a hard keep; the binding's per-unit cap compares
  the piece's AH price, so a green the AH pays well for still goes to the bank alt.
- Popups beside their opener (operator, same day: the new popups "overlap the existing menus
  and you cant read the new popup easily without closing the old one"): `Widgets.PlaceBeside`
  puts settings / friends / the bank alt summary to the right of the Mailworthy window that
  opened them, else to its left, else squarely over it; centred from `/mw` and the minimap
  button. Every window is opaque now (backdrop alpha 1) and clamped to the screen.
- Sell what I gather (operator, 2026-11-06: "some players use gathering professions simply to
  gather materials to send to the ah ... a toggle in the ui, off by default"): setting
  `sellGathered` (off), the settings button "Sell what I gather" under What gets mailed.
  Only changes the gather-and-craft overlap (a pure gatherer already mailed everything): what
  `Valuation.GATHERED_MATS` (Mining 186 = metal & stone, Herbalism 182 = herbs, Skinning 393 =
  leather, Fishing 356 = meat and fish subclass) brings in skips the "your X needs it" keep and
  is valued like anything else. Mining covers bars too (one subclass; smelting is Mining's).
- Optional deps: `.pkgmeta` `optional-dependencies` auctionator, siz-disenchantvalue and (since
  2026-10-26, the project being back) disenchantry: a slug that disappears fails the CurseForge
  upload with error 1018 (v0.8.0 and v0.9.0 did on disenchantry in October 2026), so if a tag's
  release run fails on it, drop the slug and re-tag; `## OptionalDeps: Auctionator,
  DisenchantValue, Disenchantry`.
- Disenchantry as a first-class disenchant source (operator, 2026-10-26: "support that as a first
  class enchanting market addon"): it has no API (its 1.1.5 zip was read; everything is in its
  private namespace), so `Disenchant.lua` carries its tables and formula and Mailworthy's number
  equals its tooltip. Source order: Siz DisenchantValue (learned values), the tables, Auctionator's
  own call. With Auctionator alone the tables still work ("era tables"); only the default of the
  checkbox depends on a disenchant addon being installed.

- Stale-prices nudge (operator, 2026-11-06: "10 people using mailworthy and 8 of them have scanned
  the ah but 2 haven't scanned in a week ... the 2 get a signal next time they look at the mailbox
  button"): `Stale.lua`. Chosen: share only each player's scan day, never prices (spoofable, and
  they don't fit a 255-byte message); display only, never a decision input; the nudge starts past
  3 days (operator, same day: "set that threshold to 3 days instead of 7"), while Valuation's
  7-day `maxAgeDays` still decides when prices stop counting (the text then says items stay); a quiet nudge with no fresher
  peer too, so a guild without other Mailworthy users still sees it; "comms range" is the guild /
  group channels, so the signal waits in SavedVariables for the next mailbox visit.

- UX pass (operator, 2026-11-06: "simplify the ui and ux while still keeping functionality";
  prototype `media/ux-pass-prototype.png` approved first): every window shows one task at a time
  and hides what doesn't apply; nothing was removed except the mailbox window's Close button (the
  X, Escape and Circle close it). Mailbox window: the bindings block only with bindings (Friends
  is in Settings otherwise), the lock hint on the Mailing heading, the fees line doubles as the
  mailer's status, the prices source moved to Settings, the window fits its rows. Settings: bank
  alt on one row + Change... (the picker is its own view, and the first-run view). Friends: list
  and add views. `Nav.Revalidate` moves the controller highlight off a button that a view switch
  hid. Also from the operator that day: Send on the **Inbox** tab "didn't do anything, it felt
  like a bug" (the status said why, too quietly): the button now reads "Open the Send Mail tab"
  and the window follows the player to that tab (we still never switch tabs ourselves).
  2026-11-06 later: v0.16.1 put a secure "click" button on the Send Mail tab in Send's place;
  in game it didn't show ("hides unless you are on the send mail tab ... otherwise just
  don't show it"), so it is gone: on the Inbox there is no Send button, only the note. Same
  day: "when sending to multiple people ... make sure the receiver is made clear": one "To:"
  line per recipient and the Mailing list grouped by recipient.

- Bindings (operator, 2026-10-26: "send my enchanting mats to a guild member and bind that,
  until cancelled; easy to X on each send and to remove; few settings; an insane market high
  still goes to my alt"): `Routes.lua` / `RoutesUI.lua` / `Comms.lua`, PLAN "Bindings". Chosen:
  the cap is a per-unit price stepper on the binding row (5g default), not a slider (numbers
  use steppers, controller rule); a binding beats the "keep my professions' materials" default;
  the bank alt's tags ignore bindings; delivery follows the profession (operator, same day:
  "get the materials to the friend that actually has the profession rather than their alt for
  the AH"): hellos carry every character's crafting professions, `Routes.Crafter` picks the
  bound player or the character of theirs that has the profession, and the "To their alt"
  toggle of the first draft is gone; the real recipient is always shown. Default scope: all
  the account's characters on the realm + faction. Not built: a slider widget, a never-mail
  list, typed names in the friends window (candidates only).

## 7. State right now

- alpha5's in-game check passed (DISCOVERY-SESSION-2.md "Results of the alpha5 run");
  the one bug it showed (`PadKey.Check` erroring while idle) is fixed in v0.2.0.
- Tags so far: v0.2.0 (Phase 1), v0.3.0 (settings), v0.4.0 (sending), v0.5.0 (bank alt
  view), v0.5.1 (window refreshes after sending), v0.6.0, v0.7.0 (2026-10-14), v0.8.0
  (decision rule v2, 2026-10-20), v0.9.0 (CurseForge feedback: reagent bag, mailbox-only
  glow, 2026-10-22; its upload and v0.8.0's failed on the then-dead `disenchantry`
  relation), v0.9.1 (relation dropped; the first file on CurseForge since v0.7.0), v0.10.0
  (Siz DisenchantValue as the disenchant source, 2026-10-21), v0.11.0 (profession materials
  kept, 2026-10-22), v0.12.0 (description refresh, 2026-10-24), **v0.13.0** (bindings: a
  profession's materials to a friend with delivery by profession; Disenchantry as a
  disenchant source through the ported era tables; `disenchantry` relation restored,
  2026-10-26), **v0.14.0** (UX pass: one task per window, windows fit their content; Send
  on the Inbox says to open the Send Mail tab and the window follows; PR #33, 2026-11-06),
  **v0.15.0** (the stale-prices nudge: `Stale.lua`, the "!" on the Mailworthy button past 3
  days, peers' scan days over the addon messages; PR #34, 2026-11-06). **CurseForge has
  v0.15.0 as its latest file** (release run 42242514018: "Uploading
  Mailworthy-v0.15.0-forever.zip (1.60.1 release) ... Success!"); its project description
  is `media/curseforge-description.html` as of PR #30 (pasted by the operator).
- Confirmed in game: the `/mw scan` math (v0.2.0, by hand), settings with mouse and
  controller and after `/reload`, one-press sending with no money / COD, the window
  lists, row locks, minimap button (v0.4.0; operator 2026-10-14).
- Phase 5 (release clean-up) built: the self-test is gone, `/mw report` replaces it.
  Pending: the Phase 4c check and a v1.0 spot check on one build
  (DISCOVERY-SESSION-2.md "v1.0 check"), then tag `v1.0.0` when the operator says so.
- Still open: AH cut (needs a sale mail; the invoice reader in `Report.lua` logs it),
  disenchant prices for green items (Siz DisenchantValue, or the era tables with
  Disenchantry: see either in game), ForeverMail compatibility (replaces the mailbox
  window), the in-game checks of bindings and of the Disenchantry value (item 7 below), of
  the UX pass (item 8) and of the stale-prices nudge (item 9), and README "Beta unknowns".

## 8. What's left (in order)

1. Phases 1-5 are built (see PLAN "Phases" and the module table above).
2. **Run the v1.0 check** with the operator (DISCOVERY-SESSION-2.md "v1.0 check"); fix
   what fails in its own PR first.
3. **Tag `v1.0.0`** when the operator says so.
4. In-game check of the 2026-10-21 feedback build: a white item in the reagent bag shows in
   `/mw scan` and the window and gets mailed; Alt+click / L3 lock it; the lock glow is gone
   away from the mailbox except a 3 s flash on a new lock, back at one, and the settings
   button turns it on everywhere.
5. After 1.0: an in-game check of decision rule v2 (`/mw scan` after an Auctionator scan: the
   "(3-day median ...)" and "market: ..." workings, "launch day N", a B item on the bank alt);
   a tailor's cloth (or any crafter's material) shown as "KEEP ... your Tailoring needs it" in
   `/mw scan` and the window, and mailed again with the setting off;
   the AH cut from a sale mail (`[invoice]` lines in `/mw report`), a green item's DE verdict
   with Siz DisenchantValue installed (`/mw scan` "disenchant Xc each" against its tooltip,
   `/mw report` "Siz DisenchantValue installed"), ForeverMail compatibility.
6. README "Beta unknowns" table and PLAN's "Still open" list kept current after each report.
7. In-game check of bindings (2026-10-26): `/mw friends` lists guild members with "online" and
   professions (C_Club on Forever) and party members; a binding's materials show "to <first
   name>" in the window and arrive with subject "Mailworthy 1/1: Enchanting materials";
   Skip once / Remove; two Mailworthy users see each other in `/mw report` ("mailworthy peer"
   with their other crafters) and a binding for a profession only an alt of theirs has shows
   "delivered to their ... character" and arrives there.
8. In-game check of the UX pass (2026-11-06), mouse and controller: the mailbox window's
   height follows its rows (no gaps, nothing overlapping on the Mailing heading line), the
   bindings block appears only with a binding; opened on the Inbox, Send reads "Open the Send
   Mail tab" and the window follows to Send Mail, where Send works; settings open on the picker
   with no bank alt, Change... / Back, and the D-pad reaches every button in both views; the
   friends window's list and add views, Back from step 2 and step 1; long button texts fit
   ("Keep my professions' materials: on (Tailoring, Enchanting)").
9. In-game check of the stale-prices nudge (2026-11-06): with two guild members running
   Mailworthy, one scans the AH and the other hasn't for over 3 days (a week for the "stay in your bags" wording): the stale one's
   `/mw report` shows "price stamp: <name> scanned 0 day(s) ago", the Mailworthy button shows
   "!", the window's top line names the fresh player, and one chat line appears at the mailbox.
   After their own scan, all of it is gone. `/mw report` "price freshness" reads a plausible age.
