# Mr. Plow - Procedural Levels Prototype

This build expands the snow removal prototype into a sequence of randomized
properties. Every completed property generates a new layout with different
houses, parked cars, bins, snow depth, and obstacle positions.

## Main Features

- Automatic level progression
- Randomized property layout for every level
- One to three procedural houses
- One to six parked cars depending on the level
- Cars may stand directly inside the snow-covered area
- Snow under solid obstacles is excluded from the completion requirement
- Solid collision around houses, cars, and bins
- Smaller dense snow cells with varied depth
- Procedural snow shader
- Snow spray and removal animation
- First-person controls
- Four visible equipment models
- Money carries between levels
- Purchased upgrades carry between levels
- Automatic progress saving between game sessions
- Completion bonuses that increase with level difficulty

No external models, textures, plugins, or asset packs are required.

## Requirements

- Godot Engine 4.7 or newer
- Git for contributing to the repository

The project uses Godot's Compatibility renderer by default. Developers using a
modern dedicated GPU may switch the project to Forward+.

## Installation

Close Godot before replacing files.

Extract the archive directly into the root of the existing `mr-plow`
repository and allow existing files to be replaced.

Example on Linux Mint:

```bash
unzip -o ~/Downloads/mr-plow-procedural-levels.zip \
  -d ~/Dokumente/Projekte/mr-plow
```

The archive replaces:

```text
project.godot
scenes/main.tscn
scripts/main.gd
scripts/player.gd
```

It does not include or overwrite:

```text
.git/
.gitignore
LICENSE
README.md
```

Open `project.godot` with Godot and press `F5`.

## Controls

| Input | Action |
|---|---|
| W, A, S, D | Move |
| Mouse | Look around |
| Left mouse button | Remove snow |
| Space | Remove snow |
| U | Purchase the next equipment upgrade |
| R | Generate fresh snow on the current property |
| Escape | Release or capture the mouse cursor |

## Level Progression

A level is complete when all accessible snow sections have been removed.
Snow located inside the collision footprint of a house, car, or bin is not
generated and therefore does not block completion.

After completion:

1. The player receives a completion bonus.
2. Money and equipment progress are saved.
3. The next level is generated automatically.
4. Houses, cars, bins, and snow depth are randomized again.
5. Later levels contain more obstacles and slightly deeper snow.

## Persistent Progress

Progress is saved to:

```text
user://mr_plow_progress.json
```

The saved values are:

- current level
- money
- purchased equipment level

The exact operating-system path is managed by Godot.

To start from the beginning, delete the application's Godot user-data folder
or remove `mr_plow_progress.json` from that folder.

## Project Structure

```text
mr-plow/
├── scenes/
│   └── main.tscn
├── scripts/
│   ├── main.gd
│   └── player.gd
├── project.godot
└── README_PROCEDURAL_LEVELS.md
```

## Important Code Areas

The procedural level system is located in:

```text
scripts/main.gd
```

Relevant functions include:

```gdscript
_start_level()
_generate_houses()
_generate_cars()
_generate_small_obstacles()
_generate_snow()
_finish_level()
_save_progress()
_load_progress()
```

The first-person controller and procedural equipment models are located in:

```text
scripts/player.gd
```

## Difficulty Scaling

The snow grid grows gradually from 29 x 29 to a maximum of 35 x 35 cells.

Obstacle counts also increase:

- houses: one to three
- cars: one to six
- bins: one to four

Higher levels also provide a larger per-tile payout and a larger completion
bonus.

## Contributing

Create a branch before making changes:

```bash
git checkout -b feature/procedural-improvement
```

After testing the project:

```bash
git add .
git commit -m "Add procedural levels and persistent progression"
git push origin feature/procedural-improvement
```

Open a pull request and describe:

- what was changed
- how it was tested
- whether save compatibility changed
- any expected performance impact

## Performance Notes

The maximum snow grid contains 1,225 cells before obstacle footprints are
removed. Cars and houses reduce the actual count.

For lower-end systems, reduce these values near the top of
`scripts/main.gd`:

```gdscript
const BASE_GRID_SIZE := 29
const MAX_GRID_SIZE := 35
const SNOW_TILE_SPACING := 0.68
```

A lower `MAX_GRID_SIZE`, such as `31`, reduces the maximum number of snow
nodes.

## Prototype Limitations

This remains a cell-based snow system rather than a physically deformable
snow simulation. The smaller overlapping cells, procedural surface material,
variable snow depth, removal animation, and particle spray are used to create
a more convincing shoveling effect while keeping the project understandable
and editable for contributors.
