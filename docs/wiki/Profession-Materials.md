# Profession Materials

Your crafters need their materials. Mailworthy keeps them in your bags instead of mailing them to the auction house, **until you've levelled past them**. Then they're sold like anything else, or sent to a friend who still needs them.

Don't want any of this? Settings → **Keep my professions' materials: off**. Then every material is judged on price like any other item and goes to your bank alt.

## What each profession keeps

Each crafting profession keeps its own kind of material:

| Profession | Keeps |
|---|---|
| Tailoring | cloth (and bolts, spider silks) |
| First Aid | cloth, plus the herbs, venom sacs, leather and poultice reagents Forever's First Aid uses (it makes the healing potions on Forever, plus Anti-Venoms, Tourniquets and Poultices) |
| Leatherworking | leather, hides and scales |
| Blacksmithing | metal and stone (ore, bars, stones) |
| Engineering | metal and stone, plus parts, explosives and devices |
| Alchemy | herbs |
| Enchanting | dust, essences, shards and rods |
| Cooking | meat, fish and the other things recipes call for |

On top of that, each profession keeps the **other** materials it levels with: a blacksmith's gems and low-level elementals, an engineer's cloth, a cook's tea herbs, a tailor's leather and pearls. But only **while levelling**: valuables a profession only uses at skill 300 (Essence of Water, Righteous Orb, Star Ruby, Arcanite Bar, Black Lotus...) still go to the auction house. Lock one to keep it (see [[Item Locks]]).

Gathering professions (Mining, Herbalism, Skinning, Fishing) keep nothing: what you gather is what you sell. A miner who is also a blacksmith keeps the ore for the blacksmithing. If you'd rather sell what you gather, turn on **Sell what I gather** in [[Settings]].

## Levelling past a material

Once your skill is high enough that a material no longer gives you skill-ups, there's no reason to hoard it. Mailworthy knows when that happens for every material:

- **First Aid cloth:** kept until the next bandage can be learned. Linen Cloth is done at **80** (Wool Bandage), Wool at **150**, Silk at **210**, Mageweave at **260**.
- **Everything else:** kept until **every recipe that uses it has turned grey** for you. That includes recipes that use it through something you make first: bolts of cloth, cured hides, grinding stones, blasting powders, engineering parts.
- **Never outgrown:** anything a recipe still uses at skill 300 (Runecloth, Rugged Leather, Thorium, Dream Dust and up). Those stay for good.

The window tells you where you stand: *your First Aid needs it (until skill 150)*.

### Some examples

| Profession | Kept until |
|---|---|
| Tailoring | Linen Cloth 115 · Wool 160 · Silk 220 · Mageweave 250 · Runecloth never |
| Leatherworking | Light Leather 135 · Medium 170 · Heavy 215 · Thick 275 (then see conversions below) · Light Hide 165 · Heavy Hide 265 |
| Blacksmithing | Rough Stone 155 · Copper and Bronze 185 · Steel 230 · Mithril 285 · **Iron Bar never** (Iron Buckles go into a skill-310 belt) |
| Engineering | Rough Stone 95 · Copper and Bronze Bar 270 (Bronze Tubes go into scopes and the Goblin Bomb Dispenser) · Iron 265 |
| Enchanting | Strange Dust 205 · Soul Dust 230 · Vision Dust 285 · Dream Dust never |
| Alchemy | Peacebloom and Silverleaf 120 · Mageroyal 185 · Bruiseweed 240 · Wild Steelbloom 255 |
| Cooking | each ingredient on its own, from Small Spider Leg 90 to Hyjal Berries 285 |

### Alchemy's potion herbs

Some herbs stop giving skill-ups but still make potions alchemists brew all the way to 60. Mailworthy keeps them **for good**: Swiftthistle (Swiftness Potion), Stranglekelp and Oily Blackmouth (Free Action Potion), Goldthorn, Khadgar's Whisker, Arthas' Tears, Purple Lotus and Wintersbite.

### Leather: convert or sell?

Leatherworkers can turn lower leather into higher leather: 3 Ruined Leather Scraps make a Light Leather, 4 Light make a Medium, 5 Medium a Heavy, 6 Heavy a Thick, 6 Thick a Rugged. So once you're past a leather's own recipes, Mailworthy checks the auction house:

- If the converted leather is worth **more** than the leather it takes, the leather stays: *convert it: 4 make a Medium Leather (pays more)*.
- If selling the leather as it is pays at least as much, it's mailed to be sold.
- If a price is missing, it stays, just in case.

## Where the numbers come from

Every one of Forever's recipes (over 2,000 across the eight crafting professions) was read one by one. That gave each recipe's skill levels and ingredients from Forever's own game data. Forever's recipes are **not** the same as old Classic's: many materials stay useful much longer, because of the new recipe sets.

The whole table is in the addon (`TierData.lua`). If you find a number that's wrong for you in game, please report it on CurseForge or GitHub.

### Checked against your own profession window

Live numbers can move, so Mailworthy also checks the table against your game. When you open one of your crafting professions, it reads the colour of every recipe you know. If a recipe that isn't grey yet still uses a material the table says you're done with, that material stays until the recipe turns grey, and the window says why: *your Tailoring needs it (Soft-soled Linen Boots still yellow)*. It only reads the window, it never clicks anything. `/mw report` lists what it found; `/mw feature tierCheck off` turns the check off.

## Friends' skills count too

If you send a profession's materials to a friend (see [[Friends and Bindings]]), Mailworthy applies the same rule to **their** skill. Once your friend's tailoring is past Linen Cloth, your linen goes to your bank alt instead.

A binding only sends a profession's **primary** materials (cloth to a tailor or a first-aider, herbs to an alchemist, and so on). The extras a profession levels with, like an engineer's cloth, a blacksmith's gems or a first-aider's herbs, stay on the normal rules.

To turn the tiers off and keep every material at any skill: `/mw feature tiers off`.
