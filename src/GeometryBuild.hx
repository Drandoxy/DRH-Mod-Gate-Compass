package mods.gate_compass;

import box2D.dynamics.B2Body;
import box2D.dynamics.B2Fixture;
import box2D.collision.shapes.B2CircleShape;
import box2D.collision.shapes.B2PolygonShape;
import distributedObjects.DistributedDungeonFloor;
import distributedObjects.NPCGameObject;
import mods.api.dungeon.Tile;
import openfl.geom.Point;

/** One fixture, cell, signature or flood node per step. Publish only when complete. */
class GeometryBuild {
	public var done = false;
	public var changed = true;
	public var phase(default, null) = 0;
	public var steps = 0;
	public var cells:Array<Bool> = [];
	public var hazards:Array<Bool> = [];
	public var near:Array<Bool> = [];
	public var rooms:Array<Tile> = [];
	public var clearance:Array<Int> = [];
	public var tilesByPosition:Map<String, Tile> = new Map();
	public var left = 0.;
	public var top = 0.;
	public var spacing = 0.;
	public var width = 0;
	public var height = 0;
	public var layout:String;

	var floor:DistributedDungeonFloor;
	var tiles:Array<Tile>;
	var previous:GeometryBuild;
	var blocks:B2Fixture->Bool;
	var body:B2Body;
	var fixture:B2Fixture;
	var bodyReady = false;
	var bodyHazard = false;
	var signatures:Map<String, Int> = new Map();
	var keys:Array<String> = [];
	var shapes:Array<GeometryShape> = [];
	var cursor = 0;
	var tileIndex = 0;
	var part = 0;
	var subdivisions = 0;
	var shapeIndex = 0;
	var sx = 0;
	var sy = 0;
	var x0 = 0;
	var x1 = 0;
	var y1 = 0;
	var shapeReady = false;
	var queue:Array<Int> = [];
	var head = 0;

	public function new(floor:DistributedDungeonFloor, tiles:Array<Tile>, previous:GeometryBuild, blocks:B2Fixture->Bool) {
		this.floor = floor;
		this.tiles = tiles.copy();
		this.previous = previous;
		this.blocks = blocks;
		var parts = [
			for (t in tiles)
				t.id + ":" + t.x + ":" + t.y + ":" + t.category + ":" + t.exits.join(",")
		];
		parts.sort(Reflect.compare);
		layout = parts.join(";");
		body = floor.box2DWorld.GetBodyList();
	}

	public function cancel():Void {
		done = true;
		previous = null;
		body = null;
		fixture = null;
		blocks = null;
		shapes = [];
		queue = [];
	}

	public function runSlice(ms:Float, maxSteps:Int = 4096):Int {
		var end = haxe.Timer.stamp() + ms / 1000;
		var count = 0;
		while (!done && count < maxSteps) {
			step();
			count++;
			if (haxe.Timer.stamp() >= end)
				break;
		}
		return count;
	}

	function add(shape:GeometryShape):Void {
		var key = shape.key();
		var count = signatures.get(key);
		if (count == null) {
			keys.push(key);
			count = 0;
		}
		signatures.set(key, count + 1);
		shapes.push(shape);
	}

	function collect():Void {
		if (body == null) {
			phase = 1;
			cursor = 0;
			return;
		}
		if (!bodyReady) {
			var data = body.GetUserData();
			var npc = data == null || floor.remoteActors == null ? null : Std.downcast(floor.remoteActors.itemFor(data), NPCGameObject);
			bodyHazard = npc != null && npc.gmNpc != null && npc.gmNpc.Species == "TRAP";
			if (!body.IsActive() && !bodyHazard) {
				body = body.GetNext();
				return;
			}
			fixture = body.GetFixtureList();
			bodyReady = true;
		}
		if (fixture == null) {
			body = body.GetNext();
			bodyReady = false;
			return;
		}
		var current = fixture;
		fixture = fixture.GetNext();
		if (!bodyHazard && !blocks(current))
			return;
		var polygon = Std.downcast(current.GetShape(), B2PolygonShape);
		var circle = Std.downcast(current.GetShape(), B2CircleShape);
		if (polygon != null && polygon.GetVertexCount() >= 3) {
			var vertices = polygon.GetVertices();
			var points:Array<Point> = [];
			for (i in 0...polygon.GetVertexCount()) {
				var p = body.GetWorldPoint(cast vertices[i]);
				points.push(new Point(p.x * 50, p.y * 50));
			}
			add(new GeometryShape(bodyHazard, points, 0, 0, 0));
		} else if (circle != null) {
			var p = body.GetWorldPoint(circle.GetLocalPosition());
			add(new GeometryShape(bodyHazard, null, p.x * 50, p.y * 50, circle.GetRadius() * 50));
		}
	}

	function dimensions():Void {
		left = Math.POSITIVE_INFINITY;
		top = left;
		var right = Math.NEGATIVE_INFINITY;
		var bottom = right;
		for (t in tiles) {
			left = Math.min(left, t.x);
			top = Math.min(top, t.y);
			right = Math.max(right, t.x + Tile.SIZE);
			bottom = Math.max(bottom, t.y + Tile.SIZE);
		}
		subdivisions = Std.int(Math.max(1, Math.min(25, Math.floor(256 * Tile.SIZE / Math.max(right - left, bottom - top)))));
		spacing = Tile.SIZE / subdivisions;
		width = Std.int(Math.ceil((right - left) / spacing));
		height = Std.int(Math.ceil((bottom - top) / spacing));
	}

	function finish():Void {
		done = true;
		previous = null;
		body = null;
		fixture = null;
		blocks = null;
		shapes = [];
		queue = [];
	}

	public function step():Void {
		if (done)
			return;
		steps++;
		if (phase == 0) {
			collect();
			return;
		}
		if (phase == 1) {
			if (previous == null || layout != previous.layout || keys.length != previous.keys.length) {
				previous = null;
				dimensions();
				phase = 2;
				cursor = 0;
				return;
			}
			if (cursor < keys.length) {
				var key = keys[cursor++];
				if (signatures.get(key) != previous.signatures.get(key)) {
					previous = null;
					dimensions();
					phase = 2;
					cursor = 0;
				}
				return;
			}
			changed = false;
			finish();
			return;
		}
		if (phase == 2) {
			if (cursor++ < width * height) {
				cells.push(false);
				hazards.push(false);
				near.push(false);
				rooms.push(null);
				clearance.push(1000);
				return;
			}
			phase = 3;
			return;
		}
		if (phase == 3) {
			if (tileIndex >= tiles.length) {
				phase = 4;
				return;
			}
			var t = tiles[tileIndex];
			if (part == 0)
				tilesByPosition.set(t.x + ":" + t.y, t);
			var col = Math.round((t.x - left) / spacing) + part % subdivisions;
			var row = Math.round((t.y - top) / spacing) + Std.int(part / subdivisions);
			var i = row * width + col;
			rooms[i] = t;
			cells[i] = true;
			if (++part >= subdivisions * subdivisions) {
				part = 0;
				tileIndex++;
			}
			return;
		}
		if (phase == 4) {
			if (shapeIndex >= shapes.length) {
				phase = 5;
				cursor = 0;
				return;
			}
			var shape = shapes[shapeIndex];
			if (!shapeReady) {
				x0 = Std.int(Math.max(0, Math.floor((shape.minX - left) / spacing) - 1));
				sy = Std.int(Math.max(0, Math.floor((shape.minY - top) / spacing) - 1));
				x1 = Std.int(Math.min(width, Math.ceil((shape.maxX - left) / spacing) + 1));
				y1 = Std.int(Math.min(height, Math.ceil((shape.maxY - top) / spacing) + 1));
				sx = x0;
				shapeReady = true;
			}
			if (sy >= y1 || x0 >= x1) {
				shapeIndex++;
				shapeReady = false;
				return;
			}
			var i = sy * width + sx;
			near[i] = true;
			if (shape.contains(left + (sx + .5) * spacing, top + (sy + .5) * spacing)) {
				if (shape.hazard)
					hazards[i] = true;
				else
					cells[i] = false;
			}
			if (++sx >= x1) {
				sx = x0;
				sy++;
			}
			return;
		}
		if (phase == 5) {
			if (cursor >= cells.length) {
				phase = 6;
				return;
			}
			var i = cursor++;
			var col = i % width;
			var row = Std.int(i / width);
			if (!cells[i]) {
				clearance[i] = 0;
				return;
			}
			if (col == 0 || row == 0 || col == width - 1 || row == height - 1) {
				clearance[i] = 0;
				queue.push(i);
			} else if (!cells[i - 1] || !cells[i + 1] || !cells[i - width] || !cells[i + width]) {
				clearance[i] = 1;
				queue.push(i);
			}
			return;
		}
		if (phase == 6) {
			if (head >= queue.length) {
				finish();
				return;
			}
			var i = queue[head++];
			var col = i % width;
			var row = Std.int(i / width);
			for (d in 0...4) {
				var x = col + (d == 0 ? -1 : d == 1 ? 1 : 0);
				var y = row + (d == 2 ? -1 : d == 3 ? 1 : 0);
				if (x < 0 || y < 0 || x >= width || y >= height)
					continue;
				var next = y * width + x;
				if (!cells[next] || clearance[next] <= clearance[i] + 1)
					continue;
				clearance[next] = clearance[i] + 1;
				queue.push(next);
			}
			return;
		}
	}
}
