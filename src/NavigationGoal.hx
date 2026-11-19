package mods.gate_compass;

import mods.api.dungeon.Tile;

/** A boss objective outranks decorative exit tiles in a multi-room arena. */
class NavigationGoal {
	public static function choose(tiles:Array<Tile>):Tile {
		var exit:Tile = null;
		for (tile in tiles) {
			if (boss(tile))
				return tile;
			if (exit == null && tile.category == "EXIT_TILE")
				exit = tile;
		}
		return exit;
	}

	public static function boss(tile:Tile):Bool {
		return tile != null && (tile.category == "BOSS_TILE" || tile.id == "454.1334956026168" || tile.id == "271.1333708475942");
	}

	public static function verified(tile:Tile, hasGate:Bool):Bool {
		return tile != null && (boss(tile) || hasGate);
	}
}
