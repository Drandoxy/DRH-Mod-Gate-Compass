# Gate Compass

<!-- drh:show -->
Gate Compass points toward the dungeon gate with optional 2D, ground and Pathfinder guides.

## Guides

- **2D Compass**: a golden compass you can drag and resize.
- **3D Compass**: a ground ring and direction triangle, coloured for the dungeon theme.
- **Pathfinder**: a lavender path with collision-checked curves and fading ends.

Enable each independently. Both compasses aim toward a far visible point along the route, with collision and trap checks, even when the line is hidden. Guidance accounts for walls, permanent obstacles and traps, while ignoring breakable props. Supported boss-only rooms show **Defeat the boss**.

## Settings

Use the five switches in **MODS** for 2D, 3D, Pathfinder, smoothing and low power. For the seven appearance sliders, open **MODS > Gate Compass > Adjust appearance**, or press **Ctrl + Shift + G**.

- Adjust circle/arrow sizes, stroke widths and arrow distance.
- **Line length**: 300–2,200 world units; default 2,200.
- **Line start distance**: 0–500 world units from your hero; default 135. It is capped below line length so a section remains visible. This does not change the compass steering target.
- **Smooth Compass** gives smooth turns; turn it off for immediate direction changes.
- **Reset** restores appearance defaults without moving the panel. Settings, positions and sizes save automatically.

The appearance panel defaults to the side. Move the appearance panel by its title bar; its bottom-right corner resizes it. **Ctrl + Shift + Q** toggles navigation and releases its caches when off.

## Low power mode

**Low power mode** combines lighter drawing effects with smaller navigation work budgets and slower updates. The live route uses a reusable destination field, updates the nearby bend as you move, and animates close route changes after collision checks. Navigation pauses behind game menus and releases its resources when all guides are off or you leave.
<!-- /drh:show -->

## In-game previews

<table>
<tr>
<td width="50%" align="center"><a href="docs/images/compass-with-effects.png"><img src="docs/images/compass-with-effects.png" alt="2D compass, 3D compass and Pathfinder with effects enabled" width="600"></a><br><strong>With Effects</strong></td>
<td width="50%" align="center"><a href="docs/images/compass-reduced-effects.png"><img src="docs/images/compass-reduced-effects.png" alt="2D compass, 3D compass and Pathfinder with Reduced Effects enabled" width="600"></a><br><strong>Reduced Effects</strong></td>
</tr>
</table>

### Settings

<a href="docs/images/compass-settings.png"><img src="docs/images/compass-settings.png" alt="Compass settings with display switches, Smooth Compass, Reduced Effects, appearance sliders and Reset" width="420"></a>

## Install

Use **DRH Launcher** to install Gate Compass when available in its mod catalogue, or download the ZIP from the [latest release](https://github.com/Drandoxy/DRH-Mod-Gate-Compass/releases/latest) and install it through the launcher.

Requires **Dungeon Rampage Haxe 18** and **Mod API 1.4 or later**, including API 1.5. Release history is available on the [Releases page](https://github.com/Drandoxy/DRH-Mod-Gate-Compass/releases).

The live guide reuses a destination field. Normal steering updates at about 10 Hz, with earlier updates at corners, room changes and large jumps. Line animation stays independent of the navigation clock.
