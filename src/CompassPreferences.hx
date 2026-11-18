package mods.gate_compass;

class CompassPreferences {
	var path:String;
	var dirty = false;
	var values:Dynamic = {};

	public function new(data:String) {
		path = data + "/compass-appearance.json";
		try {
			values = haxe.Json.parse(sys.io.File.getContent(path));
			if (values == null)
				values = {};
		} catch (_:Dynamic) {
			// Read the API's previous options once. Never write its settings file.
			try {
				var old:Dynamic = haxe.Json.parse(sys.io.File.getContent(data + "/settings.json"));
				if (old.options != null)
					values = old.options;
			} catch (_:Dynamic) {}
		}
	}

	public function flag(key:String, fallback:Bool):CompassOption<Bool> {
		var raw:Dynamic = Reflect.field(values, key);
		var initial = raw == true ? true : (raw == false ? false : fallback);
		var option:CompassOption<Bool> = null;
		option = new CompassOption(initial, function() {
			Reflect.setField(values, key, option.value);
			dirty = true;
		});
		return option;
	}

	public function slider(key:String, fallback:Float, min:Float, max:Float):CompassOption<Float> {
		var raw = Std.parseFloat(Std.string(Reflect.field(values, key)));
		var initial = Math.isNaN(raw) ? fallback : Math.max(min, Math.min(max, raw));
		var option:CompassOption<Float> = null;
		option = new CompassOption(initial, function() {
			Reflect.setField(values, key, option.value);
			dirty = true;
		});
		return option;
	}

	public function flush():Void {
		if (!dirty)
			return;
		try {
			sys.io.File.saveContent(path, haxe.Json.stringify(values, null, "  "));
			dirty = false;
		} catch (_:Dynamic) {}
	}
}
