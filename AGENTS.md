# Mailworthy agent rules

Mailworthy is a WoW Forever addon (`## Interface: 16001`). Start with
`docs/HANDOFF.md` (state, decisions, pitfalls, what's left), then `docs/PLAN.md`
(design) and `docs/FOREVER-UI-NOTES.md` (Blizzard source findings, taint rules).

## Safety (STRICT)

- Mail goes **only** to the recipients shown in the preview, and only after the
  player presses Send: the saved bank alt, and, for a binding (`Routes.lua`), the
  bound player, or the character of theirs that has the bound profession as their
  own Mailworthy reported it (never their bank alt for the AH). A guild template rule
  (`Guild.lua`) is a binding only once the player turned the guild rules on, only when its
  author is a guild master or officer in their own roster (any member may pass a copy on), and
  only to a player in that roster (operator, 2026-11-07). With **Return to sender**
  (`Returns.lua`) on for the visit, also the player who mailed this character an item, for
  what the mail ledger shows they mailed it and it hasn't mailed back (whole stacks; no
  system, COD or returned mail), whatever its price, and only when that player is shown in
  the preview like any recipient, a "To:" line and the "back to <name>" chip on each row
  (operator, 2026-11-08: "any new recipient should be shown even if its a return to
  sender"). Never attach money.
  Never mail a locked item.
- Never mail an item an active quest's objective names, quest item or not (operator,
  2026-11-08). Never mail a conjured item (a Healthstone, a mana gem, a mage's food and water;
  `Conjured.lua`; operator, 2026-11-10: "should always be keep as they are ephemeral items"). Without a bank alt (optional), or with it skipped for the visit, its share
  stays in the bags; only bindings mail.
- A binding or a return never overrides a hard keep (locked, soulbound, quest, conjured, in use, tool); at or
  above its price cap the normal rule applies and the item goes to the bank alt.
- Re-check each slot right before attaching it; skip anything that changed.
- Without Auctionator (no price source), the only items mailed are unlocked, tradeable white
  (common) items and the staple trade goods (`Valuation.STAPLES`, whatever their quality)
  (operator, 2026-11-08: "Whites + staples + recipes"; recipes only to their profession's
  binding). With Auctionator (or TSM), an item without an auction price, or whose only price
  is past the age limit, goes to the **bank alt**, never to a class binding (operator,
  2026-11-08: "going to the bank alt on no data is better than holding on the main";
  "Yes, gear goes too"; "Stale prices go too"; replaces "an item without a price stays in
  the bags" and its launch-days 0-13 exception for white trade goods). Grey junk stays, an
  item whose price call failed stays, and the hard keeps above come first.
  A profession binding mails its materials and its profession's recipes to the bound player
  whatever their price (operator, 2026-11-08: "keep as is"; recipes: "recipes should go to
  their respective profession mappings"), under its price cap when there is a price; a class
  binding follows the price rules above.

## Never write into Blizzard's controller UI (STRICT)

Every one of these tainted gamepad input in game (jumping, targeting, item use
blocked until /reload):

- no prompted bindings on Blizzard footers, no `GamepadSharedUtility` footers of
  our own, no `FrameControlsManager` registration, no `ShowUIPanel` for our frames;
- no entries in the gamepad "More" menu (`Menu.ModifyMenu("MORE_CONTEXT_ACTIONS")`);
- no Lua fields written on Blizzard frames, no `smartNavigation*` / `OnSmartNav*` /
  `buttonContext` keys on ours;
- no `CreateFrame` while a gamepad panel is open: create every frame at login
  (on UIParent, then `SetParent`);
- never switch mail tabs from addon code (`MailFrameTab_OnClick`);
- **never call `SetFocus`** (it crashed the gamepad UI in LedgerLink).

Allowed: our own override bindings on our own frame (`PadKey.lua`, out of combat,
cleared on focus loss and at `PLAYER_REGEN_DISABLED`), `hooksecurefunc` post-hooks,
textures / font strings on Blizzard frames kept in our own tables, read-only
`FrameControlsManager:GetActiveFrame()` / `SmartNavigation:GetCurrentButton()`.
`spec/no_gamepad_taint_spec.lua` guards this; keep it passing.

## Input (STRICT)

- **Keyboard/mouse first**, controller too: every feature works with both.
- Controller navigation in our windows goes through `Nav.lua` + `PadKey.lua`
  (Mailworthy's own highlight and bindings), not Blizzard's smart navigation.
- No right-click-only, modifier-only (Alt+click has the controller's L3 twin),
  drag or hover-only actions; no required typing.
- Every piece that touches Blizzard UI has a `/mw feature` switch.
- CI's `controller` job is the controller gate: `spec/dpad_reach_spec.lua` walks the D-pad over
  every view of every window (each button reachable from the top-left one, a way back from each)
  and fails for a window with no walk; with the padkey, nav, ux_views and no_gamepad_taint specs.
  A new window or view adds its walk there; never loosen it to make a change pass.

## Critical path (STRICT)

`spec/critical_path_spec.lua` is the shipping gate: a mailbox visit with a realistic
bag, by mouse and by controller, with and without Auctionator, with a binding, with a guild
template (on and off), with Return to sender (on a main and on the bank alt), and on
an older build's SavedVariables; every mail checked against the Safety rules above, and
what was previewed must be exactly what was sent. CI runs it as its own job,
`critical-path`, which main's branch protection requires (operator, 2026-11-07); `release.yml`
publishes a tag only after all of CI passes.

- Never loosen, skip or delete one of its assertions to make a change pass; fix the
  change. If the operator changes a rule on purpose, update the test in the same PR
  and say so in the PR description.
- A new way to mail (a recipient kind, a send path, a SavedVariables migration) adds
  its case here. Keep it to outcomes: thresholds and prices belong in other specs.

## Working rules

- Branches and PRs only; never push to `main`, never force-push.
- The operator merges PRs without saying so: gate every push to a PR branch on
  `gh pr view N --json state --jq .state` being `OPEN`; if merged, branch from
  `origin/main` and open a new PR.
- Tag only when the operator says so ("tag vX.Y.Z"). Every tag publishes to
  CurseForge (project 1743661); plain `vX.Y.Z` = release file. Watch the release run
  and report the CurseForge upload line.
- Never invent WoW API functions: read Blizzard's Forever source
  (Ketho/wow-ui-source-forever) first; wrap anything unverified in `pcall` / nil
  checks and list it under "Beta unknowns" in README.md.
- In-game checks go into one copyable report (`/mw report`), not
  lists of `/dump` lines. Ask for an in-game test only when research shows the fix
  is real.
- Mailworthy files share names with LedgerLink's (`media/logo-400.png`, ...): link
  them by full path in messages.
- Before every push: `eval "$(luarocks --lua-version=5.1 path)"`, then
  `busted --lua=luajit` and `luacheck .`.
- **Codex review before every PR** (operator, 2026-11-07): before opening a PR, have Codex
  review the branch's diff against `origin/main` (Claude Code: the `codex:codex-rescue`
  subagent, review only, no edits), check each finding against the code, fix the real ones
  with a spec each, and list in the PR description what Codex found and what was fixed or why
  not. Commits pushed to an open PR that change behaviour get the same review.
  **Not for a docs-only PR** (operator, 2026-11-09: "theres no reason to codex review a docs
  only pr"): a PR that changes no Lua, spec, `.toc` / packaging or CI workflow (markdown,
  prototype sheets and images under `media/`) skips it; its description says "docs only".
