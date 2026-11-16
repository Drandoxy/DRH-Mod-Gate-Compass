package mods.gate_compass;

import mods.api.Context;
import openfl.display.Bitmap;
import openfl.display.BitmapData;
import openfl.display.Sprite;
import openfl.events.Event;
import openfl.events.MouseEvent;
import openfl.filters.ColorMatrixFilter;
import openfl.filters.DropShadowFilter;
import openfl.geom.Point;
import openfl.text.Font;
import openfl.text.TextField;
import openfl.text.TextFieldAutoSize;
import openfl.text.TextFormat;

class FloatingCompass extends Sprite {
    static inline final SIZE = 88.;
    var ctx:Context;
    var layoutFile:String;
    var needle = new Sprite();
    var grip = new Sprite();
    var boss = new Sprite();
    var bossLines:Array<TextField> = [];
    var arrowArt:BitmapData;
    var bossFontChecked = false;
    var heading:Float = 0;
    var hasHeading = false;
    var lastTurn = 0;
    public var smooth=true;
    var dragKind = 0;
    var startX:Float;
    var startY:Float;
    var startLeft:Float;
    var startTop:Float;
    var startScale:Float;

    public function new(context:Context) {
        super();
        ctx = context;
        layoutFile = ctx.data + "/compass-layout.json";
        visible = false;
        buttonMode = true;

        graphics.lineStyle(2, 0x89602E);
        graphics.beginFill(0x251A13, 0.93);
        graphics.drawCircle(44, 44, 42);
        graphics.endFill();
        graphics.lineStyle(1, 0xC39856, 0.8);
        graphics.drawCircle(44, 44, 37);
        for (i in 0...8) {
            var a = i * Math.PI / 4;
            graphics.moveTo(44 + Math.cos(a) * 31, 44 + Math.sin(a) * 31);
            graphics.lineTo(44 + Math.cos(a) * 36, 44 + Math.sin(a) * 36);
        }
        needle.x = 44;
        needle.y = 44;
        needle.mouseEnabled = false;
        needle.mouseChildren = false;
        drawNeedle();
        addChild(needle);

        boss.mouseEnabled = false;
        boss.mouseChildren = false;
        for (word in ["Defeat", "the", "boss"]) {
            var line = new TextField();
            line.autoSize = TextFieldAutoSize.LEFT;
            line.selectable = false;
            line.defaultTextFormat = bossFormat("_sans");
            line.text = word;
            boss.addChild(line);
            bossLines.push(line);
        }
        layoutBossText();
        boss.filters = [new DropShadowFilter(1, 90, 0x391511, 1, 2, 2, 2)];
        boss.visible = false;
        addChild(boss);

        grip.graphics.beginFill(0, 0);
        grip.graphics.drawRect(0, 0, 19, 19);
        grip.graphics.endFill();
        grip.graphics.lineStyle(1.5, 0xD3AB69);
        grip.graphics.moveTo(3, 16);
        grip.graphics.lineTo(16, 3);
        grip.graphics.moveTo(9, 16);
        grip.graphics.lineTo(16, 9);
        grip.x = grip.y = 69;
        grip.buttonMode = true;
        addChild(grip);
        addEventListener(MouseEvent.MOUSE_DOWN, startDragGesture);
        addEventListener(Event.ADDED_TO_STAGE, added);
        loadLayout();
    }

    function drawNeedle():Void {
        try {
            var folder = haxe.io.Path.directory(Sys.programPath());
            var path = folder + "/Resources/Glyphs/Others/Arrows/Directional_Arrow_Straight.png";
            arrowArt = BitmapData.fromFile(path);
        } catch (_:Dynamic) {}
        if (arrowArt != null) {
            var arrow = new Bitmap(arrowArt, "auto", true);
            arrow.width = 81;
            arrow.height = 54 * arrowArt.height / arrowArt.width;
            arrow.x = -arrow.width / 2;
            arrow.y = -arrow.height / 2;
            arrow.filters = [new ColorMatrixFilter([
                1, 0, 0, 0, 18,
                0.75, 0, 0, 0, 10,
                0.28, 0, 0, 0, 0,
                0, 0, 0, 1, 0
            ])];
            needle.addChild(arrow);
            return;
        }
        var pen = needle.graphics;
        needle.scaleX = needle.scaleY = 1.5;
        pen.lineStyle(2, 0x754618);
        pen.beginFill(0xF3B743);
        pen.moveTo(29, 0);
        pen.lineTo(5, -15);
        pen.lineTo(5, -6);
        pen.lineTo(-25, -6);
        pen.lineTo(-25, 6);
        pen.lineTo(5, 6);
        pen.lineTo(5, 15);
        pen.lineTo(29, 0);
        pen.endFill();
    }

    public function setThemeColor(color:Int):Void {
        // The original 2D compass keeps its golden artwork in every dungeon.
        needle.filters = [];
    }

    public function showIdle():Void {
        visible = true;
        needle.visible = hasHeading && !boss.visible;
        clampPosition();
    }

    public function aim(dx:Float, dy:Float):Void {
        visible = true;
        boss.visible = false;
        if (Math.isFinite(dx) && Math.isFinite(dy) && dx * dx + dy * dy >= 64) {
            heading = Math.atan2(dy, dx) * 180 / Math.PI;
            if (!hasHeading) {
                needle.rotation = heading;
                hasHeading = true;
            }
        }
        if(!smooth&&hasHeading)needle.rotation=heading;
        needle.visible = hasHeading;
        clampPosition();
    }

    public function turn(now:Int):Void {
        var elapsed = Math.min(50, Math.max(0, now - lastTurn));
        lastTurn = now;
        if (!visible || !needle.visible || !hasHeading) return;

        var delta = (heading - needle.rotation + 540) % 360 - 180;
        needle.rotation += smooth ? delta * (1-Math.exp(-elapsed/50.)) : delta;
    }

    public function resetHeading():Void {
        hasHeading = false;
        needle.visible = false;
        boss.visible = false;
    }

    public function showBoss():Void {
        if (!bossFontChecked) {
            bossFontChecked = true;
            for (font in Font.enumerateFonts(false)) {
                var name = font.fontName.toLowerCase();
                if (name.indexOf("fat rhino") < 0 && name.indexOf("fatrhino") < 0) continue;
                var format = bossFormat(font.fontName);
                for (line in bossLines) {
                    line.embedFonts = true;
                    line.defaultTextFormat = format;
                    line.setTextFormat(format);
                }
                layoutBossText();
                break;
            }
        }
        visible = true;
        needle.visible = false;
        boss.visible = true;
        clampPosition();
    }

    function layoutBossText():Void {
        var y = 0.;
        for (line in bossLines) {
            line.x = (SIZE - line.width) / 2;
            line.y = y;
            y += line.textHeight + 1;
        }
        var last = bossLines[bossLines.length - 1];
        boss.y = (SIZE - last.y - last.height) / 2;
    }

    static function bossFormat(face:String):TextFormat {
        return new TextFormat(face, 15, 0xFF6850, true);
    }

    function added(event:Event):Void {
        clampPosition();
    }

    function startDragGesture(event:MouseEvent):Void {
        if (stage == null) return;
        dragKind = event.target == grip ? 2 : 1;
        var p = ctx.overlay.globalToLocal(new Point(event.stageX, event.stageY));
        startX = p.x;
        startY = p.y;
        startLeft = x;
        startTop = y;
        startScale = scaleX;
        stage.addEventListener(MouseEvent.MOUSE_MOVE, moveDragGesture);
        stage.addEventListener(MouseEvent.MOUSE_UP, endDragGesture);
        stage.addEventListener(Event.DEACTIVATE, endDragGesture);
        event.stopPropagation();
    }

    function moveDragGesture(event:MouseEvent):Void {
        var p = ctx.overlay.globalToLocal(new Point(event.stageX, event.stageY));
        if (dragKind == 2) {
            var delta = (p.x - startX + p.y - startY) / 2;
            var maximum = Math.min(2.5, Math.min((ctx.viewWidth - x) / SIZE, (ctx.viewHeight - y) / SIZE));
            scaleX = scaleY = Math.max(0.6, Math.min(maximum, startScale + delta / SIZE));
        } else {
            x = startLeft + p.x - startX;
            y = startTop + p.y - startY;
        }
        clampPosition();
        event.updateAfterEvent();
    }

    function endDragGesture(event:Event):Void {
        if (dragKind == 0) return;
        dragKind = 0;
        if (stage != null) {
            stage.removeEventListener(MouseEvent.MOUSE_MOVE, moveDragGesture);
            stage.removeEventListener(MouseEvent.MOUSE_UP, endDragGesture);
            stage.removeEventListener(Event.DEACTIVATE, endDragGesture);
        }
        try {
            sys.io.File.saveContent(layoutFile, haxe.Json.stringify({x: x, y: y, scale: scaleX}));
        } catch (error:Dynamic) {
            ctx.log("Could not save compass layout: " + Std.string(error));
        }
    }

    function clampPosition():Void {
        if (ctx.viewWidth <= 0 || ctx.viewHeight <= 0) return;
        x = Math.max(0, Math.min(x, ctx.viewWidth - SIZE * scaleX));
        y = Math.max(0, Math.min(y, ctx.viewHeight - SIZE * scaleY));
    }

    function loadLayout():Void {
        x = 35;
        y = 230;
        try {
            if (!sys.FileSystem.exists(layoutFile)) return;
            var saved:Dynamic = haxe.Json.parse(sys.io.File.getContent(layoutFile));
            x = number(saved.x, x);
            y = number(saved.y, y);
            scaleX = scaleY = Math.max(0.6, Math.min(2.5, number(saved.scale, 1)));
        } catch (error:Dynamic) {
            ctx.log("Could not load compass layout: " + Std.string(error));
        }
    }

    static function number(value:Dynamic, fallback:Float):Float {
        if (!Std.isOfType(value, Float) && !Std.isOfType(value, Int)) return fallback;
        var n:Float = value;
        return Math.isFinite(n) ? n : fallback;
    }

    public function destroy():Void {
        endDragGesture(null);
        removeEventListener(Event.ADDED_TO_STAGE, added);
        removeEventListener(MouseEvent.MOUSE_DOWN, startDragGesture);
        if (arrowArt != null) arrowArt.dispose();
        arrowArt = null;
    }
}
