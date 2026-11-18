package mods.gate_compass;

import openfl.geom.Point;
import mods.api.dungeon.Tile;

class RoutePlan {
	public var cell:Int;
	public var room:Tile;
	public var job:RoutePlanJob;
	public var line:Array<Point>;
	public var used = 0;
	public var ms = 0.;
	public var failed = false;

	public function new(cell:Int, room:Tile) {
		this.cell = cell;
		this.room = room;
	}
}
