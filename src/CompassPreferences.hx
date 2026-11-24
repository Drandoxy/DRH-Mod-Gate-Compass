package mods.gate_compass;

class CompassPreferences {
	var path:String;
	var dirty = false;
	var values:Dynamic = {};
	var log:String->Void;

	public function new(data:String, ?log:String->Void) {
		this.log = log;
		path = data + "/compass-appearance.json";
		if (sys.FileSystem.exists(path)) {
			try {
				values = haxe.Json.parse(sys.io.File.getContent(path));
				if (values == null)
					values = {};
				return;
			} catch (error:Dynamic) {
				values = {};
				report("Could not read compass-appearance.json: " + Std.string(error));
			}
		}
		// Read the API's previous options once. Never write its settings file.
		var oldPath = data + "/settings.json";
		if (!sys.FileSystem.exists(oldPath))
			return;
		try {
			var old:Dynamic = haxe.Json.parse(sys.io.File.getContent(oldPath));
			if (old != null && old.options != null)
				values = old.options;
		} catch (error:Dynamic) {
			report("Could not read the previous settings.json: " + Std.string(error));
		}
	}

	function report(message:String):Void {
		if (log != null)
			log(message);
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
		} catch (error:Dynamic) {
			report("Could not save compass-appearance.json: " + Std.string(error));
		}
	}
}
