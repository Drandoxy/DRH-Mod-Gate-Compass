package mods.gate_compass;

import openfl.geom.Point;

/** Match the visible ribbon against nearby segments of the previous route. */
class RouteMotion {
	public static function match(previous:Array<Point>, next:Array<Point>, mask:Array<Bool>):Array<Point> {
		var from:Array<Point> = [];
		var cursor = 0;
		var lastProgress = 0.;
		for (i in 0...next.length) {
			var target = next[i];
			if (!(i > 0 && mask[i - 1]) && !(i < mask.length && mask[i])) {
				from.push(target);
				continue;
			}
			var best = 42. * 42.;
			var match:Point = null;
			var progress = 0.;
			for (j in cursor...previous.length - 1) {
				if (match != null && j > progress + 8)
					break;
				var a = previous[j];
				var b = previous[j + 1];
				var dx = b.x - a.x;
				var dy = b.y - a.y;
				var square = dx * dx + dy * dy;
				if (square < .001)
					continue;
				var t = Math.max(0., Math.min(1., ((target.x - a.x) * dx + (target.y - a.y) * dy) / square));
				if (j + t < lastProgress)
					continue;
				var px = a.x + t * dx;
				var py = a.y + t * dy;
				var ex = target.x - px;
				var ey = target.y - py;
				var distance = ex * ex + ey * ey;
				if (distance < best) {
					best = distance;
					match = new Point(px, py);
					progress = j + t;
				}
			}
			if (match == null)
				return null;
			cursor = Std.int(progress);
			lastProgress = progress;
			from.push(match);
		}
		return from;
	}

	public static function frame(from:Array<Point>, to:Array<Point>, mask:Array<Bool>, t:Float, grid:WalkGrid, checkSweep:Bool = false):Array<Point> {
		var points = [
			for (i in 0...to.length)
				new Point(from[i].x + (to[i].x - from[i].x) * t, from[i].y + (to[i].y - from[i].y) * t)
		];
		if (checkSweep) {
			for (i in 0...points.length) {
				var visible = (i > 0 && mask[i - 1]) || (i < mask.length && mask[i]);
				if (visible && Point.distance(from[i], to[i]) >= .01 && !grid.canConnectRouteHead(from[i], to[i]))
					return null;
			}
		}
		for (i in 0...mask.length) {
			if (!mask[i])
				continue;
			if (Point.distance(from[i], to[i]) < .01 && Point.distance(from[i + 1], to[i + 1]) < .01)
				continue;
			if (!grid.canConnectRouteHead(points[i], points[i + 1]))
				return null;
		}
		return points;
	}
}
