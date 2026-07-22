# Mr. Plow - Improved Snow Prototype

This version replaces the large snow plates from the earlier prototype with a
much denser snow field and adds visual feedback intended to make shoveling feel
more physical.

## Improvements

- 29 x 29 removable snow grid
- 841 smaller snow sections
- Overlapping tiles to reduce visible seams
- Procedural snow shader with color variation and micro-surface variation
- Uneven snow depth and thicker snow near the driveway edges
- Small snow lumps distributed across the surface
- Snow banks around the driveway
- Snow caps on the roof, trees, and fence
- Animated snow pieces when they are removed
- Snow spray particles made from small procedural meshes
- Stronger shovel movement animation
- Improved winter lighting
- Visible driveway grooves after snow has been cleared

No external models, textures, plugins, or asset packs are required.

## Requirements

- Godot Engine 4.7 or newer
- Git, when working with the repository

The project uses the Compatibility renderer to remain usable on a broad range
of systems. It can be switched to Forward+ in the Godot project settings when
developing on a modern dedicated GPU.

## Installation

Close Godot before replacing the project files.

Extract the ZIP directly into the root of the existing `mr-plow` repository.
Allow existing files to be replaced.

On Linux Mint, when the ZIP is stored in the Downloads directory:

```bash
unzip -o ~/Downloads/mr-plow-improved-snow.zip \
  -d ~/Dokumente/Projekte/mr-plow
```

The archive replaces:

```text
project.godot
scenes/main.tscn
scripts/main.gd
scripts/player.gd
```

It does not contain `.git`, `.gitignore`, `LICENSE`, or the main `README.md`.

Open `project.godot` in Godot and press `F5`.

## Controls

| Input | Action |
|---|---|
| W, A, S, D | Move |
| Mouse | Look around |
| Left mouse button | Shovel snow |
| Space | Shovel snow |
| U | Purchase the next upgrade |
| R | Generate fresh snow |
| Escape | Release or capture the mouse cursor |

## Performance

This prototype creates 841 removable snow nodes. A modern desktop computer
should handle this comfortably, but the constants at the beginning of
`scripts/main.gd` can be changed:

```gdscript
const SNOW_GRID_SIZE := 29
const SNOW_TILE_SPACING := 0.72
const SNOW_TILE_SIZE := 0.78
```

Reducing `SNOW_GRID_SIZE` to `25` lowers the removable tile count from 841 to
625.

## Saving the Changes

After testing:

```bash
git add .
git commit -m "Improve snow density and shoveling effects"
git push
```

## Technical Note

The snow is still a prototype based on removable cells rather than a fully
deformable snow simulation. The smaller overlapping cells, varying heights,
surface shader, removal animation, and spray effect are intended to provide a
more convincing result while keeping the system understandable and editable.
