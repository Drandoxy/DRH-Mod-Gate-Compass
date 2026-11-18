package mods.gate_compass;

/** Also catches exit/death/results menus covered by another popup. */
class CompassPause {
	public static function blocked(top:String, layers:String):Bool {
		for (layer in [
			"EXIT_DUNGEON",
			"EXIT_INFINITE_DUNGEON",
			"SETTINGS_MENU",
			"REVIVE_MENU",
			"DISTRIBUTED_DUNGEON_SUMMARY"
		])
			if (top == layer || (layers != null && layers.indexOf(layer + ", ") >= 0))
				return true;
		return false;
	}
}
