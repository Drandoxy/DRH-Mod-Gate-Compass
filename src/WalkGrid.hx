package mods.gate_compass;

import box2D.collision.shapes.B2CircleShape;
import box2D.collision.shapes.B2PolygonShape;
import box2D.common.math.B2Vec2;
import box2D.dynamics.B2Fixture;
import dBGlobals.DBGlobal;
import distributedObjects.DistributedDungeonFloor;
import distributedObjects.NPCGameObject;
import mods.api.dungeon.Tile;
import openfl.geom.Point;

class WalkGrid {
	public var routeLine:Array<Point> = [];
	public var visualRoute:Array<Point> = [];
	public var lowPower = false;
	public var routeDirection = new Point(1, 0);

	var anchorRoutes:Map<String, Array<Array<Point>>> = new Map();
	var anchorProgress:Map<String, Int> = new Map();
	var anchorCursor = 0;
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
	var refineSource:Array<Point>;
	var refineResult:Array<Point>;
	var refineRoom:Tile;
	var refineAt = 0;
	var refineCandidate = 0;
	var curveLine:Array<Point>;
	var curveResult:Array<Point>;
	var curveAt = 0;
	var shortcutsComplete = false;
	var cornerCache:Map<String, Array<Point>> = new Map();
	var cornerKeys:Array<String> = [];
	var nextVisualPublish = 0;
	var curveCache:Array<{source:Array<Point>, rounded:Array<Point>}> = [];

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
		cancelRefinement();
		lineOrigin = null;
		curveCache = [];
		cornerCache = new Map();
		cornerKeys = [];
		routeLine = [];
		visualRoute = [];
		edgeChecks = new Map();
		invalidateRoute();
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

	function corridorClear(x:Float, y:Float, target:Point, ignoredGate:UInt = 0):Bool {
		if (cachedQueries)
			return clearGridLine(x, y, target);
		if (!canAim(x, y, target, ignoredGate) || !clearGridLine(x, y, target))
			return false;
		var dx = target.x - x;
		var dy = target.y - y;
		var length = Math.sqrt(dx * dx + dy * dy);
		if (length < 0.001)
			return true;
		var radius = 16.;
		var nx = -dy / length * radius;
		var ny = dx / length * radius;
		for (side in [-1, 1]) {
			var end = new Point(target.x + nx * side, target.y + ny * side);
			// The center grid already includes the agent radius. Side rays
			// check actual shapes without inflating that radius a second time.
			if (!canAim(x + nx * side, y + ny * side, end, ignoredGate))
				return false;
		}
		return true;
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
		cancelRefinement();
		lineOrigin = null;
		curveCache = [];
		cornerCache = new Map();
		cornerKeys = [];
		anchorRoutes = new Map();
		anchorProgress = new Map();
		anchorCursor = 0;
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
		invalidateRoute();
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

	public function prepareField(goal:Tile, gate:Point, gateId:UInt):Void {
		var key = goal.id + ":" + goal.x + ":" + goal.y + ":" + gateId + (gate == null ? "" : ":" + gate.x + ":" + gate.y);
		if (field != null && field.key == key)
			return;
		routeLine = [];
		visualRoute = [];
		lineOrigin = null;
		curveCache = [];
		cornerCache = new Map();
		cornerKeys = [];
		cancelRefinement();
		anchorRoutes = new Map();
		anchorProgress = new Map();
		anchorCursor = 0;
		focusAnnounced = false;
		field = new RouteField(goal, gate, gateId, key, cells.length);
		routeGoal = key;
		routeGateId = gateId;
	}

	/** One reverse search fills the next step for every reachable cell. */
	public function prioritize(x:Float, y:Float):Void {
		focusCell = cellAt(x, y);
	}

	public function advanceField(allowWarmup:Bool = true):Bool {
		if (field == null)
			return false;
		if (refineSource != null) {
			if (roomAtCell(focusCell) != refineRoom)
				cancelRefinement();
			else {
				var refineDeadline = haxe.Timer.stamp() + (lowPower ? 0.00025 : 0.0005);
				for (i in 0...4) {
					if (refineSource == null)
						break;
					if (refineStep())
						return true;
					if (haxe.Timer.stamp() >= refineDeadline)
						break;
				}
			}
		}

		if (field.phase == 2) {
			if (lowPower || !allowWarmup)
				return false;
			// Work follows the current room. Returning to a room resumes its
			// remaining samples; abandoned rooms receive no preparation time.
			var tile = roomAtCell(focusCell);
			if (tile == null)
				return false;
			var roomKey = tileKey(tile.x, tile.y);
			var progress = anchorProgress.get(roomKey);
			var part = progress == null ? 0 : progress;
			if (part >= 6)
				return false;
			anchorProgress.set(roomKey, part + 1);
			anchorCursor++;
			{
				var x = tile.x + (part % 3 + 0.5) * Tile.SIZE / 3;
				var y = tile.y + (Std.int(part / 3) + 0.5) * Tile.SIZE / 2;
				var cell = cellAt(x, y);
				var best = -1;
				var distance = Math.POSITIVE_INFINITY;
				if (cell >= 0)
					for (dy in -2...3)
						for (dx in -2...3) {
							var candidate = index(cell % width + dx, Std.int(cell / width) + dy);
							if (!walkable(candidate) || !field.settled[candidate] || rooms[candidate] != tile)
								continue;
							var p = point(candidate);
							var d = (p.x - x) * (p.x - x) + (p.y - y) * (p.y - y);
							if (d < distance) {
								distance = d;
								best = candidate;
							}
						}
				var route = best < 0 ? [] : cachedLine(best, point(best));
				var key = tileKey(tile.x, tile.y);
				var routes = anchorRoutes.get(key);
				if (routes == null) {
					routes = [];
					anchorRoutes.set(key, routes);
				}
				routes.push(route);
			}
			return false;
		}
		var f = field;
		var deadline = haxe.Timer.stamp()
			+ (lowPower ? (focusCell >= 0 && focusCell < f.settled.length && !f.settled[focusCell] ? 0.001 : 0.00035) : (focusCell >= 0
				&& focusCell < f.settled.length && !f.settled[focusCell] ? 0.003 : 0.001));
		var work = 0;
		while (work++ < 1536 && haxe.Timer.stamp() < deadline) {
			if (f.phase == 0) {
				var side = Math.round(Tile.SIZE / step);
				if (f.scan < side * side) {
					var offset = f.scan++;
					var cell = index(Math.round((f.goal.x - left) / step) + offset % side, Math.round((f.goal.y - top) / step) + Std.int(offset / side));
					if (!walkable(cell))
						continue;
					var p = point(cell);
					if (!f.goal.contains(p.x, p.y))
						continue;
					var end = f.gate == null ? new Point(f.goal.x + Tile.SIZE / 2, f.goal.y + Tile.SIZE / 2) : f.gate;
					var dx = p.x - end.x;
					var dy = p.y - end.y;
					var distance = dx * dx + dy * dy;
					if (f.gate != null && canAim(p.x, p.y, f.gate, f.gateId) && hazardFree(p.x, p.y, f.gate)) {
						// Closed gates can split the nearest cells into separate
						// islands. Cache every visible approach, on either side.
						f.seeds.push(cell);
						f.scores[cell] = Math.sqrt(distance) / step;
						f.next[cell] = cell;
					}
					if (distance < f.distance && (f.gate == null || canAim(p.x, p.y, f.gate, f.gateId))) {
						f.seed = cell;
						f.distance = distance;
					}
					continue;
				}
				if (f.seed < 0) {
					f.phase = 2;
					return true;
				}
				if (f.seeds.length == 0) {
					f.scores[f.seed] = 0;
					f.next[f.seed] = f.seed;
					f.seeds.push(f.seed);
				}
				for (seed in f.seeds)
					fieldPush(f.heap, new RouteNode(seed, f.scores[seed]));
				f.phase = 1;
			}
			if (f.heap.length == 0) {
				f.phase = 2;
				return true;
			}
			var current = heapPop(f.heap, f.scores);
			if (f.settled[current])
				continue;
			f.settled[current] = true;
			var col = current % width;
			var row = Std.int(current / width);
			for (next in [
				index(col - 1, row),
				index(col + 1, row),
				index(col, row - 1),
				index(col, row + 1)
			]) {
				if (!walkable(next) || f.settled[next] || !canCross(current, next))
					continue;
				var score = f.scores[current] + 1 + (hazards[current] ? 24 : 0) + 3. / (clearance[current] + 1);
				if (score >= f.scores[next])
					continue;
				f.scores[next] = score;
				f.next[next] = current;
				// Reverse Dijkstra uses immutable costs, with no per-hero search.
				fieldPush(f.heap, new RouteNode(next, score));
			}
			if (!focusAnnounced && current == focusCell) {
				focusAnnounced = true;
				adoptLine(cachedLine(current, point(current)), point(current));
				// Publish the main spawn-to-gate line immediately, before
				// preparing up to six rough alternatives per room in later slices.
				return true;
			}
		}
		return false;
	}

	public function waypoint(x:Float, y:Float, goal:Tile, gate:Point, gateId:UInt = 0):Point {
		prepareField(goal, gate, gateId);
		if (lineOrigin != null && Point.distance(lineOrigin, new Point(x, y)) >= 900) {
			var start = cellAt(x, y);
			if (field != null && start >= 0 && field.settled[start] && field.next[start] >= 0) {
				var next = cachedLine(start, new Point(x, y));
				if (next.length > 1)
					adoptLine(next, new Point(x, y));
			}
		}

		// Keep a valid branch stable instead of swapping nearby anchors on
		// every small movement or as additional anchors finish warming.
		var currentRoom = roomAtCell(cellAt(x, y));
		if (routeLine.length > 1 && refineRoom != currentRoom) {
			var start = cellAt(x, y);
			if (field != null && start >= 0 && field.settled[start] && field.next[start] >= 0)
				adoptLine(cachedLine(start, new Point(x, y)), new Point(x, y));
			else
				startRefinement(routeLine, currentRoom);
		}
		var existing = followLine(x, y);
		if (existing != null)
			return existing;
		var tile = roomAtCell(cellAt(x, y));
		var routes = tile == null || lowPower ? null : anchorRoutes.get(tileKey(tile.x, tile.y));
		var chosen:Array<Point> = null;
		var closest = Math.POSITIVE_INFINITY;
		cachedQueries = true;
		if (routes != null)
			for (line in routes)
				for (i in 0...line.length - 1) {
					var a = line[i];
					var b = line[i + 1];
					var dx = b.x - a.x;
					var dy = b.y - a.y;
					var length = dx * dx + dy * dy;
					var t = length == 0 ? 0. : Math.max(0, Math.min(1, ((x - a.x) * dx + (y - a.y) * dy) / length));
					var p = new Point(a.x + dx * t, a.y + dy * t);
					var distance = (p.x - x) * (p.x - x) + (p.y - y) * (p.y - y);
					if (distance < closest && clearGridLine(x, y, p)) {
						closest = distance;
						chosen = line;
					}
				}
		cachedQueries = false;
		if (chosen != null)
			adoptLine(chosen, new Point(x, y));
		var retained = followLine(x, y);
		if (retained != null)
			return retained;
		var start = cellAt(x, y);
		if (start < 0 || field == null || !field.settled[start] || field.next[start] < 0)
			return null;
		// Initial guidance uses the already-built field while anchor lines fill.
		adoptLine(cachedLine(start, new Point(x, y)), new Point(x, y));
		return followLine(x, y);
	}

	function cachedLine(start:Int, origin:Point):Array<Point> {
		var raw = [origin];
		var current = start;
		var guard = 0;
		var reached = false;
		var distance = 0.;
		var previous = origin;
		var limit = Math.min(cells.length, 256);
		while (guard++ < limit) {
			var at = point(current);
			raw.push(at);
			distance += Point.distance(previous, at);
			previous = at;
			if (field.next[current] == current) {
				reached = true;
				break;
			}
			if (distance >= 3600)
				break;
			var next = field.next[current];
			if (next < 0)
				return [];
			current = next;
		}
		if (reached && field.gate != null)
			raw.push(field.gate);
		return compactLine(raw);
	}

	function adoptLine(line:Array<Point>, origin:Point):Void {
		routeLine = line;
		lineOrigin = origin;
		startRefinement(line, roomAtCell(focusCell));
	}

	function startRefinement(line:Array<Point>, room:Tile):Void {
		cancelRefinement();
		refineRoom = room;
		if (visualRemaining(visualRoute) < 0)
			visualRoute = [];
		for (cached in curveCache) {
			if (cached.source == line || cached.rounded == line) {
				routeLine = cached.rounded;
				visualRoute = cached.rounded;
				return;
			}
		}
		if (line == null || line.length < 3 || room == null) {
			if (line != null && line.length == 2)
				visualRoute = line;
			return;
		}
		refineSource = line;
		refineResult = [line[0]];
		curveLine = refineResult;
		curveResult = [line[0]];
		curveAt = 1;
		shortcutsComplete = false;
		nextVisualPublish = 0;
		refineAt = 0;
		refineCandidate = Std.int(Math.min(line.length - 1, 3));
	}

	function cancelRefinement():Void {
		refineSource = null;
		refineResult = null;
		refineRoom = null;
		curveLine = null;
		curveResult = null;
		curveAt = 0;
	}

	// One short candidate per frame; no scan of all distant route endpoints.
	// The source remains visible until the entire replacement is validated.
	function refineStep():Bool {
		if (curveLine != null && (curveAt < curveLine.length - 1 || shortcutsComplete))
			return curveStep();
		var source = refineSource;
		var at = source[refineAt];
		var candidate = source[refineCandidate];
		var accept = refineCandidate == refineAt + 1;
		if (!accept && Point.distance(at, candidate) <= 400) {
			cachedQueries = true;
			accept = corridorClear(at.x, at.y, candidate) && hazardFree(at.x, at.y, candidate);
			cachedQueries = false;
		}
		if (!accept) {
			refineCandidate--;
			return false;
		}
		refineResult.push(candidate);
		refineAt = refineCandidate;
		if (refineAt >= source.length - 1) {
			shortcutsComplete = true;
			return false;
		}

		refineCandidate = Std.int(Math.min(source.length - 1, refineAt + 3));
		return false;
	}

	// At most one corner per update. Cache the finished curve; no smoothing
	// or collision tests run again until the underlying route changes.
	function curveStep():Bool {
		if (curveAt >= curveLine.length - 1) {
			if (!shortcutsComplete)
				return false;
			curveResult.push(curveLine[curveLine.length - 1]);
			if (routeLine == refineSource) {
				if (curveCache.length >= 8)
					curveCache.shift();
				curveCache.push({source: refineSource, rounded: curveResult});
				routeLine = curveResult;
				visualRoute = curveResult;
			}
			refineSource = null;
			refineResult = null;
			curveLine = null;
			curveResult = null;
			return true;
		}
		var a = curveLine[curveAt - 1];
		var b = curveLine[curveAt];
		var c = curveLine[curveAt + 1];
		curveAt++;
		var key = a.x + ":" + a.y + ":" + b.x + ":" + b.y + ":" + c.x + ":" + c.y + ":" + lowPower;
		var cached = cornerCache.get(key);
		if (cached != null) {
			if (cached.length == 0)
				curveResult.push(b);
			else
				for (point in cached)
					curveResult.push(point);
			publishVisualPrefix();
			return false;
		}

		var ab = Point.distance(a, b);
		var bc = Point.distance(b, c);
		var radius = Math.min(60, Math.min(ab, bc) * 0.25);
		if (radius < 2) {
			curveResult.push(b);
			publishVisualPrefix();
			return false;
		}
		var enter = new Point(b.x + (a.x - b.x) * radius / ab, b.y + (a.y - b.y) * radius / ab);
		var leave = new Point(b.x + (c.x - b.x) * radius / bc, b.y + (c.y - b.y) * radius / bc);
		var arc = [enter];
		var samples = lowPower ? 4 : 8;
		for (i in 1...samples + 1) {
			var t = i / samples;
			var u = 1 - t;
			arc.push(new Point(u * u * enter.x + 2 * u * t * b.x + t * t * leave.x, u * u * enter.y + 2 * u * t * b.y + t * t * leave.y));
		}
		// The connector to enter is a subset of an already validated straight
		// segment. Only the newly rounded arc needs fresh bounded checks.
		var previous = enter;
		var safe = true;
		cachedQueries = true;
		for (i in 1...arc.length) {
			var point = arc[i];
			if (!corridorClear(previous.x, previous.y, point) || !hazardFree(previous.x, previous.y, point)) {
				safe = false;
				break;
			}
			previous = point;
		}
		cachedQueries = false;
		if (cornerKeys.length >= (lowPower ? 32 : 128))
			cornerCache.remove(cornerKeys.shift());
		cornerKeys.push(key);
		cornerCache.set(key, safe ? arc : []);
		if (safe) {
			for (point in arc)
				curveResult.push(point);
		} else
			curveResult.push(b);
		publishVisualPrefix();
		return false;
	}

	// A previous curved route is a handoff buffer, valid only near the player
	// and within the same immutable geometry generation.
	function visualRemaining(line:Array<Point>):Float {
		if (line == null || line.length < 2 || focusCell < 0 || focusCell >= cells.length)
			return -1;
		var origin = point(focusCell);
		var best = Math.POSITIVE_INFINITY;
		var remaining = 0.;
		var tail = 0.;
		for (offset in 0...line.length - 1) {
			var i = line.length - 2 - offset;
			var a = line[i];
			var b = line[i + 1];
			var dx = b.x - a.x;
			var dy = b.y - a.y;
			var square = dx * dx + dy * dy;
			var length = Math.sqrt(square);
			var t = square == 0 ? 0. : Math.max(0, Math.min(1, ((origin.x - a.x) * dx + (origin.y - a.y) * dy) / square));
			var ex = a.x + dx * t - origin.x;
			var ey = a.y + dy * t - origin.y;
			var distance = ex * ex + ey * ey;
			if (distance < best) {
				best = distance;
				remaining = tail + (1 - t) * length;
			}
			tail += length;
		}
		return best <= 95 * 95 ? remaining : -1;
	}

	function publishVisualPrefix():Void {
		var now = openfl.Lib.getTimer();
		if (curveResult.length < 2 || (visualRoute.length > 0 && now < nextVisualPublish))
			return;
		var previous = visualRemaining(visualRoute);
		var next = visualRemaining(curveResult);
		// Do not replace a usable line with a tiny prefix hidden by the
		// player-distance fade, or one the player would immediately outrun.
		if (previous >= 250 && next < Math.min(previous, 2300))
			return;
		if (next < 600)
			return;
		visualRoute = curveResult.copy();
		nextVisualPublish = now + 100;
	}

	// Only merge collinear validated grid edges. This inexpensive first pass
	// never shortcuts across a wall or invents a diagonal through an obstacle.
	static function compactLine(raw:Array<Point>):Array<Point> {
		if (raw.length < 3)
			return raw;
		var result = [raw[0]];
		for (i in 1...raw.length - 1) {
			var a = result[result.length - 1];
			var b = raw[i];
			var c = raw[i + 1];
			var dx = b.x - a.x;
			var dy = b.y - a.y;
			var ex = c.x - b.x;
			var ey = c.y - b.y;
			if (Math.abs(dx * ey - dy * ex) > 0.001 || dx * ex + dy * ey <= 0)
				result.push(b);
		}
		result.push(raw[raw.length - 1]);
		return result;
	}

	public function invalidateRoute():Void {
		gentleTarget = null;
		gentleOrigin = null;
	}

	function hazardFree(x:Float, y:Float, target:Point):Bool {
		var count = Std.int(Math.ceil(Point.distance(new Point(x, y), target) / (step / 2)));
		for (i in 0...count + 1) {
			var t = count == 0 ? 0. : i / count;
			var cell = cellAt(x + (target.x - x) * t, y + (target.y - y) * t);
			if (cell >= 0 && hazards[cell])
				return false;
		}
		return true;
	}

	function followLine(x:Float, y:Float):Point {
		if (routeLine.length < 2)
			return null;
		var best = Math.POSITIVE_INFINITY;
		var segment = -1;
		var projection:Point = null;
		for (i in 0...routeLine.length - 1) {
			var a = routeLine[i];
			var b = routeLine[i + 1];
			var dx = b.x - a.x;
			var dy = b.y - a.y;
			var length = dx * dx + dy * dy;
			var t = length == 0 ? 0. : Math.max(0, Math.min(1, ((x - a.x) * dx + (y - a.y) * dy) / length));
			var p = new Point(a.x + dx * t, a.y + dy * t);
			var distance = Point.distance(new Point(x, y), p);
			if (distance < best) {
				best = distance;
				segment = i;
				projection = p;
			}
		}
		if (segment < 0 || best > 95)
			return null;
		var remaining = 192.;
		var from = projection;
		var target = routeLine[segment + 1];
		for (i in segment + 1...routeLine.length) {
			var p = routeLine[i];
			var distance = Point.distance(from, p);
			if (distance > 0.001)
				routeDirection = new Point((p.x - from.x) / distance * 100, (p.y - from.y) / distance * 100);
			if (distance >= remaining) {
				target = new Point(from.x + (p.x - from.x) * remaining / distance, from.y + (p.y - from.y) * remaining / distance);
				break;
			}
			target = p;
			remaining -= distance;
			from = p;
		}
		var ignoredGate = segment == routeLine.length - 2 ? routeGateId : 0;
		if (!clearGridLine(x, y, target))
			target = routeLine[segment + 1];
		if (!clearGridLine(x, y, target) && segment != routeLine.length - 2)
			return null;
		return target;
	}

	static function fieldPush(heap:Array<RouteNode>, node:RouteNode):Void {
		heap.push(node);
		var i = heap.length - 1;
		while (i > 0) {
			var parent = Std.int((i - 1) / 2);
			if (heap[parent].cost <= node.cost)
				break;
			heap[i] = heap[parent];
			i = parent;
		}
		heap[i] = node;
	}

	static function heapPop(heap:Array<RouteNode>, scores:Array<Float>):Int {
		var result = heap[0].cell;
		var last = heap.pop();
		if (heap.length == 0)
			return result;
		var i = 0;
		while (i * 2 + 1 < heap.length) {
			var child = i * 2 + 1;
			if (child + 1 < heap.length && heap[child + 1].cost < heap[child].cost)
				child++;
			if (last.cost <= heap[child].cost)
				break;
			heap[i] = heap[child];
			i = child;
		}
		heap[i] = last;
		return result;
	}

	static function tileKey(x:Int, y:Int):String {
		return x + ":" + y;
	}

	public function isGentleDirection(x:Float, y:Float, target:Point):Bool {
		return target == gentleTarget && gentleOrigin != null && Math.abs(x - gentleOrigin.x) < step && Math.abs(y - gentleOrigin.y) < step
			&& canAim(x, y, target, 0, true);
	}

	function clearGridLine(x:Float, y:Float, target:Point):Bool {
		var dx = target.x - x;
		var dy = target.y - y;
		var samples = Std.int(Math.ceil(Math.max(Math.abs(dx), Math.abs(dy)) * 4 / step));
		var previous = cellAt(x, y);
		if (previous < 0)
			return false;
		for (i in 1...samples + 1) {
			var next = cellAt(x + dx * i / samples, y + dy * i / samples);
			if (next == previous)
				continue;
			if (!walkable(next))
				return false;
			var col = next % width - previous % width;
			var row = Std.int(next / width) - Std.int(previous / width);
			if (col != 0 && row != 0) {
				var horizontal = previous + col;
				var vertical = previous + row * width;
				if ((rooms[previous] != rooms[next] && rooms[previous] != rooms[horizontal] && rooms[previous] != rooms[vertical])
					|| !walkable(horizontal)
					|| !walkable(vertical)
					|| !canCross(previous, horizontal)
					|| !canCross(previous, vertical)
					|| !canCross(horizontal, next)
					|| !canCross(vertical, next))
					return false;
			} else {
				if (!canCross(previous, next))
					return false;
			}
			previous = next;
		}
		return true;
	}
}
