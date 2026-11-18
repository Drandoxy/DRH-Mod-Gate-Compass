package mods.gate_compass;

import mods.api.Context;
import openfl.display.Sprite;
import openfl.display.DisplayObjectContainer;
import openfl.events.MouseEvent;
import openfl.events.KeyboardEvent;
import openfl.text.TextField;
import openfl.text.TextFormat;

/** Small mod-owned modal, with no global navigation callback replacement. */
class CapacityDialog extends Sprite {
	var yes:Sprite;
	var no:Sprite;
	var onYes:Void->Void;
	var onNo:Void->Void;
	var keyboard:DisplayObjectContainer;
	var choice = -1;
	var closed = false;

	public function new(ctx:Context, title:String, message:String, onYes:Void->Void, onNo:Void->Void) {
		super();
		this.onYes = onYes;
		this.onNo = onNo;
		graphics.beginFill(0, .6);
		graphics.drawRect(0, 0, ctx.viewWidth, ctx.viewHeight);
		graphics.endFill();
		addEventListener(MouseEvent.MOUSE_DOWN, block);
		addEventListener(MouseEvent.CLICK, block);
		var board = new Sprite();
		board.graphics.lineStyle(2, 0x90B985);
		board.graphics.beginFill(0x17271D, .99);
		board.graphics.drawRoundRect(0, 0, 540, 350, 18, 18);
		board.graphics.endFill();
		var scale = Math.min(1, Math.min((ctx.viewWidth - 24) / 540, (ctx.viewHeight - 24) / 350));
		board.scaleX = board.scaleY = Math.max(.5, scale);
		board.x = (ctx.viewWidth - 540 * board.scaleX) / 2;
		board.y = (ctx.viewHeight - 350 * board.scaleY) / 2;
		addChild(board);
		text(board, title, 24, 18, 492, 36, 21, 0xFFE482);
		text(board, message, 24, 67, 492, 208, 15, 0xF2F8EF);
		no = button(onYes == null ? "Close" : "No", function() {
			finish(false);
		});
		no.x = onYes == null ? 190 : 72;
		no.y = 290;
		board.addChild(no);
		if (onYes != null) {
			yes = button("Yes", function() {
				finish(true);
			});
			yes.x = 308;
			yes.y = 290;
			board.addChild(yes);
		}
		keyboard = ctx.overlay.stage;
		if (keyboard != null)
			keyboard.addEventListener(KeyboardEvent.KEY_DOWN, key, true);
	}

	function text(parent:Sprite, value:String, x:Float, y:Float, w:Float, h:Float, size:Int, color:Int):Void {
		var f = new TextField();
		f.defaultTextFormat = new TextFormat("_sans", size, color, true);
		f.x = x;
		f.y = y;
		f.width = w;
		f.height = h;
		f.wordWrap = true;
		f.selectable = false;
		f.mouseEnabled = false;
		f.text = value;
		parent.addChild(f);
	}

	function button(label:String, callback:Void->Void):Sprite {
		var s = new Sprite();
		s.graphics.lineStyle(1, 0x90B985);
		s.graphics.beginFill(0x236D2B);
		s.graphics.drawRoundRect(0, 0, 160, 38, 8, 8);
		s.graphics.endFill();
		text(s, label, 12, 6, 136, 27, 16, 0xFFFFFF);
		s.buttonMode = true;
		s.addEventListener(MouseEvent.CLICK, function(e) {
			e.stopPropagation();
			callback();
		});
		return s;
	}

	function block(e:MouseEvent):Void {
		e.stopPropagation();
	}

	function key(e:KeyboardEvent):Void {
		if (e.keyCode == 27) {
			e.stopPropagation();
			finish(false);
		} else if (e.keyCode == 37 || e.keyCode == 39) {
			e.stopPropagation();
			choice = choice < 0 ? 0 : choice == 0 && yes != null ? 1 : 0;
			no.alpha = choice == 0 ? 1 : .75;
			if (yes != null)
				yes.alpha = choice == 1 ? 1 : .75;
		} else if (e.keyCode == 13 && choice >= 0) {
			e.stopPropagation();
			finish(choice == 1);
		}
	}

	function finish(accepted:Bool):Void {
		if (closed)
			return;
		var callback = accepted ? onYes : onNo;
		destroy();
		if (callback != null)
			callback();
	}

	public function destroy():Void {
		if (closed)
			return;
		closed = true;
		if (keyboard != null)
			keyboard.removeEventListener(KeyboardEvent.KEY_DOWN, key, true);
		keyboard = null;
		onYes = null;
		onNo = null;
		removeEventListener(MouseEvent.MOUSE_DOWN, block);
		removeEventListener(MouseEvent.CLICK, block);
		if (parent != null)
			parent.removeChild(this);
	}
}
