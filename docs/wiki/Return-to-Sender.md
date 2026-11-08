# Return to Sender

Your bank alt has a bag full of things your mains sent it, and now you want some of it back. Or a friend mailed you materials you can't use. **Return to sender** puts everything someone mailed you on the Mailing list, addressed back to them, in one press.

## Using it

1. At a mailbox, open the Mailworthy window (any character: mains and the bank alt alike).
2. Press **Return to sender**, next to Settings. It lights up and reads **Return to sender: on**, and one chat line says what goes back: *Return to sender on: 3 stacks go back to Ann, Bob. Check the list, then press Send.*
3. Check the list. Each returned item has a **back to Bob** chip, and every person who gets something back has their own "To:" line.
4. Press **Send**.

Press the button again to go back to the normal list. It also turns itself off when you close the mailbox.

## What goes back

- Whatever another character mailed **this** character: one of your own characters, a friend, a guildmate.
- Up to what they sent and you haven't mailed back to them since. If Bob sent you 20 Linen Cloth and you already mailed him 5, up to 15 go back.
- **Whole stacks only**, biggest first, never more than is owed. A stack bigger than what's owed stays and follows the normal rules.
- At **any price**, even what a vendor would pay more for.
- If two people sent you the same item, the latest sender comes first.

A return comes before a binding and before your bank alt. Whatever isn't going back is judged like any other item.

## What never goes back

- Anything that always stays: locked items, soulbound and quest items, items an active quest asks for, tools. See [[What Stays in Your Bags]].
- Mail from the auction house or other system mail, cash-on-delivery mail (you paid for it), and your own mail that came back to you.

## How it knows

Return to sender reads the [[Mail Ledger]]: who sent you what, and what you've taken out of the mailbox. So it only knows about mail you took since the ledger came in (Mailworthy 0.25). If the ledger shows nothing, the chat line says so.

Returned items go in their own mail, with the subject **Mailworthy 1/2: returned to you**.

## With a controller

Move the highlight to **Return to sender** with the D-pad and press **Cross**. See [[Playing with a Controller]].

## Turning it off

`/mw feature returnToSender off`, then `/reload`, removes the button. It's also gone while the mail ledger is off (`/mw feature ledger off`).
