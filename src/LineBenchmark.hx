package mods.gate_compass;

import openfl.geom.Point;

/** Temporary native ribbons using the normal line renderer and current styling. */
class LineBenchmark extends starling.display.Sprite {
	public var trial:DrawingTrial;
	public var count(default, null) = 0;

	var batches:Array<RouteBatch> = [];
	var strokeScale:Float;
	var length:Float;
	var reduced:Bool;

	public function new(started:Float, width:Float, length:Float, reduced:Bool) {
		super();
		touchable = false;
		trial = new DrawingTrial(started);
		this.strokeScale = width;
		this.length = length;
		this.reduced = reduced;
	}

	public function tick(now:Float, frameMs:Float):Void {
		if (trial.done)
			return;
		var building = count < trial.target(now);
		if (building) {
			addLine(count);
			count++;
		}
		trial.sample(now, frameMs, count, building);
	}

	function addLine(index:Int):Void {
		var points:Array<Point> = [];
		var segments = Std.int(Math.max(24, Math.ceil(length / (reduced ? 20 : 10))));
		var radius = Math.min(450, Math.max(140, length / 5));
		for (i in 0...segments + 1) {
			var angle = i / segments * Math.PI * 1.55 + index * 2.399963;
			var r = radius * (.88 + .12 * Math.sin(angle * 3 + index));
			points.push(new Point(Math.cos(angle) * r, Math.sin(angle) * r * .72));
		}
		var mask = [for (i in 0...segments) true];
		for (layer in (reduced ? 1 : 0)...2) {
			var batch = RouteRibbon.batch(points, layer == 0 ? 0x9564C7 : 0xE9D2FE, (layer == 0 ? 11.52 : 5.4) * strokeScale, layer == 0 ? 0.4032 : 0.95,
				!reduced);
			batch.show(mask);
			addChild(batch.mesh);
			batches.push(batch);
		}
	}

	public function destroy():Void {
		for (batch in batches)
			batch.destroy();
		batches = [];
		removeFromParent();
		dispose();
	}
}
