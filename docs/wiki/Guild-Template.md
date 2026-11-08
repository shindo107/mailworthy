# Guild Template

![One template for the whole guild](https://raw.githubusercontent.com/sjdodge123/mailworthy/main/media/gallery/05-guild-template.png)

*"Herbs to Ann, dust to Bob, cloth to Sela."* A **guild template** lets your guild master decide, once, who in the guild gets each profession's materials. Every guildmate running Mailworthy can turn it on, and from then on their mailbox sends those materials to the right person, the same way a [[binding|Friends and Bindings]] does.

It lives in its own window, **Guild materials**: Settings → **Guild...**, or `/mw guild`.

## For guild members

1. When your guild master publishes a template, you get one chat line, and the settings button reads **Guild (new template)...**. The Guild window shows **Guild template from ...: N rules (new)**, with every rule.
2. Press **Use guild rules**. Nothing is mailed to anyone in the guild before you do.
3. That's it. At the mailbox, the guild's rules show under **Bindings** marked "(guild)", and the top of the window names everyone who gets mail before you press Send.

When the guild master changes the template, your Mailworthy picks the change up on its own and tells you in chat.

### Turning it off

One press: **Guild rules: on**, in the Guild window or on the Bindings heading of the mailbox window. Your materials go back to your own rules straight away. The settings button then reads **Guild (rules off)...**; press **Guild rules: off** in the Guild window to turn them back on.

For a single visit, **Skip once** works on a guild rule like on any binding.

### You come first

- **Your own bindings win.** If you bound Enchanting to someone yourself, the guild's Enchanting rule is left out for you.
- **Your own professions win.** If you're a tailor, the guild's Tailoring rule is left out: you keep your cloth (see [[Profession Materials]]). The Guild window says why next to the rule: "(not here: you have Tailoring)".
- Everything that keeps an item in your bags still does: locks, soulbound and quest items, items a quest asks for, tools. See [[What Stays in Your Bags]].
- Each rule has a **price cap**, like a binding: at or above it, a material goes to your bank alt to be sold instead.

`/mw report` lists each guild rule that's left out for you, and why.

## What a rule sends

A rule is a profession binding, so it sends the same things: the profession's **primary materials** and its **recipes** (see [[Friends and Bindings]]). Herbs are **Alchemy**, cloth is **Tailoring**, dust and greens are **Enchanting**, metal and stone are **Blacksmithing** or **Engineering**, and so on. When two rules take the same material (metal and stone), it goes to whichever guildmate has the lower skill, so both keep levelling.

Class items ("Mage items") can't be guild rules; they're personal bindings only.

## For guild masters and officers

The guild master and the rank right below (usually officers) can make and change the template, in the same Guild window.

1. Open it: Settings → **Guild...**, or `/mw guild`. Without a template it says **No guild template yet: add a rule for each profession, then Publish to guild.**
2. Press **Add a rule...**, pick a guild member (or **yourself**: you're first in the list), then the profession whose materials they get.
3. Set each rule's price cap with **-** and **+**. One rule per profession: adding a second for the same profession replaces the first. **Remove** takes a rule out.
4. Press **Publish to guild**. Everyone in the guild running Mailworthy and online right now gets it. Whoever logs in later gets a copy from any guildmate who has it, so you don't need to be online. With nothing changed, the button reads **Send again**.

Your own copy turns on when you publish. You can turn it off for yourself like anyone else. A rule naming you sends you the guild's materials; your own Mailworthy never mails you.

## Good to know

- **Anyone can pass it on, only officers can write it.** Any guildmate running Mailworthy hands a copy to whoever logs in. Each copy names who wrote it, and your Mailworthy checks that person's rank in **your own** guild roster: a copy written by anyone below the officers is ignored, and so is any rule that names someone outside the guild.
- If someone ever passes on a copy in an officer's name that the officer never published, that officer's Mailworthy notices the next time it sees it and sends the real one again, which replaces it everywhere. Until then, the chat line names every rule, and the mailbox window shows every recipient before you press Send.
- No template showing? It comes from any guildmate running Mailworthy who has it, when you log in. If nobody with a copy was online, open the Guild window later to ask again.
- The template travels over the guild's hidden addon messages, never in chat: see [[Mailworthy Talks to Mailworthy]].
- A rule sends materials to the guildmate's character that has the profession, if they run Mailworthy too (never their bank alt).
- `/mw feature guildTemplate off` (then `/reload`) turns the whole feature off.
