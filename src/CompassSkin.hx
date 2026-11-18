package mods.gate_compass;

import mods.api.Context;
import brain.assetRepository.AssetLoadingComponent;
import brain.assetRepository.SwfAsset;
import facade.DBFacade;
import openfl.display.Sprite;
import openfl.display.MovieClip;
import openfl.display.DisplayObject;

/** Town board/button artwork only. Text and input remain owned by this mod. */
class CompassSkin {
	var facade:DBFacade;
	var hovers:Array<ButtonHover> = [];
	var loader:AssetLoadingComponent;
	var asset:SwfAsset;
	var pending:Array<Void->Void> = [];
	var dead = false;

	public function new(ctx:Context) {
		if (ctx.core == null || ctx.core.facade == null)
			return;
		facade = ctx.core.facade;
		loader = new AssetLoadingComponent(ctx.core.facade);
		loader.getSwfAsset(DBFacade.buildFullDownloadPath("Resources/Art2D/UI/db_UI_town.swf"), function(value:SwfAsset) {
			if (dead)
				return;
			asset = value;
			var work = pending;
			pending = [];
			for (paint in work)
				paint();
		});
	}

	function symbol(name:String):MovieClip {
		if (asset == null)
			return null;
		var type:Dynamic = asset.getClass(name);
		return type == null ? null : cast ASCompat.createInstance(type, []);
	}

	function schedule(paint:Void->Void):Void {
		if (asset != null)
			paint();
		else
			pending.push(paint);
	}

	static function fit(art:DisplayObject, w:Float, h:Float):Void {
		art.scaleX = art.scaleY = 1;
		var bounds = art.getBounds(art);
		if (bounds.width <= 0 || bounds.height <= 0)
			return;
		art.scaleX = w / bounds.width;
		art.scaleY = h / bounds.height;
		art.x = -bounds.x * art.scaleX;
		art.y = -bounds.y * art.scaleY;
	}

	public function board(parent:Sprite, w:Float, h:Float):Void {
		var back = new Sprite();
		back.mouseEnabled = false;
		back.mouseChildren = false;
		parent.addChildAt(back, 0);
		var g = back.graphics;
		g.lineStyle(6, 0x39352D);
		g.beginFill(0x783700);
		g.drawRoundRect(0, 0, w, h, 12, 12);
		g.endFill();
		g.lineStyle(3, 0xC7C7B3);
		g.drawRoundRect(3, 3, w - 6, h - 6, 9, 9);
		schedule(function() {
			var popup = symbol("popup");
			if (popup == null)
				return;
			var base = popup.getChildByName("popup_base");
			if (base == null)
				return;
			fit(base, w, h);
			back.graphics.clear();
			back.addChild(base);
		});
	}

	/** Same authored title ribbon as the Party Time town notifications. */
	public function banner(parent:Sprite, title:String, width:Float):Void {
		var ribbon = new Sprite();
		ribbon.mouseEnabled = false;
		ribbon.mouseChildren = false;
		parent.addChild(ribbon);
		var caption = new openfl.text.TextField();
		caption.defaultTextFormat = new openfl.text.TextFormat("_sans", 24, 0xFFD900, true);
		caption.width = width - 64;
		caption.height = 38;
		caption.x = 32;
		caption.y = -20;
		caption.text = title.toUpperCase();
		var format = caption.defaultTextFormat;
		format.align = openfl.text.TextFormatAlign.CENTER;
		caption.defaultTextFormat = format;
		caption.setTextFormat(format);
		caption.mouseEnabled = false;
		parent.addChild(caption);
		schedule(function() {
			var popup = symbol("popup");
			if (popup == null)
				return;
			var art = popup.getChildByName("banner_title_label");
			if (art != null) {
				fit(art, width - 56, 56);
				art.x += 28;
				art.y -= 28;
				ribbon.addChild(art);
			}
		});
	}

	static function hitArea(parent:Sprite, w:Float, h:Float):Void {
		// Artwork and captions deliberately do not receive mouse input. Keep
		// an independent parent hit shape before and after the async art load.
		parent.graphics.beginFill(0, 0);
		parent.graphics.drawRect(0, 0, w, h);
		parent.graphics.endFill();
		parent.mouseEnabled = true;
	}

	public function closeButton(parent:Sprite, size:Float):Void {
		hitArea(parent, size, size);
		hovers.push(new ButtonHover(parent, facade));
		var back = new Sprite();
		back.mouseEnabled = false;
		back.mouseChildren = false;
		parent.addChildAt(back, 0);
		var g = back.graphics;
		g.lineStyle(2, 0x211D15);
		g.beginFill(0x45433C);
		g.drawCircle(size / 2, size / 2, size / 2 - 2);
		g.endFill();
		g.lineStyle(5, 0xFFFFFF);
		g.moveTo(size * .34, size * .34);
		g.lineTo(size * .66, size * .66);
		g.moveTo(size * .66, size * .34);
		g.lineTo(size * .34, size * .66);
		schedule(function() {
			var popup = symbol("popup");
			if (popup == null)
				return;
			var cross = popup.getChildByName("close");
			if (cross == null)
				return;
			fit(cross, size, size);
			back.graphics.clear();
			back.addChild(cross);
		});
	}

	public function button(parent:Sprite, w:Float, h:Float):Void {
		hitArea(parent, w, h);
		hovers.push(new ButtonHover(parent, facade));
		var back = new Sprite();
		back.mouseEnabled = false;
		back.mouseChildren = false;
		parent.addChildAt(back, 0);
		var g = back.graphics;
		g.lineStyle(2, 0x142000);
		g.beginFill(0x169400);
		g.drawRoundRect(0, 0, w, h, 8, 8);
		g.endFill();
		schedule(function() {
			var clip = symbol("UI_prompt_button_extended");
			if (clip == null)
				return;
			var label = clip.getChildByName("label");
			if (label != null)
				label.visible = false;
			// Hide authored text under every known prompt label name; captions are
			// separate, unscaled TextFields so their proportions never stretch.
			for (i in 0...clip.numChildren) {
				var child = clip.getChildAt(i);
				if (Std.isOfType(child, openfl.text.TextField))
					child.visible = false;
			}
			fit(clip, w, h);
			back.graphics.clear();
			back.addChild(clip);
		});
	}

	public function destroy():Void {
		dead = true;
		for (hover in hovers)
			hover.destroy();
		hovers = [];
		pending = [];
		asset = null;
		if (loader != null)
			loader.destroy();
		loader = null;
	}
}
