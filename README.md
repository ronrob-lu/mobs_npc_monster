# Randomized Humanoids

This is a Luanti (formerly Minetest) mod that adds randomized attribute variation to humanoid monster-type mobs.
A critical aspect of this mod is its dual-game compatibility across the Minetest Game (MTG) ecosystem (using `mobs_redo`) and Mineclonia (using `mcl_mobs`). Since both games run on the single Luanti engine, they share the same rendering pipeline and logic underneath.

## Dual-Game Architecture

The mod detects at load-time whether `mobs_redo` or `mcl_mobs` is present and abstracts the registration process. Both APIs handle mobs slightly differently but underneath everything is hooked up to standard entity definitions. We normalize properties like health and damage and ensure compatibility regardless of which system is loaded.

## Asset Discovery & Requirements

The mod automatically scans `models/` and `textures/` to dynamically load mobs.

1. **Models:**
   - Drop GLB, B3D, or OBJ files into the `models/` folder.
   - Example: `zombie.glb`. The name of the mob is extracted as `zombie`.

2. **Textures:**
   - Place textures in the `textures/` folder.
   - The mod looks for an exact match (e.g., `zombie.png`) or variant prefixes (e.g., `zombie_variant1.png`).
   - All variants found will be applied. In MTG, mobs randomly choose between variant textures upon spawning.

3. **Spawn Egg Icons:**
   - An inventory icon must be placed in `textures/` named `inv_<character>.png` (e.g., `inv_zombie.png`).
   - If not found, the mod falls back to the first available character texture, but warns the user.
   - Using this egg spawns the mob using identical randomization logic as naturally generated ones.

## Model Formatting (GLB vs B3D)

Luanti interprets model formats similarly across games.
- **GLB** is natively supported but animation bounds are evaluated in SECONDS rather than frames. This mod contains an internal parser for GLB to detect the appropriate animation length bounds. The 180° Y-rotation issue common with GLB is resolved natively via a configuration flag.
- **B3D** is fully supported and recommended if GLB animation or rotation complexities become problematic. It uses frame-based animation limits.

### Animations

The mod seeks to map the following 25 animations across actions:
`static`, `idle`, `walk`, `sprint`, `sit`, `drive`, `die`, `pick-up`, `emote-yes`, `emote-no`, `holding-right`, `holding-left`, `holding-both`, `holding-right-shoot`, `holding-left-shoot`, `holding-both-shoot`, `attack-melee-right`, `attack-melee-left`, `attack-kick-right`, `attack-kick-left`, `interact-right`, `interact-left`, `wheelchair-sit`, `wheelchair-move-forward`, `wheelchair-move-back`, `wheelchair-move-left`, `wheelchair-move-right`.

Mapping differences between `mobs_redo` and `mcl_mobs` are abstracted gracefully.

## Customization

You can control variance amounts via Luanti's Settings menu. Under the hood, these values dictate randomized variation relative to the base values on initialization. (e.g. Health varies ±30%, Damage varies ±25%). The random seed uses the standard game state generator globally provided by Luanti.

## Installation
Since everything runs under the Luanti engine, installation is identical: drop the `randomized_humanoids` folder into the respective `/mods/` directory of your world or minetest path.

## Credits & License
- **Code:** Licensed under MIT by ronrob-lu.
- **Assets:** Licensed under CC0 1.0 Universal by Kenney.
Please refer to `LICENSE.md` for full texts.
