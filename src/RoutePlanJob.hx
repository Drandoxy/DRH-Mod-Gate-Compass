package mods.gate_compass;

import openfl.geom.Point;

/** Original farthest-visible simplification and 140-unit/12-sample curves,
	expressed as resumable extraction, probe and arc-generation steps. */
class RoutePlanJob {
	public var waiting = false;
	public var seen:Map<Int, Bool> = new Map();
	public var done = false;
	public var cancelled = false;
	public var result:Array<Point> = [];
	public var steps = 0;
	public var probeSamples = 0;
	public var phase(default, null) = 0;

	var grid:RouteGrid;
	var next:Array<Int>;
	var cell:Int;
	var gate:Point;
	var raw:Array<Point>;
	var simple:Array<Point> = [];
	var rounded:Array<Point> = [];
	var guard = 0;
	var distanceLimit:Float;
	var extractedDistance = 0.;
	var at = 0;
	var candidate = 0;
	var probe:RouteProbe;
	var corner = 1;
	var attempt = 0;
	var radius = 0.;
	var ab = 0.;
	var bc = 0.;
	var a:Point;
	var b:Point;
	var c:Point;
	var enter:Point;
	var leave:Point;
	var arc:Array<Point>;
	var arcIndex = 0;

	public function new(grid:RouteGrid, next:Array<Int>, start:Int, origin:Point, gate:Point, distanceLimit:Float = 0) {
		this.grid = grid;
		this.next = next;
		cell = start;
		this.gate = gate;
		this.distanceLimit = distanceLimit;
		raw = [origin];
	}

	public function cancel():Void {
		cancelled = true;
		done = true;
		result = [];
		probe = null;
		raw = [];
		simple = [];
		rounded = [];
	}

	public function runSlice(milliseconds:Float, maxSteps:Int):Int {
		var deadline = haxe.Timer.stamp() + milliseconds / 1000;
		var count = 0;
		while (!done && count < maxSteps) {
			step();
			count++;
			if (waiting || haxe.Timer.stamp() >= deadline)
				break;
		}
		return count;
	}

	public function step():Void {
		if (done)
			return;
		waiting = false;
		steps++;
		if (phase == 0) {
			if (cell < 0 || cell >= next.length || guard++ >= grid.cells.length) {
				done = true;
				return;
			}
			seen.set(cell, true);
			var position = grid.point(cell);
			extractedDistance += Point.distance(raw[raw.length - 1], position);
			raw.push(position);
			var reached = next[cell] == cell;
			if (reached || (distanceLimit > 0 && extractedDistance >= distanceLimit)) {
				if (reached && gate != null)
					raw.push(gate);
				simple = [raw[0]];
				at = 0;
				candidate = raw.length - 1;
				phase = 1;
			} else
				cell = next[cell];
			return;
		}
		if (phase == 1) {
			if (at >= raw.length - 1) {
				if (simple.length < 3) {
					result = simple;
					done = true;
					return;
				}
				rounded = [simple[0]];
				corner = 1;
				phase = 2;
				return;
			}
			if (candidate <= at + 1) {
				acceptShortcut(at + 1);
				return;
			}
			if (probe == null) {
				probe = new RouteProbe(grid, raw[at], raw[candidate]);
				return;
			}
			var before = probe.samples;
			probe.step();
			probeSamples += probe.samples - before;
			waiting = probe.waiting;
			if (probe.done) {
				var allowed = probe.allowed;
				probe = null;
				if (allowed)
					acceptShortcut(candidate);
				else
					candidate--;
			}
			return;
		}
		if (phase == 2) {
			if (corner >= simple.length - 1) {
				rounded.push(simple[simple.length - 1]);
				result = rounded;
				done = true;
				return;
			}
			a = simple[corner - 1];
			b = simple[corner];
			c = simple[corner + 1];
			ab = Point.distance(a, b);
			bc = Point.distance(b, c);
			radius = Math.min(140., Math.min(ab, bc) * 0.4);
			attempt = 0;
			phase = 3;
			return;
		}
		if (phase == 3) {
			if (attempt >= 5 || radius < 2 || ab == 0 || bc == 0) {
				rounded.push(b);
				corner++;
				phase = 2;
				return;
			}
			enter = new Point(b.x + (a.x - b.x) * radius / ab, b.y + (a.y - b.y) * radius / ab);
			leave = new Point(b.x + (c.x - b.x) * radius / bc, b.y + (c.y - b.y) * radius / bc);
			arc = [enter];
			arcIndex = 1;
			phase = 4;
			return;
		}
		if (phase == 4) {
			if (arcIndex > 12) {
				arcIndex = 0;
				probe = null;
				phase = 5;
				return;
			}
			var t = arcIndex++ / 12.;
			var u = 1 - t;
			arc.push(new Point(u * u * enter.x + 2 * u * t * b.x + t * t * leave.x, u * u * enter.y + 2 * u * t * b.y + t * t * leave.y));
			return;
		}
		if (phase == 5) {
			if (arcIndex >= arc.length) {
				for (point in arc)
					rounded.push(point);
				corner++;
				phase = 2;
				return;
			}
			if (probe == null) {
				probe = new RouteProbe(grid, arcIndex == 0 ? rounded[rounded.length - 1] : arc[arcIndex - 1], arc[arcIndex]);
				return;
			}
			var before = probe.samples;
			probe.step();
			probeSamples += probe.samples - before;
			waiting = probe.waiting;
			if (probe.done) {
				var allowed = probe.allowed;
				probe = null;
				if (allowed)
					arcIndex++;
				else {
					attempt++;
					radius *= 0.5;
					phase = 3;
				}
			}
		}
	}

	function acceptShortcut(index:Int):Void {
		simple.push(raw[index]);
		at = index;
		candidate = raw.length - 1;
	}
}
