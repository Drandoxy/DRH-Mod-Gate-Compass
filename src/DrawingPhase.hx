package mods.gate_compass;

class DrawingPhase {
	public var lines:Int;
	public var samples:Array<Float> = [];

	public function new(lines:Int) {
		this.lines = lines;
	}

	public function summary():Dynamic {
		if (samples.length == 0)
			return {
				lines: lines,
				samples: 0,
				meanMs: 0.,
				p95Ms: 0.,
				fps: 0.
			};
		var sorted = samples.copy();
		sorted.sort(function(a:Float, b:Float) {
			return a < b ? -1 : a > b ? 1 : 0;
		});
		var total = 0.;
		for (v in sorted)
			total += v;
		var mean = total / sorted.length;
		return {
			lines: lines,
			samples: sorted.length,
			meanMs: mean,
			p95Ms: sorted[Std.int(Math.ceil(sorted.length * .95)) - 1],
			fps: 1000 / mean
		};
	}
}
