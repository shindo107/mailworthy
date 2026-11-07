# Commands and Troubleshooting

## Slash commands

| Command | Does |
|---|---|
| `/mw` | Settings |
| `/mw scan` | What Mailworthy would mail and why, **with all the numbers** (sends nothing) |
| `/mw friends` | Your bindings and your guild's template |
| `/mw summary` | On your bank alt: what to list, disenchant or vendor |
| `/mw locks` | This character's locked items |
| `/mw report` | A copyable report for bug reports |
| `/mw feature <name> on/off` | Turn one part of Mailworthy off (then `/reload`); `/mw feature` lists them |
| `/mw help` | All commands |

## "Why did it mail / keep that?"

Run `/mw scan`. Every item gets a line with its verdict and the math behind it: vendor value, auction price (and how many days it's based on), market, fees, gain against the minimum, and for profession materials which skill keeps it or which friend's skill is past it.

## Something looks wrong

1. Run `/mw report`, copy the text and attach it to your bug report on CurseForge or GitHub. It has your settings, the scan, your bindings, the Mailworthys you've heard from, recent errors, and which game functions were available.
2. If a piece of the interface misbehaves (especially with a controller), turn just that piece off and `/reload`:

| Switch | Turns off |
|---|---|
| `mailButton` | The Mailworthy button under the mail window |
| `padTriangle` / `padNav` / `padLock` | Triangle to open, D-pad navigation, L3 lock |
| `altClickLock` | Alt+click lock |
| `slotBorder` | The blue lock glow |
| `minimapButton` | The minimap button |
| `bankAltTags` / `tooltipLines` | Bag tags / tooltip lines on the bank alt |
| `comms` | Messages between Mailworthys |
| `staleNudge` | The old-prices reminder |
| `tiers` | Levelling past materials (every material is kept at any skill) |
| `guildTemplate` | The guild template: nothing heard, sent or applied |

## Common questions

**It says "no auction price yet" for something.** Auctionator hasn't seen it on the auction house. Scan, and it's judged next visit.

**The Send button is missing.** You're on the Inbox tab. Mail only goes out from Send Mail; open that tab.

**My tailor's cloth is being mailed.** Your Tailoring is past it (every recipe using it is grey for you): see [[Profession Materials]]. Lock it to keep it anyway, or `/mw feature tiers off`.

**My guild's template isn't showing.** It comes from any guildmate running Mailworthy who has it, when you log in; if nobody with a copy was online, open Friends later to ask again. `/mw report` has a "guild template" line, and one line for each rule left out for you and why.

**My friend isn't getting anything.** Check the window's bindings: maybe it's skipped this visit, at the price cap, or your friend is past those materials. `/mw report` lists each binding with the friend's known skill.
