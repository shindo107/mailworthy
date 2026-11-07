# Material tier data for Mailworthy/TierData.lua (tools/tiers/build.py writes it).
# Research 2026-11-06: every Forever recipe per profession (zockify Forever recipe tables, Forever client
# 1.60.1.70790, checked against wago.tools DB2 for Tailoring and Blacksmithing; item IDs checked on
# nether.wowhead.com/forever/tooltip/item/<id>). A row = the skill at which every non-holiday recipe
# using the item (directly or through a part this profession makes) has gone grey; First Aid cloth
# uses the next bandage's learn skill instead (operator). Greys of 300 and up have no row: kept forever.
# Checked 2026-11-06 against Blizzard's Game Data API (namespace static-forever-us, build 1.60.1.70399):
# every item ID and name, every reagent the API reaches and all five leather conversions match. The API
# has no recipe colours, so every threshold is still unverified (the in-game tier check, TierCheck.lua).
# Rows: (itemID, skill, name, why). Only thresholds below 300 (anything used at 300+ has no row).
TAILORING = [
 (2589,115,"Linen Cloth","Soft-soled Linen Boots via bolt"),(2996,115,"Bolt of Linen Cloth",""),
 (2592,160,"Wool Cloth","Phoenix Pants / Gloves via bolt (Bindings learn 125?)"),(2997,160,"Bolt of Woolen Cloth",""),
 (3182,175,"Spider's Silk","Robes of Arcana, Silky Leggings"),
 (4337,215,"Thick Spider's Silk","Icy Cloak"),
 (4306,220,"Silk Cloth","Crimson Silk Gloves via bolt"),(4305,220,"Bolt of Silk Cloth",""),
 (10285,245,"Shadow Silk","Shadoweave Mask / Boots"),
 (4338,250,"Mageweave Cloth","Stormcloth Boots, Nether* Cuffs via bolt"),(4339,250,"Bolt of Mageweave",""),
]
BLACKSMITHING = [
 (2835,155,"Rough Stone","Ironforge Breastplate via Rough Grinding Stone"),(3470,155,"Rough Grinding Stone",""),
 (2770,185,"Copper Ore","Copper and Bronze Bar"),(2840,185,"Copper Bar","Sterling Silver Breastplate"),
 (2771,185,"Tin Ore","Bronze Bar"),(3576,185,"Tin Bar","Bronze Bar"),
 (2841,185,"Bronze Bar","Silvered Chain Leggings sets"),
 (2836,190,"Coarse Stone","Iron Counterweight via Coarse Grinding Stone"),(3478,190,"Coarse Grinding Stone",""),
 (3859,230,"Steel Bar","Steel Plate Helm"),
 (2838,260,"Heavy Stone","Shining Mithril Pants via Heavy Grinding Stone"),(3486,260,"Heavy Grinding Stone",""),
 (3858,285,"Mithril Ore","Truesilver Champion"),(3860,285,"Mithril Bar",""),
 (7912,290,"Solid Stone","Officer's / Sentinel's Waistguard via Solid Grinding Stone"),(7966,290,"Solid Grinding Stone",""),
]
ENGINEERING = [
 (260784,65,"SAF-T Tabs",""),(4405,80,"Crude Scope",""),
 (2835,95,"Rough Stone","Satchel of Copper Bombs via Rough Blasting Powder"),(4357,95,"Rough Blasting Powder",""),
 (4360,95,"Rough Copper Bomb",""),
 (249391,145,"Pyrite","9-60 Battery Pack"),(4361,155,"Copper Tube",""),
 (4380,175,"Big Bronze Bomb",""),(260794,180,"EZ-Thro Wrap",""),
 (2836,195,"Coarse Stone","SAF-T Bronze Bomb via Coarse Blasting Powder"),(4364,195,"Coarse Blasting Powder",""),
 (260796,195,"No Slip SAF-T Padding",""),
 (4359,210,"Handful of Copper Bolts",""),(4363,210,"Copper Modulator",""),(5507,210,"Ornate Spyglass",""),
 (3859,215,"Steel Bar","Gyromatic Micro-Adjustor"),  # Coal: no row, smelts into Azerothium (SAF-T, 300)
 (4375,225,"Whirring Bronze Gizmo",""),(249425,225,"Bauxite","Shafety Sheep via Sandpaper"),
 (249432,225,"Sandpaper",""),(260799,225,"SAF-T Bell",""),
 (4382,240,"Bronze Framework",""),(4387,240,"Iron Strut",""),(4394,240,"Big Iron Bomb",""),
 (260801,240,"EZ-Thro Fireproof Fuse",""),
 (2775,245,"Silver Ore","SAF-T Bomb via Silver Contact"),(2842,245,"Silver Bar",""),(4404,245,"Silver Contact",""),
 (2838,245,"Heavy Stone","SAF-T Bomb via Heavy Blasting Powder"),(4377,245,"Heavy Blasting Powder",""),
 (2772,265,"Iron Ore","Gnomish Rocket Boots via Gyrochronatom"),(3575,265,"Iron Bar",""),(4389,265,"Gyrochronatom",""),
 (2770,270,"Copper Ore","into Bronze"),(2840,270,"Copper Bar","own use 210; smelts into Bronze"),
 (2771,270,"Tin Ore","into Bronze"),(3576,270,"Tin Bar","into Bronze"),
 (2841,270,"Bronze Bar","Goblin Bomb Dispenser via Bronze Tube / Accurate Scope"),(4371,270,"Bronze Tube",""),
 (4407,270,"Accurate Scope",""),
 (260808,280,"EZ-Thro Tru-Trigger",""),(260804,290,"SAF-T Casing",""),(16005,295,"Dark Iron Bomb",""),
]
ENCHANTING = [
 (247786,25,"Mote of Magic","Bracer - Inferior Stamina"),
 (6338,170,"Silver Rod",""),
 (10978,180,"Small Glimmering Shard","Glimmering Staff, Orb of Souls"),
 (10938,180,"Lesser Magic Essence","Mystic Mushroom (Greater; pair unverified)"),(10939,180,"Greater Magic Essence",""),
 (10940,205,"Strange Dust","Chest - Lesser Absorption"),
 (10998,215,"Lesser Astral Essence","Chest - Minor Stats, Runed Golden Rod"),(11082,215,"Greater Astral Essence",""),
 (11084,215,"Large Glimmering Shard","Chest - Minor Stats"),(11128,215,"Golden Rod",""),
 (11083,230,"Soul Dust","Bracer - Stamina"),
 (11138,235,"Small Glowing Shard","Lesser Beastslayer"),
 (11144,260,"Truesilver Rod",""),
 (11134,265,"Lesser Mystic Essence","Bracer - Lesser Healing Power"),(11135,265,"Greater Mystic Essence",""),
 (11139,280,"Large Glowing Shard","2H - Lesser Strength"),
 (11137,285,"Vision Dust","Gloves - Strength"),
]
COOKING = [
 (1475,45,"Small Venom Sac",""),(2447,45,"Peacebloom",""),(6291,85,"Raw Brilliant Smallfish",""),
 (6303,85,"Raw Slitherskin Mackerel",""),(2672,90,"Stringy Wolf Meat",""),(5465,90,"Small Spider Leg",""),
 (2886,100,"Crag Boar Rib",""),(5466,100,"Scorpid Stinger",""),
 (6889,95,"Small Egg","Breakfast Omelette (Egg Nog is Winter Veil)"),(5467,115,"Kodo Meat",""),
 (785,125,"Mageroyal",""),(723,130,"Goretusk Liver",""),(2673,130,"Coyote Meat",""),(5468,130,"Soft Frenzy Flesh",""),
 (5469,130,"Strider Meat",""),(6289,130,"Raw Longjaw Mud Snapper",""),(6317,130,"Raw Loch Frenzy",""),
 (6361,130,"Raw Rainbow Fin Albacore",""),(2452,140,"Swiftthistle",""),(3172,140,"Boar Intestines",""),
 (3173,140,"Bear Meat",""),(3174,140,"Spider Ichor",""),(729,155,"Stringy Vulture Meat",""),
 (731,155,"Goretusk Snout",""),(2674,155,"Crawler Meat",""),(2924,160,"Crocolisk Meat",""),
 (21071,160,"Raw Sagefish",""),(2675,165,"Crawler Claw",""),(6522,165,"Deviate Fish",""),
 (251524,165,"Whimsyfin",""),(1468,170,"Murloc Fin",""),(2677,170,"Boar Ribs",""),(5051,170,"Dig Rat",""),
 (5503,170,"Clam Meat",""),(1080,175,"Tough Condor Meat",""),(1081,175,"Crisp Spider Meat",""),
 (5470,180,"Thunder Lizard Tail",""),(6308,180,"Raw Bristle Whisker Catfish",""),(3357,185,"Liferoot",""),
 (2251,190,"Gooey Spider Leg",""),(5637,195,"Large Fang",""),(3667,200,"Tender Crocolisk Meat",""),
 (1015,205,"Lean Wolf Flank",""),(5504,205,"Tangy Clam Meat",""),(3685,210,"Raptor Egg",""),
 (8959,220,"Raw Spinefin Halibut",""),(769,230,"Chunk of Boar Meat",""),(3731,230,"Lion Meat",""),
 (6362,230,"Raw Rockscale Cod",""),(3818,235,"Fadeleaf",""),(730,240,"Murloc Eye",""),
 (8838,250,"Sungrass",""),(3821,255,"Goldthorn",""),(4655,255,"Giant Clam Meat",""),
 (8365,255,"Raw Mithril Head Trout",""),(13890,255,"Raw Plated Armorfish",""),(21153,255,"Raw Greater Sagefish",""),
 (8146,270,"Wicked Claw",""),(4402,280,"Small Flame Sac",""),(12037,280,"Mystery Meat",""),
 (12204,280,"Heavy Kodo Meat",""),(12205,280,"White Spider Meat",""),(249796,285,"Hyjal Berries",""),
 (13465,290,"Mountain Silversage",""),
]

FIRST_AID = [
 (2589,80,"Linen Cloth","Wool Bandage learn 80"),(2447,95,"Peacebloom","Minor Healing Potion"),
 (2450,125,"Briarthorn","Lesser Healing Potion"),(2592,150,"Wool Cloth","Silk Bandage learn 150"),
 (1475,150,"Small Venom Sac","Anti-Venom"),(2453,175,"Bruiseweed","Healing Potion"),
 (4306,210,"Silk Cloth","Mageweave Bandage learn 210"),(3357,215,"Liferoot","Greater Healing Potion"),
 (4338,260,"Mageweave Cloth","Runecloth Bandage learn 260"),(8838,270,"Sungrass","Superior Healing Potion"),
 (4304,280,"Thick Leather","Leather Tourniquet"),
]
# Large Venom Sac, Golden Sansam, Rugged Leather, Huge Venom Sac; and Forever's poultices and Potent
# Anti-Venom (API check 2026-11-06): Swollen Venom Sac, Murloc Fin, Spider Ichor, Elemental Water,
# Essence of Water (their greys are unknown, so kept for good).
FIRST_AID_KEEP_FOREVER = [1288,13464,8170,19441,255645,1468,3174,7070,7080]

# Leatherworking: leather up-conversions use their direct grey; past it, Tiers.CONVERT decides by AH prices.
LEATHERWORKING = [
 (2934,40,"Ruined Leather Scraps","Light Leather recipe"),(5082,95,"Thin Kodo Leather",""),
 (7286,125,"Black Whelp Scale",""),(5784,130,"Slimy Murloc Scale",""),
 (2318,135,"Light Leather","own recipes; then converts to Medium"),(6471,140,"Perfect Deviate Scale",""),
 (7287,145,"Red Whelp Scale",""),(783,165,"Light Hide","class leather sets via Cured Light Hide (unverified)"),
 (4231,165,"Cured Light Hide",""),(2319,170,"Medium Leather","own recipes; then converts to Heavy"),
 (6470,170,"Deviate Scale",""),(4461,180,"Raptor Hide",""),
 (4232,205,"Medium Hide","Mender's mail via Cured Medium Hide"),(4233,205,"Cured Medium Hide",""),
 (7392,205,"Green Whelp Scale",""),(5785,205,"Thick Murloc Scale",""),
 (4234,215,"Heavy Leather","own recipes; then converts to Thick"),(7428,215,"Shadowcat Hide",""),
 (8368,240,"Thick Wolfhide",""),(8167,250,"Turtle Scale",""),
 (4235,265,"Heavy Hide","Mender's Leather Bracers via Cured Heavy Hide"),(4236,265,"Cured Heavy Hide",""),
 (8154,265,"Scorpid Scale",""),(8165,270,"Worn Dragonscale",""),
 (4304,275,"Thick Leather","own recipes; then converts to Rugged"),
 (8169,290,"Thick Hide","Mender's mail belts via Cured Thick Hide"),(8172,290,"Cured Thick Hide",""),
 (8150,290,"Deeprock Salt",""),(249428,290,"Pristine Hide",""),
]
CONVERT_LW = [(2934,2318,3),(2318,2319,4),(2319,4234,5),(4234,4304,6),(4304,8170,6)]

# Alchemy: levelling herbs only; herbs that still make level-60 potions have no row (operator: keep forever).
ALCHEMY = [
 (249399,90,"Frilled Lichen","Cerulean Dye"),(2447,120,"Peacebloom","Elixir of Minor Fortitude"),
 (765,120,"Silverleaf","Elixir of Minor Agility"),(249424,155,"Rosecap","Magenta Dye"),
 (785,185,"Mageroyal","Lesser Mana Potion"),(2450,190,"Briarthorn","Lesser Troll's Blood Elixir"),
 (2449,215,"Earthroot","Elixir of Ogre Strength"),(3356,235,"Kingsblood","Great Rage Potion"),
 (2453,240,"Bruiseweed","Troll's Blood Elixir"),(3357,250,"Liferoot","Nature Protection Potion"),
 (8153,250,"Wildvine","Wildvine Potion"),(3355,255,"Wild Steelbloom","Elixir of Defense"),
 (249274,270,"Stranglevine","Viridian Dye"),
]

# Materials outside the profession's own subclasses, kept while levelling (operator 2026-11-06:
# "levelling ones only"): (itemID, grey, name). Only greys below 300.
OUT = {
 197: [(7069,205,"Elemental Air"),(7070,205,"Elemental Water"),(7067,215,"Elemental Earth"),
       (7068,280,"Elemental Fire"),(7077,280,"Heart of Fire"),(7079,280,"Globe of Water"),
       (10286,250,"Heart of the Wild"),(7972,260,"Ichor of Undeath"),(2318,130,"Light Leather"),
       (2319,165,"Medium Leather"),(4234,215,"Heavy Leather"),(4304,250,"Thick Leather"),
       (8153,250,"Wildvine"),(8831,275,"Purple Lotus"),(249391,175,"Pyrite"),(2842,175,"Silver Bar"),
       (6037,250,"Truesilver Bar"),(3577,290,"Gold Bar"),(11082,175,"Greater Astral Essence"),
       (11134,190,"Lesser Mystic Essence"),(11137,235,"Vision Dust"),(11175,250,"Greater Nether Essence"),
       (16203,275,"Greater Eternal Essence"),(11178,280,"Large Radiant Shard"),(5500,160,"Iridescent Pearl"),
       (1210,175,"Shadowgem"),(5498,175,"Small Lustrous Pearl"),(3864,215,"Citrine"),(1529,250,"Jade"),
       (18240,295,"Ogre Tannin"),(7071,215,"Iron Buckle")],
 165: [(7067,290,"Elemental Earth"),(7070,290,"Elemental Water"),(5500,290,"Iridescent Pearl"),
       (3864,290,"Citrine"),(3182,290,"Spider's Silk"),(7971,290,"Black Pearl"),(14048,295,"Bolt of Runecloth"),
       (18240,295,"Ogre Tannin"),(8153,285,"Wildvine"),(7075,285,"Core of Earth"),(7077,265,"Heart of Fire"),
       (11176,255,"Dream Dust"),(4338,225,"Mageweave Cloth"),(11137,225,"Vision Dust"),(7079,245,"Globe of Water"),
       (8146,240,"Wicked Claw"),(4305,210,"Bolt of Silk Cloth"),(7071,215,"Iron Buckle"),
       (4096,215,"Coarse Gorilla Hair"),(4337,215,"Thick Spider's Silk"),(1210,205,"Shadowgem"),
       (1206,185,"Moss Agate"),(5498,175,"Small Lustrous Pearl"),(5637,175,"Large Fang"),(11083,175,"Soul Dust"),
       (249410,170,"Sulfuric Acid"),(2997,170,"Bolt of Woolen Cloth"),(3356,160,"Kingsblood"),
       (5116,150,"Long Tail Feather"),(10940,110,"Strange Dust"),(249409,170,"Cerulean Dye"),
       (8151,235,"Flask of Mojo"),(8152,255,"Flask of Big Mojo")],
 164: [(774,120,"Malachite"),(818,205,"Tigerseye"),(1210,255,"Shadowgem"),(1206,265,"Moss Agate"),
       (1705,265,"Lesser Moonstone"),(3864,280,"Citrine"),(1529,290,"Jade"),(13926,290,"Golden Pearl"),
       (5500,180,"Iridescent Pearl"),(5498,190,"Small Lustrous Pearl"),(5635,200,"Sharp Claw"),
       (5637,210,"Large Fang"),(7069,215,"Elemental Air"),(7068,215,"Elemental Fire"),(7070,215,"Elemental Water"),
       (7075,270,"Core of Earth"),(7972,275,"Ichor of Undeath"),(7081,285,"Breath of Wind"),
       (7079,290,"Globe of Water"),(2318,125,"Light Leather"),(2319,185,"Medium Leather"),
       (4234,255,"Heavy Leather"),(249427,280,"Pristine Leather"),(4304,285,"Thick Leather"),
       (2589,105,"Linen Cloth"),(4338,265,"Mageweave Cloth"),(8831,290,"Purple Lotus"),(8153,295,"Wildvine"),
       (10940,185,"Strange Dust"),(10938,185,"Lesser Magic Essence"),(11139,275,"Large Glowing Shard"),
       (249432,290,"Sandpaper"),(249410,290,"Sulfuric Acid")],
 202: [(774,270,"Malachite"),(1210,200,"Shadowgem"),(1705,265,"Lesser Moonstone"),(1529,285,"Jade"),
       (4611,225,"Blue Pearl"),(818,270,"Tigerseye"),(1206,200,"Moss Agate"),(3864,270,"Citrine"),
       (2318,160,"Light Leather"),(2319,230,"Medium Leather"),(4234,265,"Heavy Leather"),
       (2589,210,"Linen Cloth"),(2592,240,"Wool Cloth"),(10285,290,"Shadow Silk"),(4337,250,"Thick Spider's Silk"),
       (2996,225,"Bolt of Linen Cloth"),(4305,185,"Bolt of Silk Cloth"),(4339,290,"Bolt of Mageweave"),
       (249428,240,"Pristine Hide"),(10286,285,"Heart of the Wild"),(7972,280,"Ichor of Undeath"),
       (8153,285,"Wildvine"),(11175,235,"Greater Nether Essence"),(16203,280,"Greater Eternal Essence"),
       (8151,250,"Flask of Mojo"),(4402,175,"Small Flame Sac"),(8150,270,"Deeprock Salt"),
       (255007,80,"Golem Isospring"),(249409,145,"Cerulean Dye"),(249430,195,"Magenta Dye")],
 333: [(6037,275,"Truesilver Bar"),(12359,260,"Thorium Bar"),(7909,285,"Aquamarine"),(8838,285,"Sungrass"),
       (249391,265,"Pyrite"),(249410,265,"Sulfuric Acid"),(249424,265,"Rosecap"),(249425,265,"Bauxite"),
       (249432,265,"Sandpaper"),(7392,260,"Green Whelp Scale"),(7971,260,"Black Pearl"),(8170,260,"Rugged Leather"),
       (3819,250,"Wintersbite"),(5637,235,"Large Fang"),(7067,235,"Elemental Earth"),(7068,235,"Elemental Fire"),
       (5500,215,"Iridescent Pearl"),(2772,210,"Iron Ore"),(3356,210,"Kingsblood"),(6370,210,"Blackmouth Oil"),
       (6371,190,"Fire Oil"),(1210,180,"Shadowgem"),(2775,180,"Silver Ore"),(249399,180,"Frilled Lichen")],
 171: [(5635,130,"Sharp Claw"),(1288,185,"Large Venom Sac"),(5637,235,"Large Fang"),(4402,250,"Small Flame Sac"),
       (7972,270,"Ichor of Undeath"),(730,270,"Murloc Eye"),(249391,90,"Pyrite"),(3858,270,"Mithril Ore"),
       (3575,280,"Iron Bar"),(3860,280,"Mithril Bar"),(12359,290,"Thorium Bar"),(12363,290,"Arcane Crystal"),
       (251291,290,"Heavy Thorium Bar"),(248819,290,"Fel Crystal"),(6522,160,"Deviate Fish")],
}
# Kept forever outside the subclasses (no row): the operator's alchemy potion fish; a cook's
# own ingredients the game files under other classes.
KEEP_FOREVER = {
 129: FIRST_AID_KEEP_FOREVER,
 171: [6358],                         # Oily Blackmouth (Free Action Potion)
 185: [13755, 13893, 18255],          # Raw Winter Squid, Large Raw Mightfish, Runn Tum Tuber
}
