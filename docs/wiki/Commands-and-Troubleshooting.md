# Commands and Troubleshooting

## Slash commands

`/mailworthy` works everywhere `/mw` does.

| Command | Does |
|---|---|
| `/mw` (or `/mw settings`) | Settings |
| `/mw scan` | What Mailworthy would mail and why, **with all the numbers** (sends nothing) |
| `/mw friends` | Your bindings: send a profession's materials to a friend |
| `/mw guild` | Your guild's template: turn the guild rules on or off; officers edit it here |
| `/mw ledger` | The mail ledger: what you owe, and **Export log...** |
| `/mw summary` | On your bank alt (or without one): what to list, disenchant or vendor |
| `/mw locks` | This character's locked items |
| `/mw report` | A copyable report for bug reports |
| `/mw feature <name> on/off` | Turn one part of Mailworthy off (then `/reload`); `/mw feature` alone lists them all with their state |
| `/mw help` | All commands |

## "Why did it mail / keep that?"

Open the Mailworthy window and hover the item in your bags: the tooltip says where it goes or why it stays. For the full math, run `/mw scan`. Every item gets a line with its verdict and the numbers behind it: vendor value, auction price (and how many days it's based on), market, fees, gain against the minimum, and for profession materials which skill keeps it or which friend's skill is past it.

## Something looks wrong

1. Run `/mw report`, copy the text and attach it to your bug report on CurseForge or GitHub. It has your settings, your bindings, the guild template, the Mailworthys you've heard from, the bag addons Mailworthy found, recent errors, and which game functions were available. For a pricing question, add the text from `/mw scan` (the item-by-item numbers).
2. If a piece of Mailworthy misbehaves (especially with a controller), turn just that piece off and `/reload`:

| Switch | Turns off |
|---|---|
| `mailButton` | The Mailworthy button under the mail window |
| `autoOpen` | The window opening by itself on the Send Mail tab |
| `padTriangle` / `padNav` / `padLock` | Triangle to open, D-pad navigation, L3 lock |
| `altClickLock` | Alt+click lock |
| `slotBorder` | The blue lock glow |
| `minimapButton` | The minimap button |
| `bankAltTags` | The AH / B / DE / V bag tags, everywhere they show |
| `tooltipLines` | Mailworthy's lines in item tooltips |
| `bankAltMail` | On the bank alt, the Mailworthy button opens only the summary instead of the window |
| `returnToSender` | The Return to sender button |
| `ledger` | The mail ledger, the pay-back lines, and Return to sender with them |
| `questNeeds` | Keeping items an active quest asks for (quest items themselves still stay) |
| `comms` | Messages between Mailworthys |
| `peerMark` | The Mailworthy icon after the names of players who run it |
| `staleNudge` | The old-prices reminder |
| `tiers` | Levelling past materials (every material is kept at any skill) |
| `tierCheck` | Reading your profession window to check the material tiers |
| `guildTemplate` | The guild template: nothing heard, sent or applied |
| `baganatorTags` / `bagnonTags` / `arkInventoryTags` / `betterBagsTags` | Tags and lock glow in that bag addon (see [[Bag Addons]]) |
| `auctionatorTags` | Tags on Auctionator's Selling tab |

## Common questions

**An item shows "No price".** Your price addon hasn't seen it on the auction house yet. It goes to your bank alt to wait for a price. See [[Price Sources]].

**It says "the price lookup failed".** Auctionator or TSM couldn't answer for that item, so it stays: it never goes to your bank alt or a friend on a failed lookup. (Return to sender needs no price, so it can still send it back.)

**Send is greyed out and says "Click Send Mail".** You're on the Inbox tab. Mail only goes out from Send Mail; click that tab and the window follows you.

**The window opened by itself.** It opens when you click the Send Mail tab. `/mw feature autoOpen off` stops that.

**"Not sent: ... Check the list, then press Send again."** Something in your bags changed between the list and Send (an item moved, a quest picked it up, a friend's skill changed). The list now shows where everything goes; press Send again.

**My Crisp Spider Meat isn't being mailed.** A quest in your log asks for it. Turn the quest in (or abandon it) and it's judged again.

**My tailor's cloth is being mailed.** Your Tailoring is past it (every recipe using it is grey for you): see [[Profession Materials]]. Lock it to keep it anyway, or `/mw feature tiers off`.

**Nothing goes to my bank alt.** Check the "To:" line: maybe you pressed **Skip once**, or you have no bank alt set (Settings → **Choose...**), or you're on the bank alt.

**My guild's template isn't showing.** It comes from any guildmate running Mailworthy who has it, when you log in; if nobody with a copy was online, open the Guild window (`/mw guild`) later to ask again. `/mw report` has a "guild template" line, and one line for each rule left out for you and why.

**My friend isn't getting anything.** Check the window's bindings: maybe it's skipped this visit, at the price cap, or your friend is past those materials. `/mw report` lists each binding with the friend's known skill. A binding takes only primary materials: see [[Friends and Bindings]].

**Return to sender finds nothing.** It only knows mail you took out of the mailbox since the [[Mail Ledger]] came in. See [[Return to Sender]].
