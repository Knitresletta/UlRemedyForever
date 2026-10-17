# UlRemedyForever

A lightweight quality-of-life collection for **World of Warcraft: Forever**. A dozen small utilities in one addon, each individually toggleable with a slash command. Settings persist between sessions.

A separate addon from [UlRemedy](https://github.com/Knitresletta/UlRemedy) (retail). Only the features that make sense in Forever are included.

> **Status:** tested in-game on the Forever beta client (build 1.60.1).

## Price sharing: what leaves your machine

Since 1.10.0 the addon **shares auction prices with other UlRemedyForever users on your realm**, and this is **on by default**. Read this before you decide to keep it.

- **How:** addons have no network access. The only way two addons can talk is addon messages over the game's chat system. The addon joins a chat channel named `UlRemedyAH` (kept out of your chat windows, but it takes a channel number) and sends addon messages there. Nobody sees them as text.
- **What is sent:** item ID, lowest buyout per unit and the age of that price, for the prices *this character saw itself* at the auction house in the last 24 hours, plus a short hello on joining that says how fresh your newest price is. The chat system attaches your character name to every message, as it does to all chat.
- **What is never sent:** gold, bag or bank contents, other characters, and prices you received from others (nothing is relayed, so nothing echoes around the channel).
- **When:** after a full scan (unless someone else's broadcast came in within the last ten minutes), and on request from a newly joined user who asks the user with the freshest data for a copy, whispered as addon messages to that user only.
- **What comes in:** prices from others are stored when they are newer than yours and shown in the tooltip with a "shared" tag, so you can tell them apart. Everything received is checked and bounded; garbage is dropped.
- **Off:** `/ur auctionshare` or the Price Sharing checkbox in `/ur`. The channel is left at once. `/ur ahshare` shows what has been sent and received.

## Features

**Auto Repair**: Repairs your gear when you open a vendor. Guild bank funds first when they actually cover the cost, your own gold as fallback, and it only reports success once the repair is confirmed.

**Junk Seller**: Sells all grey items when you open a vendor.

**Junk Deleter** (off by default): When your bags are full, deletes the cheapest grey item to free a slot, so you can keep looting. It only ever touches grey (junk) items, and skips locked items, quest items and items whose vendor price the client has not cached yet. "Cheapest" means the stack with the lowest total vendor value. It stays idle while a vendor window is open, since the junk seller sells the greys there instead. Each deletion is reported in chat with the item and its value. The Forever client only lets an addon delete an item in response to a click or key press, so when the silent routes are refused a small popup appears naming the item, and one click on **Delete** removes it. Cancelling the popup pauses the feature until your bags have a free slot again. Turn it on with `/ur junkdelete`.

**Vendor Window**: A bigger merchant window. Every item the vendor sells is shown in one scrollable grid instead of ten per page, with a search box, a quality filter (all, uncommon+, rare+, epic+), a usable-only checkbox and a sort order (vendor order, name, price, quality). Drag the grip in the bottom-right corner to resize the window; it remembers its size across characters. Buying works exactly as before (right-click buys, shift-click buys a stack, drag to the cursor), because the grid uses Blizzard's own item slots. The buyback tab uses the same grid. `/ur vendorreset` restores the default size.

**Vendor Bags**: A bag panel docked to the right of the vendor window showing everything in your bags. One click sells an item; green and better items ask for confirmation first, locked items, quest items and items without a vendor value are never sold. Shift-click links an item in chat. A search box dims everything that does not match. While the panel is on, Blizzard's own bags stay closed at vendors. Turn the panel off with `/ur vendorbags` to get the normal bags back.

**Group Invite**: Auto-accepts group invites from friends, Battle.net friends and guildmates. Unknown inviters are left for you to handle.

**Enhanced Trainer**: Adds a **Train All** button to trainers that learns everything you can afford in one click.

**Trainer Preview**: What your class trainer has for you, without walking there. The list is learned on each visit to your class trainer (every ability and rank with its level and price, remembered per class across your characters), so visit the trainer once and it is filled in. A **Trainer** tab in the spellbook, to the right of Blizzard's own tabs, shows what is available now with the total price, and what is coming up at which level. Hovering a line shows the spell's tooltip. On level up a chat line names the abilities that just became available and what they cost in total. Ranks you have replaced with a higher rank do not count as missing. A visit only adds to the list, it never shrinks it. Beast Training shares the trainer window and is left alone (Train All is hidden there too; the client blocks it), and a pet trainer's wares are filtered out by name. `/ur tp` prints diagnostics, `/ur tpreset` forgets the list for the current class.

**Cursor Ring**: A dusty purple ring with a soft silver glow that follows your mouse cursor, visible on light and dark backgrounds alike.

**Movable Windows**: The standard Blizzard windows (character, spellbook, talents, quest log, friends, guild, trainer, merchant, mail, bank, professions, and any other window Blizzard registers as a panel) and every bag can be dragged anywhere, overlap each other, and come back where you left them the next time they open. Click a window to bring it in front. The world map is included. The spellbook and talent window (one window on this client) is the exception: it stays under Blizzard's control, because detaching it breaks its cooldown display, but it can still be dragged and comes back where you left it, and windows it closes on opening are reopened. Escape still closes them. Positions are shared across your characters. `/ur winreset` forgets all saved positions; turning the feature off takes full effect after `/reload`. If your action bars ever vanish in combat, turn it off with `/ur windows` and `/reload`, and please report it.

**Bag Sort Button**: Blizzard's bag sort button is back on the combined bag. The Forever client draws its slot counter over the button in that corner, so it is there but cannot be seen or clicked; the addon moves it to the right end of the search box and shortens the search box to make room. Clicking it is Blizzard's own sort, nothing else. Separate bags are not touched, their backpack shows the button already.

**Minimap Button**: One button on the minimap for the whole Ul family. Left-click opens a menu with rows for the inventory browser and the playtime window, and one per installed sibling addon (UlDungeonCompanion, UlSource), right-click opens this addon's options, and hovering lists them. The options window is not in the menu, the right click is its row. Drag it around the minimap's edge; the spot is remembered. This addon owns the button and the menu; the others register themselves at login and have no button of their own. `/ur minimap` hides it, `/ur hub` prints what is registered.

**Inventory Tracker**: Remembers gold, bag contents and bank contents for every character you log in with. Hovering an item shows which of your characters have it and whether it sits in their bags or bank, with a total across characters. `/ur inv` opens a window where you can browse each character's items, search by name, and see gold per character and in total. The All characters view shows each item once, with the counts added up and every holder named; hover the row for the breakdown. Bags and gold update live; the bank is read each time you open it, so a character's bank snapshot is from their last bank visit. Characters you no longer play can be removed with the **Forget character** button.

**Playtime**: Remembers `/played` for every character you log in with and shows it in a window of its own: one bar per character in class color, longest first, the time at the end of each bar, and the total across all of them at the top. Hover a row for the time at the current level, the character's share and when it was last seen. The bar of the character you are on keeps growing while the window is open. The addon asks the client once a few seconds after login and keeps that one answer out of chat; a `/played` you type yourself prints as usual and updates the record. The record is brought up to date at logout and reload. `/ur played` or the Playtime row in the minimap button's menu opens the window, `/ur pt` prints diagnostics.

**Chat Copy**: A small Copy button at the chat frame's top-right corner opens the chat log in a window where the text can be selected and copied: everything is selected on open, so Ctrl+C copies the lot, and a drag selects part of it. Colour codes and link wrappers are stripped. The lines come from the selected chat tab, as many as the chat itself still keeps. `/ur chat` opens the window too.

**Dark Mode**: Turns Blizzard's frame borders dark grey: the bronze edges and corners around windows, bars, bags, unit frames, tooltips and the minimap. Backgrounds, pages, icons, portraits, bar fills and text are left alone, so content stays as it was inside darker frames. Off by default; the Dark Mode row under Interface turns it on, `/ur shade` sets how dark (0.35 by default, lower is darker). `/ur darkprobe` lists which frames were found and what was shaded in each, `/ur darkprobe mouse` names the frame under the mouse.

**Reagent Tooltip**: Items that are used as a reagent in a profession recipe get a "Used by: Alchemy, Engineering" line in their tooltip. Professions this character knows are green, the rest grey. Smelting counts as Mining, so ore shows Mining next to the professions that use the bars, and rogue poison materials show Poisons. Two sources feed it. A shipped table generated from game data by `tools/build_reagents.py` (currently from the vanilla 1.12 database, so it does not know recipes that are new in Forever), and what the addon learns in play: every time a profession window has its recipe list up, every recipe's reagents are read and remembered account-wide. Open each of your professions once and the line is right for Forever for those professions, on all your characters. Recipes the window does not list (unlearned drop recipes) are not seen, so learning only ever adds professions to an item, never removes one. `/ur rs` shows what has been learned, `/ur rsreset` forgets it.

**Auction Prices**: Items get an "Auction:" line in their tooltip with the lowest buyout per unit the auction house showed last time, and how long ago that was, right under the vendor sell price and in the same coin format. For a stack, a second line gives the price of the whole stack ("Auction x20:"). The game has no price database to ask, so the addon remembers what the auction house shows while you are there: everything you browse or search for is remembered on its own, and the whole list is read quietly each time you open the auction house when the last full scan is more than 15 minutes old (as often as the client allows). The quiet scan is read slowly, a few hundred auctions per frame, so it is not felt; the **Scan prices** button in the auction house window does the same at once. Prices are kept per realm and faction, account-wide. No average and no history, just the last thing the auction house showed. `/ur ah` prints what is known and which auction house data the client delivers, `/ur ahreset` forgets the prices for this realm and faction.

**Price Sharing**: Swaps auction prices with other UlRemedyForever users on your realm over a hidden chat channel, so one person's auction house visit fills everyone's tooltips. Shared prices are tagged "shared" in the tooltip and never override a price you saw yourself in the last ten minutes. See *Price sharing: what leaves your machine* at the top for exactly what is sent. `/ur ahshare` prints diagnostics.

**Flight Paths**: Shows every flight master for your faction on the world map, including the ones you have not discovered yet. Undiscovered ones are tinted red, drawn slightly larger and have a pulsing red ring behind them; the ones you know are drawn as the normal faction icon. On a continent map (all of Eastern Kingdoms or Kalimdor) every icon is drawn a quarter smaller so they do not crowd each other; zone maps keep the full size. The locations come from the Forever client's own flight path table (so new Forever zones such as Riverglades and Mount Hyjal are included) and are projected onto whichever map you have open. Flight points the game already draws itself are left alone. Clicking a pin sets a map waypoint where the client supports it. The Forever client currently reports every flight path as known, so the addon keeps its own list instead: each time you open a flight master, every path you can fly to from there is saved for that character (paths the flight master lists as unreachable are ignored, since on Forever that includes undiscovered ones). Until you have done that once, all paths show as undiscovered. `/ur fp` prints diagnostics for the open map.

**Transports**: Shows boats, zeppelins, the Deeprun Tram and the Darnassus portals on the world map, each with a tooltip naming where it goes. Dock and tower positions come from the Forever client's transport route table, and the tram and portal positions from its area trigger table, so the Forever-only routes (Stormwind Harbor, Southshore, Powderfuse Port, Zephras Isle) are included. Clicking a pin sets a map waypoint where the client supports it.

**Zone Levels**: The level range a zone is meant for and whose territory it is (Alliance, Horde, Contested), under the zone's name when the mouse rests on it on a continent map, colored for your level: yellow fits, green is easy, orange is soon, red is too high, grey is outgrown. The retail map has this line built in, but the Forever client has no level data for its zones, so the line stays empty; the addon fills it, and steps aside for any zone the client does give a range. The ranges are Forever's own, read from the beta client by ForeverChanges (`tools/fetch_zones.py` regenerates the table), and they differ from the classic ones in most zones. Zones the client has no range for yet (Mount Hyjal, Shen'dralas) show nothing. `/ur zones` prints every zone with its range and the zone maps the data does not know.

**Loot Rolls**: While a group loot roll is running, a small window lists every group member with what they chose (Need, Greed, Pass, Disenchant) and what they rolled, under the item's icon and name, so several rolls at once stay apart. The winner is shown for a few seconds after the roll ends. It sits to the right of the party frames by default; `/ur rollside` (or the button in `/ur`) cycles between right of the party frames, left of them, above the chat, and free, and dragging the window anywhere makes it free. `/ur rolltest` shows a fake roll with your current group so you can place it. The choices come from the game's loot history (the same data as Blizzard's loot history window), with the loot messages in chat as a fallback on clients that still print them.

## Options and commands

Type `/ur` to open the options window: one checkbox per feature, grouped under Vendor, Group, Interface, Items and Map, in the game's own style, in two columns, plus buttons for the inventory browser and the reset actions. Escape closes it. Every feature can also be toggled from chat with `/ur <feature>`, and `/ur help` prints the full command list.

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
| `/ur trainerpreview` | Toggle the Trainer tab in the spellbook and the level-up note |
| `/ur shade <0.2-1>` | How dark Dark Mode shades the frame art (lower is darker) |
| `/ur darkprobe [frame\|mouse]` | What Dark Mode found, every texture in one frame and whether it was shaded, or the name of the frame under the mouse |
| `/ur chat` | Open the chat log in a window the text can be copied from |
| `/ur tp` | Print trainer preview diagnostics (what is remembered, what is available now) |
| `/ur tpreset` | Forget the remembered trainer list for the current class |
| `/ur tplevel [n]` | What the level-up line would say at level n (current level when left out), and why |
| `/ur cursor` | Toggle the cursor ring |
| `/ur windows` | Toggle movable windows (drag Blizzard windows and bags; positions are remembered) |
| `/ur winreset` | Forget all saved window positions |
| `/ur win` | Print movable windows diagnostics, including the name of the window under the mouse |
| `/ur bagsort` | Toggle the sort button on the combined bag |
| `/ur minimap` | Toggle the minimap button |
| `/ur hub` | Print minimap button diagnostics and the Ul addons registered in its menu |
| `/ur errors` | Save this session's Lua errors and warnings, and the blocked actions behind the alert icon in the AddOns list (which function, how often, where from), to the saved variables and print a summary. Also done automatically on reload and logout. |
| `/ur inventory` | Toggle the inventory tracker (tooltip lines and scanning) |
| `/ur inv` | Open or close the inventory browser window |
| `/ur playtime` | Toggle playtime tracking |
| `/ur played` | Open or close the playtime window (a bar per character, total across them) |
| `/ur pt` | Print playtime diagnostics |
| `/ur reagents` | Toggle the reagent tooltip line |
| `/ur rs` | Print what the reagent tooltip has learned from profession windows |
| `/ur rsreset` | Forget what the reagent tooltip learned in play |
| `/ur auction` | Toggle the auction price tooltip lines and the Scan prices button |
| `/ur ah` | Print auction price diagnostics (items known, last scan, what the client offers) |
| `/ur ahreset` | Forget every auction price for this realm and faction |
| `/ur auctionshare` | Toggle price sharing with other users over the hidden chat channel |
| `/ur ahshare` | Print price sharing diagnostics (channel, sent, received, peers) |
| `/ur flightpaths` | Toggle flight path pins on the world map |
| `/ur transports` | Toggle boat, zeppelin, tram and portal pins on the world map |
| `/ur zonelevels` | Toggle zone level ranges under the zone name on continent maps |
| `/ur zones` | Print the zone level ranges and the zone maps the data does not know |
| `/ur rolls` | Toggle the loot roll window |
| `/ur rollside` | Cycle where the loot roll window sits (party frames, chat, free) |
| `/ur rolltest` | Show a test loot roll with your current group |
| `/ur fp` | Print flight path diagnostics for the open map |
| `/ur fpreset` | Forget this character's known flight paths and sync again at a flight master |
| `/ur jd` | Print junk deleter diagnostics (free slots, cheapest junk, last trigger) |

## For other Ul addons: joining the minimap menu

An addon gets a row in the minimap button's menu by registering once at `PLAYER_LOGIN`. The guard makes it a no-op when UlRemedyForever is not installed, so the addon keeps working on its own.

```lua
if UlRemedy and UlRemedy.Register then
    UlRemedy.Register({
        id = "UlSource",                                   -- unique, registering again replaces the row
        title = "UlSource",                                -- shown in the menu and the tooltip
        icon = "Interface\\AddOns\\UlSource\\media\\icon",  -- optional
        open = UlSource.ToggleWindow,                      -- called on click
    })
end
```

Add `## OptionalDeps: UlRemedyForever` to the addon's TOC so the client loads UlRemedyForever first. Nothing else is shared: no code, no saved variables.

## Installation

Copy the `UlRemedyForever` folder into the `Interface/AddOns/` folder of your World of Warcraft: Forever installation.
