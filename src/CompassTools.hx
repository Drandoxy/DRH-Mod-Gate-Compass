package mods.gate_compass;

import mods.api.Context;
import openfl.display.Sprite;
import openfl.events.MouseEvent;
import openfl.text.TextField;
import openfl.text.TextFormat;
import openfl.geom.Point;

class CompassTools extends Sprite {
	static inline final PANEL_WIDTH = 460.;
	static inline final PADDING = 24.;
	static inline final TRACK_WIDTH = PANEL_WIDTH - PADDING * 2;
	static inline final SLIDER_WIDTH = TRACK_WIDTH - 16;
	static inline final BUTTON_WIDTH = (TRACK_WIDTH - 16) / 2;
	static inline final BUTTON_HEIGHT = 38.;

	var skin:CompassSkin;
	var popupHeight = 365.;
	var ctx:Context;

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

	public function new(ctx:Context, controls:Array<CompassControl>, ?commit:Void->Void) {
		super();
		this.ctx = ctx;
		skin = new CompassSkin(ctx);
		this.commit = commit;
		this.controls = controls;
		var settingsEnd = 70 + controls.length * 46;
		popupHeight = settingsEnd + 82;
		grip(popupGrip, popup, PANEL_WIDTH - 16, popupHeight - 16);
		skin.board(popup, PANEL_WIDTH, popupHeight);
		var header = new Sprite();
		header.graphics.beginFill(0, 0);
		header.graphics.drawRect(0, 0, PANEL_WIDTH - 70, 48);
		header.graphics.endFill();
		skin.banner(header, "Adjust appearance", PANEL_WIDTH);
		header.buttonMode = true;
		header.addEventListener(MouseEvent.MOUSE_DOWN, drag);
		popup.addChild(header);
		skin.closeButton(closeButton, 38);
		closeButton.x = PANEL_WIDTH - 6 - 19;
		closeButton.y = 8 - 19;
		closeButton.addEventListener(MouseEvent.CLICK, close);
		popup.addChild(closeButton);
		var reset = new Sprite();
		reset.name = "reset";
		skin.button(reset, BUTTON_WIDTH, BUTTON_HEIGHT);
		buttonCaption(reset, "Reset");
		reset.x = PADDING;
		reset.y = settingsEnd + 20;
		reset.buttonMode = true;
		reset.addEventListener(MouseEvent.CLICK, resetDefaults);
		popup.addChild(reset);
		for (i in 0...controls.length) {
			var text = label("", 14);
			text.x = PADDING;
			text.y = 70 + i * 46;
			labels.push(text);
			popup.addChild(text);
			var track = new Sprite();
			track.x = PADDING + 8;
			track.y = 102 + i * 46;
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

		popup.setChildIndex(popupGrip, popup.numChildren - 1);
		popup.addEventListener(MouseEvent.MOUSE_DOWN, block);
		popup.x = 44;
		popup.visible = true;
		addChild(popup);
		refresh();
		defaultLayout();
	}

	function buttonCaption(parent:Sprite, text:String, w:Float = BUTTON_WIDTH, h:Float = BUTTON_HEIGHT, size:Int = 15):TextField {
		var caption = label(text.toUpperCase(), size);
		caption.width = w;
		caption.height = h;
		caption.autoSize = openfl.text.TextFieldAutoSize.NONE;
		var format = new TextFormat("_sans", size, 0xFFFFFF, true);
		format.align = openfl.text.TextFormatAlign.CENTER;
		caption.defaultTextFormat = format;
		caption.setTextFormat(format);
		caption.y = (h - caption.textHeight) / 2 - 2;
		skin.textStyle(caption, size, 0xFFFFFF, true, true, function() {
			caption.y = (h - caption.textHeight) / 2 - 2;
		});
		caption.mouseEnabled = false;
		parent.addChild(caption);
		return caption;
	}

	function label(text:String, size:Int):TextField {
		var t = new TextField();
		t.defaultTextFormat = new TextFormat("_sans", size, 0xF2F8EF, true);
		t.width = TRACK_WIDTH;
		t.height = 27;
		t.selectable = false;
		t.text = text;
		skin.textStyle(t, size, 0xF2F8EF);
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
		popup.x = Math.max(8, ctx.viewWidth - PANEL_WIDTH * popup.scaleX - 24);
		popup.y = Math.max(0, (ctx.viewHeight - popupHeight) / 2);
		clampPopup();
	}

	function resetDefaults(e:MouseEvent):Void {
		e.stopPropagation();
		for (c in controls)
			c.option.value = c.defaultValue;
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
		var fit = Math.min(2, Math.min((ctx.viewWidth - 16) / PANEL_WIDTH, (ctx.viewHeight - 16) / popupHeight));
		if (fit > 0 && popup.scaleX > fit)
			popup.scaleX = popup.scaleY = fit;
		popup.x = Math.max(-x, Math.min(ctx.viewWidth - x - PANEL_WIDTH * popup.scaleX, popup.x));
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
			popup.x = Math.max(-x, Math.min(ctx.viewWidth - x - PANEL_WIDTH * popup.scaleX, at.x - offset.x));
			popup.y = Math.max(-y, Math.min(ctx.viewHeight - y - popupHeight * popup.scaleY, at.y - offset.y));
		}
		if (active >= 0) {
			var p = tracks[active].globalToLocal(new Point(e.stageX, e.stageY));
			var c = controls[active];
			var value = c.minimum + Math.max(0, Math.min(1, p.x / SLIDER_WIDTH)) * (c.maximum - c.minimum);
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
		for (i in 0...controls.length) {
			var c = controls[i];
			labels[i].text = c.label + ": " + Math.round(c.option.value * 100) / 100;
			var g = tracks[i].graphics;
			g.clear();
			g.beginFill(0, 0);
			g.drawRect(-6, -12, SLIDER_WIDTH + 12, 24);
			g.endFill();
			g.lineStyle(6, 0x3C210D);
			g.moveTo(0, 0);
			g.lineTo(SLIDER_WIDTH, 0);
			var at = (c.option.value - c.minimum) / (c.maximum - c.minimum) * SLIDER_WIDTH;
			g.lineStyle(6, 0xFFCE54);
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
		var layoutFile = ctx.data + "/compass-tools.json";
		if (!sys.FileSystem.exists(layoutFile))
			return;
		try {
			var p:Dynamic = haxe.Json.parse(sys.io.File.getContent(layoutFile));
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
		} catch (error:Dynamic) {
			ctx.log("Could not read the appearance panel position: " + Std.string(error));
		}
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
		} catch (error:Dynamic) {
			ctx.log("Could not save the appearance panel position: " + Std.string(error));
		}
	}

	public function destroy():Void {
		skin.destroy();
		finish(null);
		popup.removeEventListener(MouseEvent.MOUSE_DOWN, block);
		if (parent != null)
			parent.removeChild(this);
	}
}
