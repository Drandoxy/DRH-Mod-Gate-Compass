import mods.gate_compass.Compass;
import mods.gate_compass.RouteHead;
import mods.gate_compass.RouteMotion;
import mods.gate_compass.WalkGrid;
import openfl.geom.Point;

private class LocalGrid extends WalkGrid {
	public var blocked = false;

	override public function canConnectRouteHead(from:Point, to:Point):Bool {
		return !blocked;
	}
}

@:access(mods.gate_compass.Compass)
class RouteHeadChecks {
	static function main():Void {
		var line = [for (i in 0...101) new Point(i * 10, 0)];
		var grid = new LocalGrid();
		var head = RouteHead.connect(line, 100, 30, grid);
		if (head == null || head.points[0].y != 30 || head.points[12] != line[head.join])
			throw "connector did not join unchanged route geometry";
		var sparse = [new Point(0, 0), new Point(1000, 0)];
		var sparseHead = RouteHead.connect(sparse, 100, 30, grid);
		if (sparseHead == null || Point.distance(sparseHead.points[12], head.points[12]) > .001
			|| Point.distance(sparseHead.direction(30), head.direction(30)) > .001)
			throw "sparse navigation and dense display produced different steering";
		var moved = RouteHead.connect(line, 101, 30, grid);
		if (moved == null || Math.abs(moved.points[12].x - head.points[12].x - 1) > .001)
			throw "connector join snapped between route vertices";
		if (RouteHead.connect(line, 100, 0, grid) == null)
			throw "connector disappeared when approaching the route centre";
		var ctx:mods.api.Context = Type.createEmptyInstance(mods.api.Context);
		var compass = new Compass(ctx);
		compass.routeGrid = grid;
		compass.setDisplayMode("line");
		compass.setRoute(line);
		var direction = head.direction(30);
		if (direction.x <= 0 || direction.y >= 0)
			throw "shared connector direction did not turn toward the line";
		var originalMesh = compass.routeBatches[0].mesh;
		compass.setWorldPosition(100, 30);
		if (compass.headBatches.length == 0 || compass.routeBatches[0].mesh != originalMesh)
			throw "moving the connector replaced the fixed route mesh";
		grid.blocked = true;
		if (RouteHead.connect(line, 108, 35, grid) != null)
			throw "blocked connector was accepted";
		compass.setWorldPosition(110, 36);
		if (compass.headBatches.length != 0 || compass.routeBatches[0].mesh != originalMesh)
			throw "blocked connector did not restore the original route";
		compass.bendOrigin = new Point(100, 30);
		compass.bendTime = 1000;
		var eased = compass.smoothBendOrigin(140, 30, 1025);
		if (eased.x <= 100 || eased.x >= 140 || !compass.bendMoving)
			throw "small movement snapped instead of easing";
		var jumped = compass.smoothBendOrigin(500, 30, 1050);
		if (jumped.x != 500 || compass.bendMoving)
			throw "large jump did not respond immediately";
		compass.destroy();
		var near = [for (i in 0...101) new Point(i * 10, 20)];
		var mask = [for (i in 0...100) true];
		var matched = RouteMotion.match(line, near, mask);
		if (matched == null || RouteMotion.frame(matched, near, mask, .5, grid) != null)
			throw "transition through a blocked corridor was accepted";
		grid.blocked = false;
		var frame = RouteMotion.frame(matched, near, mask, .5, grid);
		if (frame == null || frame[50].y != 10)
			throw "nearby route did not interpolate geometrically";
		near[50].y = 90;
		if (RouteMotion.match(line, near, mask) != null)
			throw "distant branch should switch directly";
		trace("PASS: local connector, collision fallback and persistent route mesh");
	}
}
