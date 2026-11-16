package mods.gate_compass;
class CompassControl {
    public var label:String;public var option:mods.api.settings.Slider;public var minimum:Float;public var maximum:Float;
    public function new(label:String,option:mods.api.settings.Slider,minimum:Float,maximum:Float){this.label=label;this.option=option;this.minimum=minimum;this.maximum=maximum;}
}
