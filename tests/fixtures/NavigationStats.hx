package;

/** Small aggregate counters; no samples or file writes inside a micro-step. */
class NavigationStats {
	public var trace = false;

	static final SLICE_BOUNDS = [.25, .5, 1., 2., 4., 8., 16., 32., 64., 128.];

	public var sliceHistogram:Array<Int> = [0, 0, 0, 0, 0, 0, 0, 0, 0, 0];
	public var initialSearchStarted = -1.;
	public var firstPlanDelayMs = -1.;
	public var firstCompassDelayMs = -1.;
	public var firstMeshDelayMs = -1.;

	var events:Array<Dynamic> = [];

	public var geometryMs = 0.;
	public var maximumGeometryMs = 0.;
	public var meshMs = 0.;
	public var maximumMeshMs = 0.;
	public var requests = 0;
	public var hits = 0;
	public var completed = 0;
	public var cancelled = 0;
	public var workSteps = 0;
	public var probeSamples = 0;
	public var slices = 0;
	public var computeMs = 0.;
	public var maximumSliceMs = 0.;
	public var overBudget = 0;
	public var updateCount = 0;
	public var updateMs = 0.;
	public var maximumUpdateMs = 0.;
	public var swaps = 0;
	public var rejectedSwaps = 0;
	public var zeroMasks = 0;

	public function new() {}

	public function slice(ms:Float, budget:Float, count:Int):Void {
		var bounds = SLICE_BOUNDS;
		var bucket = 0;
		while (bucket < bounds.length - 1 && ms > bounds[bucket])
			bucket++;
		sliceHistogram[bucket]++;
		slices++;
		computeMs += ms;
		maximumSliceMs = Math.max(maximumSliceMs, ms);
		workSteps += count;
		if (ms > budget + 0.15)
			overBudget++;
	}

	public function update(ms:Float):Void {
		updateCount++;
		updateMs += ms;
		maximumUpdateMs = Math.max(maximumUpdateMs, ms);
	}

	public function event(kind:String, details:Dynamic):Void {
		if (!trace)
			return;
		if (events.length >= 32)
			events.shift();
		events.push({time: haxe.Timer.stamp(), kind: kind, details: details});
	}

	public function snapshot():Dynamic {
		return {
			requests: requests,
			build: "0.2.38",
			firstCompassDelayMs: firstCompassDelayMs,
			firstPlanDelayMs: firstPlanDelayMs,
			firstMeshDelayMs: firstMeshDelayMs,
			geometryMs: geometryMs,
			maximumGeometryMs: maximumGeometryMs,
			meshMs: meshMs,
			maximumMeshMs: maximumMeshMs,
			cacheHits: hits,
			completed: completed,
			cancelled: cancelled,
			workSteps: workSteps,
			probeSamples: probeSamples,
			slices: slices,
			sliceHistogram: sliceHistogram.copy(),
			computeMs: computeMs,
			maximumSliceMs: maximumSliceMs,
			overBudget: overBudget,
			updateCount: updateCount,
			updateMs: updateMs,
			maximumUpdateMs: maximumUpdateMs,
			rendererSwaps: swaps,
			rejectedBlankSwaps: rejectedSwaps,
			zeroVisibilityMasks: zeroMasks,
			events: events.copy()
		};
	}
}
