# What Stays in Your Bags

Mailworthy only ever mails what you see in the window, and only after you press **Send**. Some things it never mails, whatever they're worth, and nothing overrides them: not the price, not a friend's binding, not your guild's rules, not [[Return to Sender]].

| Always stays | Why |
|---|---|
| **Locked items** | You said so. See [[Item Locks]]. |
| **Soulbound and quest items** | The game won't let them be mailed. They're not even listed. |
| **Items an active quest asks for** | Crisp Spider Meat while Redridge Goulash is in your quest log, even though it isn't a "quest item". The window says *Redridge Goulash needs it*, and it never gets a vendor tag. Turn the quest in and it's judged like anything else. |
| **Items the game is using** | For example, an item on your cursor or in a trade window. |
| **Profession tools** | Fishing poles, Mining Pick, Blacksmith Hammer, Skinning Knife, Flint and Tinder, Arclight Spanner, Gyromatic Micro-Adjustor, enchanting rods. |
| **Your professions' materials** | Cloth for your tailor, herbs for your alchemist, and so on, until you've levelled past them. See [[Profession Materials]]. |
| **Items not loaded yet** | Right after login the game may not have an item's details; it's listed next time. |
| **Gold** | Never attached, never sent as cash on delivery. |

And these stay because of the numbers:

- Anything that sells **better at a vendor**, or not enough better on the AH to be worth the trip (the minimum gain, see [[How Mailworthy Decides]]).
- **Grey junk** with no auction price: sell it at a vendor.
- An item whose **price lookup failed**: Mailworthy never mails on a failed lookup.
- Without Auctionator or TSM, anything green or better that isn't a staple trade good (unless one of your bindings takes it). See [[Price Sources]].

## Your bank alt's share

What would go to your bank alt stays in your bags when:

- you **don't have a bank alt** (it's optional),
- you pressed **Skip once** beside your bank alt for this visit,
- you're **on your bank alt** (it sells what it has).

These items are listed under Staying with what they would have been and why, for example *Auction +5s: no bank alt*. Your bindings and Return to sender still mail.

## Hover to see why

While the Mailworthy window is open, hover any item in your bags (or highlight it with a controller) and the tooltip says what Mailworthy does with it. On your bank alt, on a character without one, or with Settings → **Bag tags: every character**, it does so any time:

- **Mailworthy [Auction]** *Auction price today: ...* (or **[Disenchant]**, **[Bank]**, **[Vendor now]**, with the numbers)
- **Mailworthy [Mail]** *Goes to your bank alt at the mailbox: no auction price yet.* (or to which friend)
- **Mailworthy [Keep]** *Stays in your bags: your Blacksmithing needs it (until skill 200).*

With the window open, the tooltip matches the window exactly.

## Safety checks while sending

Right before attaching each stack, Mailworthy checks that slot again. If the item moved, changed, got locked, or a quest now asks for it, it's skipped. If anything would now go to someone the list didn't show, nothing is sent: the list redraws and you press Send again. Mail only goes to the people shown in the window.
