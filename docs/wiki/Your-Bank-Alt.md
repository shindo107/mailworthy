# Your Bank Alt

The bank alt is where everything ends up, and Mailworthy turns it into a to-do list. It's **optional**: without one, Mailworthy still works (see the end of this page).

## Picking one

Settings → **Choose...** (or **Change...** once you have one) opens **Who gets your mail?**:

- **Pick from the list:** your characters on this realm and faction that Mailworthy has seen.
- **This character is my bank alt:** press it while logged in on the bank alt itself (for example when it's on a second WoW account).
- **Or type a name:** for a character Mailworthy hasn't seen yet. Press **Use name** twice to confirm.

The bank alt is saved per realm and faction, so all your characters there send to the same place. See [[Getting Started]].

## Bag tags

Each item in the bank alt's bags gets a small corner tag, worked out again with **the bank alt's own, fresh prices** (the market may have moved since you mailed it):

| Tag | Do this |
|---|---|
| **AH** (blue) | List it on the auction house |
| **B** | Bank it: it should sell for more in a later phase of the realm (see [[How Mailworthy Decides]]). You can still list it any time; tags are advice. |
| **DE** (purple) | Disenchant it: the materials are worth more |
| **V** | Vendor it: today a vendor pays more |

A legend under your bags says what each tag means. The tags also show in Baganator, Bagnon, ArkInventory and BetterBags, and on Auctionator's Selling tab: see [[Bag Addons]].

Want the tags on all your characters, not just the bank alt? Settings → **Bag tags: every character**.

## Tooltips

Hover an item (or highlight it with a controller) and the tooltip adds:
- **Today's verdict**, with the price and how old it is.
- **Why it was mailed**: for example "Mailed for: Auction +8s 21c, Nov 6, from Roknua", or "Mailed for: No auction price yet".
- For an item without a tag, **why it stays**: "Stays in your bags: this is your bank alt (no auction price yet)."

If the market changed, you see both, so you know why it's here and what to do now.

## At the mailbox

On the bank alt, the Mailworthy window opens like on any other character, with a few differences:

- The top line says **This is your bank alt: what's worth selling stays**. Its own share is listed under Staying; it never mails itself.
- Your [[bindings|Friends and Bindings]] still mail from it, so it can pass cloth on to your guild's tailor.
- **Return to sender** sends back what your other characters (or other players) mailed it: see [[Return to Sender]].
- **Summary...** (top right, where other characters have Skip once) opens the summary below.

Prefer the old way, where the button opened only the summary? `/mw feature bankAltMail off`, then `/reload`.

## The summary

**Mailworthy: what to sell** sums up what to list and the expected gain, what to bank for later, what to disenchant, and what's now better at a vendor. Open it with **Summary...** in the bank alt's Mailworthy window, Settings → **Bank alt summary...**, or `/mw summary`. **Scan details** shows every item with the numbers.

## Skip once

On your other characters, the bank alt's "To:" line has a **Skip once** button. Pressed, the bank alt's share stays in your bags for this visit (bindings still go). **Undo skip** brings it back; it resets when you close the mailbox.

## No bank alt?

That's fine. The Mailworthy window still opens, and:

- the top line says **No bank alt: what's worth selling stays**;
- what would go to a bank alt is listed under Staying (*Auction +5s: no bank alt*);
- your bindings and Return to sender still mail;
- your own bags get the **AH / B / DE / V** tags, so you can sell it all yourself.

## On your main, after sending

After you press Send, the items left in your main's bags that sell better at a vendor get a **V** tag (grey junk too) for the rest of the session. Next time you pass a vendor, sell the V's. Locking an item removes its V.
