# MiyoHUD

MiyoHUD is a compact [Windower 4](https://www.windower.net/) HUD for Final Fantasy XI. It combines target information, monster details, and character point progress in one draggable overlay.

## Features

- Displays the selected target's hex ID and distance.
- Shows target names using colors based on target type.
- Shows monster HP, family, job, level range, aggro behavior, and linking behavior when data is available.
- Tracks EXP, Limit Points/Merits, and Capacity Points/Job Points.
- Keeps a fixed four-row layout to avoid resizing when targets change.
- Saves the HUD position through Windower's configuration system.

## Requirements

- Windower 4
- The standard Windower Lua libraries: `luau`, `texts`, `config`, `packets`, `resources`, and `sqlite3`
- The included `database.db` file for monster details

## Installation

1. Download or clone this repository.
2. Copy the complete `MiyoHUD` folder into your Windower `addons` directory. Keep `MiyoHUD.lua` and `database.db` together.
3. Start Windower and enter the following command in the FFXI chat window:

   ```text
   //lua load MiyoHUD
   ```

To load MiyoHUD automatically, add this line to your Windower `scripts/init.txt` file:

```text
lua load MiyoHUD
```

## Commands

| Command | Description |
| --- | --- |
| `//mh pos <x> <y>` | Moves the HUD to the specified screen coordinates and saves the position. |
| `//mh show` | Shows the HUD. |
| `//mh hide` | Hides the HUD. |
| `//mh db` | Checks whether the monster database is available. |
| `//mh dbreload` | Closes and reloads the monster database. |
| `//mh reload` | Reloads MiyoHUD. |
| `//mh unload` | Unloads MiyoHUD. |

The overlay can also be dragged with the mouse. Its position is saved automatically.

## Notes

- Monster details are matched by monster name and current zone. If `database.db` is missing or cannot be opened, the rest of the HUD continues to work.
- The HUD is hidden while zoning and when no character is logged in.
- MiyoHUD currently targets English resource and database names.

## Author

Created by [k0de-0x16](https://github.com/k0de-0x16).
