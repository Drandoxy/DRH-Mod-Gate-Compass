# Gate Compass

<!-- drh:show -->
Find your way to the dungeon exit with **Gate Compass**. Choose **Original 2D**, **3D**, **3D + Line**, or **Line only** in the **Compass mode** setting.

The ground compass follows your hero with a ring and direction triangle that change color to contrast with the dungeon theme. Ring and triangle use the same tint and opacity; the original 2D arrow uses the same theme color. The optional lavender route appears on the ground beneath characters and foreground scenery. Both compass styles follow the same route direction, even when the line is hidden. The original 2D compass can be dragged and resized; ground-compass size is adjustable in Settings.

Routes are cached from the gate across the known map, with 36 starting routes per tile. The main spawn route is prioritized before the remaining cache warms. Routes account for walls, permanent obstacles, and traps; breakable props are ignored. New areas and changed obstacles update the cache. The line has softened edges and collision-checked rounded corners where space permits.

Inside the exit room, guidance leads to the gate even while it is closed. Boss-only rooms show **Defeat the boss** in Original 2D mode only. The compass hides during Settings, the exit dialog, and dungeon results.

Unused visual buffers and generated textures are released when changing display modes. Routing stays active for the selected mode; disabling Gate Compass stops its updates and clears the cache.
<!-- /drh:show -->

## Preview

<table>
<tr>
<td width="70%" align="center"><img src="docs/images/compass-gameplay.png" alt="Golden Gate Compass pointing toward the exit during a dungeon run" width="800"><br>Directions to the exit</td>
<td width="30%" align="center"><img src="docs/images/boss-objective.png" alt="Gate Compass displaying Defeat the boss on three centered lines" width="350"><br>Boss objective</td>
</tr>
</table>

## Changes in 0.2.0

- Added four compass display modes and a glowing lavender ground route.
- Added shared route caching, 36 starting routes per tile, and prioritized startup guidance.
- Improved obstacle handling, rounded corners, and fast direction changes.
- Added Settings visibility handling and visual-resource cleanup.
- Uses public host rendering interfaces through `extends`; tested with DRH 18.

## Changes in 0.2.1

- Added Compass Toggle, default Ctrl+Shift+Q, sharing the Enable Gate Compass setting.
- Turning off stops subscriptions and frame updates and releases route caches and visual resources.
- Boss objective text is shown only in Original 2D mode.

## Changes in 0.2.2

- Added automatic contrasting compass colors for all nine dungeon theme families.
- Ring and triangle share the same color; the 2D arrow follows the same palette.
- Theme selection runs on geometry refresh, without per-frame color calculations. The route remains lavender.

![Theme color examples](docs/images/compass-theme-preview.png)
