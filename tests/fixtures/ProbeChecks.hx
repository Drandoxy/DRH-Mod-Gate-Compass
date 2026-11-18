import mods.gate_compass.WalkGrid;
import mods.api.dungeon.Tile;
import openfl.geom.Point;

private class CountingChordGrid extends WalkGrid {
	public var blocked = false;
	public var checks = 0;
	public var failProbe = false;

	override public function canAim(x:Float, y:Float, target:Point, ignoredGate:UInt = 0, smallObstacle:Bool = false):Bool {
		checks++;
		if (failProbe)
			throw "synthetic collision failure";
		return !blocked;
	}
}

@:access(mods.gate_compass.WalkGrid)
class ProbeChecks {
	static function main():Void {
		var grid = new CountingChordGrid();
		grid.width = 30;
		grid.height = 30;
		grid.left = 0;
		grid.top = 0;
		grid.step = 10;
		var tile = new Tile("room", 0, 0);
		grid.cells = [for (i in 0...900) true];
		grid.rooms = [for (i in 0...900) tile];
		grid.nearCollider = [for (i in 0...900) false];
		grid.hazards = [for (i in 0...900) false];
		grid.floor = new distributedObjects.DistributedDungeonFloor();
		grid.routeLine = [new Point(200, 200), new Point(230, 200)];
		if (grid.followLine(201, 201) == null || grid.checks != 1)
			throw "identical terminal chords were not deduplicated";
		grid.blocked = true;
		if (grid.followLine(201, 201) != null)
			throw "collision result leaked into a later sample";
		if (grid.canConnectRouteHead(new Point(201, 201), new Point(230, 200)))
			throw "render connector reused stale steering cache";
		grid.blocked = false;
		if (grid.followLine(201, 201) == null)
			throw "cleared wall remained cached";
		grid.failProbe = true;
		var failed = false;
		try
			grid.followLine(201, 201)
		catch (_:Dynamic)
			failed = true;
		if (!failed || grid.probingSteering)
			throw "exception left the collision cache scope active";
		trace("PASS: exact chord reuse inside a sample; changed collision state observed on later samples and rendering");
	}
}
