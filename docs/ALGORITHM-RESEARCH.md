# Decision algorithm research (2026-10-20)

**Status:** sections 4.1-4.5 are built (decision rule v2, PLAN "Decision rule"); the
beta build check is in section 1.

Goal (operator): **the most gold while leveling, with the player doing no math.**
Every factor below has to work with the defaults and no new setting the player must
understand. This doc covers two things: whether the current beta build needs an
addon update (no), and what should change in the mail / vendor / bank decision, ranked
by impact for Mailworthy.

## 1. Beta build check: no update needed

| Fact | Finding |
|---|---|
| Latest beta client | 1.60.1.**70450** (Oct 16); 70425 (Oct 15) carried the last real changes |
| Interface number | still **16001** (set in 70170 on Oct 1; the client version string has not moved off 1.60.1) |
| Beta ends | Oct 21 Pacific (stress test takes over, beta reopens after) |
| Launch | **Nov 4, 2026, 3 PM PST** (epoch `1793833200`); first raids Dec 9 (= launch day 35) |
| Addon-facing changes Oct 1 to 16 | none listed: no mail, bag, container, auction API or SavedVariables changes; `WOW_PROJECT_CAMELOT` constant added Oct 1; gamepad bindings made static Oct 1 |
| Game-data changes that touch our numbers | Oct 15: "many profession-created items have reduced vendor sell prices" (we read live vendor prices, nothing to change); Oct 15: AH gained an equip-level column |
| Mail globals we call | `GetSendMailPrice`, `GetInboxInvoiceInfo`, `GetSendMailItem`, `ClickSendMailItemButton`, `SetSendMailMoney`, `SetSendMailCOD`, `GetInboxHeaderInfo` all still used by `Blizzard_MailFrame/MailFrame.lua` on the `forever` branch |
| Removed globals reported by addon authors | `GetItemInfo`, `GetSpellInfo`, `math.randomseed`, ... reported nil on some builds. `Prices.lua` already prefers `C_Item.GetItemInfo` / `C_Item.GetItemInfoInstant` with the global as fallback; nothing else we call is on that list |
| Source mirrors | Ketho's `wow-ui-source-forever` stopped at 70009 (Sep 24); Bleakfiber's snapshot is 70205 (Oct 3). **No source for 70425 / 70450 exists**, so the API check above rests on the patch notes plus the mail frame at 70009 |

What to do before launch: nothing in code. Run `/mw report` once on the stress-test
build (Oct 21) and once on launch day; confirm Auctionator's Forever file still exposes
`API.v1` (340/341 did). If anything is blocked, that is the first PR.

## 2. What players actually use to decide AH vs vendor

Sources: Classic forum threads, Wowpedia "Working the Auction House", TSM / Lazy
Goldmaker price-source guides, the Forever beta AH guide (warcraftforever.games), and
three keep-or-sell addons updated this month (KeepOrSell, AuctionHouse Forever,
MuleMate / AuctionWorthy from PLAN "Related addons"). Nobody publishes week-by-week
price curves for fresh realms (NexusHub's API is gone; TSM has no region data on
Forever), so the time-based findings below are the consistent community account, not
measured data. Mailworthy should **measure them itself** (section 4).

| # | Factor | How players use it | Mailworthy today |
|---|---|---|---|
| 1 | **Net vs vendor after fees** | 5% faction cut (15% neutral), deposit lost if it expires, "if the deposit is more than it sells for, vendor it". Rules of thumb: MuleMate 110% of vendor, KeepOrSell 2x vendor, Wowpedia "vendor after it expires twice" | done: `ahNet = price x n x 0.95 - deposit - postage`, mail at >= 5s and 25% |
| 2 | **Is the price real?** | min buyout is "usually lower than market value and misleading when unusually low" (one 1c undercut); goblins use a market value / median, never the single lowest listing; AHF uses "the middle of the cheapest listings" | **not done**: we use Auctionator's single last-scan minimum |
| 3 | **Will it sell before it expires?** (liquidity) | TSM sale rate / sold-per-day; "avoid items where very few sell a day"; raw materials move constantly, crafted goods and low greens don't | **not done**: deposit counted as lost (relist factor 1.0) stands in for it, for every item alike |
| 4 | **How much is already listed** (competition) | number of listings / quantity available vs what you post; on a pooled commodity AH (Forever uses the modern `C_AuctionHouse`, commodities per unit) only the units priced below yours matter | **not done**: Auctionator stores the quantity, we don't read it |
| 5 | **Where the server is in its life** | week 1-2: everything raw sells (crafters levelling, bags), gold is scarce so nominal prices are low but demand is total; weeks 3-8: low-level mats glut as the population passes through; month 2+: alts and inflation lift low-level mats again, vendor prices stay fixed copper so the vendor gets relatively worse forever; raid opening lifts enchanting mats, herbs, elementals | **not done** |
| 6 | **Price age** | scan daily, distrust old data | done: 7-day max age |
| 7 | **Bag space and time** | the real constraint while levelling; vendoring is "guaranteed silver now" | partly: one-press mailing removes the time cost on the main; the bank alt still pays posting time per stack |

Prior-art thresholds for reference: MuleMate mails when AH after cut >= 110% of vendor;
KeepOrSell puts an item in "AuctionHouse" at >= 2x vendor and otherwise junk, with "no
auction price means no junk". Ours (5s and 25%) sits between them.

## 3. Data we can get without the player doing anything

| Signal | Source | Status |
|---|---|---|
| Unit price, age, exactness, disenchant | `Auctionator.API.v1` (stable, confirmed in game) | in use |
| **Quantity available** at the last scan, per day | `Auctionator.Database:GetPriceHistory(dbKey)[i].available` (Auctionator sums `available` over every listing in a full scan; `a[day]` keeps the day's max) | **not stable API** (README: "any other function may break"); `pcall` + nil checks, listed under Beta unknowns |
| **Daily price history** (up to 21 days, Auctionator default `PRICE_HISTORY_DAYS`) | same call: `minSeen` (lowest min buyout of the day), `maxSeen` (highest min buyout of the day) | same |
| dbKey for a link | `Auctionator.Utilities.BasicDBKeyFromLink(link)` = item ID as a string for everything but high-level gear | same |
| Days since launch | `GetServerTime()` (documented in Forever) minus `1793833200`; fall back to the first time Mailworthy saw this realm (`MailworthyDB.realms[realm].firstSeen`) for any later realm | new, trivial |
| Commodity or item | `C_AuctionHouse.GetItemCommodityStatus` (2 = commodity; measured) | available |

Nothing here needs the AH open, and nothing writes into Blizzard UI.

## 4. Proposed changes, ranked by impact

Impact = extra gold for a levelling player x how often it triggers, divided by
risk and code. All of them are pure `Valuation` logic plus one adapter function in
`Prices.lua`; nothing touches the controller UI.

### 4.1 HIGH: value items at a smoothed price, not the last minimum

Replace the single last-scan min buyout with the **median of the daily `maxSeen` over
the last 3 scanned days** (fall back to the API price when history is missing). Mark
the verdict "(1 scan)" when only one day exists. Why first: one 1-copper undercut
or one empty market flips a verdict today, in both directions, and this costs the
player nothing to understand. Cheap: ~30 lines plus specs.

**Revised 2026-11-07** (CurseForge report, Silk Cloth valued at 5s 30c while Auctionator's
last scan said 2s 70c): the median now only ever **lowers** the price. `maxSeen` is the
day's *highest* minimum buyout (Auctionator `Database/Mixin.lua`, `h[day]`), so on a
falling market, which a fresh realm is for every low-level material, the median of the
last three days' highs trails the market and over-values in the unsafe direction (mail,
postage, deposit for something that lists under the threshold). The last scan is what a
listing competes with today and what Auctionator shows, so it wins when lower; the median
still caps an empty-market spike. A below-market undercut now keeps the item for one scan,
the cautious direction.

### 4.2 HIGH: a fresh-realm default for unpriced white trade goods

In the first weeks almost nothing has a price even with Auctionator installed, and
"no price" currently means **keep for the vendor**. On a fresh realm the opposite is
right for cloth, ore, herbs, leather: they always sell. Rule: with Auctionator present
but no price, mail white (quality 1) **trade goods (class 7)** and tag them `AH` on the
bank alt, exactly like the no-Auctionator rule already does for every white item. Stop
doing it once the item has a price or after launch day 14, whichever comes first. This
is where most levelling gold is made and where our data is thinnest.

### 4.3 HIGH: a liquidity factor from supply and trend (competition)

From the history, compute per item:

```
available = quantity listed at the last scan (units)
trend     = median(maxSeen, last 3 days) / median(maxSeen, days 4-10) - 1    -- nil with < 4 days
glut      = available >= 10 x our count  and  trend <= -0.25
thin      = available == 0 or nil for 7 days with a price older than 3 days
```

Use it two ways, both invisible to the player:

- **Expected price haircut**: `glut` values the item at the 3-day `minSeen` instead of
  the median (you will be undercutting into a falling market), and counts the deposit
  as lost (relist 1.0). Everything else counts the deposit at **0.5** (refunded when it
  sells; raw materials sell). Today's 1.0 for all items is the single biggest reason
  cheap stacks of cloth fail the 5s gate.
- **Bank trigger**: `glut` on a bank-eligible item (4.4) means "mail it, don't list it".

"How many other stacks" is not available as a count; the AH is pooled per unit for
commodities on Forever, so units available is the right measure anyway.

### 4.4 MEDIUM-HIGH: the **Bank** category (operator request)

A fourth verdict next to AH / DE / V: **B**: mail it to the bank alt, but **hold it**
for a later phase where it sells higher. The main's window shows it in the Mailing list
with a "bank" chip; the bank alt sees a `B` tag, the tooltip says "Bank: expected to
sell higher after Dec 9 (raids)" and the summary gets a "Bank" line. It is still mailed
through the same safe path (unlocked, tradeable, to the saved alt, after Send).

An item is **B** when it would be mailed anyway (AH or common route) **and** one of:

1. **Phase list**: its item class / subclass is on the late-demand list and the
   server is before the phase that wants it:
   - enchanting materials (dust, essence, shard; class 7 subclass 12) before day 35
     (first raids Dec 9): everybody enchants at 60, nobody while levelling;
   - herbs from Bruiseweed up (level 20+ herbs, class 7 subclass 9) before day 35:
     raid consumables;
   - elemental drops (Elemental Earth / Fire / Water / Air, Essence of X, class 7
     subclass 10 "elemental") before day 35;
   - level 40+ ore and bars (Mithril, Truesilver, Thorium) before day 35.
   Low-level cloth, ore, leather and herbs are **not** on it: the levelling player
   needs the gold now (mount at 40), and their later recovery is slow and uncertain.
2. **Measured glut** (4.3) on any trade good whose 10-day `maxSeen` median is at least
   1.5x today's price: the market is flooded right now and was better last week.

Cap: B never applies after launch day 60 (the phase table is over; from there the
measured signal in 4.3 alone decides, and only as a haircut). Bank space on the alt is
finite, so B is selective by design; the player can still lock an item to keep it, or
the bank alt can list a B item whenever they like (tags are advice).

Cost: a phase table and list in `Valuation`, `route = "bank"` through `Bags`, `Mailer`
(no change), `MailWindow` chip, `BankAlt` tag + tooltip + summary line, `Report`.
Medium. Risk: a wrong phase list banks gold the player wanted; mitigated by the
"would be mailed anyway" precondition and the day-60 cap.

### 4.5 MEDIUM: server age as a threshold modifier

Days since launch feeds three small things, no new setting:

| Launch day | Effect |
|---|---|
| 0-13 | 4.2 fresh-realm default on; min gain stays 5s / 25% |
| 14-34 | 4.4 phase list active; glut detection has enough history to work |
| 35+ | enchanting / herb / elemental B items switch to AH; vendor gets relatively worse as gold inflates: grow `minGain` by 1/180 per day past day 35, capped at 2x (5s until day 35, 6s 52c at day 90) so the preview does not fill with 5s items the player no longer cares about |

Low code, medium value; mostly it keeps the preview short later on.

### 4.6 LOW: stack-count competition for gear

For non-commodity items (greens, weapons) `available` is a listing count. The DE route
already dominates for greens with Disenchantry; a listing count adds little. Skip.

### 4.7 LOW: `exact` flag

Auctionator's `IsAuctionDataExactByItemLink` is already read and unused. Apply a 10%
haircut to inexact prices in 4.1. One line, small gain.

## 5. Recommended order

1. **4.1 + 4.7** (smoothed price): one PR, pure `Valuation` + `Prices.History`.
2. **4.2** (fresh-realm default) + the `ServerDay` helper from 4.5: must ship before Nov 4.
3. **4.3** (liquidity haircut, relist factor 0.5 by default) with its specs.
4. **4.4** (Bank category) on top of 4.3 and the phase table.
5. **4.5** threshold scaling, last, after a few weeks of real data from `/mw report`.

Every PR adds its unknowns to README "Beta unknowns": `Auctionator.Database` history
being readable on Forever, `GetItemCommodityStatus` away from the AH, and the
`GetServerTime` anchor.

## 6. Sources

Build and API:
[MMO-Champion Oct 15 notes](https://www.mmo-champion.com/content/14618-WoW-Forever-Beta-Development-Notes-October-15),
[every beta build in order](https://wowforevertierlist.com/beta/patch-notes),
[Blizzard forum: addon feedback](https://us.forums.blizzard.com/en/wow/t/wow-forever-beta-addon-feedback/2385926),
[Forever addon dev guide, interface 16001](https://wowforeverguides.com/addons/developers),
[Icy Veins roadmap](https://www.icy-veins.com/wow-forever/roadmap),
[wowguide roadmap](https://wowguide.net/en/guides/wow-forever-roadmap),
[Ketho/wow-ui-source-forever](https://github.com/Ketho/wow-ui-source-forever).

Market behaviour:
[Forever AH guide (cut, durations, beta prices)](https://warcraftforever.games/guides/auction-house),
[Wowpedia: Working the Auction House](https://wowpedia.fandom.com/wiki/Working_the_Auction_House),
[Classic forum: AH vs selling on a new server](https://us.forums.blizzard.com/en/wow/t/auction-house-vs-selling-for-new-server/197786),
[Classic forum: vendor instead of AH?](https://us.forums.blizzard.com/en/wow/t/do-you-mostly-vendor-instead-of-sell-on-ah/289082),
[TSM value sources](https://support.tradeskillmaster.com/en_US/custom-strings/which-value-sources-can-i-use-and-what-do-they-mean),
[Lazy Goldmaker: TSM tooltip](https://thelazygoldmaker.com/what-on-earth-does-the-tsm-tooltip-mean),
[Lazy Goldmaker: price data on anniversary realms](https://thelazygoldmaker.com/this-is-how-you-get-pricing-data-for-the-anniversary-realms),
[Fresh Classic investment guide](https://www.mmojugg.com/news/fresh-classic-wow-servers-investment-guide.html),
[Forever gold farming guide](https://timesaver.gg/blog/wow-forever-gold-farming-guide).

Prior art and Auctionator internals:
[KeepOrSell](https://github.com/svengabr/KeepOrSell),
[AuctionHouse Forever](https://github.com/severd8/auctionhouseforever),
Auctionator `Source/Database/Mixin.lua` and `Source/API/v1/README.md` (public copy at
`aby-ui/repo-base`; the `l` / `h` / `a` per-day fields and `GetPriceHistory`).
