# Mail Ledger

Mailworthy keeps a log of every mail your characters send and everything they take out of the mailbox. It does two things with it: shows you where items went, and reminds you when someone sent you more than you've sent back.

Open it with `/mw ledger`, Settings → **Mail ledger...**, **Mail ledger...** in the Friends window, or **Ledger...** on the pay-back line of the mailbox window.

## The log

Every mail sent from any of your characters (Mailworthy's own Send and the game's Send button) and every item or gold taken out of the mailbox (one click, or Open All) is logged: the date, both names, the subject, each item with its count and value, and gold.

**Export log...** puts all of it in a box you can copy from, oldest first, so you can show anyone where items went. The newest 2000 entries are kept for each realm and faction.

## Paying back

When another player mails you more than you've mailed them back, you see it:

- in chat, when you take it: *Received 20 Linen Cloth (10s) from Bob. You've received 10s more from Bob than you've sent back.*
- at the top of the Mailworthy window, with a **Ledger...** button;
- in the **Mail ledger** window: one row per player, what they sent you, and **Mark paid**;
- on that player's binding in Friends: "(you've received 10s more from them)".

Pay back however you like: by mail, in materials or gold. It counts when it goes. Settled another way (a trade, gold in person)? Press **Mark paid**, then **Sure?**. The log keeps the record.

**Only your own side ever shows.** Mailworthy never lists who owes *you*.

## What counts

- Items and gold from **other players**, both ways.
- Not: your own characters, the auction house or other system mail, cash-on-delivery mail.
- A mail that comes back returned takes back what you sent.

## What things are worth

Values are taken **when the mail is sent**:

- What you send: your own auction price at the time.
- What you receive, when the sender runs Mailworthy too: their Mailworthy tells yours the value it took. If your own scan was more up to date that day, yours is used instead, and your Mailworthy tells theirs, so both of you see the same number. A sender's value never counts for more than 3 times your own price.
- Otherwise: your own price when you take it. An item with no price is listed by count only.

The export shows where each value came from and how old its scan was.

## Turning it off

`/mw feature ledger off`, then `/reload`, stops all of it: no log, no pay-back lines, and no [[Return to Sender]] (which reads the log).
