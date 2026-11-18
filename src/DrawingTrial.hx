package mods.gate_compass;

/** Eight seconds from first real line-work step, with a quiet baseline first. */
class DrawingTrial {
	public static inline final DURATION = 8.;

	public var started:Float;
	public var done = false;
	public var stopped = "";
	public var phases:Array<DrawingPhase> = [
		new DrawingPhase(1),
		new DrawingPhase(4),
		new DrawingPhase(8),
		new DrawingPhase(16),
		new DrawingPhase(32)
	];

	var lastCount = -1;
	var lastTime:Float;
	var countChanged = 0.;
	var severe = 0;

	public function new(started:Float) {
		this.started = started;
		lastTime = started;
	}

	public function remaining(now:Float):Float {
		return Math.max(0, DURATION - (now - started));
	}

	public function phase(now:Float):Int {
		var t = now - started;
		return t < 2 ? 0 : t < 3.5 ? 1 : t < 5 ? 2 : t < 6.5 ? 3 : 4;
	}

	public function target(now:Float):Int {
		return phases[phase(now)].lines;
	}

	public function sample(now:Float, frameMs:Float, actual:Int, building:Bool):Void {
		if (done)
			return;
		lastTime = now;
		if (frameMs > 1000) {
			done = true;
			stopped = "The test was interrupted by a long pause.";
			return;
		}
		if (now - started >= DURATION) {
			done = true;
			return;
		}
		if (frameMs > 250)
			severe++;
		else
			severe = 0;
		if (severe >= 3) {
			done = true;
			stopped = "Stopped after repeated very slow frames.";
			return;
		}
		if (actual != lastCount) {
			lastCount = actual;
			countChanged = now;
		}
		var p = phase(now);
		var begins = p == 0 ? 0. : p == 1 ? 2. : p == 2 ? 3.5 : p == 3 ? 5. : 6.5;
		if (!building && actual == phases[p].lines && now - started - begins > .25 && now - countChanged > .25 && frameMs > 0 && frameMs < 500)
			phases[p].samples.push(frameMs);
	}

	public function result():Dynamic {
		var rows = [for (p in phases) p.summary()];
		var baseline = rows[0];
		var stable = 0;
		if (baseline.samples >= 8) {
			for (row in rows)
				if (row.samples >= 8 && row.meanMs <= baseline.meanMs * 1.2 + 1 && row.p95Ms <= baseline.p95Ms * 1.25 + 1)
					stable = row.lines;
		}
		return {
			durationSeconds: DURATION,
			actualSeconds: Math.max(0, lastTime - started),
			completed: done && stopped == "" && lastTime - started >= DURATION,
			stopped: stopped,
			baseline: baseline,
			stableAdditionalLines: stable,
			phases: rows,
			valid: baseline.samples >= 8
		};
	}
}
