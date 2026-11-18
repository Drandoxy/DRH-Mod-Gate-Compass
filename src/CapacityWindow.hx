package mods.gate_compass;

class CapacityWindow {
	public var started:Float;
	public var baseCompleted:Int;
	public var baseMs:Float;
	public var milestone = 0;
	public var baseline:WorkBaseline;
	public var label:String;
	public var travelled = 0.;
	public var lastTime:Float;
	public var lastX:Float;
	public var lastY:Float;
	public var teleports = 0;

	public function new(label:String, started:Float, stats:NavigationStats, x:Float, y:Float, ?baseline:WorkBaseline) {
		this.baseline = baseline == null ? new WorkBaseline(stats) : baseline;
		this.label = label;
		this.started = started;
		lastTime = started;
		lastX = x;
		lastY = y;
		baseCompleted = this.baseline.completed;
		baseMs = this.baseline.computeMs;
	}
}
