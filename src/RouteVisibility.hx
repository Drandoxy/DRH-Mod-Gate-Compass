package mods.gate_compass;

import openfl.geom.Point;

class RouteVisibility {
	public static inline final START_DISTANCE = 135.; // User-selected distance ahead of the character.

	public static function mask(points:Array<Point>, worldX:Float, worldY:Float, minimum:Float, maximum:Float):Array<Bool> {
		if (points == null || points.length < 2)
			return [];
		var nearest = -1;
		var best = Math.POSITIVE_INFINITY;
		var nearestT = 0.;
		var count = points.length - 1;
		for (i in 0...count) {
			var a = points[i];
			var b = points[i + 1];
			var dx = b.x - a.x;
			var dy = b.y - a.y;
			var length = dx * dx + dy * dy;
			var t = length == 0 ? 0. : Math.max(0, Math.min(1, ((worldX - a.x) * dx + (worldY - a.y) * dy) / length));
			var ex = a.x + dx * t - worldX;
			var ey = a.y + dy * t - worldY;
			var distance = ex * ex + ey * ey;
			if (distance < best) {
				best = distance;
				nearest = i;
				nearestT = t;
			}
		}
		var mask:Array<Bool> = [];
		var along = 0.;
		for (index in 0...count) {
			var a = points[index];
			var b = points[index + 1];
			var length = openfl.geom.Point.distance(a, b);
			if (index < nearest) {
				mask.push(false);
				continue;
			}
			if (index == nearest)
				along = -length * nearestT;
			var midpoint = along + length / 2;
			mask.push(midpoint >= minimum && midpoint <= maximum);
			along += length;
		}
		return mask;
	}

	public static function drawable(mask:Array<Bool>):Bool {
		for (value in mask)
			if (value)
				return true;
		return false;
	}
}
