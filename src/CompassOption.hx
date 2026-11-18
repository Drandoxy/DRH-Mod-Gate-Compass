package mods.gate_compass;

/** Local panel preferences do not register duplicate rows in MODS. */
class CompassOption<T> {
	public var value(default, set):T;

	var listeners:Array<T->Void> = [];
	var save:Void->Void;

	public function new(value:T, save:Void->Void) {
		this.value = value;
		this.save = save;
	}

	function set_value(next:T):T {
		if (value == next)
			return value;
		value = next;
		if (save != null)
			save();
		for (listener in listeners.copy())
			listener(next);
		return value;
	}

	public function onChange(listener:T->Void):Dynamic {
		listeners.push(listener);
		return {
			cancel: function() {
				listeners.remove(listener);
			}
		};
	}
}
