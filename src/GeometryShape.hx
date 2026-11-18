package mods.gate_compass;

import openfl.geom.Point;

/** A detached collision snapshot: no live native object during rasterization. */
class GeometryShape {
	public var hazard:Bool;
	public var points:Array<Point>;
	public var cx:Float;
	public var cy:Float;
	public var radius:Float;
	public var minX:Float;
	public var minY:Float;
	public var maxX:Float;
	public var maxY:Float;

	public function new(hazard:Bool, points:Array<Point>, cx:Float, cy:Float, radius:Float) {
		this.hazard = hazard;
		this.points = points;
		this.cx = cx;
		this.cy = cy;
		this.radius = radius;
		if (points == null) {
			var r = radius + 20;
			minX = cx - r;
			maxX = cx + r;
			minY = cy - r;
			maxY = cy + r;
		} else {
			minX = Math.POSITIVE_INFINITY;
			minY = minX;
			maxX = Math.NEGATIVE_INFINITY;
			maxY = maxX;
			for (p in points) {
				minX = Math.min(minX, p.x);
				minY = Math.min(minY, p.y);
				maxX = Math.max(maxX, p.x);
				maxY = Math.max(maxY, p.y);
			}
			minX -= 20;
			minY -= 20;
			maxX += 20;
			maxY += 20;
		}
	}

	public function key():String {
		return (hazard ? "H" : "B") + (points == null ? cx + ":" + cy + ":" + radius : [for (p in points) p.x + ":" + p.y].join(","));
	}

	public function contains(x:Float, y:Float):Bool {
		if (points == null) {
			var dx = x - cx;
			var dy = y - cy;
			return dx * dx + dy * dy <= (radius + 20) * (radius + 20);
		}
		var inside = false;
		var a = points[points.length - 1];
		for (b in points) {
			var dx = b.x - a.x;
			var dy = b.y - a.y;
			var square = dx * dx + dy * dy;
			if (square > 0) {
				var t = Math.max(0, Math.min(1, ((x - a.x) * dx + (y - a.y) * dy) / square));
				var ex = x - a.x - t * dx;
				var ey = y - a.y - t * dy;
				if (ex * ex + ey * ey <= 400)
					return true;
			}
			if ((a.y > y) != (b.y > y) && x < a.x + (y - a.y) * dx / dy)
				inside = !inside;
			a = b;
		}
		return inside;
	}
}
