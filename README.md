# UlRemedyForever

A lightweight quality-of-life collection for **World of Warcraft: Forever**. Five small utilities in one addon, each individually toggleable with a slash command. Settings persist between sessions.

A separate addon from [UlRemedy](https://github.com/Knitresletta/UlRemedy) (retail). Only the features that make sense in Forever are included.

> **Status:** early port, written before the Forever beta opened. Not yet verified on the Forever client.

## Features

**Auto Repair**: Repairs your gear when you open a vendor. Guild bank funds first when they actually cover the cost, your own gold as fallback, and it only reports success once the repair is confirmed.

**Junk Seller**: Sells all grey items when you open a vendor.

**Group Invite**: Auto-accepts group invites from friends, Battle.net friends and guildmates. Unknown inviters are left for you to handle.

**Enhanced Trainer**: Adds a **Train All** button to trainers that learns everything you can afford in one click.

**Cursor Ring**: A dusty purple ring with a soft silver glow that follows your mouse cursor, visible on light and dark backgrounds alike.

## Commands

Type `/ur` to list every feature and its current state.

| Command | Description |
|---------|-------------|
| `/ur repair` | Toggle auto repair |
| `/ur junk` | Toggle junk seller |
| `/ur groupinvite` | Toggle group invite auto-accept |
| `/ur trainer` | Toggle the trainer Train All button |
| `/ur cursor` | Toggle the cursor ring |

## Installation

Copy the `UlRemedyForever` folder into the `Interface/AddOns/` folder of your World of Warcraft: Forever installation.
