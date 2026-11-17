package mods.gate_compass;

import actor.ActorView;
import mods.api.Context;
import openfl.display.BitmapData;
import openfl.geom.Matrix;
import starling.display.Image;
import starling.display.Quad;
import starling.textures.Texture;
import starling.events.Event;
import starling.styles.MeshStyle;
import openfl.display.Sprite;
import openfl.text.Font;
import openfl.text.TextField;
import openfl.text.TextFieldAutoSize;
import openfl.text.TextFormat;

/** Native world marker between scenery and actor layers, using public host access. */
class Compass extends starling.display.Sprite {
    var ctx:Context;
    var themeColor=0x00DFFF;
    var ringArt:Image;
    var displayMode = "ground_line";
    var owner:ActorView;
    var routeVisual = new starling.display.Sprite();
    var routeBatches:Array<RouteBatch> = [];
    var lastVisibilityX = Math.POSITIVE_INFINITY;
    var lastVisibilityY = Math.POSITIVE_INFINITY;
    var shownRoute:Array<openfl.geom.Point>;
    var displayRoute:Array<openfl.geom.Point> = [];
    // Fit to the visible white stroke decoded from db_fx_player_ring's ATF,
    // excluding transparent atlas padding. HeroOwnerView applies scale 0.75.
    static inline final FLATTEN = 0.6264075354;
    static inline final RING_X = -0.41416017;
    static inline final RING_Y = -4.36789838;
    static inline final RING_ROTATION = -0.000567615;
    var mount = new starling.display.Sprite();
    var backdrop:brain.starling.StarlingLayer;
    var textures:Array<Texture> = [];
    var bitmaps:Array<BitmapData> = [];
    var groundRing = new starling.display.Sprite();
    var orbit = new starling.display.Sprite();
    var groundNeedle:Image;
    var groundBoss:Image;
    var groundGuide:Quad;
    var ring = new Sprite();
    var needle = new Sprite();
    var boss = new Sprite();
    var heading = 0.;
    var hasHeading = false;
    var lastTurn = 0;
    public var smooth=true;
    public var reducedEffects=false;
    var lastVisibilityTime=0;
    var directionX = 0.;
    var directionY = 0.;
    var size = 1.;
    var arrowSize=1.;var ringWidth=1.;var lineWidth=1.;var arrowOffset=0.;
    static inline final RADIUS = 98.8;
    static inline final COLOR = 0x88E9E7;

    public function new(context:Context) {
        super();
        ctx = context;
        visible = false;
        touchable = false;
        mount.touchable = false;
        // Static concentric strokes give a soft cyan halo and white core;
        // no per-frame blur filter or texture upload is needed.
        for (stroke in [20., 15., 10., 6.]) {
            ring.graphics.lineStyle(stroke * 0.7 * ringWidth, COLOR, stroke == 20 ? 0.08 : stroke == 15 ? 0.15 : stroke == 10 ? 0.32 : 0.8);
            ring.graphics.drawCircle(0, 0, RADIUS * 0.78);
        }
        ring.graphics.lineStyle(3.15 * ringWidth, 0xFFFFFF, 1);
        ring.graphics.drawCircle(0, 0, RADIUS * 0.78);
        // The cyan base sits outside the ring's core, with a matching halo.
        for (stroke in [12., 8., 4.]) {
            needle.graphics.lineStyle(stroke, COLOR, stroke == 12 ? 0.08 : stroke == 8 ? 0.2 : 0.5);
            needle.graphics.moveTo(RADIUS * 0.78 * 1.45 + 6 + ((76. + 39) - (76. * 0.78 * 1.45 + 6)) * 2.34, 0);
            needle.graphics.lineTo(RADIUS * 0.78 * 1.45 + 6, -35.568);
            needle.graphics.moveTo(RADIUS * 0.78 * 1.45 + 6, 35.568);
            needle.graphics.lineTo(RADIUS * 0.78 * 1.45 + 6 + ((76. + 39) - (76. * 0.78 * 1.45 + 6)) * 2.34, 0);
        }
        needle.graphics.lineStyle(0, COLOR, 0);
        needle.graphics.beginFill(COLOR, 0.95);
        needle.graphics.moveTo(RADIUS * 0.78 * 1.45 + 6 + ((76. + 39) - (76. * 0.78 * 1.45 + 6)) * 2.34, 0);
        needle.graphics.lineTo(RADIUS * 0.78 * 1.45 + 6, -35.568);
        needle.graphics.lineTo(RADIUS * 0.78 * 1.45 + 6, 35.568);
        needle.graphics.lineTo(RADIUS * 0.78 * 1.45 + 6 + ((76. + 39) - (76. * 0.78 * 1.45 + 6)) * 2.34, 0);
        needle.graphics.endFill();
        needle.graphics.beginFill(0xFFFFFF, 1);
        needle.graphics.moveTo(RADIUS * 0.78 * 1.45 + 5 + ((76. + 33) - (76. * 0.78 * 1.45 + 5)) * 2.34, 0);
        needle.graphics.lineTo(RADIUS * 0.78 * 1.45 + 2, -19.89);
        needle.graphics.lineTo(RADIUS * 0.78 * 1.45 + 2, 19.89);
        needle.graphics.lineTo(RADIUS * 0.78 * 1.45 + 5 + ((76. + 33) - (76. * 0.78 * 1.45 + 5)) * 2.34, 0);
        needle.graphics.endFill();
        addChildAt(routeVisual, 0);
        mount.addChild(this);
        mount.addEventListener(Event.ENTER_FRAME, syncCamera);
    }

    function buildVisuals():Void {
        var face = "_sans";
        for (font in Font.enumerateFonts(false)) {
            var name = font.fontName.toLowerCase();
            if (name.indexOf("fat rhino") >= 0 || name.indexOf("fatrhino") >= 0) { face = font.fontName; break; }
        }
        var y = -27.;
        for (word in ["Defeat", "the", "boss"]) {
            var line = new TextField();
            line.autoSize = TextFieldAutoSize.LEFT;
            line.selectable = false;
            line.embedFonts = face != "_sans";
            line.defaultTextFormat = new TextFormat(face, 15, 0xFF6850, true);
            line.text = word;
            line.x = -line.width / 2;
            line.y = y;
            y += line.textHeight + 1;
            boss.addChild(line);
        }
        // Draw the stroke separately from its radius so width can change
        // without fading it or shrinking the ring. Preserve the artwork's
        // visible-radius allowance and the established center/perspective.
        var ringImage=baked(ring,208,208,104,104);
        ringImage.pivotX=ringImage.pivotY=104;
        ringImage.scaleX=1.45;ringImage.scaleY=FLATTEN*1.45;
        ringImage.x=0;ringImage.y=0;
        ringImage.alpha=1;
        ringArt=ringImage;
        ringArt.color=0xFFFFFF;
        groundRing.addChild(ringImage);
        groundNeedle = baked(needle, 384, 384, 192, 192);
        groundNeedle.pivotX = groundNeedle.pivotY = 192;
        groundNeedle.rotation=heading;
        groundNeedle.color=0xFFFFFF;
        orbit.addChild(groundNeedle);
        groundRing.addChild(orbit);
        groundGuide = new Quad(1, 2, COLOR);
        groundGuide.pivotY = 1;
        groundGuide.alpha = 0.35;
        addChild(groundGuide);
        addChild(groundRing);
        groundBoss = baked(boss, 120, 90, 60, 30);
        groundBoss.pivotX = 60;
        groundBoss.y = 65;
        groundBoss.visible = false;
        addChild(groundBoss);
        setSize(size);
        setDisplayMode(displayMode);
        positionArrow();
    }

    function baked(source:Sprite, width:Int, height:Int, offsetX:Float, offsetY:Float):Image {
        var bitmap = new BitmapData(width, height, true, 0);
        bitmap.draw(source, new Matrix(1, 0, 0, 1, offsetX, offsetY));
        // Replace only the cyan pigment. Neutral white cores and alpha/glow
        // remain intact instead of tinting the entire image with Image.color.
        if(source==ring || source==needle){
            var tr=(themeColor>>16)&255;var tg=(themeColor>>8)&255;var tb=themeColor&255;
            for(py in 0...height)for(px in 0...width){
                var pixel=bitmap.getPixel32(px,py);var alpha=(pixel>>>24)&255;
                if(alpha==0)continue;
                var r=(pixel>>16)&255;var g=(pixel>>8)&255;var b=pixel&255;
                var pigment=Math.min(1.,(Math.max(r,Math.max(g,b))-Math.min(r,Math.min(g,b)))/119.);
                if(pigment<=0)continue;
                var nr=Std.int(Math.max(0,Math.min(255,r+(tr-136)*pigment)));
                var ng=Std.int(Math.max(0,Math.min(255,g+(tg-233)*pigment)));
                var nb=Std.int(Math.max(0,Math.min(255,b+(tb-231)*pigment)));
                bitmap.setPixel32(px,py,(alpha<<24)|(nr<<16)|(ng<<8)|nb);
            }
        }
        if(reducedEffects&&(source==ring||source==needle))for(py in 0...height)for(px in 0...width){
            var pixel=bitmap.getPixel32(px,py);if(((pixel>>>24)&255)<80)bitmap.setPixel32(px,py,0);
        }
        var texture = Texture.fromBitmapData(bitmap, false);
        bitmaps.push(bitmap);
        textures.push(texture);
        var image = new Image(texture);
        // Keep mod-owned textures out of the game's multi-atlas animation
        // batches, without altering the host's global style or game textures.
        image.setStyle(new MeshStyle());
        image.alpha = 1;
        return image;
    }

    public function attach(view:ActorView):Void {
        if (owner == view && mount.parent != null && (groundNeedle != null || !wantsGround())) return;
        owner = view;
        var facade = ctx.core.facade;
        var manager = facade == null ? null : facade.starlingLayerManager;
        var background = manager == null ? null : manager.getLayer(10);
        var actors = manager == null ? null : manager.getLayer(20);
        if (background == null || actors == null || actors.parent == null) return;
        if (groundNeedle == null && wantsGround()) buildVisuals();
        backdrop = background;
        if (mount.parent != actors.parent)
            actors.parent.addChildAt(mount, actors.parent.getChildIndex(actors));
        syncCamera(null);
    }

    function syncCamera(event:Event):Void {
        if (backdrop != null) mount.transformationMatrix = backdrop.transformationMatrix;
        if (owner != null && owner.root != null) {
            setWorldPosition(owner.root.x, owner.root.y);
            // The vanilla foot ring belongs to the animated body, not directly
            // to the actor root. Follow that same public transform chain.
            if (owner.body != null) {
                var center=owner.root.globalToLocal(owner.body.localToGlobal(new openfl.geom.Point(RING_X,RING_Y)));
                groundRing.x=center.x; groundRing.y=center.y;
            }
        }
    }

    public function setWorldPosition(worldX:Float, worldY:Float):Void {
        x = worldX;
        y = worldY;
        routeVisual.x = -worldX;
        routeVisual.y = -worldY;
        var now=openfl.Lib.getTimer();
        if(reducedEffects&&lastVisibilityX!=Math.POSITIVE_INFINITY&&now-lastVisibilityTime<66)return;
        if (Math.abs(worldX - lastVisibilityX) + Math.abs(worldY - lastVisibilityY) < 16) return;
        lastVisibilityX = worldX; lastVisibilityY = worldY;lastVisibilityTime=now;
        if (routeVisual.visible && displayRoute.length > 1 && routeBatches.length > 0) {
            var nearest = -1; var best = Math.POSITIVE_INFINITY;var nearestT=0.;
            var count = displayRoute.length - 1;
            for (i in 0...count) {
                var a = displayRoute[i]; var b = displayRoute[i + 1];
                var dx = b.x - a.x; var dy = b.y - a.y;
                var length = dx * dx + dy * dy;
                var t = length == 0 ? 0. : Math.max(0, Math.min(1, ((worldX - a.x) * dx + (worldY - a.y) * dy) / length));
                var ex = a.x + dx * t - worldX; var ey = a.y + dy * t - worldY;
                var distance = ex * ex + ey * ey;
                if (distance < best) { best = distance; nearest = i; nearestT=t; }
            }
            var mask:Array<Bool>=[];var along=0.;
            for(index in 0...count){
                var a=displayRoute[index];var b=displayRoute[index+1];
                var length=openfl.geom.Point.distance(a,b);
                if(index<nearest){mask.push(false);continue;}
                if(index==nearest)along=-length*nearestT;
                var midpoint=along+length/2;
                mask.push(midpoint>=184 && midpoint<=2200);
                along+=length;
            }
            for (batch in routeBatches) batch.show(mask);
        }
    }

    public function detach():Void {
        mount.removeFromParent();
        backdrop = null;
        owner = null;
    }

    public function setThemeColor(color:Int):Void {
        if(themeColor==color)return;
        themeColor=color;
        if(groundNeedle!=null){releaseGround();if(wantsGround())buildVisuals();}
    }

    function wantsGround():Bool { return displayMode=="ground"||displayMode=="ground_line"; }

    function releaseRoute():Void {
        for(batch in routeBatches)batch.destroy();
        routeBatches=[];displayRoute=[];shownRoute=null;routeVisual.visible=false;
    }

    function releaseGround():Void {
        groundRing.removeChildren(0,-1,true);
        orbit=new starling.display.Sprite();
        if(groundBoss!=null){groundBoss.removeFromParent();groundBoss.dispose();}
        if(groundGuide!=null){groundGuide.removeFromParent();groundGuide.dispose();}
        groundNeedle=null;groundBoss=null;groundGuide=null;ringArt=null;
        for(texture in textures)texture.dispose();for(bitmap in bitmaps)bitmap.dispose();
        textures=[];bitmaps=[];boss=new Sprite();
    }

    public function setDisplayMode(value:String):Void {
        displayMode=value;
        groundRing.visible=wantsGround();
        if(wantsGround()&&groundNeedle==null&&owner!=null&&mount.parent!=null)buildVisuals();
        if(!wantsGround()&&groundNeedle!=null)releaseGround();
        var line=value=="ground_line"||value=="line";
        if(!line)releaseRoute();
        else routeVisual.visible=shownRoute!=null;
    }

    public function setReducedEffects(value:Bool):Void {
        if(reducedEffects==value)return;
        reducedEffects=value;lastVisibilityTime=0;
        if(groundNeedle!=null){releaseGround();if(wantsGround())buildVisuals();}
        var line=shownRoute;releaseRoute();if(line!=null)setRoute(line);
    }

    public function configure(circle:Float,arrow:Float,routeWidth:Float,stroke:Float,offset:Float):Void {
        arrowSize=arrow;arrowOffset=offset;setSize(circle);
        if(lineWidth!=routeWidth){lineWidth=routeWidth;var line=shownRoute;shownRoute=null;if(line!=null)setRoute(line);}
        if(ringWidth!=stroke){
            ringWidth=stroke;ring.graphics.clear();
            for(width in [20.,15.,10.,6.]){ring.graphics.lineStyle(width*0.7*ringWidth,COLOR,width==20?0.08:width==15?0.15:width==10?0.32:0.8);ring.graphics.drawCircle(0,0,RADIUS*0.78);}
            ring.graphics.lineStyle(3.15*ringWidth,0xFFFFFF,1);ring.graphics.drawCircle(0,0,RADIUS*0.78);
            if(groundNeedle!=null){releaseGround();if(wantsGround())buildVisuals();}
        }
        positionArrow();
    }

    function positionArrow():Void {
        if(groundNeedle==null)return;
        var radius=RADIUS*0.78*1.45;
        var shift=(radius*size+6+arrowOffset-(radius+6)*arrowSize)/size;
        groundNeedle.scaleX=groundNeedle.scaleY=arrowSize/size;
        groundNeedle.x=Math.cos(groundNeedle.rotation)*shift;
        groundNeedle.y=Math.sin(groundNeedle.rotation)*shift;
    }

    public function setSize(value:Float):Void {
        size = value;
        groundRing.x = RING_X;
        groundRing.y = RING_Y;
        groundRing.rotation = RING_ROTATION;
        groundRing.alpha = 1;
        groundRing.blendMode = "normal";
        groundRing.scaleX = value;
        groundRing.scaleY = value;
        orbit.scaleY = FLATTEN;
    }

    public function showIdle():Void {
        visible = true;
        if (groundNeedle != null) groundNeedle.visible = hasHeading && !groundBoss.visible;
    }

    public function aim(dx:Float, dy:Float):Void {
        visible = true;
        if (groundNeedle == null) return;
        groundBoss.visible = false;
        if (Math.isFinite(dx) && Math.isFinite(dy) && dx * dx + dy * dy >= 64) {
            heading = Math.atan2(dy / FLATTEN, dx);
            directionX = dx;
            directionY = dy;
            if (!hasHeading) groundNeedle.rotation = heading;
            hasHeading = true;
            if(!smooth)groundNeedle.rotation=heading;
        }
        groundNeedle.visible = hasHeading;
        positionArrow();
    }

    public function turn(now:Int):Void {
        var elapsed = lastTurn == 0 ? 0 : Math.min(50, Math.max(0, now - lastTurn));
        lastTurn = now;
        if (groundNeedle == null || !visible || !hasHeading || groundBoss.visible) return;
        var delta = (heading - groundNeedle.rotation + Math.PI * 3) % (Math.PI * 2) - Math.PI;
        groundNeedle.rotation += smooth ? delta * (1-Math.exp(-elapsed/75.)) : delta;
        positionArrow();
        groundGuide.visible = false;
    }

    public function setRoute(points:Array<openfl.geom.Point>):Void {
        routeVisual.visible = displayMode == "ground_line" || displayMode == "line";
        if (!routeVisual.visible) return;
        if (points == null || points.length < 2) return;
        if (shownRoute == points) return;
        shownRoute = points;
        for (batch in routeBatches) batch.destroy();
        // Subdivision only affects visibility; it does not move the stored route.
        displayRoute = [];
        if (points.length > 0) displayRoute.push(points[0]);
        for (i in 0...points.length - 1) {
            var a = points[i]; var b = points[i + 1];
            if (openfl.geom.Point.distance(a, b) < 0.01) continue;
            var count = Std.int(Math.max(1, Math.ceil(openfl.geom.Point.distance(a, b) / 10)));
            for (j in 1...count + 1) displayRoute.push(new openfl.geom.Point(a.x + (b.x - a.x) * j / count, a.y + (b.y - a.y) * j / count));
        }
        routeBatches = [];
        for (layer in (reducedEffects?1:0)...2) {
            var color = layer == 0 ? 0x9564C7 : 0xE9D2FE;
            var width = (layer == 0 ? 11.52 : 5.4)*lineWidth;
            var opacity = layer == 0 ? 0.4032 : 0.95;
            var batch = RouteRibbon.batch(displayRoute, color, width, opacity,!reducedEffects);
            routeBatches.push(batch); routeVisual.addChild(batch.mesh);
        }
        lastVisibilityX = Math.POSITIVE_INFINITY;
        setWorldPosition(x, y);
    }

    public function hideRoute():Void { routeVisual.visible = false; }

    public function resetHeading():Void {
        hasHeading = false;
        releaseRoute();
        if (groundNeedle == null) return;
        groundNeedle.visible = false;
        groundBoss.visible = false;
        groundGuide.visible = false;
    }

    public function showBoss():Void {
        visible = true;
        routeVisual.visible = false;
        if (groundNeedle == null) return;
        groundNeedle.visible = false;
        groundGuide.visible = false;
        groundBoss.visible = false;
    }

    public function destroy():Void {
        detach();
        releaseRoute();
        mount.removeEventListener(Event.ENTER_FRAME, syncCamera);
        mount.removeChild(this);
        dispose();
        mount.dispose();
        for (texture in textures) texture.dispose();
        for (bitmap in bitmaps) bitmap.dispose();
        textures = [];
        bitmaps = [];
    }
}
