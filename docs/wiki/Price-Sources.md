# Price Sources

Mailworthy never scans the auction house itself. It reads the prices another addon has already gathered. The settings window's bottom line says which one it uses ("Prices: Auctionator").

| You have | Settings says | Mailworthy uses |
|---|---|---|
| **Auctionator** | Prices: Auctionator | Auctionator's scans (recommended) |
| **TradeSkillMaster** only | Prices: TradeSkillMaster | TSM's prices for your realm |
| Both | Prices: Auctionator (TSM installed, not used) | Auctionator |
| Neither | Prices: none (install Auctionator or TSM; only white items are mailed) | No prices: the simple rule below |

## Auctionator

Run an Auctionator scan at the auction house now and then. Mailworthy uses its last scan, held down by the middle of the last three scanned days when that is lower, and also reads how old each price is, how flooded the market is, and whether the price matched the exact item. See [[How Mailworthy Decides]].

- Once your prices are **over 3 days old**, the Mailworthy button gets a **!** and the window reminds you to scan. A guildmate's fresher scan makes it louder: see [[Mailworthy Talks to Mailworthy]].
- A price **over 7 days old** stops counting: the item is treated as having no price.

## TradeSkillMaster

Without Auctionator, Mailworthy takes TSM's prices for **your realm**: its lowest buyout, or its market value when that is lower. Never region prices: the item sells on your realm's auction house.

TSM doesn't tell other addons how old a price is or how it moved, so with TSM alone:
- there's no "price too old" rule and no reminder to rescan,
- there's no three-day median and no flood check.

If both addons are installed, Auctionator wins, for exactly those reasons.

## Neither

Without a price addon there's nothing to compare, so Mailworthy keeps it simple:

- It mails every unlocked, tradeable **white** item.
- It mails the **staple trade goods** below, whatever their colour (so green and blue essences and shards go too).
- **Grey** items stay ("junk: sell it at a vendor").
- Anything **green or better** stays ("uncommon: needs Auctionator prices").
- Your [[bindings|Friends and Bindings]] still send their profession's materials and recipes.

The total line in the window says "No Auctionator: white items and staple trade goods go."

## When an item has no price

With Auctionator or TSM installed, an item they have no auction price for goes **to your bank alt** to wait for one, with a **No price** chip. Gear goes too. The exceptions:

| Item | What happens |
|---|---|
| Grey junk | Stays, for the vendor |
| The price lookup failed | Stays ("the price lookup failed") |
| A staple trade good | Mailed as a **Common** item (and tagged **Bank** if raiders will want it later) |
| A recipe with a binding for its profession | Goes to that friend (see [[Friends and Bindings]]) |
| Anything that always stays | Stays: locks, soulbound and quest items, tools ([[What Stays in Your Bags]]) |
| No bank alt, or skipped this visit | Stays in your bags |

A **class binding** ("Mage items") never takes an item without a current auction price: it goes to your bank alt instead.

## Staple trade goods

These always sell above a vendor, on any realm, at any level. Mailworthy mails them even without a price:

| Kind | Items |
|---|---|
| Cloth | Linen, Wool, Silk, Mageweave, Runecloth, Felcloth |
| Leather | Ruined Leather Scraps; Light, Medium, Heavy, Thick and Rugged Leather |
| Hides | Light, Medium, Heavy, Thick and Rugged Hide |
| Ore | Copper, Tin, Iron, Silver, Gold, Mithril, Truesilver, Thorium, Dark Iron |
| Bars | Copper, Tin, Bronze, Silver, Iron, Gold, Steel, Mithril, Truesilver, Thorium |
| Stone | Rough, Coarse, Heavy, Solid, Dense |
| Herbs | all 28, from Peacebloom and Silverleaf to Black Lotus |
| Elemental | Elemental Earth, Fire, Air and Water; Core of Earth, Heart of Fire, Globe of Water, Breath of Wind; Essence of Earth, Fire, Water, Air and Undeath; Living Essence, Ichor of Undeath |
| Enchanting | Strange, Soul, Vision, Dream and Illusion Dust; Lesser and Greater Magic, Astral, Mystic, Nether and Eternal Essence; Small and Large Glimmering, Glowing, Radiant and Brilliant Shard |

A staple **with** a price is judged on that price like anything else.

## Disenchant values

For green, blue and purple gear, Mailworthy can compare disenchanting too (Settings → **Include disenchant value**). The value comes from:

- **[Siz DisenchantValue](https://www.curseforge.com/wow/addons/siz-disenchantvalue)**, learned from your own disenchants, when it's installed;
- otherwise the classic disenchant tables (the same number **[Disenchantry](https://www.curseforge.com/wow/addons/disenchantry)** shows in its tooltip), priced with Auctionator or TSM.

The comparison is on by default when either addon is installed. The settings button says which source is used ("Include disenchant value: on (era tables)").
