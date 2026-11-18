package mods.gate_compass;

import mods.api.dungeon.Tile;
import openfl.geom.Point;

class RouteField {
	public var goal:Tile;
	public var gate:Point;
	public var gateId:UInt;
	public var key:String;
	public var scores:Array<Float>;
	public var next:Array<Int>;
	public var settled:Array<Bool>;
	public var heap:Array<RouteNode> = [];
	public var scan = 0;
	public var seed = -1;
	public var seeds:Array<Int> = [];
	public var distance = Math.POSITIVE_INFINITY;
	public var phase = 0;

	public function new(goal:Tile, gate:Point, gateId:UInt, key:String, count:Int) {
		this.goal = goal;
		this.gate = gate;
		this.gateId = gateId;
		this.key = key;
		scores = [for (i in 0...count) Math.POSITIVE_INFINITY];
		next = [for (i in 0...count) -1];
		settled = [for (i in 0...count) false];
	}
}
