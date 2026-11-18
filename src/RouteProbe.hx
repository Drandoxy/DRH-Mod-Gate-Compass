package mods.gate_compass;

import openfl.geom.Point;

/** One occupancy/hazard sample per step: no unbounded line test in a slice. */
class RouteProbe {
	public var waiting = false;
	public var done = false;
	public var allowed = false;
	public var samples = 0;

	var grid:RouteGrid;
	var x:Float;
	var y:Float;
	var dx:Float;
	var dy:Float;
	var count:Int;
	var index = 1;
	var previous:Int;
	var phase = 0;

	public function new(grid:RouteGrid, a:Point, b:Point) {
		this.grid = grid;
		x = a.x;
		y = a.y;
		dx = b.x - a.x;
		dy = b.y - a.y;
		count = Std.int(Math.ceil(Math.max(Math.abs(dx), Math.abs(dy)) * 4 / grid.spacing));
		previous = grid.cellAt(x, y);
		if (!grid.walkable(previous))
			done = true;
	}

	public function step():Void {
		if (done)
			return;
		waiting = false;
		grid.waiting = false;
		samples++;
		if (phase == 0) {
			if (index > count) {
				phase = 1;
				index = 0;
				count = Std.int(Math.ceil(Math.sqrt(dx * dx + dy * dy) / (grid.spacing / 2)));
				return;
			}
			var t = index++ / count;
			var next = grid.cellAt(x + dx * t, y + dy * t);
			if (next == previous)
				return;
			if (!grid.walkable(next)) {
				done = true;
				return;
			}
			var col = next % grid.width - previous % grid.width;
			var row = Std.int(next / grid.width) - Std.int(previous / grid.width);
			if (col != 0 && row != 0) {
				var horizontal = previous + col;
				var vertical = previous + row * grid.width;
				if ((grid.rooms[previous] != grid.rooms[next]
					&& grid.rooms[previous] != grid.rooms[horizontal]
					&& grid.rooms[previous] != grid.rooms[vertical])
					|| !grid.walkable(horizontal)
					|| !grid.walkable(vertical)
					|| !grid.cross(previous, horizontal)
					|| !grid.cross(previous, vertical)
					|| !grid.cross(horizontal, next)
					|| !grid.cross(vertical, next)) {
					if (grid.waiting) {
						waiting = true;
						index--;
						return;
					}
					done = true;
					return;
				}
			} else if (!grid.cross(previous, next)) {
				if (grid.waiting) {
					waiting = true;
					index--;
					return;
				}
				done = true;
				return;
			}
			previous = next;
		} else {
			if (index > count) {
				done = true;
				allowed = true;
				return;
			}
			var t = count == 0 ? 0. : index / count;
			index++;
			var cell = grid.cellAt(x + dx * t, y + dy * t);
			if (cell >= 0 && grid.hazards[cell])
				done = true;
		}
	}
}
