package mods.gate_compass;

/** Cache count changes warm-up duration, not the fixed per-update slice budget. */
class CapacityAdvice {
	public static function recommend(current:Int, frames:Int, steadyMs:Float, p95SliceMs:Float, completed:Int):Int {
		if (frames < 30 || completed < 3)
			return 0;
		var average = Math.max(0, steadyMs) / frames;
		// Preserve the tested selection when average mod work is modest. Long full
		// routes and isolated worst-case pauses are not evidence that the cache is too large.
		var count = Std.int(Math.max(10, Math.min(81, current)));
		if (average <= 1.5 && p95SliceMs <= 4.)
			return count;
		var cpuFactor = average > 1.5 ? 1.5 / average : 1.;
		var tailFactor = p95SliceMs > 4.?4. /
		p95SliceMs:1.;
		return Std.int(Math.max(10, Math.min(count, Math.floor(count * Math.min(cpuFactor, tailFactor)))));
	}

	public static function percentile(hist:Array<Int>):Float {
		var bounds = [.25, .5, 1., 2., 4., 8., 16., 32., 64., 128.];
		var total = 0;
		for (n in hist)
			total += n;
		if (total == 0)
			return 0.;
		var target = Math.ceil(total * .95);
		var seen = 0;
		for (i in 0...hist.length) {
			seen += hist[i];
			if (seen >= target)
				return bounds[i];
		}
		return 128.;
	}
}
