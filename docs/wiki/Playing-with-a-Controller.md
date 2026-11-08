# Playing with a Controller

Everything in Mailworthy works with keyboard and mouse, and with a gamepad alone. Nothing needs right-clicks, dragging, hovering or typing: names are picked from lists, numbers use + and − buttons, and every toggle is a button that lights up while it's on.

| Task | Controller | Mouse / keyboard |
|---|---|---|
| Open Mailworthy at a mailbox | Switch to the Send Mail tab (**R1**): it opens by itself. **Triangle** closes and reopens it | Click the **Send Mail** tab, or **Mailworthy** under the mail window |
| Move around the window | **D-pad** moves Mailworthy's own gold highlight | Mouse |
| Press a button or row | **Cross** | Click |
| Keep an item (lock it) | Highlight its row, press **Cross**; or **L3** on it in your bags | Click its row; or Alt+click it in your bags |
| Skip a binding or your bank alt this visit | **Cross** on **Skip once** | Click **Skip once** |
| Send back what people mailed you | **Cross** on **Return to sender** | Click **Return to sender** |
| Close the window | **Circle** (or Triangle) | X or Escape |

On the Inbox tab nothing can be sent: pressing the Mailworthy button there tells you to press R1, and the greyed Send button reads **Send Mail tab: R1**.

When a controller is in use, each window's bottom line shows the buttons: Cross press, Circle close, D-pad move.

## Windows on top of windows

Press **Settings**, **Friends...** or **Ledger...** with Cross and the highlight moves into the new window at once. Close it (Circle, or the mouse) and the highlight goes back to the button that opened it. Settings, Friends, Guild and the Mail ledger all work with the controller away from a mailbox too.

## Staying out of the game's way

Mailworthy uses its **own** highlight and buttons in its own windows. It deliberately stays out of the game's built-in controller menus, because addons that hook into them can break jumping, targeting and item use until a /reload. Its buttons are only active while its window is open, never in combat, and they're released while the interface is hidden (Alt+Z), so Cross jumps again.

The minimap button is mouse-only (the controller can't reach minimap buttons); everything it opens is also reachable from the mailbox or a `/mw` command.

If a controller piece ever misbehaves, `/mw feature padTriangle off`, `padNav off` or `padLock off` (then `/reload`) turns just that piece off. See [[Commands and Troubleshooting]].
