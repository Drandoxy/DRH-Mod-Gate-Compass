import mods.gate_compass.*;

import box2D.collision.shapes.B2CircleShape;
import box2D.collision.shapes.B2PolygonShape;
import box2D.common.math.B2Vec2;
import box2D.dynamics.B2Fixture;
import dBGlobals.DBGlobal;
import distributedObjects.DistributedDungeonFloor;
import distributedObjects.NPCGameObject;
import mods.api.dungeon.Tile;
import openfl.geom.Point;

class GeometryOracle {
	public var routeLine:Array<Point> = [];
	public var visualRoute:Array<Point> = [];
	public var lowPower = false;
	public var routeDirection = new Point(1, 0);

	public var routeLimit = 36;
	public var stats = new NavigationStats();

	var heroX = 0.;
	var heroY = 0.;

	var knownLines:Array<Array<Point>> = [];
	var hazards:Array<Bool> = [];
	var clearance:Array<Int> = [];
	var markingHazard = false;
	var field:RouteField;
	var focusCell = -1;
	var focusAnnounced = false;
	var cachedQueries = false;
	var routeGoal = "";
	var routeGateId:UInt = 0;
	var shapeKey = "";
	var lineOrigin:Point;

	var shapeParts:Array<String> = [];
	var cells:Array<Bool> = [];
	var rooms:Array<Tile> = [];
	var tilesByPosition:Map<String, Tile> = new Map();
	var nearCollider:Array<Bool> = [];
	var floor:DistributedDungeonFloor;
	var edgeChecks:Map<Int, Bool> = new Map();
	var gentleTarget:Point;
	var gentleOrigin:Point;
	var left:Float;
	var top:Float;
	var step:Float;
	var width:Int;
	var height:Int;

	public function new() {}

	public function refresh(floor:DistributedDungeonFloor, tiles:Array<Tile>):Void {
		var sameFloor = this.floor == floor;
		this.floor = floor;
		if (tiles.length == 0 || floor.box2DWorld == null) {
			clear();
			return;
		}
		// Fingerprint before rasterization or route invalidation. The previous
		// implementation rebuilt all cells and clearance even for identical data.
		shapeParts = [
			for (tile in tiles)
				tile.id + ":" + tile.x + ":" + tile.y + ":" + tile.category + ":" + tile.exits.join(",")
		];
		var shapes:Array<{
			hazard:Bool,
			points:Array<Point>,
			cx:Float,
			cy:Float,
			radius:Float
		}> = [];
		forEachCollision(function(points) {
			shapeParts.push((markingHazard ? "H" : "P") + [for (p in points) p.x + ":" + p.y].join(","));
			shapes.push({
				hazard: markingHazard,
				points: points,
				cx: 0.,
				cy: 0.,
				radius: 0.
			});
		}, function(cx, cy, radius) {
			shapeParts.push((markingHazard ? "H" : "C") + cx + ":" + cy + ":" + radius);
			shapes.push({
				hazard: markingHazard,
				points: null,
				cx: cx,
				cy: cy,
				radius: radius
			});
		});
		shapeParts.sort(Reflect.compare);
		var key = shapeParts.join(";");
		shapeParts = [];
		if (sameFloor && key == shapeKey)
			return;
		field = null;
		lineOrigin = null;
		routeLine = [];
		visualRoute = [];
		edgeChecks = new Map();
		cells = [];
		rooms = [];
		tilesByPosition = new Map();
		nearCollider = [];

		left = Math.POSITIVE_INFINITY;
		top = Math.POSITIVE_INFINITY;
		var right = Math.NEGATIVE_INFINITY;
		var bottom = Math.NEGATIVE_INFINITY;
		for (tile in tiles) {
			left = Math.min(left, tile.x);
			top = Math.min(top, tile.y);
			right = Math.max(right, tile.x + Tile.SIZE);
			bottom = Math.max(bottom, tile.y + Tile.SIZE);
		}
		var subdivisions = Std.int(Math.max(1, Math.min(25, Math.floor(256 * Tile.SIZE / Math.max(right - left, bottom - top)))));
		step = Tile.SIZE / subdivisions;
		width = Std.int(Math.ceil((right - left) / step));
		height = Std.int(Math.ceil((bottom - top) / step));

		cells = [for (i in 0...width * height) false];
		hazards = [for (i in 0...width * height) false];
		nearCollider = [for (i in 0...width * height) false];
		for (tile in tiles) {
			tilesByPosition.set(tileKey(tile.x, tile.y), tile);
			var col = Math.round((tile.x - left) / step);
			var row = Math.round((tile.y - top) / step);
			for (y in row...row + subdivisions)
				for (x in col...col + subdivisions) {
					var i = y * width + x;
					rooms[i] = tile;
					cells[i] = true;
				}
		}

		for (shape in shapes) {
			markingHazard = shape.hazard;
			if (shape.points != null)
				markPolygon(shape.points);
			else
				markCircle(shape.cx, shape.cy, shape.radius);
		}
		markingHazard = false;
		buildClearance();
		shapeKey = key;
	}

	function buildClearance():Void {
		clearance = [for (i in 0...cells.length) 1000];
		var queue:Array<Int> = [];
		for (i in 0...cells.length) {
			var col = i % width;
			var row = Std.int(i / width);
			if (!cells[i] || col == 0 || row == 0 || col == width - 1 || row == height - 1) {
				clearance[i] = 0;
				queue.push(i);
			}
		}
		var head = 0;
		while (head < queue.length) {
			var i = queue[head++];
			var col = i % width;
			var row = Std.int(i / width);
			for (next in [
				index(col - 1, row),
				index(col + 1, row),
				index(col, row - 1),
				index(col, row + 1)
			]) {
				if (next < 0 || next >= cells.length || clearance[next] <= clearance[i] + 1)
					continue;
				clearance[next] = clearance[i] + 1;
				queue.push(next);
			}
		}
	}

	function forEachCollision(polygonFound:Array<Point>->Void, circleFound:Float->Float->Float->Void):Void {
		if (floor == null || floor.box2DWorld == null)
			return;
		var body = floor.box2DWorld.GetBodyList();
		while (body != null) {
			var actorData = body.GetUserData();
			var actor = actorData == null
				|| floor.remoteActors == null ? null : Std.downcast(floor.remoteActors.itemFor(actorData), NPCGameObject);
			var persistentTrap = actor != null && actor.gmNpc != null && actor.gmNpc.Species == "TRAP";
			if (body.IsActive() || persistentTrap) {
				var fixture = body.GetFixtureList();
				while (fixture != null) {
					var data = body.GetUserData();
					var npc = data == null
						|| floor.remoteActors == null ? null : Std.downcast(floor.remoteActors.itemFor(data), NPCGameObject);
					markingHazard = npc != null && npc.gmNpc != null && npc.gmNpc.Species == "TRAP";
					if (markingHazard || blocksMovement(fixture)) {
						var polygon = Std.downcast(fixture.GetShape(), B2PolygonShape);
						var circle = Std.downcast(fixture.GetShape(), B2CircleShape);
						if (polygon != null && polygon.GetVertexCount() >= 3) {
							var vertices = polygon.GetVertices();
							var points = [];
							for (i in 0...polygon.GetVertexCount()) {
								var vertex = body.GetWorldPoint(cast vertices[i]);
								points.push(new Point(vertex.x * 50, vertex.y * 50));
							}
							polygonFound(points);
						} else if (circle != null) {
							var center = body.GetWorldPoint(circle.GetLocalPosition());
							circleFound(center.x * 50, center.y * 50, circle.GetRadius() * 50);
						}
					}
					markingHazard = false;
					fixture = fixture.GetNext();
				}
			}
			body = body.GetNext();
		}
	}

	// Keep a small clearance around static collision shapes without sealing narrow doors.
	static inline final CLEARANCE = 20.;

	function markCircle(cx:Float, cy:Float, radius:Float):Void {
		var extent = radius + CLEARANCE;
		markCells(cx - extent, cy - extent, cx + extent, cy + extent, function(x, y) {
			var dx = x - cx;
			var dy = y - cy;
			return dx * dx + dy * dy <= extent * extent;
		});
	}

	function markPolygon(points:Array<Point>):Void {
		var minX = Math.POSITIVE_INFINITY;
		var minY = Math.POSITIVE_INFINITY;
		var maxX = Math.NEGATIVE_INFINITY;
		var maxY = Math.NEGATIVE_INFINITY;
		for (p in points) {
			minX = Math.min(minX, p.x);
			minY = Math.min(minY, p.y);
			maxX = Math.max(maxX, p.x);
			maxY = Math.max(maxY, p.y);
		}
		markCells(minX - CLEARANCE, minY - CLEARANCE, maxX + CLEARANCE, maxY + CLEARANCE, function(x, y) {
			var inside = false;
			var a = points[points.length - 1];
			for (b in points) {
				var dx = b.x - a.x;
				var dy = b.y - a.y;
				var lengthSquared = dx * dx + dy * dy;
				if (lengthSquared > 0) {
					var t = Math.max(0, Math.min(1, ((x - a.x) * dx + (y - a.y) * dy) / lengthSquared));
					var ex = x - a.x - t * dx;
					var ey = y - a.y - t * dy;
					if (ex * ex + ey * ey <= CLEARANCE * CLEARANCE)
						return true;
				}
				if ((a.y > y) != (b.y > y) && x < a.x + (y - a.y) * dx / dy)
					inside = !inside;
				a = b;
			}
			return inside;
		});
	}

	function markCells(minX:Float, minY:Float, maxX:Float, maxY:Float, contains:Float->Float->Bool):Void {
		var x0 = Std.int(Math.max(0, Math.floor((minX - left) / step) - 1));
		var y0 = Std.int(Math.max(0, Math.floor((minY - top) / step) - 1));
		var x1 = Std.int(Math.min(width, Math.ceil((maxX - left) / step) + 1));
		var y1 = Std.int(Math.min(height, Math.ceil((maxY - top) / step) + 1));
		for (y in y0...y1)
			for (x in x0...x1) {
				var i = y * width + x;
				nearCollider[i] = true;
				if (contains(left + (x + 0.5) * step, top + (y + 0.5) * step)) {
					if (markingHazard)
						hazards[i] = true;
					else
						cells[i] = false;
				}
			}
	}

	public function clear():Void {
		field = null;
		lineOrigin = null;
		clearance = [];
		shapeParts = [];
		focusCell = -1;
		focusAnnounced = false;
		knownLines = [];
		routeLine = [];
		visualRoute = [];
		hazards = [];
		shapeKey = "";
		edgeChecks = new Map();
		cells = [];
		rooms = [];
		tilesByPosition = new Map();
		nearCollider = [];
		floor = null;
	}

	public function cellAt(x:Float, y:Float):Int {
		if (cells.length == 0)
			return -1;
		var col = Math.floor((x - left) / step);
		var row = Math.floor((y - top) / step);
		return index(col, row);
	}

	public function roomAtCell(cell:Int):Tile {
		return cell < 0 || cell >= cells.length ? null : rooms[cell];
	}

	function index(x:Int, y:Int):Int {
		return x < 0 || y < 0 || x >= width || y >= height ? -1 : y * width + x;
	}

	function walkable(i:Int):Bool {
		return i >= 0 && i < cells.length && cells[i];
	}

	function blocksMovement(fixture:B2Fixture, ignoredGate:UInt = 0):Bool {
		if (fixture.IsSensor() || !fixture.GetBody().IsActive())
			return false;
		var bits = fixture.GetFilterData().categoryBits;
		var data = fixture.GetBody().GetUserData();
		if (ignoredGate != 0 && data == ignoredGate)
			return false;
		var npc = data == null || floor.remoteActors == null ? null : Std.downcast(floor.remoteActors.itemFor(data), NPCGameObject);
		// A closed, authored door is still a route passage. Its surrounding
		// wall fixtures remain blockers; only the door actor is traversable in
		// this guidance cache, so it can lead to an unlockable exit.
		if (npc != null && npc.gmNpc != null && npc.gmNpc.Species == "DOOR")
			return false;
		if (npc != null && npc.isProp && npc.gmNpc != null && npc.gmNpc.IsAttackable && npc.gmNpc.Species != "TRAP")
			return false;
		if (npc != null && npc.gmNpc != null && npc.gmNpc.Species == "TRAP" && npc.team == DBGlobal.TEAM_3)
			return false;
		if (npc != null && npc.gmNpc != null && npc.gmNpc.Species == "TRAP") {
			var kind = Std.string(npc.gmNpc.Constant).toUpperCase();
			// Spike strips count as a route even while their damage is active.
			if (kind.indexOf("SPIKE") >= 0)
				return false;
		}
		return (bits & DBGlobal.B2D_ENVIRONMENT_MASK) != 0
			|| (npc != null && npc.isProp && !npc.isNavigable && bits != DBGlobal.B2D_COMBAT_MASK);
	}

	public function canAim(x:Float, y:Float, target:Point, ignoredGate:UInt = 0, smallObstacle:Bool = false):Bool {
		if (floor == null || floor.box2DWorld == null || target == null || !Math.isFinite(x) || !Math.isFinite(y) || !Math.isFinite(target.x)
			|| !Math.isFinite(target.y))
			return false;
		if (x == target.x && y == target.y)
			return true;
		var from = new B2Vec2(x / 50, y / 50);
		var to = new B2Vec2(target.x / 50, target.y / 50);
		for (hit in floor.box2DWorld.RayCastAll(from, to)) {
			var fixture = Std.downcast(hit, B2Fixture);
			if (fixture == null || !blocksMovement(fixture, ignoredGate))
				continue;
			var circle = Std.downcast(fixture.GetShape(), B2CircleShape);
			if (!smallObstacle || circle == null || circle.GetRadius() * 50 > 55)
				return false;
		}
		return true;
	}

	function canCross(from:Int, to:Int):Bool {
		if (!walkable(from)
			|| !walkable(to)
			|| Math.abs(from % width - to % width) + Math.abs(Std.int(from / width) - Std.int(to / width)) != 1)
			return false;
		var a = rooms[from];
		var b = rooms[to];
		if (a == null || b == null)
			return false;
		if (a == b && !nearCollider[from] && !nearCollider[to])
			return true;
		var lower = Std.int(Math.min(from, to));
		var key = lower * 2 + (Math.abs(from - to) == 1 ? 0 : 1);
		var cached = edgeChecks.get(key);
		if (cached != null)
			return cached;
		if (cachedQueries)
			return false;
		// Authored exit flags are incomplete on some floors. Confirm the seam in the live world.
		var start = point(from);
		var end = point(to);
		var open = canAim(start.x, start.y, end);
		edgeChecks.set(key, open);
		return open;
	}

	function point(i:Int):Point {
		return new Point(left + (i % width + 0.5) * step, top + (Std.int(i / width) + 0.5) * step);
	}

	public function regionAt(x:Float, y:Float):String {
		var tile = roomAtCell(cellAt(x, y));
		if (tile == null)
			return "";
		return tile.x + ":" + tile.y + ":" + Math.floor((x - tile.x) / 150) + ":" + Math.floor((y - tile.y) / 150);
	}

	static function tileKey(x:Float,y:Float):String { return x+":"+y; }
}
