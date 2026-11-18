package mods.gate_compass;

/** The artwork contains cyan (green max/red min) and neutral white only. */
class PaletteTransform {
	public static function matrix(color:Int):Array<Float> {
		var r = (((color >> 16) & 255) - 136) / 119.;
		var g = (((color >> 8) & 255) - 233) / 119.;
		var b = ((color & 255) - 231) / 119.;
		return [1 - r, r, 0, 0, 0, -g, 1 + g, 0, 0, 0, -b, b, 1, 0, 0, 0, 0, 0, 1, 0];
	}
}
