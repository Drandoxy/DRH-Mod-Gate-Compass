import mods.gate_compass.Main;
import mods.gate_compass.RouteRibbon;
import openfl.geom.Point;

/** Rendering and scheduling contracts behind the frame-time improvements (offline doubles). */
class PerformanceChecks {
	static function check(ok:Bool, message:String):Void {
		if (!ok)
			throw message;
	}

	static function main() {
		// Frame share: same work per second, smaller slices at high frame rates.
		var at160 = @:privateAccess Main.frameShare(6.25, 16);
		check(Math.abs(at160 - 6.25 / 16) < 1e-9, "160 FPS share wrong");
		check(Math.abs(at160 * 1.5 * (1000 / 6.25) - 1.5 * (1000 / 16)) < 1e-6, "160 FPS work per second changed");
		check(@:privateAccess Main.frameShare(33, 16) == 1, "slow frames must keep the full slice");
		check(@:privateAccess Main.frameShare(1, 16) == 0.15, "very fast frames keep a minimum slice");
		// Line layers: drawn from their own buffer, refilled only when the visible part changes.
		var points = [for (i in 0...40) new Point(i * 10, 0)];
		var batch = RouteRibbon.batch(points, 0xFFFFFF, 5, 0.9, true);
		check(batch.mesh.batchable == false, "route mesh is still copied into the shared batch every frame");
		var fills = batch.mesh.fills;
		var mask = [for (i in 0...39) i > 3 && i < 30];
		batch.show(mask);
		check(batch.mesh.fills == fills + 1, "visible change did not refill the route buffer once");
		batch.show(mask);
		check(batch.mesh.fills == fills + 1, "unchanged visibility refilled the route buffer");
		batch.destroy();
		trace("PASS: frame-time route slices and non-batchable route meshes");
	}
}
