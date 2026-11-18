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

	public var stats:NavigationStats;

	var windowX = Math.POSITIVE_INFINITY;
	var windowY = Math.POSITIVE_INFINITY;
	var blankMask = false;
	var themeColor = 0x00DFFF;
	var ringArt:Image;
	var displayMode = "ground_line";
	var owner:ActorView;
	var routeVisual = new starling.display.Sprite();
	var routeBatches:Array<RouteBatch> = [];
	var motionTarget:Array<openfl.geom.Point>;
	var motionEnd:Array<openfl.geom.Point>;
	var motionFrames:Array<Array<openfl.geom.Point>> = [];
	var motionMask:Array<Bool>;
	var motionFrame = 0;
	var nextMotionFrame = 0;

	function cancelMotion():Void {
		motionTarget = null;
		motionEnd = null;
		motionFrames = [];
		motionMask = null;
	}

	function drawMotionFrame(now:Int):Void {
		if (motionTarget == null || now < nextMotionFrame || !routeVisual.visible)
			return;
		var finished = motionFrame >= motionFrames.length;
		var points = finished ? motionEnd : motionFrames[motionFrame++];
		var replacement = buildRouteBatches(points, motionMask);
		for (batch in replacement)
			routeVisual.addChild(batch.mesh);
		for (batch in routeBatches)
			batch.destroy();
		routeBatches = replacement;
		displayRoute = points;
		nextMotionFrame = now + 24;
		if (finished) {
			shownRoute = motionTarget;
			cancelMotion();
			lastVisibilityX = Math.POSITIVE_INFINITY;
		}
	}

	var headBatches:Array<RouteBatch> = [];
	var bendOrigin:openfl.geom.Point;
	var bendTime = 0;
	var bendMoving = false;

	function smoothBendOrigin(worldX:Float, worldY:Float, now:Int):openfl.geom.Point {
		var target = new openfl.geom.Point(worldX, worldY);
		if (bendOrigin == null || openfl.geom.Point.distance(bendOrigin, target) > 120) {
			bendOrigin = target;
			bendMoving = false;
		} else {
			var elapsed = Math.min(50, Math.max(0, now - bendTime));
			var alpha = 1 - Math.exp(-elapsed / 100.);
			bendOrigin = new openfl.geom.Point(bendOrigin.x + (worldX - bendOrigin.x) * alpha, bendOrigin.y + (worldY - bendOrigin.y) * alpha);
			bendMoving = openfl.geom.Point.distance(bendOrigin, target) > .75;
			if (!bendMoving)
				bendOrigin = target;
		}
		bendTime = now;
		return bendOrigin;
	}

	public var routeGrid:WalkGrid;

	function clearRouteHead():Void {
		for (batch in headBatches)
			batch.destroy();
		headBatches = [];
	}

	function updateRouteHead(worldX:Float, worldY:Float):Bool {
		if (routeGrid == null || fadingBatches.length > 0)
			return false;
		var minimum = RouteVisibility.startDistance(lineStart, lineLength);
		var origin = smoothBendOrigin(worldX, worldY, openfl.Lib.getTimer());
		var head = RouteHead.connect(displayRoute, origin.x, origin.y, routeGrid);
		if (head == null && bendMoving) {
			bendOrigin = new openfl.geom.Point(worldX, worldY);
			bendMoving = false;
			head = RouteHead.connect(displayRoute, worldX, worldY, routeGrid);
		}
		if (head == null)
			return false;
		// Include the first straight tail segment in the curved mesh. The
		// remaining tail starts at the next shared cross section.
		var headPoints = head.points.copy();
		var tailStart = head.join;
		var headLength = head.length;
		if (head.join + 1 < displayRoute.length - 1) {
			var next = displayRoute[head.join + 1];
			headLength += openfl.geom.Point.distance(headPoints[headPoints.length - 1], next);
			headPoints.push(next);
			tailStart++;
		}
		var headMask = RouteHead.mask(headPoints, 0, 0, minimum, lineLength);
		var tailMask = RouteHead.mask(displayRoute, tailStart, headLength, minimum, lineLength);
		if (!RouteVisibility.drawable(tailMask))
			return false;
		var drawHead = RouteVisibility.drawable(headMask);
		var joined = drawHead && headMask[headMask.length - 1] && tailMask[tailStart];
		var replacement:Array<RouteBatch> = [];
		if (drawHead) {
			for (layer in (reducedEffects ? 1 : 0)...2) {
				var color = layer == 0 ? 0x9564C7 : 0xE9D2FE;
				var width = (layer == 0 ? 11.52 : 5.4) * lineWidth;
				var opacity = layer == 0 ? 0.4032 : 0.95;
				var batch = RouteRibbon.batch(headPoints, color, width, opacity, !reducedEffects);
				batch.show(headMask, false, joined);
				replacement.push(batch);
			}
		}
		for (batch in routeBatches)
			batch.show(tailMask, joined);
		for (batch in replacement)
			routeVisual.addChild(batch.mesh);
		clearRouteHead();
		headBatches = replacement;
		blankMask = false;
		return true;
	}

	var fadingBatches:Array<RouteBatch> = [];
	var fadingAlpha:Array<Float> = [];
	var arrivingAlpha:Array<Float> = [];
	var fadeStarted = 0;

	function finishRouteFade():Void {
		for (batch in fadingBatches)
			batch.destroy();
		fadingBatches = [];
		fadingAlpha = [];
		for (i in 0...arrivingAlpha.length)
			if (i < routeBatches.length)
				routeBatches[i].mesh.alpha = arrivingAlpha[i];
		arrivingAlpha = [];
	}

	function updateRouteFade(now:Int):Void {
		if (fadingBatches.length == 0)
			return;
		var progress = Math.max(0., Math.min(1., (now - fadeStarted) / 50.));
		for (i in 0...fadingBatches.length)
			fadingBatches[i].mesh.alpha = fadingAlpha[i] * (1 - progress);
		for (i in 0...routeBatches.length)
			routeBatches[i].mesh.alpha = arrivingAlpha[i] * progress;
		if (progress >= 1) {
			finishRouteFade();
			lastVisibilityX = Math.POSITIVE_INFINITY;
		}
	}

	var lastVisibilityX = Math.POSITIVE_INFINITY;
	var lastVisibilityY = Math.POSITIVE_INFINITY;
	var shownRoute:Array<openfl.geom.Point>;
	var rejectedRoute:Array<openfl.geom.Point>;
	var rejectedX = 0.;
	var rejectedY = 0.;
	var displayRoute:Array<openfl.geom.Point> = [];

	// Fit to the visible white stroke decoded from db_fx_player_ring's ATF,
	// excluding transparent atlas padding. HeroOwnerView applies scale 0.75.
	static inline final FLATTEN = 0.6264075354;
	static inline final RING_X = -0.41416017;
	static inline final RING_Y = -4.36789838;
	static inline final RING_ROTATION = -0.000567615;

	// The host inserts HUD/overlay layers by scanning StarlingLayer.sortIndex.
	// A plain Sprite here terminates that scan and puts later UI behind scenery.
	var mount = new brain.starling.StarlingLayer(15, "gateCompass", "normal", false, null, false);
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

	public var smooth = true;
	public var reducedEffects = false;

	var lastVisibilityTime = 0;
	var lineLength = 2200.;
	var lineStart = 135.;
	var directionX = 0.;
	var directionY = 0.;
	var size = 1.;
	var arrowSize = 1.;
	var ringWidth = 1.;
	var lineWidth = 1.;
	var arrowOffset = 0.;

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
			if (name.indexOf("fat rhino") >= 0 || name.indexOf("fatrhino") >= 0) {
				face = font.fontName;
				break;
			}
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
		var ringImage = baked(ring, 208, 208, 104, 104);
		ringImage.pivotX = ringImage.pivotY = 104;
		ringImage.scaleX = 1.45;
		ringImage.scaleY = FLATTEN * 1.45;
		ringImage.x = 0;
		ringImage.y = 0;
		ringImage.alpha = 1;
		ringArt = ringImage;
		ringArt.color = 0xFFFFFF;
		groundRing.addChild(ringImage);
		groundNeedle = baked(needle, 384, 384, 192, 192);
		groundNeedle.pivotX = groundNeedle.pivotY = 192;
		groundNeedle.rotation = heading;
		groundNeedle.color = 0xFFFFFF;
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
		if (source == ring || source == needle) {
			bitmap.applyFilter(bitmap, bitmap.rect, new openfl.geom.Point(), new openfl.filters.ColorMatrixFilter(PaletteTransform.matrix(themeColor)));
			if (reducedEffects)
				bitmap.threshold(bitmap, bitmap.rect, new openfl.geom.Point(), "<", 0x50000000, 0, 0xFF000000, false);
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
		if (owner == view && mount.parent != null && (groundNeedle != null || !wantsGround()))
			return;
		owner = view;
		var facade = ctx.core.facade;
		var manager = facade == null ? null : facade.starlingLayerManager;
		var background = manager == null ? null : manager.getLayer(10);
		var actors = manager == null ? null : manager.getLayer(20);
		if (background == null || actors == null || actors.parent == null)
			return;
		if (groundNeedle == null && wantsGround())
			buildVisuals();
		backdrop = background;
		if (mount.parent != actors.parent)
			actors.parent.addChildAt(mount, actors.parent.getChildIndex(actors));
		syncCamera(null);
	}

	function syncCamera(event:Event):Void {
		if (!visible)
			return;
		var now = openfl.Lib.getTimer();
		updateRouteFade(now);
		drawMotionFrame(now);
		if (backdrop != null)
			mount.transformationMatrix = backdrop.transformationMatrix;
		if (owner != null && owner.root != null) {
			setWorldPosition(owner.root.x, owner.root.y);
			// The vanilla foot ring belongs to the animated body, not directly
			// to the actor root. Follow that same public transform chain.
			if (owner.body != null) {
				var center = owner.root.globalToLocal(owner.body.localToGlobal(new openfl.geom.Point(RING_X, RING_Y)));
				groundRing.x = center.x;
				groundRing.y = center.y;
			}
		}
	}

	public function setWorldPosition(worldX:Float, worldY:Float):Void {
		x = worldX;
		y = worldY;
		routeVisual.x = -worldX;
		routeVisual.y = -worldY;
		if (motionTarget != null)
			return;
		if (routeVisual.visible && shownRoute != null && Math.abs(worldX - windowX) + Math.abs(worldY - windowY) > 600)
			setRoute(shownRoute, true);
		var now = openfl.Lib.getTimer();
		if (bendMoving && now - lastVisibilityTime < 24)
			return;
		var moved = Math.abs(worldX - lastVisibilityX) + Math.abs(worldY - lastVisibilityY);
		if (reducedEffects && moved < 96 && lastVisibilityX != Math.POSITIVE_INFINITY && now - lastVisibilityTime < 66)
			return;
		if (!bendMoving && Math.abs(worldX - lastVisibilityX) + Math.abs(worldY - lastVisibilityY) < (reducedEffects ? 16 : 8))
			return;
		lastVisibilityX = worldX;
		lastVisibilityY = worldY;
		lastVisibilityTime = now;
		if (routeVisual.visible && displayRoute.length > 1 && routeBatches.length > 0) {
			if (updateRouteHead(worldX, worldY))
				return;
			clearRouteHead();
			var mask = RouteVisibility.mask(displayRoute, worldX, worldY, RouteVisibility.startDistance(lineStart, lineLength), lineLength);
			var blank = !RouteVisibility.drawable(mask);
			if (stats != null && blank && !blankMask) {
				stats.zeroMasks++;
				stats.event("empty-mask", {x: worldX, y: worldY, points: displayRoute.length});
			}
			blankMask = blank;
			for (batch in routeBatches)
				batch.show(mask);
		}
	}

	public function detach():Void {
		mount.removeFromParent();
		backdrop = null;
		owner = null;
	}

	public function setThemeColor(color:Int):Void {
		if (themeColor == color)
			return;
		themeColor = color;
		if (groundNeedle != null) {
			releaseGround();
			if (wantsGround())
				buildVisuals();
		}
	}

	function wantsGround():Bool {
		return displayMode == "ground" || displayMode == "ground_line";
	}

	function releaseRoute():Void {
		bendOrigin = null;
		bendMoving = false;
		cancelMotion();
		clearRouteHead();
		finishRouteFade();
		for (batch in routeBatches)
			batch.destroy();
		routeBatches = [];
		displayRoute = [];
		shownRoute = null;
		rejectedRoute = null;
		routeVisual.visible = false;
	}

	function releaseGround():Void {
		groundRing.removeChildren(0, -1, true);
		orbit = new starling.display.Sprite();
		if (groundBoss != null) {
			groundBoss.removeFromParent();
			groundBoss.dispose();
		}
		if (groundGuide != null) {
			groundGuide.removeFromParent();
			groundGuide.dispose();
		}
		groundNeedle = null;
		groundBoss = null;
		groundGuide = null;
		ringArt = null;
		for (texture in textures)
			texture.dispose();
		for (bitmap in bitmaps)
			bitmap.dispose();
		textures = [];
		bitmaps = [];
		boss = new Sprite();
	}

	public function setDisplayMode(value:String):Void {
		displayMode = value;
		groundRing.visible = wantsGround();
		if (wantsGround() && groundNeedle == null && owner != null && mount.parent != null)
			buildVisuals();
		if (!wantsGround() && groundNeedle != null)
			releaseGround();
		var line = value == "ground_line" || value == "line";
		if (!line)
			releaseRoute();
		else
			routeVisual.visible = shownRoute != null;
	}

	public function setReducedEffects(value:Bool):Void {
		if (reducedEffects == value)
			return;
		reducedEffects = value;
		lastVisibilityTime = 0;
		if (groundNeedle != null) {
			releaseGround();
			if (wantsGround())
				buildVisuals();
		}
		var line = shownRoute;
		releaseRoute();
		if (line != null)
			setRoute(line);
	}

	public function setLineStart(value:Float):Void {
		lineStart = Math.max(0, Math.min(500, value));
		rejectedRoute = null;
		lastVisibilityX = Math.POSITIVE_INFINITY;
		lastVisibilityY = Math.POSITIVE_INFINITY;
		if (shownRoute != null)
			setRoute(shownRoute, true);
	}

	public function setLineLength(value:Float):Void {
		var next = Math.max(300, Math.min(2200, value));
		if (next == lineLength)
			return;
		lineLength = next;
		rejectedRoute = null;
		// Reapply the visibility mask even while the hero is standing still.
		lastVisibilityX = Math.POSITIVE_INFINITY;
		lastVisibilityY = Math.POSITIVE_INFINITY;
		lastVisibilityTime = 0;
		if (shownRoute != null)
			setRoute(shownRoute, true);
	}

	public function configure(circle:Float, arrow:Float, routeWidth:Float, stroke:Float, offset:Float):Void {
		arrowSize = arrow;
		arrowOffset = offset;
		setSize(circle);
		if (lineWidth != routeWidth) {
			lineWidth = routeWidth;
			var line = shownRoute;
			shownRoute = null;
			rejectedRoute = null;
			if (line != null)
				setRoute(line);
		}
		if (ringWidth != stroke) {
			ringWidth = stroke;
			ring.graphics.clear();
			for (width in [20., 15., 10., 6.]) {
				ring.graphics.lineStyle(width * 0.7 * ringWidth, COLOR, width == 20 ? 0.08 : width == 15 ? 0.15 : width == 10 ? 0.32 : 0.8);
				ring.graphics.drawCircle(0, 0, RADIUS * 0.78);
			}
			ring.graphics.lineStyle(3.15 * ringWidth, 0xFFFFFF, 1);
			ring.graphics.drawCircle(0, 0, RADIUS * 0.78);
			if (groundNeedle != null) {
				releaseGround();
				if (wantsGround())
					buildVisuals();
			}
		}
		positionArrow();
	}

	function positionArrow():Void {
		if (groundNeedle == null)
			return;
		var radius = RADIUS * 0.78 * 1.45;
		var shift = (radius * size + 6 + arrowOffset - (radius + 6) * arrowSize) / size;
		groundNeedle.scaleX = groundNeedle.scaleY = arrowSize / size;
		groundNeedle.x = Math.cos(groundNeedle.rotation) * shift;
		groundNeedle.y = Math.sin(groundNeedle.rotation) * shift;
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
		if (groundNeedle != null)
			groundNeedle.visible = hasHeading && !groundBoss.visible;
	}

	public function aim(dx:Float, dy:Float):Void {
		visible = true;
		if (groundNeedle == null)
			return;
		groundBoss.visible = false;
		if (Math.isFinite(dx) && Math.isFinite(dy) && dx * dx + dy * dy >= 64) {
			heading = Math.atan2(dy / FLATTEN, dx);
			directionX = dx;
			directionY = dy;
			if (!hasHeading)
				groundNeedle.rotation = heading;
			hasHeading = true;
			if (!smooth)
				groundNeedle.rotation = heading;
		}
		groundNeedle.visible = hasHeading;
		positionArrow();
	}

	public function turn(now:Int):Void {
		var elapsed = lastTurn == 0 ? 0 : Math.min(50, Math.max(0, now - lastTurn));
		lastTurn = now;
		if (groundNeedle == null || !visible || !hasHeading || groundBoss.visible)
			return;
		var delta = (heading - groundNeedle.rotation + Math.PI * 3) % (Math.PI * 2) - Math.PI;
		groundNeedle.rotation += smooth ? delta * (1 - Math.exp(-elapsed / (Math.abs(delta) > Math.PI * .65 ? 18. : 28.))) : delta;
		positionArrow();
		groundGuide.visible = false;
	}

	function buildRouteBatches(nextDisplay:Array<openfl.geom.Point>, mask:Array<Bool>):Array<RouteBatch> {
		var nextBatches:Array<RouteBatch> = [];
		for (layer in (reducedEffects ? 1 : 0)...2) {
			var color = layer == 0 ? 0x9564C7 : 0xE9D2FE;
			var width = (layer == 0 ? 11.52 : 5.4) * lineWidth;
			var opacity = layer == 0 ? 0.4032 : 0.95;
			var batch = RouteRibbon.batch(nextDisplay, color, width, opacity, !reducedEffects);
			batch.show(mask);
			nextBatches.push(batch);
		}
		return nextBatches;
	}

	public function setRoute(points:Array<openfl.geom.Point>, refreshWindow:Bool = false):Void {
		routeVisual.visible = displayMode == "ground_line" || displayMode == "line";
		if (!routeVisual.visible)
			return;
		if (points == null || points.length < 2)
			return;
		if (!refreshWindow && (motionTarget == points || (motionTarget == null && shownRoute == points)))
			return;
		if (rejectedRoute == points && Math.abs(x - rejectedX) + Math.abs(y - rejectedY) < 32)
			return;
		var meshStarted = haxe.Timer.stamp();
		// Prepare a complete replacement without touching the displayed meshes.
		var window = RouteWindow.cut(points, x, y, lineLength + 1000);
		var nextDisplay:Array<openfl.geom.Point> = [];
		nextDisplay.push(window[0]);
		for (i in 0...window.length - 1) {
			var a = window[i];
			var b = window[i + 1];
			var distance = openfl.geom.Point.distance(a, b);
			if (distance < 0.01)
				continue;
			var count = Std.int(Math.max(1, Math.ceil(distance / (reducedEffects ? 20 : 10))));
			for (j in 1...count + 1)
				nextDisplay.push(new openfl.geom.Point(a.x + (b.x - a.x) * j / count, a.y + (b.y - a.y) * j / count));
		}
		var mask = RouteVisibility.mask(nextDisplay, x, y, RouteVisibility.startDistance(lineStart, lineLength), lineLength);
		// A new prefix entirely inside the head fade must not erase a good line.
		if (!RouteVisibility.drawable(mask)) {
			if (stats != null) {
				stats.rejectedSwaps++;
				stats.event("blank-replacement", {x: x, y: y, points: points.length});
			}
			rejectedRoute = points;
			rejectedX = x;
			rejectedY = y;
			return;
		}
		rejectedRoute = null;
		var live = routeGrid != null;
		if (live && !refreshWindow && !reducedEffects && displayRoute.length > 1) {
			var matched = RouteMotion.match(displayRoute, nextDisplay, mask);
			if (matched != null) {
				var first = RouteMotion.frame(matched, nextDisplay, mask, 1. / 3., routeGrid, true);
				var second = first == null ? null : RouteMotion.frame(matched, nextDisplay, mask, 2. / 3., routeGrid);
				if (second != null) {
					motionTarget = points;
					motionEnd = nextDisplay;
					motionFrames = [first, second];
					motionMask = mask;
					motionFrame = 0;
					nextMotionFrame = openfl.Lib.getTimer();
					windowX = x;
					windowY = y;
					clearRouteHead();
					return;
				}
			}
		}
		cancelMotion();
		var nextBatches = buildRouteBatches(nextDisplay, mask);
		for (batch in nextBatches)
			routeVisual.addChild(batch.mesh);
		finishRouteFade();
		var hadHead = headBatches.length > 0;
		clearRouteHead();
		var previous = routeBatches;
		routeBatches = nextBatches;
		displayRoute = nextDisplay;
		shownRoute = points;
		windowX = x;
		windowY = y;
		blankMask = false;
		if (stats != null) {
			if (stats.swaps == 0 && stats.initialSearchStarted >= 0)
				stats.firstMeshDelayMs = (haxe.Timer.stamp() - stats.initialSearchStarted) * 1000;
			stats.swaps++;
			stats.event("route-swap", {
				x: x,
				y: y,
				sourcePoints: points.length,
				meshPoints: nextDisplay.length,
				windowRefresh: refreshWindow
			});
		}
		lastVisibilityX = x;
		lastVisibilityY = y;
		lastVisibilityTime = openfl.Lib.getTimer();
		if (!live && !refreshWindow && !reducedEffects && !hadHead && previous.length > 0) {
			fadingBatches = previous;
			fadingAlpha = [for (batch in previous) batch.mesh.alpha];
			arrivingAlpha = [for (batch in routeBatches) batch.mesh.alpha];
			fadeStarted = openfl.Lib.getTimer();
			for (batch in routeBatches)
				batch.mesh.alpha = 0;
		} else {
			for (batch in previous)
				batch.destroy();
		}
		if (stats != null) {
			var elapsed = (haxe.Timer.stamp() - meshStarted) * 1000;
			stats.meshMs += elapsed;
			stats.maximumMeshMs = Math.max(stats.maximumMeshMs, elapsed);
		}
	}

	public function hideRoute():Void {
		cancelMotion();
		if (stats != null && routeVisual.visible)
			stats.event("route-hidden", {x: x, y: y, shownPoints: shownRoute == null ? 0 : shownRoute.length});
		routeVisual.visible = false;
	}

	public function resetHeading():Void {
		hasHeading = false;
		releaseRoute();
		if (groundNeedle == null)
			return;
		groundNeedle.visible = false;
		groundBoss.visible = false;
		groundGuide.visible = false;
	}

	public function showBoss():Void {
		visible = true;
		routeVisual.visible = false;
		if (groundNeedle == null)
			return;
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
		for (texture in textures)
			texture.dispose();
		for (bitmap in bitmaps)
			bitmap.dispose();
		textures = [];
		bitmaps = [];
	}
}
