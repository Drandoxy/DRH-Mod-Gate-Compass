package mods.gate_compass;

class CompassControl {
	public var label:String;
	public var option:CompassOption<Float>;
	public var minimum:Float;
	public var maximum:Float;
	public var defaultValue:Float;
	public var step:Float;

	public function new(label:String, option:CompassOption<Float>, minimum:Float, maximum:Float, defaultValue:Float = 1, step:Float = 0.01) {
		this.label = label;
		this.option = option;
		this.minimum = minimum;
		this.maximum = maximum;
		this.defaultValue = defaultValue;
		this.step = step;
	}
}
