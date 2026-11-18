package mods.gate_compass;

/** Captured immediately before the first actual job step. */
class WorkBaseline {
	public var time:Float;
	public var completed:Int;
	public var computeMs:Float;
	public var updates:Int;
	public var updateMs:Float;
	public var geometryMs:Float;
	public var meshMs:Float;
	public var slices:Int;
	public var histogram:Array<Int>;

	public function new(stats:NavigationStats) {
		time = haxe.Timer.stamp();
		completed = stats.completed;
		computeMs = stats.computeMs;
		updates = stats.updateCount;
		updateMs = stats.updateMs;
		geometryMs = stats.geometryMs;
		meshMs = stats.meshMs;
		slices = stats.slices;
		histogram = stats.sliceHistogram.copy();
	}
}
