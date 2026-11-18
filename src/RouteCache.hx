package mods.gate_compass;

import mods.api.dungeon.Tile;
import openfl.geom.Point;

/** Completed routes survive player movement. Only pending work changes priority. */
class RouteCache {
	public var limit(default, null) = 36;
	public var lowPower = false;
	public var foreground(default, null):RoutePlan;
	public var stats:NavigationStats;

	public var preview(default, null):Array<Point>;

	var previewJob:RoutePlanJob;
	var testJob:RoutePlanJob;
	var testBegun = false;
	var previewAttempted = false;
	var grid:RouteGrid;
	var next:Array<Int>;
	var gate:Point;
	var entries:Map<Int, RoutePlan> = new Map();
	var progress:Map<String, Int> = new Map();
	var background:RoutePlan;
	var serial = 0;
	var retainedPoints = 0;

	public function new(grid:RouteGrid, next:Array<Int>, gate:Point, stats:NavigationStats) {
		this.grid = grid;
		this.next = next;
		this.gate = gate;
		this.stats = stats;
	}

	public function setLimit(value:Int):Void {
		var next = Std.int(Math.max(10, Math.min(81, value)));
		if (limit == next)
			return;
		limit = next;
		progress = new Map();
		prune();
	}

	public function request(cell:Int, urgent:Bool = true):RoutePlan {
		if (cell < 0 || cell >= grid.cells.length || !grid.walkable(cell))
			return null;
		stats.requests++;
		if (urgent && foreground != null && foreground.job != null && !foreground.job.done && foreground.job.seen.exists(cell)) {
			foreground.used = ++serial;
			return foreground;
		}
		var entry:RoutePlan = entries.get(cell);
		if (entry != null) {
			entry.used = ++serial;
			if (entry.line != null)
				stats.hits++;
		} else {
			entry = new RoutePlan(cell, grid.rooms[cell]);
			entry.used = ++serial;
			entries.set(cell, entry);
		}
		if (urgent) {
			foreground = entry;
			if (!previewAttempted && stats.completed == 0) {
				previewAttempted = true;
				previewJob = new RoutePlanJob(grid, next, cell, grid.point(cell), gate, 2800);
			}
		}
		if (entry.job == null && entry.line == null && !entry.failed)
			entry.job = new RoutePlanJob(grid, next, cell, grid.point(cell), gate);
		prune();
		return entry;
	}

	public function hasTest():Bool {
		return testJob != null;
	}

	public function requestTest(cell:Int):Void {
		cancelTest();
		testJob = new RoutePlanJob(grid, next, cell, grid.point(cell), gate, 2800);
	}

	public function cancelTest():Void {
		if (testJob != null)
			testJob.cancel();
		testJob = null;
		testBegun = false;
	}

	public function foregroundPending():Bool {
		return testJob != null || previewJob != null || (foreground != null && foreground.job != null && !foreground.job.done);
	}

	public function advance(room:Tile, budgetMs:Float, allowBackground:Bool):Bool {
		var selected:RoutePlan = null;
		if (foreground != null && foreground.job != null && !foreground.job.done)
			selected = foreground;
		else if (allowBackground && grid.complete && room != null) {
			if (background != null && background.room == room && background.job != null && !background.job.done)
				selected = background;
			else {
				background = sample(room);
				selected = background;
			}
		}
		var isTest = testJob != null;
		var isPreview = !isTest && previewJob != null;
		if (!isTest && !isPreview && (selected == null || selected.job == null))
			return false;
		var job:RoutePlanJob = isTest ? testJob : isPreview ? previewJob : selected.job;
		stats.beginWork(isTest && !testBegun);
		if (isTest)
			testBegun = true;
		var before = job.probeSamples;
		var started = haxe.Timer.stamp();
		var count = job.runSlice(budgetMs, lowPower ? 512 : 2048);
		var ms = (haxe.Timer.stamp() - started) * 1000;
		stats.slice(ms, budgetMs, count);
		stats.probeSamples += job.probeSamples - before;
		if (!isPreview && !isTest)
			selected.ms += ms;
		if (!job.done)
			return false;
		if (isTest) {
			testJob = null;
			testBegun = false;
			if (!job.cancelled && job.result.length >= 2)
				stats.completed++;
			return false;
		}
		if (isPreview) {
			previewJob = null;
			if (!job.cancelled && job.result.length >= 2)
				preview = job.result;
			stats.event("initial-curved-section", {points: job.result.length});
			return preview != null;
		}
		selected.job = null;
		if (job.cancelled || job.result.length < 2) {
			selected.failed = true;
			return false;
		}
		selected.line = job.result;
		retainedPoints += selected.line.length;
		stats.completed++;
		prune();
		return selected == foreground;
	}

	function sample(room:Tile):RoutePlan {
		var key = room.x + ":" + room.y;
		var saved = progress.get(key);
		var part = saved == null ? 0 : saved;
		if (part >= limit || roomCount(room) >= limit)
			return null;
		progress.set(key, part + 1);
		var side = Std.int(Math.ceil(Math.sqrt(limit)));
		var x = room.x + (part % side + 0.5) * Tile.SIZE / side;
		var y = room.y + (Std.int(part / side) + 0.5) * Tile.SIZE / side;
		var origin = grid.cellAt(x, y);
		if (origin < 0)
			return null;
		var best = -1;
		var distance = Math.POSITIVE_INFINITY;
		for (dy in -2...3)
			for (dx in -2...3) {
				var col = origin % grid.width + dx;
				var row = Std.int(origin / grid.width) + dy;
				if (col < 0 || row < 0 || col >= grid.width || row >= grid.height)
					continue;
				var cell = row * grid.width + col;
				if (!grid.walkable(cell) || grid.rooms[cell] != room || next[cell] < 0)
					continue;
				var point = grid.point(cell);
				var d = (point.x - x) * (point.x - x) + (point.y - y) * (point.y - y);
				if (d < distance) {
					best = cell;
					distance = d;
				}
			}
		return best < 0 ? null : request(best, false);
	}

	public function alternatives(room:Tile):Array<RoutePlan> {
		var result:Array<RoutePlan> = [];
		for (value in entries) {
			var entry:RoutePlan = value;
			if (entry.room == room && entry.line != null)
				result.push(entry);
		}
		return result;
	}

	function roomCount(room:Tile):Int {
		var count = 0;
		for (value in entries) {
			var entry:RoutePlan = value;
			if (entry.room == room)
				count++;
		}
		return count;
	}

	function remove(entry:RoutePlan):Void {
		if (entry.job != null) {
			entry.job.cancel();
			stats.cancelled++;
		}
		if (entry.line != null)
			retainedPoints -= entry.line.length;
		entries.remove(entry.cell);
		if (background == entry)
			background = null;
	}

	function prune():Void {
		var all:Array<RoutePlan> = [for (value in entries) value];
		all.sort(function(a:RoutePlan, b:RoutePlan) {
			return a.used - b.used;
		});
		var pending = 0;
		for (entry in all)
			if (entry.job != null)
				pending++;
		var maximumPoints = lowPower ? 30000 : 120000;
		var total = all.length;
		for (entry in all) {
			if (entry == foreground || entry == background)
				continue;
			if (total > limit * 8 || retainedPoints > maximumPoints || roomCount(entry.room) > limit || (pending > 8 && entry.job != null)) {
				if (entry.job != null)
					pending--;
				remove(entry);
				total--;
			}
		}
	}

	public function snapshot(heroX:Float, heroY:Float):Dynamic {
		var rooms:Map<String, Dynamic> = new Map();
		for (value in entries) {
			var entry:RoutePlan = value;
			var tile = entry.room;
			if (tile == null)
				continue;
			var key = tile.x + ":" + tile.y;
			var row:Dynamic = rooms.get(key);
			if (row == null) {
				row = {
					id: tile.id,
					x: tile.x,
					y: tile.y,
					relativeX: tile.x + Tile.SIZE / 2 - heroX,
					relativeY: tile.y + Tile.SIZE / 2 - heroY,
					tileOffsetX: Math.floor((tile.x - heroX) / Tile.SIZE),
					tileOffsetY: Math.floor((tile.y - heroY) / Tile.SIZE),
					completed: 0,
					pending: 0,
					computeMs: 0.,
					routes: []
				};
				rooms.set(key, row);
			}
			if (entry.line != null)
				row.completed++;
			else if (entry.job != null)
				row.pending++;
			row.computeMs += entry.ms;
			var origin = grid.point(entry.cell);
			row.routes.push({
				x: origin.x,
				y: origin.y,
				relativeX: origin.x - heroX,
				relativeY: origin.y - heroY,
				completed: entry.line != null,
				failed: entry.failed,
				computeMs: entry.ms,
				points: entry.line == null ? 0 : entry.line.length
			});
		}
		return {
			limit: limit,
			retainedPoints: retainedPoints,
			previewPoints: preview == null ? 0 : preview.length,
			tiles: [for (row in rooms) row]
		};
	}

	public function clear():Void {
		cancelTest();
		if (previewJob != null)
			previewJob.cancel();
		previewJob = null;
		preview = null;
		previewAttempted = false;
		for (entry in entries)
			if (entry.job != null)
				entry.job.cancel();
		entries = new Map();
		progress = new Map();
		foreground = null;
		background = null;
		retainedPoints = 0;
	}
}
