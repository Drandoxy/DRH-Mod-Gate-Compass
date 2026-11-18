package mods.gate_compass;

import mods.api.Context;
import openfl.display.Sprite;
import openfl.events.MouseEvent;
import openfl.text.TextField;
import openfl.text.TextFormat;

class CapacityHud extends Sprite {
	var label:TextField;
	var cancel:Sprite;
	var callback:Void->Void;

	public function new(ctx:Context, onCancel:Void->Void) {
		super();
		callback = onCancel;
		addEventListener(MouseEvent.MOUSE_DOWN, block);
		x = Math.max(0, (ctx.viewWidth - 410) / 2);
		y = 90;
		graphics.lineStyle(1, 0x90B985);
		graphics.beginFill(0x17271D, .97);
		graphics.drawRoundRect(0, 0, 410, 46, 10, 10);
		graphics.endFill();
		label = new TextField();
		label.defaultTextFormat = new TextFormat("_sans", 14, 0xFFE482, true);
		label.width = 326;
		label.height = 28;
		label.x = 12;
		label.y = 10;
		label.selectable = false;
		addChild(label);
		cancel = new Sprite();
		cancel.x = 334;
		cancel.y = 8;
		cancel.graphics.beginFill(0x236D2B);
		cancel.graphics.drawRoundRect(0, 0, 66, 30, 6, 6);
		cancel.graphics.endFill();
		cancel.buttonMode = true;
		var f = new TextField();
		f.defaultTextFormat = new TextFormat("_sans", 12, 0xFFFFFF, true);
		f.text = "Cancel";
		f.x = 10;
		f.y = 5;
		f.width = 56;
		f.height = 24;
		f.mouseEnabled = false;
		cancel.addChild(f);
		cancel.addEventListener(MouseEvent.CLICK, clicked);
		addChild(cancel);
	}

	function block(e:MouseEvent):Void {
		e.stopPropagation();
	}

	function clicked(e:MouseEvent):Void {
		e.stopPropagation();
		if (callback != null)
			callback();
	}

	public function show(value:String):Void {
		if (label.text != value)
			label.text = value;
	}

	public function destroy():Void {
		callback = null;
		removeEventListener(MouseEvent.MOUSE_DOWN, block);
		cancel.removeEventListener(MouseEvent.CLICK, clicked);
		if (parent != null)
			parent.removeChild(this);
	}
}
