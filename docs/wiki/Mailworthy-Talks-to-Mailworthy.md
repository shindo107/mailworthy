# Mailworthy Talks to Mailworthy

When you and your guildmates (or party) all run Mailworthy, the addons quietly say hello to each other using WoW's hidden addon messages. Nothing appears in chat. This makes [[bindings|Friends and Bindings]], fresh prices and the [[Mail Ledger]] work better, and shows you who else runs Mailworthy.

## What's shared

| Shared | With | Used for |
|---|---|---|
| Which of your characters on this realm and faction have which **crafting professions** | guild, party or raid | A binding reaches the friend's character that actually has the profession |
| Your **skill levels** in those professions | guild, party or raid | A binding stops sending materials the friend has levelled past |
| The **day** of your last Auctionator scan | guild, party or raid | Telling a guildmate their prices are old when yours are fresh |
| Your guild's **template** (written by the guild master or officers, passed on by anyone) | guild | Who gets each profession's materials, for guildmates who turned it on: see [[Guild Template]] |
| What **the items you mailed someone were worth** when you sent them, and how old your scan was (and, when the receiver's Mailworthy settles on another value, that value back to you) | only the two players of that mail, in a whisper | Both [[Mail Ledger]]s value the mail the same way |

## What's never shared

- **Your prices.** Only the day you scanned, and the value of what you mailed a player, sent to that player alone.
- Your bags, your gold, your bank alt, your ledger balances.

Everything received is checked and treated as information only. It can only change mail you already set up: a friend's hello can move a binding's mail to their crafter alt, and their skill can stop a material they've levelled past from going to them. Your guild's [[Guild Template]] adds rules only after you turn it on yourself. It never mails to anyone not shown in your window, and every recipient is shown before you press Send.

## Who runs Mailworthy

Wherever Mailworthy's windows name a player (Friends, the Guild window, the "To:" lines at the mailbox, the Mail ledger, the bank alt picker), a small **Mailworthy icon** follows the name when that player runs Mailworthy too: their Mailworthy said hello, or it's a character their hello listed, or it's one of your own characters. The bottom of the window says "(icon) runs Mailworthy" whenever one shows, so you never need to hover. `/mw feature peerMark off` hides the icons.

## When it talks

- Shortly after you log in.
- When someone new comes online in your group.
- When another Mailworthy asks (for example when someone opens their Friends or Guild window).
- At the mailbox, after you've levelled past a material (so friends stop sending it).
- After you mail a player, to tell their Mailworthy what it was worth (as soon as they're online in your guild or group).

It talks to your **guild** and your **party or raid**, and whispers only the players you've exchanged mail with (what a mail was worth, so both ledgers agree).

## "Your auction prices are old"

Mailworthy's verdicts are only as good as your prices. Once your Auctionator prices are **over 3 days old**:

- the Mailworthy button gets a grey **!**,
- the window says so at the top.

If a guildmate or party member running Mailworthy **scanned in the last 2 days**, it gets louder:

- the **!** turns orange,
- the window names them ("Bob scanned yesterday"),
- one chat line tells you at the mailbox.

Past **7 days** Mailworthy stops trusting your prices: items that only have an old price count as unpriced and go to your bank alt to wait for a fresh one (see [[Price Sources]]). Logging in with old prices also asks nearby Mailworthys to say hello, so you find out who has fresh ones. The reminder itself never changes what gets mailed.

This needs Auctionator: TradeSkillMaster doesn't say how old its prices are.

## Turning it off

- `/mw feature comms off`: no messages at all, sent or received (whispers included).
- `/mw feature staleNudge off`: no price-age reminders.
- `/mw feature peerMark off`: no Mailworthy icons after names.
