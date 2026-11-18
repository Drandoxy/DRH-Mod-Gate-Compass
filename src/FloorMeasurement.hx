package mods.gate_compass;

import mods.api.dungeon.Tile;

/** Observes real capped work, not an artificial CPU stress test. */
class FloorMeasurement {
	public var status = "8-second capacity test. Stand safely still.";
	public var localLogging = false;

	var path:String;
	var manualSession = false;
	var manual:CapacityWindow;
	var manualPending = false;
	var pendingSerial = 0;

	public var manualStarted = -1.;
	public var manualAdvice = 0;
	public var manualNote = "";

	var floor:UInt = 0;
	var floorStarted = 0.;

	public function new(data:String) {
		path = data + "/route-capacity.jsonl";
		try {
			var options:Dynamic = haxe.Json.parse(sys.io.File.getContent(data + "/local-diagnostics.json"));
			localLogging = options.enabled == true;
		} catch (_:Dynamic) {}
	}

	public function enter(id:UInt):Void {
		floor = id;
		floorStarted = haxe.Timer.stamp();
		manualSession = false;
		manual = null;
		manualPending = false;
		manualStarted = -1;
	}

	public function start(grid:WalkGrid, x:Float, y:Float):Void {
		if (grid == null || floor == 0) {
			status = "This measurement works only in a dungeon.";
			return;
		}
		manualSession = true;
		manual = null;
		manualPending = true;
		pendingSerial = grid.stats.manualSerial;
		manualStarted = -1;
		manualAdvice = 0;
		manualNote = "";
		grid.requestMeasurement();
		status = "Waiting for the first test line calculation...";
	}

	public function tick(grid:WalkGrid, tileCount:Int, x:Float, y:Float):Void {
		if (grid == null || floor == 0)
			return;
		var now = haxe.Timer.stamp();
		if (manualPending && grid.stats.manualSerial > pendingSerial && grid.stats.manualWork != null) {
			var baseline = grid.stats.manualWork;
			manual = new CapacityWindow("manual", baseline.time, grid.stats, x, y, baseline);
			manualStarted = baseline.time;
			manualPending = false;
		}
		if (manual != null) {
			sample(manual, grid, tileCount, x, y, now);
			if (manual.milestone >= 3)
				manual = null;
		}
	}

	function sample(window:CapacityWindow, grid:WalkGrid, tileCount:Int, x:Float, y:Float, now:Float):Void {
		var dx = x - window.lastX;
		var dy = y - window.lastY;
		var distance = Math.sqrt(dx * dx + dy * dy);
		if (distance > Tile.SIZE * 2)
			window.teleports++;
		else
			window.travelled += distance;
		window.lastX = x;
		window.lastY = y;
		window.lastTime = now;
		var milestones = [3., 5., 8.];
		if (window.milestone >= milestones.length)
			return;
		if (now - window.started < milestones[window.milestone])
			return;
		var requested = milestones[window.milestone++];
		var completed = grid.stats.completed - window.baseCompleted;
		var effort = grid.stats.computeMs - window.baseMs;
		var elapsed = now - window.started;
		var speed = elapsed > 0 ? window.travelled / elapsed : 0.;
		var baseline = window.baseline;
		var histogram = [
			for (i in 0...grid.stats.sliceHistogram.length)
				Std.int(Math.max(0, grid.stats.sliceHistogram[i] - baseline.histogram[i]))
		];
		var frames = grid.stats.updateCount - baseline.updates;
		var steady = Math.max(0,
			grid.stats.updateMs
			- baseline.updateMs
			- (grid.stats.geometryMs - baseline.geometryMs)
			- (grid.stats.meshMs - baseline.meshMs));
		var p95 = CapacityAdvice.percentile(histogram);
		var suggestion = CapacityAdvice.recommend(grid.routeLimit, frames, steady, p95, completed);
		var confidence = suggestion == 0 ? "insufficient" : completed >= 12 ? "higher" : "limited";
		if (window.label == "manual") {
			manualAdvice = suggestion == 0 ? grid.routeLimit : suggestion;
			manualNote = suggestion == 0 ? "Limited route sample; kept the current selection." : suggestion == grid.routeLimit ? "Current route count fits the observed CPU budget." : "Repeated route workload exceeded the observed CPU budget.";
			status = Std.int(requested) + "s: " + manualAdvice + " routes/tile. " + manualNote;
		}
		write({
			event: "measurement",
			floor: floor,
			source: window.label,
			requestedSeconds: requested,
			elapsedSeconds: elapsed,
			floorElapsed: now - floorStarted,
			hero: {
				x: x,
				y: y,
				speed: speed,
				travelled: window.travelled,
				teleports: window.teleports
			},
			totalTiles: tileCount,
			completedInWindow: completed,
			computeMsInWindow: effort,
			recommendation: suggestion,
			recommendationMethod: "frame-budget-v2",
			currentRouteLimit: grid.routeLimit,
			steadyMsPerFrame: frames > 0 ? steady / frames : 0.,
			routeSliceP95Ms: p95,
			confidence: confidence,
			lowPower: grid.lowPower,
			cache: grid.cacheSnapshot(),
			timing: grid.stats.snapshot()
		});
	}

	public function cancelManual(message:String):Void {
		manualPending = false;
		manual = null;
		manualStarted = -1;
		status = message;
		write({event: "manual-test-stopped", floor: floor, reason: message});
	}

	public function finishManual(message:String):Void {
		manualPending = false;
		manual = null;
		manualStarted = -1;
		status = message;
	}

	public function logDrawing(result:Dynamic):Void {
		write({event: "drawing-test", floor: floor, result: result});
	}

	public function suspend(grid:WalkGrid):Void {
		var id = floor;
		finish(grid);
		floor = id;
	}

	public function finish(grid:WalkGrid):Void {
		if (grid != null && floor != 0)
			write({
				event: "floor-end",
				floor: floor,
				elapsedSeconds: haxe.Timer.stamp() - floorStarted,
				timing: grid.stats.snapshot(),
				cache: grid.cacheSnapshot()
			});
		manualSession = false;
		manual = null;
		manualPending = false;
		manualStarted = -1;
		floor = 0;
	}

	function write(value:Dynamic):Void {
		if (!localLogging || !manualSession)
			return;
		try {
			var output = sys.io.File.append(path, false);
			output.writeString(haxe.Json.stringify(value) + "\n");
			output.close();
		} catch (_:Dynamic) {}
	}
}
