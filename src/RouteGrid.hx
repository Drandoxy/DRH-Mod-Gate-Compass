package mods.gate_compass;

import mods.api.dungeon.Tile;
import openfl.geom.Point;

/** Immutable geometry arrays shared by route jobs; edge answers may fill in. */
class RouteGrid {
	public var complete = false;
	public var checkEdge:Int->Int->Bool;
	public var waiting = false;
	public var cells:Array<Bool>;
	public var hazards:Array<Bool>;
	public var rooms:Array<Tile>;
	public var near:Array<Bool>;
	public var edges:Map<Int, Bool>;
	public var width:Int;
	public var height:Int;
	public var left:Float;
	public var top:Float;
	public var spacing:Float;

	public function new(cells:Array<Bool>, hazards:Array<Bool>, rooms:Array<Tile>, near:Array<Bool>, edges:Map<Int, Bool>, width:Int, height:Int, left:Float,
			top:Float, spacing:Float) {
		this.cells = cells;
		this.hazards = hazards;
		this.rooms = rooms;
		this.near = near;
		this.edges = edges;
		this.width = width;
		this.height = height;
		this.left = left;
		this.top = top;
		this.spacing = spacing;
	}

	public function cellAt(x:Float, y:Float):Int {
		var col = Std.int(Math.floor((x - left) / spacing));
		var row = Std.int(Math.floor((y - top) / spacing));
		return col < 0 || row < 0 || col >= width || row >= height ? -1 : row * width + col;
	}

	public function point(cell:Int):Point {
		return new Point(left + (cell % width + 0.5) * spacing, top + (Std.int(cell / width) + 0.5) * spacing);
	}

	public function walkable(cell:Int):Bool {
		return cell >= 0 && cell < cells.length && cells[cell];
	}

	public function cross(a:Int, b:Int):Bool {
		if (!walkable(a) || !walkable(b) || Math.abs(a % width - b % width) + Math.abs(Std.int(a / width) - Std.int(b / width)) != 1)
			return false;
		var ar:Tile = rooms[a];
		var br:Tile = rooms[b];
		if (ar == null || br == null)
			return false;
		if (ar == br && !near[a] && !near[b])
			return true;
		var key = Std.int(Math.min(a, b)) * 2 + (Math.abs(a - b) == 1 ? 0 : 1);
		var answer = edges.get(key);
		if (answer == null && checkEdge != null) {
			answer = checkEdge(a, b);
			edges.set(key, answer);
		}
		if (answer == null && !complete)
			waiting = true;
		return answer == true;
	}
}
