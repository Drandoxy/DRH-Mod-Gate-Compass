package mods.gate_compass;

/** Cheap route sampling clock; rendering and camera motion remain independent. */
class RouteClock {
	public static inline final NORMAL_MS = 100;
	public static inline final LOW_POWER_MS = 150;
	public static inline final TELEPORT_DISTANCE = 160.;

	public static function urgent(dx:Float, dy:Float, crossedTarget:Bool, enteredRoom:Bool):Bool {
		return crossedTarget || enteredRoom || dx * dx + dy * dy >= TELEPORT_DISTANCE * TELEPORT_DISTANCE;
	}

	public static function interval(lowPower:Bool):Int {
		return lowPower ? LOW_POWER_MS : NORMAL_MS;
	}
}
