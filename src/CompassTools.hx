package mods.gate_compass;

import mods.api.Context;
import openfl.display.Sprite;
import openfl.events.MouseEvent;
import openfl.text.TextField;
import openfl.text.TextFormat;
import openfl.geom.Point;

class CompassTools extends Sprite {
	var switches:Array<Sprite> = [];
	var flags:Array<CompassOption<Bool>> = [];
	var popupHeight = 365.;
	var ctx:Context;

	public var onMeasure:Void->Void;

	var measurementStatus:TextField;
	var commit:Void->Void;
	var controls:Array<CompassControl>;
	var popup = new Sprite();
	var tracks:Array<Sprite> = [];
	var labels:Array<TextField> = [];
	var active = -1;
	var moving = false;
	var offset = new Point();
	var layoutReady = false;
	var closeButton = new Sprite();

	var popupGrip = new Sprite();
	var layoutKind = 0;
	var origin = new Point();
	var initialScale = 1.;

	public function new(ctx:Context, controls:Array<CompassControl>, ?flags:Array<CompassOption<Bool>>, ?commit:Void->Void) {
		super();
		this.ctx = ctx;
		this.commit = commit;
		this.controls = controls;
		if (flags != null)
			this.flags = flags;
		var settingsEnd = 54 + this.flags.length * 30 + controls.length * 42;
		popupHeight = settingsEnd + 136;
		grip(popupGrip, popup, 304, popupHeight - 16);
		popup.graphics.beginFill(0x17271D, .98);
		popup.graphics.lineStyle(2, 0x69865A);
		popup.graphics.drawRoundRect(0, 0, 320, popupHeight, 18, 18);
		popup.graphics.endFill();
		var header = new Sprite();
		header.graphics.beginFill(0, 0);
		header.graphics.drawRect(0, 0, 278, 48);
		header.graphics.endFill();
		var title = label("Compass settings", 17);
		title.x = 20;
		title.y = 14;
		title.mouseEnabled = false;
		header.addChild(title);
		header.buttonMode = true;
		header.addEventListener(MouseEvent.MOUSE_DOWN, drag);
		popup.addChild(header);
		closeButton.graphics.beginFill(0x314D37);
		closeButton.graphics.drawRoundRect(0, 0, 28, 28, 8, 8);
		closeButton.graphics.endFill();
		closeButton.graphics.lineStyle(2, 0xFFFFFF);
		closeButton.graphics.moveTo(8, 8);
		closeButton.graphics.lineTo(20, 20);
		closeButton.graphics.moveTo(20, 8);
		closeButton.graphics.lineTo(8, 20);
		closeButton.x = 276;
		closeButton.y = 12;
		closeButton.buttonMode = true;
		closeButton.addEventListener(MouseEvent.CLICK, close);
		popup.addChild(closeButton);
		var reset = new Sprite();
		reset.graphics.beginFill(0x236D2B);
		reset.graphics.drawRoundRect(0, 0, 104, 30, 10, 10);
		reset.graphics.endFill();
		var caption = label("Reset", 14);
		caption.width = 104;
		caption.height = 24;
		caption.x = 0;
		caption.y = 6;
		caption.autoSize = openfl.text.TextFieldAutoSize.NONE;
		var resetFormat = new TextFormat("_sans", 14, 0xFFFFFF, true);
		resetFormat.align = openfl.text.TextFormatAlign.CENTER;
		caption.setTextFormat(resetFormat);
		caption.mouseEnabled = false;
		reset.addChild(caption);
		reset.x = 20;
		reset.y = settingsEnd + 26;
		reset.buttonMode = true;
		reset.addEventListener(MouseEvent.CLICK, resetDefaults);
		popup.addChild(reset);
		var names = [
			"Enable 2D Compass",
			"Enable 3D Compass",
			"Enable Pathfinder line",
			"Smooth Compass",
			"Reduced Effects",
			"Low power mode"
		];
		for (i in 0...this.flags.length) {
			var row = new Sprite();
			var name = label(names[i], 14);
			name.mouseEnabled = false;
			row.addChild(name);
			var toggle = new Sprite();
			toggle.x = 236;
			toggle.y = 0;
			row.addChild(toggle);
			switches.push(toggle);
			row.x = 20;
			row.y = 54 + i * 30;
			row.buttonMode = true;
			row.addEventListener(MouseEvent.CLICK, function(e) {
				e.stopPropagation();
				this.flags[i].value = !this.flags[i].value;
				if (commit != null)
					commit();
				refresh();
			});
			popup.addChild(row);
		}
		for (i in 0...controls.length) {
			var text = label("", 14);
			text.x = 20;
			text.y = 54 + this.flags.length * 30 + i * 42;
			labels.push(text);
			popup.addChild(text);
			var track = new Sprite();
			track.x = 20;
			track.y = 80 + this.flags.length * 30 + i * 42;
			track.buttonMode = true;
			tracks.push(track);
			popup.addChild(track);
			track.addEventListener(MouseEvent.MOUSE_DOWN, function(e) {
				e.stopPropagation();
				active = tracks.indexOf(cast e.currentTarget);
				listen();
				slide(e);
			});
		}
		var hint = label("Lagging? Reduce routes per tile.", 12);
		hint.x = 20;
		hint.y = settingsEnd;
		hint.width = 280;
		popup.addChild(hint);
		var measure = new Sprite();
		measure.graphics.beginFill(0x236D2B);
		measure.graphics.drawRoundRect(0, 0, 164, 30, 10, 10);
		measure.graphics.endFill();
		var measureLabel = label("Test capacity", 13);
		measureLabel.x = 14;
		measureLabel.y = 5;
		measureLabel.width = 150;
		measureLabel.mouseEnabled = false;
		measure.addChild(measureLabel);
		measure.x = 136;
		measure.y = settingsEnd + 26;
		measure.buttonMode = true;
		measure.addEventListener(MouseEvent.CLICK, function(e) {
			e.stopPropagation();
			if (onMeasure != null)
				onMeasure();
		});
		popup.addChild(measure);
		measurementStatus = label("8-second capacity test. Stand safely still.", 12);
		measurementStatus.x = 20;
		measurementStatus.y = settingsEnd + 64;
		measurementStatus.width = 280;
		measurementStatus.height = 64;
		measurementStatus.wordWrap = true;
		popup.addChild(measurementStatus);

		popup.setChildIndex(popupGrip, popup.numChildren - 1);
		popup.addEventListener(MouseEvent.MOUSE_DOWN, block);
		popup.x = 44;
		popup.visible = true;
		addChild(popup);
		refresh();
		defaultLayout();
	}

	public function setMeasurementStatus(value:String):Void {
		if (measurementStatus != null && measurementStatus.text != value)
			measurementStatus.text = value;
	}

	function label(text:String, size:Int):TextField {
		var t = new TextField();
		t.defaultTextFormat = new TextFormat("_sans", size, 0xF2F8EF, true);
		t.width = 300;
		t.height = 27;
		t.selectable = false;
		t.text = text;
		return t;
	}

	function block(e:MouseEvent):Void {
		e.stopPropagation();
	}

	function close(e:MouseEvent):Void {
		e.stopPropagation();
		setShown(false);
		save();
	}

	function defaultLayout():Void {
		x = 0;
		y = 0;
		popup.scaleX = popup.scaleY = Math.min(1, Math.max(.5, (ctx.viewHeight - 24) / popupHeight));
		popup.x = Math.max(0, (ctx.viewWidth - 320) / 2);
		popup.y = Math.max(0, (ctx.viewHeight - popupHeight) / 2);
		clampPopup();
	}

	function resetDefaults(e:MouseEvent):Void {
		e.stopPropagation();
		for (c in controls)
			c.option.value = c.defaultValue;
		for (i in 0...flags.length)
			flags[i].value = i > 0 && i < 4;
		defaultLayout();
		refresh();
		save();
	}

	function grip(handle:Sprite, parent:Sprite, hx:Float, hy:Float):Void {
		handle.graphics.beginFill(0x90B985, 1);
		handle.graphics.drawRect(0, 0, 16, 16);
		handle.graphics.endFill();
		var marks = new Sprite();
		marks.mouseEnabled = false;
		marks.visible = false;
		handle.addChild(marks);
		handle.graphics.beginFill(0, 0);
		handle.graphics.drawRect(0, 0, 16, 16);
		handle.graphics.endFill();
		marks.graphics.lineStyle(1, 0xFFFFFF);
		marks.graphics.moveTo(3, 12);
		marks.graphics.lineTo(12, 3);
		marks.graphics.moveTo(8, 12);
		marks.graphics.lineTo(12, 8);
		handle.addEventListener(MouseEvent.ROLL_OVER, function(e) {
			marks.visible = true;
		});
		handle.addEventListener(MouseEvent.ROLL_OUT, function(e) {
			marks.visible = false;
		});
		handle.alpha = 1;
		handle.graphics.clear();
		handle.graphics.beginFill(0, 0);
		handle.graphics.drawRect(0, 0, 16, 16);
		handle.graphics.endFill();
		handle.x = hx;
		handle.y = hy;
		handle.buttonMode = true;
		parent.addChild(handle);
		handle.addEventListener(MouseEvent.MOUSE_DOWN, resize);
	}

	function resize(e:MouseEvent):Void {
		e.stopPropagation();
		layoutKind = 3;
		origin.x = e.stageX;
		origin.y = e.stageY;
		initialScale = popup.scaleX;
		listen();
	}

	function anchorPopup():Void {
		// Keep resized controls inside the current viewport.
		clampPopup();
	}

	function clampPopup():Void {
		var fit = Math.min(2, Math.min((ctx.viewWidth - 16) / 320, (ctx.viewHeight - 16) / popupHeight));
		if (fit > 0 && popup.scaleX > fit)
			popup.scaleX = popup.scaleY = fit;
		popup.x = Math.max(-x, Math.min(ctx.viewWidth - x - 320 * popup.scaleX, popup.x));
		popup.y = Math.max(-y, Math.min(ctx.viewHeight - y - popupHeight * popup.scaleY, popup.y));
	}

	function drag(e:MouseEvent):Void {
		e.stopPropagation();
		moving = true;
		var at = globalToLocal(new Point(e.stageX, e.stageY));
		offset.x = at.x - popup.x;
		offset.y = at.y - popup.y;
		listen();
	}

	function listen():Void {
		if (stage != null) {
			stage.addEventListener(MouseEvent.MOUSE_MOVE, slide);
			stage.addEventListener(MouseEvent.MOUSE_UP, finish);
		}
	}

	function slide(e:MouseEvent):Void {
		if (layoutKind == 3) {
			var value = Math.max(.65, Math.min(2, initialScale + (e.stageX - origin.x + e.stageY - origin.y) / 645));
			popup.scaleX = popup.scaleY = value;
			anchorPopup();
		}
		if (moving) {
			var at = globalToLocal(new Point(e.stageX, e.stageY));
			popup.x = Math.max(-x, Math.min(ctx.viewWidth - x - 320 * popup.scaleX, at.x - offset.x));
			popup.y = Math.max(-y, Math.min(ctx.viewHeight - y - popupHeight * popup.scaleY, at.y - offset.y));
		}
		if (active >= 0) {
			var p = tracks[active].globalToLocal(new Point(e.stageX, e.stageY));
			var c = controls[active];
			var value = c.minimum + Math.max(0, Math.min(1, p.x / 280)) * (c.maximum - c.minimum);
			c.option.value = Math.max(c.minimum, Math.min(c.maximum, Math.round(value / c.step) * c.step));
			refresh();
		}
	}

	function finish(e:MouseEvent):Void {
		active = -1;
		moving = false;
		layoutKind = 0;
		if (stage != null) {
			stage.removeEventListener(MouseEvent.MOUSE_MOVE, slide);
			stage.removeEventListener(MouseEvent.MOUSE_UP, finish);
		}
		save();
	}

	function refresh():Void {
		for (i in 0...switches.length) {
			var g = switches[i].graphics;
			g.clear();
			g.beginFill(flags[i].value ? 0x43B750 : 0x526159);
			g.drawRoundRect(0, 0, 44, 22, 22, 22);
			g.endFill();
			g.beginFill(0xFFFFFF);
			g.drawCircle(flags[i].value ? 33 : 11, 11, 8);
			g.endFill();
		}
		for (i in 0...controls.length) {
			var c = controls[i];
			labels[i].text = c.label + ": " + Math.round(c.option.value * 100) / 100;
			var g = tracks[i].graphics;
			g.clear();
			g.beginFill(0, 0);
			g.drawRect(-6, -12, 292, 24);
			g.endFill();
			g.lineStyle(6, 0x405347);
			g.moveTo(0, 0);
			g.lineTo(280, 0);
			var at = (c.option.value - c.minimum) / (c.maximum - c.minimum) * 280;
			g.lineStyle(6, 0x72CE65);
			g.moveTo(0, 0);
			g.lineTo(at, 0);
			g.beginFill(0xFFFFFF);
			g.drawCircle(at, 0, 8);
			g.endFill();
		}
	}

	public function setShown(value:Bool):Void {
		if (value && !layoutReady && ctx.viewWidth > 0 && ctx.viewHeight > 0) {
			defaultLayout();
			load();
			layoutReady = true;
		}
		if (!value && visible)
			finish(null);
		popup.visible = true;
		visible = value;
		refresh();
	}

	function load():Void {
		try {
			var p:Dynamic = haxe.Json.parse(sys.io.File.getContent(ctx.data + "/compass-tools.json"));
			if (p.layoutVersion == 5) {
				popup.x = p.x;
				popup.y = p.y;
			} else if (p.layoutVersion == 3 || p.layoutVersion == 4) {
				popup.x = p.buttonX + p.x;
				popup.y = p.buttonY + p.y;
			}
			if (p.popupScale != null)
				popup.scaleX = popup.scaleY = Math.max(.65, Math.min(2, p.popupScale));
			clampPopup();
		} catch (_:Dynamic) {}
	}

	function save():Void {
		if (commit != null)
			commit();
		if (!layoutReady || ctx.viewWidth <= 0 || ctx.viewHeight <= 0)
			return;
		try {
			sys.io.File.saveContent(ctx.data + "/compass-tools.json", haxe.Json.stringify({
				layoutVersion: 5,
				x: popup.x,
				y: popup.y,
				popupScale: popup.scaleX
			}));
		} catch (_:Dynamic) {}
	}

	public function destroy():Void {
		onMeasure = null;
		finish(null);
		popup.removeEventListener(MouseEvent.MOUSE_DOWN, block);
		if (parent != null)
			parent.removeChild(this);
	}
}
