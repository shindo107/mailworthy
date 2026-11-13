# Mailworthy

A WoW Forever addon. Open a mailbox, press the **Mailworthy** button, and
every bag item worth more on the auction house (after fees) or disenchanted
than at the vendor goes to your bank alt. The rest stays in your bags to vendor.

- **Prices** come from Auctionator (optional, recommended) or, without it, from
  TradeSkillMaster (its AuctionDB minimum buyout, capped by its market value; Auctionator
  wins when both are installed). **Disenchant values** of
  green, blue and purple gear come from Siz DisenchantValue (optional; learned from your
  own disenchants) or from the era disenchant tables priced with Auctionator (or TSM), the
  same number Disenchantry's tooltip shows; either addon installed switches the disenchant
  comparison on. Without Auctionator or TSM, Mailworthy mails every unlocked, tradeable white
  (common) item.
- **Preview first:** it shows the recipient, what goes and why, what stays and
  why, and a **Settings** button to fix anything before you press Send.
- **Keyboard/mouse first, controller too:** everything works with keyboard and mouse, and with a gamepad alone.
- **Lock items** you never want mailed: Alt+click (mouse) or L3 / LS (press the left stick) in your bags (controller); the lock follows the item.
- **Pin items** you always want banked: Ctrl+Alt+click (mouse) or R3 / RS (press the right stick) in your bags (controller); Send mails a pinned item to your bank alt every time, from every character.
- **Every bag counts:** backpack, bags 1-4 (profession bags too) and the reagent bag.

## Using it

- **At a mailbox:** click the **Send Mail** tab and the Mailworthy window opens beside it
  (or click **Mailworthy** under the mail window; controller: R1 (RB on an Xbox controller) to the Send Mail tab opens
  it, Triangle (Y) closes and reopens it; Mailworthy's own hints draw your controller's buttons). Opened on the Inbox, its Send button is greyed out and says "Click Send Mail". The window shows who gets the mail, what goes and why,
  what stays and why, and the total gain. **Send** mails it all in one press, 12 stacks
  per mail; while it runs the button is **Stop** (the mail already on its way arrives, the rest
  stays). When it is done the window and chat say what went, to whom, for how much, and what
  stayed. If you can't pay the postage, nothing is sent and Send shows the postage instead. Pressing an item locks it, so it stays. **Skip once** beside your bank alt keeps
  its share in the bags for this visit (bindings still go). Hovering an item says what the
  window does with it, or why it stays.
- **Return to sender:** a toggle in the window, on every character (bank alt too). Pressed,
  what other characters mailed you joins the Mailing list to go back to them (whole stacks, up
  to what they sent and you haven't mailed back; never a locked or quest item); pressed again,
  the list is back to normal. It is lit while on and turns itself off when the mailbox closes.
  It reads the mail ledger, so it knows what you took from the mailbox since that came in.
  `/mw feature returnToSender off` removes it.
- **No bank alt needed:** without one, the window still opens and mails your bindings;
  what's worth selling stays in your bags (listed under Staying, e.g. "Auction +5s: no bank
  alt") and your bags carry the AH / B / DE / V tags. Pick one any time with **Choose...** in
  the settings.
- **Quests come first:** an item an active quest asks for (Crisp Spider Meat for Redridge
  Goulash, not only "quest items") stays in your bags, is never tagged for the vendor, and
  its tooltip names the quest.
- **Conjured items stay:** a Healthstone, a mana gem, a mage's food and water are never mailed
  and never listed.
- **Lock items** you never want mailed: Alt+click (mouse), L3 / LS in your bags (controller),
  or press the item in the Mailworthy window. Locked items glow blue while the Mailworthy
  window is open at the mailbox (a setting keeps the glow on everywhere), and hovering one
  says why; elsewhere a new lock glows for a moment so you see it took. Locks stay
  wherever the item moves. **Locked items** (`/mw locks`, or Settings > More) lists them with
  how many your bags hold and an Unlock button each, also for an item you banked or used up.
- **Pin items** you always want banked: Ctrl+Alt+click (mouse) or R3 / RS in your bags
  (controller), and again to unpin. A pinned item goes to your bank alt every time you press
  Send, whatever the auction house or your professions say, and carries the **B** tag on every
  character (pins are saved for the account, so the bank alt knows them). A pin never beats a
  lock or any other hard keep, and a pinned item goes to the bank alt, never to a binding's
  friend. A pin overrides the price rules: a pinned green, or grey junk, goes even without
  Auctionator. Pinned items glow green in your bags (like the lock's blue, while the Mailworthy
  window is open, or always with the glow setting; a new pin flashes), and their **B** tag,
  their "Pinned" chip and their tooltip line are the same green. `/mw pins` lists them.
- **On your bank alt:** bag slots carry **AH / B / DE / V** tags (list it, bank it for a
  later phase or for your own crafting, disenchant it, vendor it now) recomputed with that
  character's own prices;
  tooltips show today's verdict and why the item was mailed, or why it stays (a profession
  that still needs it, a quest, no price yet). The Mailworthy button opens the window there
  too: what it sells stays, and bindings and Return to sender mail from it; its **Summary...**
  button (or `/mw summary`) sums it up (`/mw feature bankAltMail off`: the button opens only
  the summary, as before).
- **Bank alt on a second WoW account** (played on another monitor): mail crosses accounts,
  saved settings don't. On your main, press **Change...** in `/mw` and type the alt's name under
  "Or type a name" (press **Use name** twice: Mailworthy hasn't seen that character). On the alt's account
  install Auctionator and Mailworthy, run an Auctionator scan there, open `/mw` and press
  **This character is my bank alt**: the tags, tooltips and summary come on. Each account
  keeps its own price scans, and the "Mailed for" tooltip line stays on the sending account.
- **No math needed:** prices are Auctionator's last scan, held down by the 3-day median
  when the last scan is a spike (one empty market can't flip a verdict), half the deposit counts (the game refunds it on a sale), a flooded
  market is valued at its floor, an item with no auction price yet goes to the bank alt to wait
  for one (grey junk stays for the vendor), recipes go to the friend bound to their
  profession, and the rule knows the realm's launch day: before the first raids enchanting materials, herbs
  and elementals are tagged **B** (bank them, they sell higher later), and later the
  minimum gain grows with the gold supply. Details: `docs/PLAN.md` "Decision rule".
- **After sending:** your main's bags tag what's left for the vendor with **V** (grey
  junk too) for the rest of the session. Lock an item to keep it and its V goes.
- **Bag addons:** the tags and the lock glow also show in **Baganator**, **Bagnon**,
  **ArkInventory** and **BetterBags** (the most-downloaded bag addons with a Forever build), with the
  legend under their bag window. In Baganator the tag takes an icon corner like its other
  widgets ("Mailworthy tags and lock glow" in its Icons settings: top left by default; move it,
  or take it out of every corner to turn Mailworthy off there). Another
  character's bags and the bank get no tags (the bank's locked items still glow).
  `/mw feature baganatorTags off` (or `bagnonTags`, `arkInventoryTags`, `betterBagsTags`) turns one off.
- **Send a profession's materials to a friend** (`/mw friends`, or the settings'
  **Friends...** button): pick a guild member, party member or one of your own
  characters (online players first; their professions are shown and suggested), then the
  profession. From then on that profession's primary materials (dust, essences and shards for
  an enchanter, plus green and blue weapons and armor for them to disenchant; cloth for a
  tailor, herbs for an alchemist, metal and stone for a blacksmith, ...) are mailed to them,
  every time, for all your
  characters on that realm and faction (or this character only). Each binding has a
  **price cap**, checked against the item's auction price each (10s for a new binding; the
  **-** and **+** buttons step it from 50c to 100g, or to no cap): anything at or above it
  follows your normal rules, so what the market wants goes to your bank alt instead. An
  **Enchanting** binding also has a **Gear** button: "Gear: all green and blue" sends every
  green and blue piece, "Gear: only when disenchanting pays more" sends a piece only when it
  disenchants for more than the auction house would net and more than a vendor pays (a piece
  with no disenchant value still goes; dust, essences, shards and recipes always go). The
  Mailworthy window lists the bindings with **Skip once** (this mailbox
  visit only) and **Remove**. Locked items still stay. If the friend runs Mailworthy too,
  it tells yours which of their characters craft what (addon messages to guild and group;
  `/mw feature comms off` stops them), and the mail goes to **whichever of their characters
  has the profession**: the friend when they do, their crafter alt when they don't, and the
  friend when nothing is known. Never their bank alt. The window names the recipient.
- **A crafter of your own:** when your bags hold what another character of yours crafts with (cloth
  for your tailor, green gear for your enchanter) and no binding takes it, the mailbox window offers
  one: "Sadie Ember is your enchanter (skill 140). Send them the 3 items that disenchant instead?"
  **Bind** makes an ordinary binding, and the list shows the items going to them before you press
  Send; **Not for Sadie** stops the offer for that character and profession. Never your bank alt, and
  never a profession this character has itself. `/mw feature crafterOffer off` turns it off.
- **Who runs Mailworthy:** wherever Mailworthy's windows name a player (the friends and guild
  windows, the "To:" lines at the mailbox, the ledger, the bank alt picker), the Mailworthy icon
  follows the name when that player runs Mailworthy too (their Mailworthy said hello, one of
  their characters it listed, or one of your own characters); the window's bottom line says
  what the icon means. `/mw feature peerMark off` hides it.
- **Update nudge:** when a player in your guild or group runs a newer Mailworthy, one chat line
  says so ("Mailworthy v0.31.0 is out (Bob has it); you have v0.30.0. Update from CurseForge."),
  once a session, and a line at the bottom of the Mailworthy window and of the settings says the
  same until you update. Each Mailworthy says its version after its hello (from this release on;
  older ones keep working and just don't say it). Only versions heard straight from a player
  count: nothing is passed on. `/mw feature versionNotice off` hides it.
- **Tags in Auctionator too:** with Auctionator installed, the same AH / B / DE / V tags the
  bags show appear on the item icons of Auctionator's Selling tab (its bag list and the item
  being posted), on the characters whose bags show them. `/mw feature auctionatorTags off`
  hides them.
- **Class-only items to a friend of that class:** a scroll or piece of gear whose tooltip says
  "Classes: Mage" can go to your mage friend. In `/mw friends`, pick the player; when their
  class is known (party, guild, your own characters), "Mage items" is the first choice. It
  takes only what your own class can't use, with the same price cap and Skip once.
- **Guild template** (`/mw guild`, or **Guild...** in Mailworthy settings): the guild master
  (or an officer, the rank right below) presses **Add a rule...** and sets one rule per
  profession: "Enchanting to Bob", "Alchemy (herbs) to Ann", "Tailoring (cloth) to me", each
  with a price cap (and, for the Enchanting rule, the same **Gear** button as a binding of your
  own), then **Publish to guild**. Every guild member running Mailworthy gets a
  chat line and the Guild window shows "Guild template from ..." with its rules; nothing is
  mailed until they press **Use guild rules** once. Later updates then apply on their own
  (with a chat line). **One press turns the guild rules off** again: "Guild rules: on" in the
  Guild window, or on the Bindings heading of the Mailworthy window. Like a binding, a rule
  takes only the profession's primary materials. When two rules take the same material
  (metal and stone: Blacksmithing and Engineering), it goes to whichever recipient has the lower
  skill in their profession, so both keep levelling. Your own bindings come
  first, and a rule for a profession you have yourself is left out (a tailor keeps their
  cloth). Skip once works on guild rules too. Any guildmate running Mailworthy passes a copy on
  to whoever logs in (hidden addon messages), so the guild master doesn't need to be online; a
  copy is taken only when its author is the guild master or an officer in your own roster, and
  only its rules for guild members. `/mw feature guildTemplate off` turns all of it off.
- **Stale auction prices** get a nudge at the mailbox: once your Auctionator prices are over
  3 days old, the Mailworthy button gets a **!** and the window says so (past 7 days
  Mailworthy stops trusting them, and those items go to the bank alt to wait for a fresh price,
  like items with no price yet). When another Mailworthy user in
  your guild or group has scanned in the last 2 days, it says who, and one chat line tells
  you at the mailbox. Only the day of each player's scan is shared (with the addon messages
  above), never prices, and it never changes what gets mailed. `/mw feature staleNudge off`
  hides it.
- **Worth a mailbox trip**: away from a mailbox, when you have 4 or fewer bag slots left and
  something in your bags would be mailed, one chat line a session says so ("2 bag slots left.
  14 items are worth mailing: +2g 10s more than vendoring."), and the minimap button's tooltip
  carries "Worth mailing now: 14 items, +2g 10s" while it holds. The count is the one on the
  backpack button (profession bags and the reagent bag don't count). Your bags are only
  valued at or under 4 free slots, out of combat, when something in them changed. Without a bank alt it speaks up only when a
  binding would mail. Nothing is sent. `/mw feature tripNudge off` hides it.
- **Mail ledger** (`/mw ledger`, Settings > Mail ledger, Friends): Mailworthy logs every mail
  your characters send (its own and Blizzard's Send button) and every item or gold you take
  out of the mailbox: date, both names, subject, each item with its count and value. **Export
  log...** puts all of it in a copy box, so you can show where items went. From the same log,
  when another player mails you more than you've mailed them back, you see it: a chat line
  when you take it ("Received 20 Linen Cloth (10s) from Bob. You've received 10s more from Bob
  than you've sent back."), a line at the top of the Mailworthy window, the ledger window and
  their binding in Friends. Pay back by mail, materials or gold; it counts when it goes.
  **Mark paid** (two presses) clears it if you settled another way. Only your own side ever
  shows: nobody is listed as owing you. Values are taken when the mail is sent: your prices
  for what you send; for what you receive, when the sender runs Mailworthy too, whichever of
  the two players had the more recent auction scan when the mail went (theirs counts at most
  3x your own price), else your price when you take it. When that value differs from the
  sender's, the receiver's Mailworthy tells theirs (as soon as the two are online in the same
  guild or group), so both see the same number. The export shows each value's scan age. Your own
  characters, the auction house, system mail and COD mail don't count; a returned mail takes
  back what you sent. `/mw feature ledger off` stops all of it.
- Profession tools (fishing poles, Mining Pick, Blacksmith Hammer, Skinning Knife, ...)
  always stay. Gold is never attached.
- **Your professions' materials stay** (on by default; the settings' "Keep my professions'
  materials" turns it off, and then everything goes to the bank alt like any other item):
  cloth for a tailor or first-aider, leather for a leatherworker, metal and stone for a
  blacksmith or engineer (plus parts, explosives and devices), herbs for an alchemist, dust,
  essences and shards for an enchanter, meat and fish for a cook. Each profession also keeps
  the other materials it **levels** with: a blacksmith's gems and lower elementals, an
  engineer's cloth, a cook's tea herbs, a first-aider's potion herbs, venom sacs and
  Tourniquet leather (Forever's First Aid makes healing potions). Valuables a profession only
  uses at skill 300 (Essence of Water, Righteous Orb, Star Ruby, Arcanite, ...) still go to
  the auction house; lock them to keep them. Gathering professions keep nothing: what they
  gather is what gets sold.
- **Materials you've levelled past are mailed again.** First Aid keeps each cloth until the
  next bandage is learnable (Linen Cloth until 80, Wool until 150, ...). Everything else is
  kept until every recipe that uses it, directly or through a part the profession makes
  (bolts, cured hides, grinding stones, blasting powders), has gone grey. That comes from all
  of Forever's recipes, read one by one (Forever reuses older materials well past where
  Classic moved on: a blacksmith keeps Iron Bar for good, for the Iron Buckle in a 310 belt).
  Alchemy herbs that still make level-60 potions (Swiftthistle, Stranglekelp, Goldthorn,
  Khadgar's Whisker, Arthas' Tears, Purple Lotus, Wintersbite, plus Oily Blackmouth) stay for
  good, and so does anything used at 300. **Leather** past its own recipes stays while
  converting it up (4 Light Leather make a Medium) is worth more at the auction house than
  selling it, and goes when selling pays. The window says "your First Aid needs it (until
  skill 80)" or "convert it: 4 make a Medium Leather (pays more)". The tables:
  `Mailworthy/TierData.lua` (built from `tools/tiers/data.py`). The same goes for
  **bindings**: once your friend's skill in the bound profession is past a material, it goes
  to your bank alt instead (or to another binding that still needs it). Their skill comes
  from their Mailworthy (sent with the addon messages above, again after each skill-up that
  passes a material), the guild roster (Blacksmithing, Tailoring, ... but not First Aid or
  Cooking), or your own character's last login. When nothing is known, the binding takes
  everything, as before. `/mw feature tiers off` keeps every material again.
- **Tier check** (the tiers above come from a beta-client snapshot, so they are checked against
  the live realm): when you open one of your own crafting professions, Mailworthy reads the
  colour of every recipe you know (orange / yellow / green / grey) and which materials it uses.
  A material the table calls done that a recipe above grey still uses (directly, or through a
  part like a bolt of cloth or a grinding stone) is listed in `/mw report` ("tier check: Linen
  Cloth still used by Soft-soled Linen Boots (yellow) at skill 120, table says done at 115"),
  and it stays in your bags until the window shows that recipe grey. First Aid cloth is not
  checked (it is done when the next bandage can be learned, not when the old one turns grey).
  Read only: nothing is clicked or changed in the profession window. The same lines are saved in
  Mailworthy's SavedVariables (`MailworthyDB.tierCheck`, written at `/reload` or logout), so
  running `/mw report` is optional. `/mw feature tierCheck off`.
- **Sell what I gather** (off by default, a setting turns it on): for a gatherer who also
  crafts with the same materials (a miner-blacksmith, an herbalist-alchemist, a
  skinner-leatherworker, a fisher-cook), what the gathering profession brings in is mailed
  to be sold instead of kept for the craft. Mining counts all metal and stone (ore, stone
  and the bars its smelting makes).

```
/mw                   settings: bank alt (pick, type, or "This character is my bank alt"), minimum gain, disenchant, listing length, tags, lock glow, profession materials, friends, guild, minimap button
/mw scan              what Mailworthy would mail and why, with the numbers (sends nothing)
/mw friends           send a profession's materials to a guild member, party member or one of your characters (bindings)
/mw guild             your guild's template: guild rules on / off; the guild master and officers edit and publish it
/mw summary           on your bank alt: what to list, disenchant or vendor
/mw locks             this character's locked items, each with Unlock (also for one no longer in your bags)
/mw pins              the account's pinned items (always mailed to the bank alt)
/mw report            a copyable report for bug reports
/mw feature <name> on|off   turn one piece off to isolate a problem (then /reload); /mw feature lists them
/mw help              all commands
```

The design, decision rule and phases are in [docs/PLAN.md](docs/PLAN.md).

## Guild contributions and the API for other addons

Mailworthy counts what each of your characters mails because of your **guild's template**
(the guild rules above), so Raid Ledger's guild contributions widget can thank the big givers.
Only a guild rule's mail counts: your own bindings, the bank alt, Return to sender and mail
sent with Blizzard's Send button never do, and neither does mail to your own characters (an alt
who is the guild's crafter included). Items count as **stack units** (20 Strange Dust in one mail
= 20), per sending character, per UTC day for the last 35 days, plus an all-time total since the
character's first counted mail. Nothing sent before this version is counted. The mail log
marks those mails "guild rule: Enchanting" in Export log. There is no switch.

Each character also tells its **guild** (only the guild) its own counts, right after its hello and
when you close the mailbox after mailing something because of the template, so any guildmate who
exports with LedgerLink carries everyone's (operator, 2026-11-08: "Yes, share in hellos"). Only the
counts and since when go; never the items or who got them. A guildmate's counts are kept
(`MailworthyDB.guildHeard`) while they're on your roster and heard from in the last 60 days, are
checked like every hello, and change nothing Mailworthy mails. Your own counts are in
`MailworthyDB.guildGiven`.

**`MailworthyAPI.v1.GetGuildExport(guildName)`** is a read-only global for other addons
(LedgerLink calls it when it builds its export string for Raid Ledger). `guildName` is optional
(default: your current guild; at logout pass the name you cached). It never errors, never writes
anything, returns new tables every call (never Mailworthy's own), and returns `nil` outside a
guild or when there is nothing to say. Otherwise, exactly the shape Raid Ledger's contract
defines (story ROK-2148; a part with nothing in it is left out):

```lua
{
  generatedAt = <GetServerTime()>,
  template = {                         -- the guild template you hold (no price caps, no on/off choice)
    rev = <revision, the author's server time>, author = "<Guild Master>",
    rules = { { professionSkillLineId = 333, recipientName = "<Name>" }, ... },   -- at most 8
  },
  peers = { { name = "<Name>", lastSeenAt = <server time> }, ... },
    -- Mailworthy users on this guild's roster heard from in the last 60 days, newest first, at most 1000
  givers = { { characterName = "<Name>", itemsAllTime = <n>, countingSince = <server time>,
               days = { { day = <floor(server time / 86400)>, items = <n> }, ... },
               asOf = <server time those counts were taken> }, ... },
    -- your characters with anything counted for this guild (asOf = generatedAt), then guildmates whose
    -- Mailworthy told yours theirs (asOf = when they did; only while on the roster); yours first, then
    -- theirs, each most first; at most 200; days ascending, the last 35 UTC days, non-zero only
}
```

Names are as Mailworthy holds them ("First Surname", no realm) and at most 48 bytes; a longer
one is left out, never shortened. Nothing else leaves: no gold, no item names, no mail log, no
bindings, no bag contents. `/mw report` has "guild contributions" and "guild export" lines (counts
only: what is counted, and what the API returns right now).

## Beta unknowns (check in game)

Everything unverified is wrapped defensively (pcall / nil checks). Results of
each in-game round are in [docs/DISCOVERY-SESSION-2.md](docs/DISCOVERY-SESSION-2.md).

| API / behaviour | What to check | Status |
|---|---|---|
| Bank pins (`Pins.lua`): Ctrl+Alt+click on a bag item reaches the `HandleModifiedItemClick` post-hook (the lock's hook, which Alt alone reaches); with Ctrl held Blizzard's dress-up case may also run for gear. Controller: `PADRSTICK` (R3 / RS) bound in the bags with `SetOverrideBindingClick`, like L3; assumed free there, not measured | Ctrl+Alt+click an item: chat says "Bank pin on ...", the slot shows **B**, the Mailworthy window lists it for the bank alt; again unpins. With a controller: R3 on a bag item does the same, and nothing else happens (no camera or target change); `/mw feature padPin off` gives R3 back | open |
| Window and controller (QoL pass B, 2026-11-09): two-way pagers ("<" beside "2/5  >") in the mail window, the ledger and the friends window, placed by anchor to the page button; D-pad Up from the top row to Send, Down from the bottom row to the top (`Nav.SetWrap`); Choose bank alt... on the To line | with a controller at the mailbox: one Up press from the first button lands on Send, Down returns; a list longer than a page shows "<" left of "1/2  >" without overlapping the heading, and both turn the page; with no bank alt, Choose bank alt... opens the picker and picking one fills the list; changing "at least" in Settings moves items between Mailing and Staying while Settings is open | open (2026-11-09) |
| Send path (QoL pass, 2026-11-09): `GetMoney()` and `GetSendMailPrice()` (both in Forever's `MailFrame.lua`, its own Send check), the `PLAYER_MONEY` event (standard, not found in Forever's source; registered in `pcall`, without it the postage note updates at the next redraw), `PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)` (the kit `MailFrame.lua` plays; `pcall`) | at a mailbox: Send, then Stop mid-run: the mail on its way arrives, the rest stays, the note says "Stopped after 1 of N"; a full send ends with "Sent N mails to ...: +gain" in the window and one chat line, and one click sound; with less money than the postage Send reads "Postage: ..." greyed out, and looting or selling a little brings it back | open (2026-11-09) |
| Trip line (2026-11-09): `C_Container.GetContainerNumFreeSlots(bag)` -> `numFreeSlots, bagFamily` (in Forever's `ContainerDocumentation.lua`; pcall'd, one bag without an answer = nothing scanned or said) summed over bags 0..`NUM_BAG_SLOTS` where `bagFamily` is 0, on `BAG_UPDATE_DELAYED` (and `PLAYER_REGEN_ENABLED`). Assumed, not measured: general bags report family 0 and a profession bag a non-zero one; a bag change always follows the loot that fills the bags; the scan at login has item data ready (a scan is repeated only when the bags, settings or bindings change, not when prices or item data arrive later) | away from a mailbox, fill the bags to 4 free slots (the backpack button's number) with something Mailworthy would mail: one chat line "N bag slots left. M items are worth mailing: +X more than vendoring.", the same N as the backpack button; hover the minimap button: "Worth mailing now: ..."; no second chat line until `/reload`; `/mw report` log lines `trip` show each scan. Off: `/mw feature tripNudge off` | open (2026-11-09) |
| Locked items window (QoL pass D, 2026-11-09; `LocksUI.lua`): no new API (`C_Container.GetContainerNumSlots` / `GetContainerItemInfo` for the "xN in your bags" counts, as the bag scan uses; `BAG_UPDATE_DELAYED` redraws it; `FontString:SetWordWrap(false)` on the rows, nil-checked and pcall'd) | `/mw locks` and Settings > More > "Locked items (N)...": the window opens (beside Settings from there), a saved item link draws as the item's coloured name in the row and a long name stays on one line, clear of Unlock; the count follows the bags; Unlock removes the lock (the blue glow goes, the mail list redraws) for an item in the bags and for one that isn't; the row stays as "unlocked" with Lock until the window closes; D-pad reaches every Unlock, the pager and Done, Cross presses, Circle closes; the Settings button's count follows | **not seen in game** (specs only) |
| Row tooltips from the controller (2026-11-09): the D-pad highlight on an item row of the Mailworthy window calls `GameTooltip:SetOwner` / `SetBagItem` / `AddLine` / `Show` from addon code (as the mouse path always has), `Hide` when it moves off; `NumLines` and `SetHyperlink(link)` (pcall'd) when the row's item already left its bag slot mid-send | with a controller at the mailbox: D-pad onto a Mailing row shows the item tooltip beside the window, ending "Press to lock: ..."; it goes when the highlight reaches Send; jumping, targeting and item use still work after closing the mailbox; `/mw report` "N row tooltip(s) shown" above 0. Off: `/mw feature tooltipLines off` | open (2026-11-09) |
| Conjured items (2026-11-10; `Conjured.lua`): the item IDs are Classic's (checked against Wowhead Classic); for anything else, `C_TooltipInfo.GetItemByID` (in Forever's `TooltipInfoDocumentation.lua`; pcall'd) and a line whose text is `ITEM_CONJURED` (a global string, not in Forever's source mirror; nil-checked, the English "Conjured Item" otherwise). Assumed: Forever's healthstones, mana gems and conjured food keep Classic's item IDs, and its tooltip data carries the "Conjured Item" line as its own line | a warlock with a Healthstone (or a mage with conjured water) at the mailbox: the item is on neither list of the Mailworthy window; `/mw report` line "conjured items (never mailed): ITEM_CONJURED = "Conjured Item"; in your bags: [Minor Healthstone] (item ID)" ("no ITEM_CONJURED text" = the global string is missing; "(tooltip)" = found by its tooltip line); `C_Item.IsItemDataCachedByID` (Forever's `ItemDocumentation.lua`; pcall'd, without it every scan reads every tooltip) | open (2026-11-10) |
| `## Interface: 16001` | addon loads without "out of date" | confirmed for LedgerLink (build 1.60.1.70205) |
| Auctionator `API.v1` on Forever | S5 | **confirmed** (Auctionator 340; price, age, exactness, disenchant calls) |
| Real AH prices for bag items | `/mw scan` after an Auctionator scan | **seen** (v0.2.0 scan: Copper Ore 1s 74c, Fishing Pole 9s, all age 0); per unit still to confirm against the tooltip; Mailworthy assumes `GetAuctionPriceByItemLink` is per unit and `GetAuctionAgeByItemLink` is in days (Auctionator's convention; S5 saw age 0) |
| TradeSkillMaster as the price source (2026-11-08, a CurseForge request; TSM 4.15 announces Forever support): `TSM_API.ToItemString(link)` -> "i:ID" (else "i:ID" read from the link), `TSM_API.GetCustomPriceValue("DBMinBuyout" / "DBMarket", itemString)` -> copper or nil + message, `TSM_API.IsCustomPriceValid(source)` to tell "no data" from a source TSM doesn't have (read in TSM 4.x's `Core/API.lua`; every call `pcall`'d, a raise or an unknown source = a failed call). Only used without Auctionator. No price age, exactness or history through the API, so with TSM alone there's no "price too old" keep, no 3-day median, no glut check and no stale-prices nudge | TSM only (Auctionator disabled), after TSM's desktop app has synced: `/mw report` "prices: TradeSkillMaster", `/mw scan` prices match TSM's tooltip "Min Buyout" (or "Market Value" when lower); with both: "prices: Auctionator (TSM installed, not used)". Open: whether Forever's TSM has realm AuctionDB data at all without the desktop app (an empty AuctionDB = every non-white item stays) | open (2026-11-08) |
| Auctionator's history: `Auctionator.Database:GetPriceHistory(key)` rows `{ rawDay, minSeen, maxSeen, available }` and `Auctionator.Utilities.BasicDBKeyFromLink(link)` (not its stable API; guarded, nil = last scan's price only) | `/mw scan` workings show "(3-day median; last scan ...)" or "(last scan; 3-day median ...)" and "market: N listed" | open |
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
| Postage / AH deposit | alpha1 self-test, LedgerLink S8; a player on CurseForge (2026-11-07) | **30c per item**; deposit floor(vendor x 5%) x 1 / 4 / 12 (2h / 8h / 24h), **at least 1s** on live Forever (reported; counted per bag stack until it is known whether it is per auction and the same for every duration) |
| AH cut | an AH sale mail (`GetInboxInvoiceInfo`) | open (5% assumed) |
| Tags and lock glow in Baganator (846, read 2026-11-08): `Baganator.API.RegisterCornerWidget` (onInit(itemButton), onUpdate(widget, details) with `details.itemID`; true holds the corner), `Baganator.CallbackRegistry:RegisterCallback("ViewComplete", fn, owner)`, `IsCornerWidgetActive(id)`, `RequestItemButtonsRefresh`, the tag anchored on our widget (Baganator places it in the chosen corner), the legend under the frame named `Baganator_*BackpackViewFrame*` found from a live button's parents (not `RegisterRegion`: Baganator calls `SetFrameLevel` on those); live buttons inherit ContainerFrameItemButtonTemplate (`GetBagID`), cached ones don't | Baganator on: AH / V / DE tags on the bag icons (top left; move "Mailworthy tags and lock glow" to another corner in its Icons settings and the tag follows), the legend under the backpack, a locked item glows with the Mailworthy window open; empty a slot, sort, switch single / category view: no tag left behind; another character's bags: no tags. `/mw report` "bag addon: Baganator v846 ..., hooked, N button(s) seen, 0 error(s), legend shown" | open (2026-11-08; the glow alone was installed on v843 on the game PC) |
| Tags and lock glow in Bagnon (12.1.x, BagBrother engine, read 2026-11-08): `hooksecurefunc(Bagnon.ContainerItem, "Update", ...)` at Mailworthy's ADDON_LOADED (BagBrother's `Item:Bind` copies class methods into each button when built, at PLAYER_ENTERING_WORLD), `IsCached` / `GetBag` / `GetID`, the button's `info.itemID` (read only), `Bagnon.Frames:Get("inventory")` for the legend | Bagnon on: tags on the inventory, the legend under it, the glow with the window open; sort and move items: tags follow; the offline character view: no tags. `/mw report` "bag addon: Bagnon ..., hooked". If the log says "Bagnon built its buttons before Mailworthy loaded", the hook came too late | open (2026-11-08) |
| Tags and lock glow in ArkInventory (its `Core/ArkInventoryAPI.lua`, author's repo, Sept 2026): `hooksecurefunc(ArkInventory.API, "ItemFrameUpdated", fn(frame, loc, bag, slot))`, `API.LocationIsOffline(loc)`, `API.getBlizzardBagIdFromWindowId(loc, bag)` (bag and bank locations only: it prints a warning for others), `API.ItemFrameItemTableGet(frame).h` (link), `Const.Location.Bag` / `Bank`, the window `ARKINV_Frame1` for the legend | ArkInventory on: tags on the bag window, the legend under it, the glow; another character's bags: no tags; no ArkInventory warnings in chat. `/mw report` "bag addon: ArkInventory ..., hooked" | open (2026-11-08) |
| Tags and lock glow in BetterBags (its Forever build `BetterBags_Camelot.toc`, Interface 16001; source read 2026-11-08): `LibStub("AceAddon-3.0"):GetAddon("BetterBags")`, `:GetModule("Events"):RegisterMessage("item/Updated" / "item/Clearing", fn(ctx, item, decoration))` as its own Masque integration uses them; the item's `currentData` (`bagid`, `slotid`, `itemInfo.itemID`, `isItemEmpty`), `isFreeSlot`, `kind` (2 = guild bank) read only; the decoration (ContainerFrameItemButtonTemplate) drawn on; `addon.Bags.Backpack.frame` for the legend | BetterBags on: tags on its bag icons, the legend under the backpack, the glow with the window open; sort, move and sell items: no tag left on a free-slot button; `/mw report` "bag addon: BetterBags ..., hooked" | open (2026-11-08) |
| Disenchant prices for green items | Auctionator with a green item in bags | open |
| Tags on Auctionator's Selling tab (`AuctionatorTags.lua`): `hooksecurefunc` on `AuctionatorGroupsViewItemMixin.SetItemInfo`, the item info's `itemLink` / `itemCount` / `locations` (ItemLocation `GetBagAndSlot`) or `location` (the posting panel's icon); the buttons built from the mixin after login (on first AH open) and pooled (`CreateFramePool`, `SetItemInfo` again on every refresh) | Auctionator 340 source (the version measured on Forever): `Source/Groups/View.lua`, `ViewItem.lua` / `.xml`, `Source/Tabs/Selling/Mixins/BagItemSelected.lua` | open (2026-11-08): on the bank alt, the Selling tab's icons show the bags' tags, after scrolling and after selling or moving a stack; `/mw report` "auctionator tags: hooked; N Auctionator button(s) seen, M tagged now" |
| Mail ledger (`Ledger.lua`): `hooksecurefunc` post-hooks on `SendMail`, `TakeInboxItem`, `TakeInboxMoney` and `AutoLootMailItem` (Blizzard's Open All and shift-click call them; read in Forever's `MailFrame.lua`); the Send Mail tab read with `GetSendMailItem` / `GetSendMailItemLink` / `GetSendMailMoney` / `GetSendMailCOD` at `MAIL_SEND_INFO_UPDATE` / `SEND_MAIL_MONEY_CHANGED` / `SEND_MAIL_COD_CHANGED` and in the hook (not in Forever's generated API docs: legacy globals, guarded); `GetInboxHeaderInfo` returns 10 `wasReturned`, 12 `canReply`, 13 `isGM` (as `MailFrame.lua` reads them); `GetInboxItem` / `GetInboxItemLink`; `MAIL_SUCCESS(itemID)` confirms a take and `MAIL_FAILED(itemID)` refuses one (MailInfoDocumentation; unanswered takes count when the mailbox closes); value whispers `SendAddonMessage(prefix, text, "WHISPER", name)` | mail a friend by hand and take a mail from them: `/mw ledger` Export log shows both lines with item names and values, the chat line appears on taking it, `/mw report` "ledger: on, N log entries ... 0 take(s) unconfirmed"; with both on Mailworthy, the receiver's export says "sender's value" | open (2026-11-07) |
| SavedVariables survive `/reload` and relog | self-test marker, v0.4.0 settings | **work** (login, character switch, `/reload`) |
| One-press sending from the Mailworthy window (no money, no COD) | v0.4.0 | **works** (operator, 2026-10-14) |
| Reagent bag (bag 5, `NUM_TOTAL_EQUIPPED_BAG_SLOTS`) scanned, locked (Alt+click, L3) and mailed like bags 0-4 | a white item in the reagent bag: `/mw scan` lists it, Send mails it | open (CurseForge user report, 2026-10-21; source-backed: `Enum.BagIndex.ReagentBag` = 5 in `Blizzard_FrameXMLBase/Constants.lua`) |
| Guild members through `C_Club.GetGuildClubId` / `GetClubMembers` / `GetMemberInfo` (`name`, `presence`, `profession1ID` / `profession2ID` as skill line IDs, as Blizzard's Communities roster reads them on Forever; `GetGuildRosterInfo` fallback), party through `GetNumGroupMembers` / `GetUnitName(unit, true)` / `UnitIsConnected`, the roster asked for with `C_GuildInfo.GuildRoster()` | `/mw friends` lists guild and party members with "online" and their professions; a two-part name without a realm suffix lands in the binding and the mail arrives | open (2026-10-26) |
| Addon messages between Mailworthys: `C_ChatInfo.RegisterAddonMessagePrefix("Mailworthy")`, `SendAddonMessage(prefix, text, "GUILD" / "PARTY" / "RAID")`, `CHAT_MSG_ADDON` (sender possibly "Name-Realm") | two guild members with Mailworthy: `/mw report` shows "mailworthy peer: <name> (<professions>; other characters: ...)" on each, `/mw friends` marks them "Mailworthy", and a binding for a profession only an alt of theirs has says "delivered to their ... character" | open (2026-10-26) |
| Button labels that fit: `Button:GetFontString()`, `FontString:GetUnboundedStringWidth()` (`GetStringWidth` as the fallback), `Set{Normal,Highlight,Disabled}FontObject(GameFont*Small)`, `FontString:SetWidth(0 / n)` (all in Forever's source; each call in `pcall`) | the settings' long toggles ("Keep my professions' materials: on (...)") and the friends window's profession list sit inside their borders, in the small font when needed; a label too long even then ends in "..." at the border | open (2026-11-07) |
| Guild template: `GetGuildInfo("player")` (guild name, rank name, 0-based rank index, as Blizzard's TabardFrame reads it), `C_Club.GetMemberInfo` `guildRankOrder` (1-based, Communities `GuildRoster.lua`; `GetGuildRosterInfo` 3rd return as the fallback), `CHAT_MSG_ADDON`'s channel "GUILD" | the guild master's `/mw report` shows "guild: <name>, rank 0, can publish"; after Publish to guild, a member's shows "guild template: from <GM> ..., in use: not chosen yet" and a chat line; Use guild rules makes the rules appear in the Mailworthy window | open (2026-11-07) |
| Skill ranks: `GetProfessionInfo` 3rd return for this character (First Aid and Cooking included), `C_Club.GetMemberInfo` `profession1Rank` / `profession2Rank` for guild members (in Forever's `ClubDocumentation.lua` and Communities roster sort) | `/mw report` "kept for First Aid 85; First Aid 85 is past Linen Cloth (mailed)"; a binding line says "skill N" with a guild member's rank, or a Mailworthy peer's "skills: ..." | open (2026-11-06) |
| Scan freshness: `Auctionator.API.v1.GetAuctionAgeByItemID(caller, itemID)` (read in Auctionator's source: days since seen, nil past 21 days; else the `item:ID` link form) over 12 everyday trade goods; the scan day sent as `F2\|<server day>` after each hello | a character that hasn't scanned for a week, in a guild with a Mailworthy user who just scanned: `/mw report` "price stamp: <name> scanned 0 day(s) ago", a **!** on the Mailworthy button and the chat line at the mailbox | open (2026-11-06) |
| Tier check: Forever's Professions window is the retail one, fed by `C_TradeSkillUI` (in Forever's source: `GetBaseProfessionInfo` / `GetChildProfessionInfo` `professionID` / `skillLevel`, `GetRecipeInfo` `learned` / `relativeDifficulty` 0 orange .. 3 grey, `GetRecipeSchematic` `reagentSlotSchematics[].reagents[].itemID` / `outputItemID`, `GetFilteredRecipeIDs`, `IsTradeSkillLinked` / `IsTradeSkillGuild` / `IsTradeSkillGuildMember` / `IsNPCCrafting`; events `TRADE_SKILL_SHOW`, `TRADE_SKILL_LIST_UPDATE`, `TRADE_SKILL_DATA_SOURCE_CHANGED`). Not in Forever's Lua, tried first: `GetAllRecipeIDs` (retail has it; else the filtered list, so a search or "skill-up only" filter hides recipes). The Classic globals (`GetTradeSkillInfo`, `GetCraftInfo`, `CRAFT_SHOW`, ...) aren't in Forever's source; they are a fallback only. The skill line comes from `GetProfessionInfo` (matched by ID, else by name) | open each crafting profession: `/mw report` "tier check: <name> <profession> <rank> read ... (N learned recipes, C_TradeSkillUI)", N close to the window's learned recipe count; then any "still used" lines, checked against the window's colours | open (2026-11-06) |
| Items an active quest needs: `C_QuestLog.GetNumQuestLogEntries` / `GetInfo` (`title`, `questID`, `isHeader`) / `GetQuestObjectives` (`text`, `type` "item") from Forever's `QuestLogDocumentation.lua`; the Vanilla quest log's `GetNumQuestLogEntries` / `GetQuestLogTitle` / `GetNumQuestLeaderBoards` / `GetQuestLogLeaderBoard` as the fallback; the objective text as "Name: 3/5" (or "3/5 Name"), matched to the bag item's name; event `QUEST_LOG_UPDATE`. A quest under a collapsed header may not be counted | with Redridge Goulash in the log, Crisp Spider Meat: Staying "Redridge Goulash needs it", `/mw scan` "KEEP [Crisp Spider Meat] ...: a quest needs it (Redridge Goulash)", no V tag; turn the quest in and it's valued again | open (operator, 2026-11-08) |
| Class-only items: `C_TooltipInfo.GetItemByID(itemID).lines[i].leftText` (TooltipDataLineType.UsageRequirement, RaceClass; `args` with `field = "leftText"` as the fallback) starting with `ITEM_CLASSES_ALLOWED` ("Classes: %s"), class names through `LOCALIZED_CLASS_NAMES_MALE` / `_FEMALE`; a guild member's class from `C_Club.GetMemberInfo` `classID` | a "Mage items" binding to a mage friend: a mage-only scroll shows "to Bob" in the Mailworthy window and arrives; `/mw report` "binding: Mage items to ..." | open (operator, 2026-11-08) |
| Lock glow only while the Mailworthy window is open (its `OnShow` / `OnHide`, `IsVisible` under the mail frame), "always" setting; a new lock flashes 3 s anywhere; a tooltip line on a glowing item (`TooltipDataProcessor.AddTooltipPostCall`, item type, `data.id`) | lock an item away from a mailbox: a 3 s glow on every stack, then nothing; open a mailbox: still nothing; open the Mailworthy window: glow, and hovering a glowing item shows "Locked in Mailworthy: ..."; close the window or the mailbox: gone | open (operator, 2026-11-07; before: any open mailbox, 2026-10-21) |
| Guild contributions shared in hellos: `G2\|<asOf>\|<i>/<n>\|<total>\|<since>\|<days back>:<units>;...` on `SendAddonMessage(prefix, text, "GUILD")` only, right after the hello and at `MAIL_CLOSED` after a counted mail; this character's own counts only | two guild members with Mailworthy, one mails a guild rule's materials and closes the mailbox: the other's `/mw report` "guild export: ..., 2 giver(s)" (theirs and the guildmate's) | open (2026-11-08) |
| Guild contributions' peer list at logout: the guild roster (`C_Club.GetClubMembers` / `GetMemberInfo`, `GetGuildRosterInfo` fallback) read every time the API is called, and on `GUILD_ROSTER_UPDATE` (at most every 10 seconds, with one more read after a burst); at `PLAYER_LOGOUT` the roster and `GetGuildInfo` may already be gone, so the last read of this session stands in for the name passed | log out with LedgerLink: its export carries `mailworthy.peers`; `/mw report` "guild contributions: this guild, N character(s), M unit(s) counted" after a guild rule's mail | open (2026-11-08) |
| The Mailworthy mark: the addon icon inline after a name (`\|TInterface\AddOns\Mailworthy\Textures\Icon:0\|t`, the same file as the minimap button; a texture escape in our own font strings, no frame) | `/mw friends` with a guild member who runs Mailworthy: the icon after their name, the footer "(icon) runs Mailworthy"; the bank alt's "To:" line at the mailbox | open (2026-11-08) |
| Controller names that follow the controller (`Gamepad.Name` / `Gamepad.Glyph`): `C_GamePad.GetDeviceMappedState(id).labelStyle` (the value Blizzard's `InputDeviceIconSetManager` picks its icon set by) "Letters" / "Generic" (Xbox) and "Reverse" (Switch): RB, LS, Y in chat for both, while the icons are the controller's own (a Switch's top button is drawn as X); the icons for `PADRSHOULDER` and `PADLSTICK` from `InputIconTextureSetUtility.GetNormalActiveInputIconButtonTexture` (in every set in Forever's `InputIconTexture.lua`) drawn in the Inbox hint and in the lock glow's tooltip line; what a Steam Deck reports (Mailworthy gives anything else the Xbox names) | with an Xbox or Switch controller, or on a Steam Deck: `/mw help` names RB / LS / Y, the Inbox hint under the mail window and a locked item's tooltip show that controller's buttons; `/mw report` gives the label style | open (only "Shapes", a PlayStation controller, has been seen in game: R1, L3, Triangle) |

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
