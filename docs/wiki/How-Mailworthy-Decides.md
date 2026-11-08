# How Mailworthy Decides

For every item in your bags, Mailworthy asks one question: **is it worth clearly more on the auction house (or disenchanted) than at a vendor, after every fee?** If yes, it's mailed. If not, it stays for the vendor.

All the stacks of one item count together, so you never get "mail 20 Linen Cloth, keep 3".

## The order of things

1. **Things that always stay** come first: locks, soulbound and quest items, items an active quest asks for, tools. See [[What Stays in Your Bags]].
2. **Your professions' materials** stay next, until you've levelled past them. See [[Profession Materials]].
3. Everything else gets **the money math** below.
4. Then it's decided **who gets it**: with [[Return to Sender]] on, what someone mailed you goes back to them first; then your [[bindings|Friends and Bindings]] and your guild's rules; everything else goes to your [[bank alt|Your Bank Alt]] (or stays in your bags if you don't have one, or skipped it this visit).

## The money math, in plain words

1. **Vendor value:** what a vendor would pay for the whole lot.
2. **Auction value:** the auction price, minus everything it costs to sell there:
   - the **AH cut** (5%),
   - **half the deposit**, because the game gives the deposit back when the item sells and raw materials do sell (the deposit grows with the listing length you chose, 24h by default, and is never under 1 silver per listing on Forever),
   - **postage**: 30 copper for each stack attached.
3. **Disenchant value** (green, blue and purple gear, when the disenchant comparison is on): what its enchanting materials sell for, minus postage.
4. The best of auction and disenchant, minus the vendor value, is the **gain**.
5. The item is mailed when the gain is at least the **minimum gain** you set: **1 silver and 25% more than the vendor price**, both, by default.

**Example:** 20 Linen Cloth, vendor 10c each, auction 15c each.
- Vendor: 2s.
- Auction: 3s, minus the 5% cut, minus half of a 1s 20c deposit, minus 30c postage, leaves 1s 95c.
- Gain: less than nothing, so it **stays** (sell it to a vendor).
- At 40c each the auction leaves 6s 70c: a gain of 4s 70c, over 1s and over 25% of 2s, so it's **mailed**.

## No price yet

A brand-new realm has lots of items nobody has listed yet. When your price addon has **no auction price** for an item, Mailworthy doesn't guess and doesn't hold it on your main: it's **mailed to your bank alt** to wait there for a price. The window shows it with a **No price** chip and no gain, and the total line counts it ("2 with no price yet").

- A price **older than 7 days** counts as no price ("auction price too old (8 days)").
- **Grey junk** with no price stays, for the vendor.
- If the **price lookup failed**, the item stays. A failure never counts as "no price yet".
- **Staple trade goods** (cloth, leather, ore, bars, stone, herbs, elementals, dust, essences, shards) are always mailed when they have no price, as a **Common** item.

Where prices come from, and what happens without a price addon: see [[Price Sources]].

## Prices you can trust

These need Auctionator, which keeps a price history (TradeSkillMaster's prices come without one):

- **The last scan, held down by a three-day median.** Mailworthy uses Auctionator's last scan, but when the middle of the last three scanned days is lower, it uses that instead. One undercutter or one empty scan can't flip a decision.
- **Gluts.** When the auction house is flooded (at least ten times what you have listed, and the price down 25% or more on last week), the item is valued at the floor of the market and the deposit counts in full.
- **Inexact prices.** When Auctionator could only match a similar name, 10% is taken off to be safe.
- **Old prices.** From 3 days the window starts nudging you to rescan. Past 7 days a price stops counting (see above).

## The realm's age matters

Mailworthy knows when Forever launched (November 4, 2026) and plays the realm's economy accordingly:

| Realm age | What changes |
|---|---|
| **Before day 35** (first raids, December 9) | **Enchanting materials, herbs past the starter ones, elementals and Mithril and up** are tagged **Bank**: hold them on the alt, raiders pay more for them soon. |
| **Until day 60** | A flooded item whose price used to be much higher is also banked until the market recovers. |
| **After day 35** | The minimum gain slowly rises with the realm's gold supply (vendor prices never change, gold does), up to twice your setting. |

## Before any of this

Some items never even get this far. They always stay: see [[What Stays in Your Bags]] and [[Profession Materials]].
