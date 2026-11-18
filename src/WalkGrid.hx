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
	var lastLineDistanceSquared = Math.POSITIVE_INFINITY;
	var liveStart = -1;
	var liveField:RouteField;

	public var routeLine:Array<Point> = [];
	public var visualRoute:Array<Point> = [];
	public var lowPower = false;
	public var routeDirection = new Point(1, 0);
	public var steeringDistance = 0.;

	public static inline final COMPASS_LOOKAHEAD = 96.;
	static final STEERING_ARCS = [192., COMPASS_LOOKAHEAD, 48., 24., 12., 6., 3., 1.];

	public var stats = new NavigationStats();

	var geometryBuild:GeometryBuild;
	var publishedGeometry:GeometryBuild;
	var queuedTiles:Array<Tile>;
	var desiredGoal:Tile;
	var desiredGate:Point;
	var desiredGateId:UInt = 0;

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
		if (tiles.length == 0 || floor.box2DWorld == null) {
			clear();
			return;
		}
		if (this.floor != null && this.floor != floor)
			clear();
		this.floor = floor;
		if (geometryBuild != null) {
			queuedTiles = tiles.copy();
			return;
		}
		geometryBuild = new GeometryBuild(floor, tiles, publishedGeometry, function(f:B2Fixture) {
			return blocksMovement(f);
		});
	}

	public function geometryPending():Bool {
		return geometryBuild != null;
	}

	public function advanceGeometry(ms:Float, maxSteps:Int = 4096):Bool {
		if (geometryBuild == null)
			return false;
		var job = geometryBuild;
		var started = haxe.Timer.stamp();
		job.runSlice(ms, maxSteps);
		var elapsed = (haxe.Timer.stamp() - started) * 1000;
		stats.geometryMs += elapsed;
		stats.maximumGeometryMs = Math.max(stats.maximumGeometryMs, elapsed);
		if (!job.done)
			return false;
		geometryBuild = null;
		if (job.changed) {
			field = null;
			lineOrigin = null;
			resetLiveRoute();
			routeLine = [];
			visualRoute = [];
			edgeChecks = new Map();
			invalidateRoute();
			focusAnnounced = false;
			cells = job.cells;
			rooms = job.rooms;
			hazards = job.hazards;
			nearCollider = job.near;
			clearance = job.clearance;
			tilesByPosition = job.tilesByPosition;
			left = job.left;
			top = job.top;
			step = job.spacing;
			width = job.width;
			height = job.height;
			publishedGeometry = job;
			shapeKey = job.layout;
			focusCell = cellAt(heroX, heroY);
			if (desiredGoal != null)
				prepareField(desiredGoal, desiredGate, desiredGateId);
			stats.event("geometry-published", {cells: cells.length, steps: job.steps});
		}
		if (queuedTiles != null) {
			var tiles = queuedTiles;
			queuedTiles = null;
			geometryBuild = new GeometryBuild(floor, tiles, publishedGeometry, function(f:B2Fixture) {
				return blocksMovement(f);
			});
		}
		return job.changed;
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

	public function clear():Void {
		if (geometryBuild != null)
			geometryBuild.cancel();
		geometryBuild = null;
		publishedGeometry = null;
		queuedTiles = null;
		desiredGoal = null;
		desiredGate = null;
		desiredGateId = 0;
		field = null;
		lineOrigin = null;
		resetLiveRoute();
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
		var body = fixture.GetBody();
		if (fixture.IsSensor() || !body.IsActive())
			return false;
		var bits = fixture.GetFilterData().categoryBits;
		var data = body.GetUserData();
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
		desiredGoal = goal;
		desiredGate = gate;
		desiredGateId = gateId;
		if (cells.length == 0)
			return;
		var key = goal.id + ":" + goal.x + ":" + goal.y + ":" + gateId + (gate == null ? "" : ":" + gate.x + ":" + gate.y);
		if (field != null && field.key == key)
			return;
		routeLine = [];
		visualRoute = [];
		lineOrigin = null;
		resetLiveRoute();
		focusAnnounced = false;
		field = new RouteField(goal, gate, gateId, key, cells.length);
		if (stats.initialSearchStarted < 0)
			stats.initialSearchStarted = haxe.Timer.stamp();
		routeGoal = key;
		routeGateId = gateId;
	}

	/** One reverse search fills the next step for every reachable cell. */
	public function prioritize(x:Float, y:Float):Void {
		heroX = x;
		heroY = y;
		focusCell = cellAt(x, y);
	}

	function resetLiveRoute():Void {
		liveStart = -1;
		liveField = null;
	}

	public function advanceField():Bool {
		var totalBudget = lowPower ? 0.6 : 1.5;
		var started = haxe.Timer.stamp();
		var changed = advanceGeometry(cells.length == 0 ? totalBudget : totalBudget * .4);
		var remaining = totalBudget - (haxe.Timer.stamp() - started) * 1000;
		if (field == null || remaining <= .02)
			return changed;
		return advanceFieldWork(remaining) || changed;
	}

	function retryGateSeeds():Bool {
		if (field == null || field.fullSeeds || field.gate == null)
			return false;
		var previous = field;
		field = new RouteField(previous.goal, previous.gate, previous.gateId, previous.key, cells.length);
		field.fullSeeds = true;
		resetLiveRoute();
		focusAnnounced = false;
		stats.event("full-gate-seed-retry", {});
		return true;
	}

	// A fixed consistent Manhattan heuristic prioritizes the initial hero.
	// Keeping it fixed lets the same search finish the reusable destination
	// field without invalidating settled costs as the player moves.
	function fieldHeuristic(cell:Int):Float {
		if (field.initialFocus < 0)
			return 0.;
		return Math.abs(cell % width - field.initialFocus % width) + Math.abs(Std.int(cell / width) - Std.int(field.initialFocus / width));
	}

	function advanceFieldWork(budgetMs:Float):Bool {
		if (field == null || field.phase == 2)
			return false;

		var f = field;
		if (f.initialFocus < 0 && focusCell >= 0)
			f.initialFocus = focusCell;
		var deadline = haxe.Timer.stamp() + budgetMs / 1000;
		var work = 0;
		while (work++ < 1536 && haxe.Timer.stamp() < deadline) {
			if (f.phase == -1) {
				if (f.initialized < f.count) {
					f.scores.push(Math.POSITIVE_INFINITY);
					f.next.push(-1);
					f.settled.push(false);
					f.initialized++;
				} else
					f.phase = 0;
				continue;
			}
			if (f.phase == 0) {
				var side = Math.round(Tile.SIZE / step);
				if (f.seedCells == null) {
					f.seedCells = [];
					for (offset in 0...side * side) {
						var cell = index(Math.round((f.goal.x - left) / step) + offset % side, Math.round((f.goal.y - top) / step) + Std.int(offset / side));
						if (walkable(cell))
							f.seedCells.push(cell);
					}
					var end = f.gate == null ? new Point(f.goal.x + Tile.SIZE / 2, f.goal.y + Tile.SIZE / 2) : f.gate;
					f.seedCells.sort(function(a:Int, b:Int) {
						var ax = left + (a % width + 0.5) * step - end.x;
						var ay = top + (Std.int(a / width) + 0.5) * step - end.y;
						var bx = left + (b % width + 0.5) * step - end.x;
						var by = top + (Std.int(b / width) + 0.5) * step - end.y;
						var ad = ax * ax + ay * ay;
						var bd = bx * bx + by * by;
						return ad < bd ? -1 : ad > bd ? 1 : 0;
					});
				}
				if (f.scan < f.seedCells.length) {
					var cell = f.seedCells[f.scan++];
					if (!walkable(cell))
						continue;
					var p = point(cell);
					if (!f.goal.contains(p.x, p.y))
						continue;
					var end = f.gate == null ? new Point(f.goal.x + Tile.SIZE / 2, f.goal.y + Tile.SIZE / 2) : f.gate;
					var dx = p.x - end.x;
					var dy = p.y - end.y;
					var distance = dx * dx + dy * dy;
					// Once a safe approach exists, distant room cells do not
					// need their own direct-to-gate ray. The field reaches them.
					if (!f.fullSeeds && f.seeds.length > 0 && distance > Math.pow(Math.max(180., step * 3), 2))
						continue;
					var visibleToGate = f.gate == null || canAim(p.x, p.y, f.gate, f.gateId);
					if (f.gate != null && visibleToGate && hazardFree(p.x, p.y, f.gate)) {
						// Closed gates can split the nearest cells into separate
						// islands. Cache every visible approach, on either side.
						f.seeds.push(cell);
						f.scores[cell] = Math.sqrt(distance) / step;
						f.next[cell] = cell;
					}
					if (distance < f.distance && visibleToGate) {
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
					fieldPush(f.heap, new RouteNode(seed, f.scores[seed] + fieldHeuristic(seed)));
				f.phase = 1;
			}
			if (f.heap.length == 0) {
				if (focusCell >= 0 && !f.settled[focusCell] && retryGateSeeds())
					return false;
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
				fieldPush(f.heap, new RouteNode(next, score + fieldHeuristic(next)));
			}
			if (!focusAnnounced && current == focusCell) {
				focusAnnounced = true;
				return true;
			}
		}
		return false;
	}

	public function waypoint(x:Float, y:Float, goal:Tile, gate:Point, gateId:UInt = 0):Point {
		prepareField(goal, gate, gateId);
		heroX = x;
		heroY = y;
		return field == null ? null : followLiveField(x, y);
	}

	function farFromRouteEnd(point:Point):Bool {
		var end = routeLine[routeLine.length - 1];
		var dx = point.x - end.x;
		var dy = point.y - end.y;
		return dx * dx + dy * dy > 600 * 600;
	}

	function followLiveField(x:Float, y:Float):Point {
		var start = cellAt(x, y);
		if (start >= 0 && !walkable(start)) {
			var closest = Math.POSITIVE_INFINITY;
			var recovered = -1;
			var col = start % width;
			var row = Std.int(start / width);
			for (dy in -2...3)
				for (dx in -2...3) {
					var candidate = index(col + dx, row + dy);
					if (!walkable(candidate) || !field.settled[candidate])
						continue;
					var at = point(candidate);
					var distance = Point.distance(new Point(x, y), at);
					if (distance < closest && canAim(x, y, at)) {
						closest = distance;
						recovered = candidate;
					}
				}
			start = recovered;
		}
		var previous = liveField == field ? followLine(x, y) : null;
		if (start < 0 || !field.settled[start] || field.next[start] < 0) {
			if (start >= 0 && field.phase == 2)
				retryGateSeeds();
			return previous;
		}
		var lineDistance = previous == null ? Math.POSITIVE_INFINITY : lastLineDistanceSquared;
		if (liveField == field && liveStart == start && previous != null && lineDistance < 12 * 12)
			return previous;
		// Keep the route ahead while its moving head can still connect nearby.
		if (previous != null && lineDistance < 32 * 32 && farFromRouteEnd(previous))
			return previous;
		var origin = new Point(x, y);
		var next = cachedLine(start, origin);
		if (next.length < 2 || !steeringClear(x, y, next[1]))
			return previous;
		next = roundLiveCorners(shortenLiveLine(next));
		if (!adoptCompleted(next))
			return previous;
		liveStart = start;
		liveField = field;
		return followLine(x, y);
	}

	function shortenLiveLine(line:Array<Point>):Array<Point> {
		var result = [line[0]];
		var from = 0;
		for (_ in 0...24) {
			if (from + 1 >= line.length)
				break;
			var to = from + 1;
			var candidate = Std.int(Math.min(line.length - 1, from + 12));
			while (candidate > to) {
				var dx = line[from].x - line[candidate].x;
				var dy = line[from].y - line[candidate].y;
				if (dx * dx + dy * dy <= 600 * 600 && canConnectRouteHead(line[from], line[candidate])) {
					to = candidate;
					break;
				}
				candidate--;
			}
			result.push(line[to]);
			from = to;
		}
		for (i in from + 1...line.length)
			result.push(line[i]);
		return result;
	}

	function roundLiveCorners(line:Array<Point>):Array<Point> {
		var result = [line[0]];
		for (i in 1...line.length - 1) {
			var a = line[i - 1];
			var b = line[i];
			var c = line[i + 1];
			var ab = Point.distance(a, b);
			var bc = Point.distance(b, c);
			var radius = Math.min(100., Math.min(ab, bc) * .4);
			if (radius < 2 || i > 24) {
				result.push(b);
				continue;
			}
			var enter = new Point(b.x + (a.x - b.x) * radius / ab, b.y + (a.y - b.y) * radius / ab);
			var leave = new Point(b.x + (c.x - b.x) * radius / bc, b.y + (c.y - b.y) * radius / bc);
			var arc = [enter];
			var safe = true;
			for (sample in 1...9) {
				var t = sample / 8.;
				var u = 1 - t;
				var point = new Point(u * u * enter.x + 2 * u * t * b.x + t * t * leave.x, u * u * enter.y + 2 * u * t * b.y + t * t * leave.y);
				if (!canConnectRouteHead(arc[arc.length - 1], point)) {
					safe = false;
					break;
				}
				arc.push(point);
			}
			if (safe)
				for (point in arc)
					result.push(point);
			else
				result.push(b);
		}
		result.push(line[line.length - 1]);
		return result;
	}

	function adoptCompleted(line:Array<Point>):Bool {
		if (line == null || line.length < 2)
			return false;
		var previous = routeLine;
		routeLine = line;
		if (followLine(heroX, heroY) == null) {
			routeLine = previous;
			return false;
		}
		visualRoute = line;
		lineOrigin = null;
		return true;
	}

	static function distanceSquaredToLine(line:Array<Point>, x:Float, y:Float):Float {
		var best = Math.POSITIVE_INFINITY;
		for (i in 0...line.length - 1) {
			var a = line[i];
			var b = line[i + 1];
			var dx = b.x - a.x;
			var dy = b.y - a.y;
			var square = dx * dx + dy * dy;
			var t = square == 0 ? 0. : Math.max(0., Math.min(1., ((x - a.x) * dx + (y - a.y) * dy) / square));
			var ex = a.x + dx * t - x;
			var ey = a.y + dy * t - y;
			best = Math.min(best, ex * ex + ey * ey);
			if (best == 0)
				return 0;
		}
		return best;
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
		// The current cell centre can be behind the hero. Connect directly to
		// the next field point when safe, rather than briefly guiding backwards
		// until a completed curve replaces this temporary line.
		if (raw.length >= 3 && canConnectRouteHead(origin, raw[2]))
			raw.splice(1, 1);
		return compactLine(raw);
	}

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

	public function canConnectRouteHead(from:Point, to:Point):Bool {
		return walkable(cellAt(from.x, from.y)) && walkable(cellAt(to.x, to.y)) && hazardFree(from.x, from.y, to) && steeringClear(from.x, from.y, to);
	}

	function hazardFree(x:Float, y:Float, target:Point):Bool {
		var dx = target.x - x;
		var dy = target.y - y;
		var count = Std.int(Math.ceil(Math.sqrt(dx * dx + dy * dy) / (step / 2)));
		var previous = -2;
		for (i in 0...count + 1) {
			var t = count == 0 ? 0. : i / count;
			var cell = cellAt(x + dx * t, y + dy * t);
			if (cell == previous)
				continue;
			previous = cell;
			if (cell >= 0 && hazards[cell])
				return false;
		}
		return true;
	}

	function steeringClear(x:Float, y:Float, target:Point, ignoredGate:UInt = 0):Bool {
		if (!clearGridLine(x, y, target)) {
			// The hero can stand safely near a wall even when this coarse
			// cell's centre is blocked. Permit only a short exact-tested exit.
			return !walkable(cellAt(x, y))
				&& walkable(cellAt(target.x, target.y))
				&& (target.x
					- x) * (target.x - x)
					+ (target.y - y) * (target.y - y) <= step * step * 9
						&& floor != null
						&& floor.box2DWorld != null
						&& exactSteeringChord(x, y, target, ignoredGate);
		}
		// Grid centres/edges cannot prove that an off-centre hero-to-target
		// chord misses a wall inside a cell. Validate that actual chord too.
		return cachedQueries || floor == null || floor.box2DWorld == null || exactSteeringChord(x, y, target, ignoredGate);
	}

	function forwardRoutePoint(segment:Int, projection:Point, ahead:Float):Point {
		var from = projection;
		for (i in segment + 1...routeLine.length) {
			var to = routeLine[i];
			var span = Point.distance(from, to);
			if (span == 0)
				continue;
			if (span >= ahead && span > .001)
				return new Point(from.x + (to.x - from.x) * ahead / span, from.y + (to.y - from.y) * ahead / span);
			ahead -= span;
			from = to;
		}
		return routeLine[routeLine.length - 1];
	}

	var chordKnown = false;
	var chordX = 0.;
	var chordY = 0.;
	var chordTargetX = 0.;
	var chordTargetY = 0.;
	var chordGate:UInt = 0;
	var chordClear = false;
	var probingSteering = false;

	function exactSteeringChord(x:Float, y:Float, target:Point, gate:UInt):Bool {
		if (!probingSteering)
			return canAim(x, y, target, gate);
		if (chordKnown && chordX == x && chordY == y && chordTargetX == target.x && chordTargetY == target.y && chordGate == gate)
			return chordClear;
		chordClear = canAim(x, y, target, gate);
		chordKnown = true;
		chordX = x;
		chordY = y;
		chordTargetX = target.x;
		chordTargetY = target.y;
		chordGate = gate;
		return chordClear;
	}

	function followLine(x:Float, y:Float):Point {
		chordKnown = false;
		probingSteering = true;
		try {
			var result = sampleLine(x, y);
			probingSteering = false;
			return result;
		} catch (error:Dynamic) {
			probingSteering = false;
			throw error;
		}
	}

	function furthestVisible(segment:Int, projection:Point, x:Float, y:Float):Point {
		// Scan route vertices backwards: a corner can hide an earlier part
		// while a later branch is visible again. Never assume monotonicity.
		var first = segment + 1;
		var limit = Std.int(Math.min(routeLine.length - 1, first + 64));
		for (offset in 0...limit - first + 1) {
			var i = limit - offset;
			var candidate = routeLine[i];
			var gate = i == routeLine.length - 1 ? routeGateId : 0;
			if (!steeringClear(x, y, candidate, gate) || !hazardFree(x, y, candidate))
				continue;
			// Refine just beyond a visible corner while every tested chord
			// remains clear. Keep the search bounded.
			if (i + 1 < routeLine.length) {
				var end = routeLine[i + 1];
				var low = 0.;
				var high = 1.;
				for (_ in 0...6) {
					var t = (low + high) / 2;
					var probe = new Point(candidate.x + (end.x - candidate.x) * t, candidate.y + (end.y - candidate.y) * t);
					if (steeringClear(x, y, probe) && hazardFree(x, y, probe))
						low = t;
					else
						high = t;
				}
				return new Point(candidate.x + (end.x - candidate.x) * low, candidate.y + (end.y - candidate.y) * low);
			}
			return candidate;
		}
		return null;
	}

	function sampleLine(x:Float, y:Float):Point {
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
			var px = a.x + dx * t;
			var py = a.y + dy * t;
			var ex = px - x;
			var ey = py - y;
			var distance = ex * ex + ey * ey;
			if (distance < best) {
				best = distance;
				segment = i;
				if (projection == null)
					projection = new Point();
				projection.x = px;
				projection.y = py;
			}
		}
		lastLineDistanceSquared = best;
		if (segment < 0 || best > 95 * 95)
			return null;
		var ignoredGate = segment == routeLine.length - 2 ? routeGateId : 0;
		var target:Point = furthestVisible(segment, projection, x, y);
		var headingPoint:Point = target;
		// Shorten the forward arc at a corner, rather than aiming back at
		// its already-passed vertex when a longer chord crosses a wall.
		for (ahead in (target == null ? STEERING_ARCS : [])) {
			var candidate = forwardRoutePoint(segment, projection, ahead);
			var dx = candidate.x - x;
			var dy = candidate.y - y;
			if (dx * dx + dy * dy < .25 || !steeringClear(x, y, candidate, ignoredGate))
				continue;
			if (target == null)
				target = candidate;
			if (ahead <= COMPASS_LOOKAHEAD) {
				headingPoint = candidate;
				break;
			}
		}
		if (target == null) {
			var corner = routeLine[segment + 1];
			var dx = corner.x - x;
			var dy = corner.y - y;
			if (dx * dx + dy * dy > .000001 && steeringClear(x, y, corner, ignoredGate)) {
				target = corner;
				headingPoint = corner;
			} else
				return null;
		}
		if (headingPoint == null)
			headingPoint = target;
		var hx = headingPoint.x - x;
		var hy = headingPoint.y - y;
		var span = Math.sqrt(hx * hx + hy * hy);
		steeringDistance = span;
		if (span > .001) {
			var scale = 100 / span;
			var nextX = hx * scale;
			var nextY = hy * scale;
			if (routeDirection.x * nextX + routeDirection.y * nextY < -5000)
				stats.event("sharp-heading-turn", {
					x: x,
					y: y,
					fromX: routeDirection.x,
					fromY: routeDirection.y,
					toX: nextX,
					toY: nextY
				});
			routeDirection.x = nextX;
			routeDirection.y = nextY;
		}
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
