# UlRemedyForever

A lightweight quality-of-life collection for **World of Warcraft: Forever**. A dozen small utilities in one addon, each individually toggleable with a slash command. Settings persist between sessions.

A separate addon from [UlRemedy](https://github.com/Knitresletta/UlRemedy) (retail). Only the features that make sense in Forever are included.

> **Status:** tested in-game on the Forever beta client (build 1.60.1).

## Features

**Auto Repair**: Repairs your gear when you open a vendor. Guild bank funds first when they actually cover the cost, your own gold as fallback, and it only reports success once the repair is confirmed.

**Junk Seller**: Sells all grey items when you open a vendor.

**Junk Deleter** (off by default): When your bags are full, deletes the cheapest grey item to free a slot, so you can keep looting. It only ever touches grey (junk) items, and skips locked items, quest items and items whose vendor price the client has not cached yet. "Cheapest" means the stack with the lowest total vendor value. It stays idle while a vendor window is open, since the junk seller sells the greys there instead. Each deletion is reported in chat with the item and its value. The Forever client only lets an addon delete an item in response to a click or key press, so when the silent routes are refused a small popup appears naming the item, and one click on **Delete** removes it. Cancelling the popup pauses the feature until your bags have a free slot again. Turn it on with `/ur junkdelete`.

**Vendor Window**: A bigger merchant window. Every item the vendor sells is shown in one scrollable grid instead of ten per page, with a search box, a quality filter (all, uncommon+, rare+, epic+), a usable-only checkbox and a sort order (vendor order, name, price, quality). Drag the grip in the bottom-right corner to resize the window; it remembers its size across characters. Buying works exactly as before (right-click buys, shift-click buys a stack, drag to the cursor), because the grid uses Blizzard's own item slots. The buyback tab uses the same grid. `/ur vendorreset` restores the default size.

**Vendor Bags**: A bag panel docked to the right of the vendor window showing everything in your bags. One click sells an item; green and better items ask for confirmation first, locked items, quest items and items without a vendor value are never sold. Shift-click links an item in chat. A search box dims everything that does not match. While the panel is on, Blizzard's own bags stay closed at vendors. Turn the panel off with `/ur vendorbags` to get the normal bags back.

**Group Invite**: Auto-accepts group invites from friends, Battle.net friends and guildmates. Unknown inviters are left for you to handle.

**Enhanced Trainer**: Adds a **Train All** button to trainers that learns everything you can afford in one click.

**Cursor Ring**: A dusty purple ring with a soft silver glow that follows your mouse cursor, visible on light and dark backgrounds alike.

**Movable Windows**: The standard Blizzard windows (character, spellbook, talents, quest log, friends, guild, trainer, merchant, mail, bank, professions, and any other window Blizzard registers as a panel) and every bag can be dragged anywhere, overlap each other, and come back where you left them the next time they open. Click a window to bring it in front. The world map is included. The spellbook and talent window (one window on this client) is the exception: it stays under Blizzard's control, because detaching it breaks its cooldown display, but it can still be dragged and comes back where you left it, and windows it closes on opening are reopened. Escape still closes them. Positions are shared across your characters. `/ur winreset` forgets all saved positions; turning the feature off takes full effect after `/reload`. If your action bars ever vanish in combat, turn it off with `/ur windows` and `/reload`, and please report it.

**Inventory Tracker**: Remembers gold, bag contents and bank contents for every character you log in with. Hovering an item shows which of your characters have it and whether it sits in their bags or bank, with a total across characters. `/ur inv` opens a window where you can browse each character's items (or all at once), search by name, and see gold per character and in total. Bags and gold update live; the bank is read each time you open it, so a character's bank snapshot is from their last bank visit. Characters you no longer play can be removed with the **Forget character** button.

**Reagent Tooltip**: Items that are used as a reagent in a profession recipe get a "Used by: Alchemy, Engineering" line in their tooltip. Professions this character knows are green, the rest grey. Smelting counts as Mining, so ore shows Mining next to the professions that use the bars, and rogue poison materials show Poisons. Two sources feed it. A shipped table generated from game data by `tools/build_reagents.py` (currently from the vanilla 1.12 database, so it does not know recipes that are new in Forever), and what the addon learns in play: every time a profession window has its recipe list up, every recipe's reagents are read and remembered account-wide. Open each of your professions once and the line is right for Forever for those professions, on all your characters. Recipes the window does not list (unlearned drop recipes) are not seen, so learning only ever adds professions to an item, never removes one. `/ur rs` shows what has been learned, `/ur rsreset` forgets it.

**Flight Paths**: Shows every flight master for your faction on the world map, including the ones you have not discovered yet. Undiscovered ones are tinted red, drawn slightly larger and have a pulsing red ring behind them; the ones you know are drawn as the normal faction icon. The locations come from the Forever client's own flight path table (so new Forever zones such as Riverglades and Mount Hyjal are included) and are projected onto whichever map you have open. Flight points the game already draws itself are left alone. Clicking a pin sets a map waypoint where the client supports it. The Forever client currently reports every flight path as known, so the addon keeps its own list instead: each time you open a flight master, every path you can fly to from there is saved for that character (paths the flight master lists as unreachable are ignored, since on Forever that includes undiscovered ones). Until you have done that once, all paths show as undiscovered. `/ur fp` prints diagnostics for the open map.

**Transports**: Shows boats, zeppelins, the Deeprun Tram and the Darnassus portals on the world map, each with a tooltip naming where it goes. Dock and tower positions come from the Forever client's transport route table, and the tram and portal positions from its area trigger table, so the Forever-only routes (Stormwind Harbor, Southshore, Powderfuse Port, Zephras Isle) are included. Clicking a pin sets a map waypoint where the client supports it.

## Commands

Type `/ur` to list every feature and its current state.

| Command | Description |
|---------|-------------|
| `/ur repair` | Toggle auto repair |
| `/ur junk` | Toggle junk seller |
| `/ur junkdelete` | Toggle the junk deleter (deletes the cheapest grey item when bags are full; off by default) |
| `/ur vendor` | Toggle the vendor window (scrollable grid, search, filters, sorting, resizable) |
| `/ur vendorbags` | Toggle the bag panel docked to the vendor window |
| `/ur vendorreset` | Reset the vendor window to its default size |
| `/ur groupinvite` | Toggle group invite auto-accept |
| `/ur trainer` | Toggle the trainer Train All button |
| `/ur cursor` | Toggle the cursor ring |
| `/ur windows` | Toggle movable windows (drag Blizzard windows and bags; positions are remembered) |
| `/ur winreset` | Forget all saved window positions |
| `/ur win` | Print movable windows diagnostics, including the name of the window under the mouse |
| `/ur inventory` | Toggle the inventory tracker (tooltip lines and scanning) |
| `/ur inv` | Open or close the inventory browser window |
| `/ur reagents` | Toggle the reagent tooltip line |
| `/ur rs` | Print what the reagent tooltip has learned from profession windows |
| `/ur rsreset` | Forget what the reagent tooltip learned in play |
| `/ur flightpaths` | Toggle flight path pins on the world map |
| `/ur transports` | Toggle boat, zeppelin, tram and portal pins on the world map |
| `/ur fp` | Print flight path diagnostics for the open map |
| `/ur fpreset` | Forget this character's known flight paths and sync again at a flight master |
| `/ur jd` | Print junk deleter diagnostics (free slots, cheapest junk, last trigger) |

## Installation

Copy the `UlRemedyForever` folder into the `Interface/AddOns/` folder of your World of Warcraft: Forever installation.
