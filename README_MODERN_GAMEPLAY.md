# Mr. Plow - Modern Gameplay Update

This update expands the procedural snow-removal prototype with a redesigned
HUD, a proper pause menu, a confirmed New Game action, and additional gameplay
systems intended to make each property more engaging.

## New Features

### Modern HUD

The interface now includes:

- Current level and contract type
- Property layout information
- Snow-clearing progress bar
- Current time, target time, and saved best time
- Money and current job earnings
- Combo multiplier
- Precision-clearing statistics
- Current equipment and clearing width
- Next equipment upgrade
- Compact control hints
- Redesigned level and completion banners

### New Game Button

A New Game button is available in both the HUD and pause menu.

Starting a new game displays a confirmation screen. Confirming the reset
returns the game to:

- Level 1
- Zero money
- Basic snow shovel
- No purchased upgrades
- No saved best times

The existing save file is overwritten with the new progress.

### Pause Menu

Press Escape to open the pause menu.

The pause menu contains:

- Resume
- New Game
- Quit

The world and level timer remain paused while the menu is open.

### Procedural Contracts

Each level receives a randomized contract modifier.

Available contract types include:

- Standard Residential
- Heavy Overnight Snow
- Morning Rush
- Crowded Driveway
- Careful Around Vehicles

Contracts can change:

- Snow depth
- Target completion time
- Number of parked vehicles
- Base payout
- Precision bonus value

### Time Targets and Star Ratings

Each property receives a calculated target time based on:

- Snow-cell count
- Number of houses
- Number of cars
- Contract type

Completing a property awards one to three stars.

Faster completion provides:

- Higher star ratings
- Additional time bonuses
- Better completion rewards

The best completion time for each level is stored in the save file.

### Combo System

Removing snow continuously builds a combo multiplier.

The multiplier increases after clearing groups of snow cells without a long
pause. The combo expires when the player stops clearing snow for too long.

The maximum multiplier is 3.00x.

### Precision Clearing

Snow close to houses, cars, and bins is treated as precision snow.

Precision snow:

- Uses a slightly different snow appearance
- Requires cleaning close to obstacles
- Provides an additional payout
- Is especially valuable during precision-focused contracts

### Existing Procedural Features

This version retains:

- Automatically generated levels
- Random house positions
- Random parked vehicles
- Cars placed directly within snow-covered areas
- Solid collisions for houses, cars, and bins
- Automatic level progression
- Persistent money and equipment upgrades
- Completion bonuses
- Dense removable snow cells
- Procedural snow surface variation
- Snow spray and shovel animation
- Increasing level size and obstacle count

## Requirements

- Godot Engine 4.7 or newer
- Git for repository contributions

The project uses the Compatibility renderer by default.

## Installation

Close Godot before replacing the project files.

Extract the archive into the root of the existing `mr-plow` repository and
allow existing files to be replaced.

Example on Linux Mint:

```bash
unzip -o ~/Downloads/mr-plow-modern-gameplay.zip \
  -d ~/Dokumente/Projekte/mr-plow
```

The archive replaces:

```text
project.godot
scenes/main.tscn
scripts/main.gd
scripts/player.gd
```

The archive does not include or overwrite:

```text
.git/
.gitignore
LICENSE
README.md
```

Open `project.godot` in Godot and press `F5`.

## Controls

| Input | Action |
|---|---|
| W, A, S, D | Move |
| Mouse | Look around |
| Left mouse button | Remove snow |
| Space | Remove snow |
| U | Purchase the next equipment upgrade |
| Escape | Open or close the pause menu |

The HUD also contains Menu and New Game buttons. Open the pause menu to make
the mouse cursor available.

## Saving

Progress is stored in:

```text
user://mr_plow_progress.json
```

The save data contains:

- Current level
- Money
- Purchased equipment level
- Best completion times

Money and equipment progress carry between levels.

## New Game Reset

To reset progress from inside the game:

1. Press Escape.
2. Select New Game.
3. Select Reset Progress.

The confirmation step prevents accidental resets.

## Main Files

```text
mr-plow/
├── scenes/
│   └── main.tscn
├── scripts/
│   ├── main.gd
│   └── player.gd
├── project.godot
└── README_MODERN_GAMEPLAY.md
```

Most gameplay, procedural generation, saving, contracts, bonuses, and HUD code
is located in:

```text
scripts/main.gd
```

The first-person controller and visible equipment models are located in:

```text
scripts/player.gd
```

## Testing Checklist

Before committing the update, verify:

1. The project opens without parser errors.
2. Escape opens and closes the pause menu.
3. Resume continues the same level and timer.
4. New Game opens a confirmation screen.
5. Cancel returns to the previous menu state.
6. Reset Progress starts at level 1 with zero money.
7. Clearing all snow advances to the next level.
8. Money and equipment remain available in the next level.
9. Restarting Godot loads the saved level, money, equipment, and best times.
10. Cars and houses block player movement.
11. Snow around obstacles can still be reached and cleared.
12. Combo and precision rewards update the HUD.

## Committing the Update

After testing:

```bash
git add .
git commit -m "Add modern HUD, new game menu, and contract gameplay"
git push
```

## Prototype Limitations

The snow remains a removable cell-based system rather than a physically
deformable snow simulation. The smaller cells, varied depth, procedural
material, removal animation, precision zones, and snow spray provide more
detailed feedback while keeping the project understandable for contributors.
