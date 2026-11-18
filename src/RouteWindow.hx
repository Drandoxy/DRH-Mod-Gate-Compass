package mods.gate_compass;

import openfl.geom.Point;

/** Keep full plans cached, but tessellate only a bounded neighbourhood. */
class RouteWindow {
	public static function cut(points:Array<Point>, x:Float, y:Float, ahead:Float):Array<Point> {
		if (points == null || points.length < 2)
			return [];
		var nearest = 0;
		var best = Math.POSITIVE_INFINITY;
		var fraction = 0.;
		for (i in 0...points.length - 1) {
			var a = points[i];
			var b = points[i + 1];
			var dx = b.x - a.x;
			var dy = b.y - a.y;
			var square = dx * dx + dy * dy;
			var t = square == 0 ? 0. : Math.max(0, Math.min(1, ((x - a.x) * dx + (y - a.y) * dy) / square));
			var ex = a.x + t * dx - x;
			var ey = a.y + t * dy - y;
			var distance = ex * ex + ey * ey;
			if (distance < best) {
				best = distance;
				nearest = i;
				fraction = t;
			}
		}
		var a = points[nearest];
		var b = points[nearest + 1];
		var length = Point.distance(a, b);
		var startT = length == 0 ? 0. : Math.max(0, fraction - 500 / length);
		var start = new Point(a.x + (b.x - a.x) * startT, a.y + (b.y - a.y) * startT);
		var result = [start];
		var remaining = ahead + (fraction - startT) * length;
		for (i in nearest...points.length - 1) {
			var from = i == nearest ? start : points[i];
			var to = points[i + 1];
			var span = Point.distance(from, to);
			if (span > remaining) {
				result.push(new Point(from.x + (to.x - from.x) * remaining / span, from.y + (to.y - from.y) * remaining / span));
				break;
			}
			result.push(to);
			remaining -= span;
		}
		return result;
	}
}
