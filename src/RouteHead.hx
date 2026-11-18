package mods.gate_compass;

import openfl.geom.Point;

/** Reconnect the hero to an existing ribbon without changing the route ahead. */
class RouteHead {
	public var points:Array<Point>;
	public var join:Int;
	public var length:Float;

	public function new(points:Array<Point>, join:Int, length:Float) {
		this.points = points;
		this.join = join;
		this.length = length;
	}

	public static function connect(tail:Array<Point>, x:Float, y:Float, grid:WalkGrid):RouteHead {
		if (tail.length < 2)
			return null;
		var nearest = 0;
		var best = Math.POSITIVE_INFINITY;
		var projected = new Point();
		for (i in 0...tail.length - 1) {
			var a = tail[i];
			var b = tail[i + 1];
			var dx = b.x - a.x;
			var dy = b.y - a.y;
			var square = dx * dx + dy * dy;
			if (square < .001)
				continue;
			var fraction = Math.max(0., Math.min(1., ((x - a.x) * dx + (y - a.y) * dy) / square));
			var ex = a.x + fraction * dx - x;
			var ey = a.y + fraction * dy - y;
			var distance = ex * ex + ey * ey;
			if (distance < best) {
				best = distance;
				nearest = i;
				projected.x = a.x + fraction * dx;
				projected.y = a.y + fraction * dy;
			}
		}
		if (best > 160 * 160)
			return null;
		// Measure from the actual projection, not from its segment's start.
		// Interpolate the join so sparse navigation and dense display ribbons
		// produce the same curve without snapping between authored vertices.
		var remaining = 300.;
		var from = projected;
		for (i in nearest + 1...tail.length) {
			var vertex = tail[i];
			var span = Point.distance(from, vertex);
			if (span < .001)
				continue;
			if (span < remaining) {
				remaining -= span;
				from = vertex;
				continue;
			}
			var fraction = remaining / span;
			var end = fraction >= .999999 ? vertex : new Point(from.x + (vertex.x - from.x) * fraction, from.y + (vertex.y - from.y) * fraction);
			var previousTail = from;
			var join = fraction >= .999999 ? i : i - 1;
			span = Point.distance(end, previousTail);
			if (span < .001)
				return null;
			var tangentX = (end.x - previousTail.x) * 120 / span;
			var tangentY = (end.y - previousTail.y) * 120 / span;
			var controlX = end.x - tangentX;
			var controlY = end.y - tangentY;
			// A connector needs to approach the join from behind its tangent.
			if ((end.x - x) * tangentX + (end.y - y) * tangentY <= 0)
				return null;
			var points = [new Point(x, y)];
			var length = 0.;
			for (sample in 1...13) {
				var t = sample / 12.;
				var u = 1 - t;
				var next = sample == 12 ? end : new Point(u * u * x + 2 * u * t * controlX + t * t * end.x, u * u * y + 2 * u * t * controlY + t * t * end.y);
				var previous = points[points.length - 1];
				if (!grid.canConnectRouteHead(previous, next))
					return null;
				length += Point.distance(previous, next);
				points.push(next);
			}
			return new RouteHead(points, join, length);
		}
		return null;
	}

	public function direction(ahead:Float):Point {
		var remaining = ahead;
		var origin = points[0];
		for (i in 1...points.length) {
			var a = points[i - 1];
			var b = points[i];
			var span = Point.distance(a, b);
			if (span >= remaining && span > .001)
				return new Point(a.x + (b.x - a.x) * remaining / span - origin.x, a.y + (b.y - a.y) * remaining / span - origin.y);
			remaining -= span;
		}
		var end = points[points.length - 1];
		return new Point(end.x - origin.x, end.y - origin.y);
	}

	public static function mask(points:Array<Point>, start:Int, along:Float, minimum:Float, maximum:Float):Array<Bool> {
		var result:Array<Bool> = [];
		for (i in 0...points.length - 1) {
			if (i < start) {
				result.push(false);
				continue;
			}
			var span = Point.distance(points[i], points[i + 1]);
			var middle = along + span / 2;
			result.push(middle >= minimum && middle <= maximum);
			along += span;
		}
		return result;
	}
}
