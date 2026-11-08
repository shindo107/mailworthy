# Bag Addons

Mailworthy draws two things on your bag icons: the **AH / B / DE / V** tags (see [[Your Bank Alt]]) and the **blue lock glow** (see [[Item Locks]]). Both work in the game's own bags and in the most popular bag addons with a Forever build, and the tags also show at the auction house in Auctionator.

| Where | Tags | Lock glow | Legend | Switch |
|---|---|---|---|---|
| The game's bags | yes | yes | under the bags | `bankAltTags`, `slotBorder` |
| **Baganator** | yes, in the icon corner you pick | yes | under the backpack | `baganatorTags` |
| **Bagnon** | yes | yes | under the inventory | `bagnonTags` |
| **ArkInventory** | yes | yes | under the bag window | `arkInventoryTags` |
| **BetterBags** | yes | yes | under the backpack | `betterBagsTags` |
| **Auctionator**'s Selling tab | yes | yes | (the bags' legend shows) | `auctionatorTags` |

Nothing needs hovering: the legend under each bag window says what the tags mean.

## When the tags show

The same in every one of them:

- on your **bank alt**;
- on a character with **no bank alt** set (it sells its own);
- on **every character**, with Settings → **Bag tags: every character**;
- on a main **after you press Send**: **V** tags on what's left for the vendor, for the rest of the session.

The lock glow shows while the Mailworthy window is open (or always, with Settings → **Lock glow: always**), and for a moment on a fresh lock.

## What gets nothing

- **Another character's bags**, when your bag addon can show them: they'd get this character's verdicts and locks, so they get no tags.
- **The bank**: bank items aren't valued, so no tags, but locked items there still glow.
- **The guild bank.**

## Baganator

Mailworthy's tag is one of Baganator's icon corner widgets, called **Mailworthy tags and lock glow**. It sits **top left** by default. Move it to another corner in Baganator's **Icons** settings and the tag follows. Take it out of every corner and Mailworthy draws nothing in Baganator.

## Auctionator's Selling tab

With Auctionator installed, the icons in its **Selling** tab's bag list, and the item you're about to post, show the same tag as in your bags, on the same characters. Mailworthy's tooltip lines show there too. A favourite that isn't in your bags gets no tag.

## Turning one off

Each has its own switch, for example `/mw feature bagnonTags off`, then `/reload`. `/mw report` has a "bag addon: ..." line for each bag addon and an "auctionator tags: ..." line, handy for a bug report.
