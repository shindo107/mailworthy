# The Mailbox Window

Open a mailbox and click the **Send Mail** tab: the Mailworthy window opens beside the mail window by itself. (You can also press **Mailworthy** under the mail window, on either tab.) It always shows you everything **before** anything is sent, and it only shows the parts that apply right now, so it's short when there's little to do.

Closed it on the Send Mail tab? It stays closed until you come back to that tab. Don't want it opening by itself? `/mw feature autoOpen off`, then `/reload`.

## From top to bottom

**To:** who gets mail this time.
- Usually just your bank alt: `To: Roknua — your bank alt`, with **Skip once** beside it (its share stays in your bags this visit; **Undo skip** brings it back).
- No bank alt? `To: No bank alt: what's worth selling stays`. On the bank alt itself: `This is your bank alt: what's worth selling stays`, with **Summary...** beside it. See [[Your Bank Alt]].
- With [[bindings|Friends and Bindings]] or [[Return to Sender]], one line per person, with what they get and how many mails: `Bob Surname — Enchanting materials · 1 mail`. If it goes to a friend's alt that has the profession, it says "(their crafter)". When there are more people than lines, the last line names the rest: `+ 2 more: Ann, Cid (see Mailing)`.
- A Mailworthy icon after a name means that player runs Mailworthy too. The bottom of the window says so whenever one shows.

**Stale prices line** (only when it applies): your Auctionator prices are getting old, maybe with the name of a guildmate who scanned recently. See [[Mailworthy Talks to Mailworthy]].

**Pay-back line** (only when it applies): *You've received 10s more from Bob than you've sent back.* with a **Ledger...** button. See [[Mail Ledger]].

**Bindings** (only when you have some): each binding with **Skip once** and **Remove** (a guild rule has only Skip once), plus **Friends...**. With guild rules in use, **Guild rules: on** turns them all off in one press. Each row shows the skill Mailworthy knows for the recipient: "(guild, skill 120)".

**Mailing:** every item that will be sent, grouped by who gets it (your bank alt first), with "N items · M mails". Each row has a coloured chip saying why it goes:

| Chip | Means |
|---|---|
| **Auction** | It sells for more on the AH (after fees) than at a vendor |
| **Disenchant** | Its enchanting materials are worth more than the item |
| **Bank** | Worth holding on the alt for a later phase of the realm (see [[How Mailworthy Decides]]) |
| **No price** | No auction price yet: your bank alt holds it until there is one |
| **Common** | Sent without a price: a white item with no price addon, or a staple trade good (see [[Price Sources]]) |
| **to Bob** | Goes to a friend through a binding or a guild rule |
| **back to Bob** | Goes back to the person who mailed it to you ([[Return to Sender]]) |

The number on the right is how much more it's worth than selling to a vendor. **Press a row to keep that item** (it gets locked and moves to Staying).

**Staying in your bags:** everything that stays, locked items first, each with a reason in plain words, for example:
- *sells better at a vendor*
- *only 50c more than a vendor (needs 1s)*
- *your First Aid needs it (until skill 150)*
- *convert it: 4 make a Medium Leather (pays more)*
- *Redridge Goulash needs it*
- *Auction +5s: no bank alt* (or *bank alt skipped*, *this is your bank alt*)
- *locked (press to unlock)*
- *junk: sell it at a vendor*
- *the price lookup failed*

Soulbound and quest items aren't listed at all (they can't be mailed anyway). Press a Staying row to lock or unlock it.

**Total:** "+1g 20s more than vendoring" (", 2 with no price yet" when some have no price), and under it the fees counted (AH cut, deposits, postage). Without a price addon: "N items to mail". While sending, this line shows progress ("Sending mail 2 of 3 to Bob..."), and afterwards what was sent or why it stopped.

**Buttons:**
- **Send**: "Send to Roknua", or "Send to Roknua, Bob" with friends. On the **Inbox** tab it's greyed out and reads **Click Send Mail**: mail only goes out from the Send Mail tab, and the window follows you there.
- **Settings**: see [[Settings]].
- **Return to sender**: lit and reading **Return to sender: on** while on. See [[Return to Sender]].

Close the window with its X, Escape, or Circle on a controller.

## If the list changes

When you press Send, Mailworthy looks at your bags once more. If anything would now go to someone the list didn't show (or in a different amount), nothing is sent: the list redraws, a line says what changed ("Not sent: ... Check the list, then press Send again."), and you press Send again.

## The Mailworthy button

The button sits under the mail window on both tabs. A **!** on it means your auction prices are getting old (grey) or a guildmate has fresher ones (orange).
