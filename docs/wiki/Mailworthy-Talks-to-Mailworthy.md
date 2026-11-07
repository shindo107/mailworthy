# Mailworthy Talks to Mailworthy

When you and your guildmates (or party) all run Mailworthy, the addons quietly say hello to each other using WoW's hidden addon messages. Nothing appears in chat. This makes two things work better: [[bindings|Friends and Bindings]] and fresh prices.

## What's shared

| Shared | Used for |
|---|---|
| Which of your characters on this realm and faction have which **crafting professions** | A binding reaches the friend's character that actually has the profession |
| Their **skill levels** in those professions | A binding stops sending materials the friend has levelled past |
| The **day** of your last Auctionator scan | Telling a guildmate their prices are old when yours are fresh |
| Your guild's **template** (written by the guild master or officers, passed on by anyone) | Who gets each profession's materials, for guildmates who turned it on: see [[Guild Template]] |

## What's never shared

- **Prices.** Only the day you scanned, never what anything costs.
- Your bags, your gold, your bank alt, your mail.

Everything received is checked and treated as information only: it can never make your Mailworthy mail something it otherwise wouldn't, or to anyone not shown in your window. The one exception is your guild's [[Guild Template]], and only after you turn it on yourself; even then every recipient is shown before you press Send.

## When it talks

- Shortly after you log in.
- When your group changes.
- When another Mailworthy asks (for example when someone opens their Friends window).
- At the mailbox, after you've levelled past a material (so friends stop sending it).

It talks to your **guild** and your **party or raid** only.

## "Your auction prices are old"

Mailworthy's verdicts are only as good as your prices. Once your Auctionator prices are **over 3 days old**:

- the Mailworthy button gets a grey **!**,
- the window says so at the top.

If a guildmate or party member running Mailworthy **scanned in the last 2 days**, it gets louder:

- the **!** turns orange,
- the window names them ("Bob scanned yesterday"),
- one chat line tells you at the mailbox.

Past **7 days** Mailworthy stops trusting your prices, and items with only old prices stay in your bags until you scan. Logging in with old prices also asks nearby Mailworthys to say hello, so you find out who has fresh ones. The nudge never changes what gets mailed.

## Turning it off

- `/mw feature comms off`: no messages at all, sent or received.
- `/mw feature staleNudge off`: no price-age reminders.
