package mods.gate_compass;

import distributedObjects.DistributedDungeonFloor;
import distributedObjects.NPCGameObject;
import modding.ModSubscription;
import mods.api.Context;
import mods.api.Mod;
import mods.api.Subscription;
import mods.api.dungeon.Floor;
import mods.api.dungeon.Hero;
import mods.api.dungeon.Tile;
import openfl.Lib;
import openfl.ui.Keyboard;
import openfl.events.Event;
import distributedObjects.HeroGameObject;
import openfl.geom.Point;

class Main extends Mod {
	var ctx:Context;
	var lastLayer:String;
	var lastLayerDepth = -1;
	var menuPaused = false;
	var preferences:CompassPreferences;
	var palette:CompassPalette;
	var themeColor = 0x00DFFF;
	var toggleSetting:Subscription;
	var listening = false;
	var visualMode = "ground_line";
	var displayFlags:Array<CompassOption<Bool>> = [];
	var floating:FloatingCompass;
	var compassSize = 1.;
	var tools:CompassTools;
	var controls:Array<CompassControl> = [];
	var appearanceSubscriptions:Array<Dynamic> = [];
	var appearanceDirty = 0;

	var subscriptions:Array<Subscription> = [];
	var geometrySubscriptions:Array<ModSubscription> = [];
	var geometryDirty = true;
	var tileLayout = "";
	var startupRefresh = 0;
	var startupPass = 0;
	var nextSearch = 0;
	var panel:Compass;
	var lastRegion = "";
	var hero:Hero;
	var floorId:UInt = 0;
	var grid:WalkGrid;
	var goal:Tile;
	var gate:Point;
	var gateId:UInt = 0;
	var waypoint:Point;
	var bossRoom = false;
	var nextGeometry = 0;
	var lastObstacleRefresh = 0;
	var nextUpdate = 0;
	// Average frame time, so background route work can be split evenly across frames.
	var lastFrameAt = 0;
	var frameMs = 16.7;
	var lastCell = -1;
	var lastSearchRoom:Tile;
	var lastSearchX = 0.;
	var lastSearchY = 0.;

	override public function init(context:Context):Void {
		ctx = context;
		preferences = new CompassPreferences(context.data, function(message) context.log(message));
		var lowPower = preferences.flag("lowPower", false);
		var legacyEffects = preferences.flag("reducedEffects", false);
		if (legacyEffects.value) {
			lowPower.value = true;
			legacyEffects.value = false;
			preferences.flush();
		}
		displayFlags = [
			preferences.flag("show2D", false),
			preferences.flag("show3D", true),
			preferences.flag("showPathfinder", true),
			preferences.flag("smoothCompass", true),
			lowPower,
			lowPower
		];
		var keys = ["show2D", "show3D", "showPathfinder", "smoothCompass", "lowPower"];
		var titles = [
			"Enable 2D Compass",
			"Enable 3D Compass",
			"Enable Pathfinder line",
			"Smooth Compass",
			"Low power mode"
		];
		for (i in 0...keys.length) {
			var local = displayFlags[i == 4 ? 5 : i];
			var native = context.settings.flag(keys[i], titles[i], "", local.value);
			// Migrate the previous panel value once; the API owns future switch saves.
			var migration = preferences.flag("nativeSwitchesV1", false);
			if (!migration.value)
				native.value = local.value;
			else
				local.value = native.value;
			appearanceSubscriptions.push(native.onChange(function(value) {
				local.value = value;
				preferences.flush();
			}));
		}
		preferences.flag("nativeSwitchesV1", false).value = true;
		preferences.flush();
		appearanceSubscriptions.push(context.settings.button("openCompassSettings", "Adjust appearance", "Open").onPress(openTools));
		appearanceSubscriptions.push(context.keys.action("openCompassPanel", "Adjust compass appearance", "Open the live appearance sliders.", Keyboard.G,
			true, true)
			.onPress(openTools));
		for (index in 0...displayFlags.length) {
			if (index == 4)
				continue;
			var flag = displayFlags[index];
			appearanceSubscriptions.push(flag.onChange(function(_) {
				updateDisplays();
			}));
		}
		updateDisplays();
		var circle = preferences.slider("circleScaleV3", 1, 0.5, 4);
		var arrow = preferences.slider("arrowScale", 1, 0.5, 3);
		var route = preferences.slider("pathfinderWidthV2", 1, 0.25, 3);
		var stroke = preferences.slider("circleStrokeV2", 1, 0.25, 3);
		var offset = preferences.slider("arrowOffsetV2", 0, -20, 100);
		var length = preferences.slider("pathfinderLength", 2200, 300, 2200);
		var lineStart = preferences.slider("lineStartDistance", 135, 0, 500);
		controls = [
			new CompassControl("Circle size", circle, 0.5, 4),
			new CompassControl("Arrow size", arrow, 0.5, 3),
			new CompassControl("Pathfinder width", route, 0.25, 3),
			new CompassControl("Circle width", stroke, 0.25, 3),
			new CompassControl("Arrow distance", offset, -20, 100, 0),
			new CompassControl("Line length", length, 300, 2200, 2200, 50),
			new CompassControl("Line start distance", lineStart, 0, 500, 135, 5)
		];
		for (control in controls)
			appearanceSubscriptions.push(control.option.onChange(function(_) {
				appearanceDirty = Lib.getTimer() + 120;
			}));
		toggleSetting = context.keys.action("compassToggle", "Compass Toggle",
			"Turn Gate Compass on or off. Off releases route caches and drawing resources.", Keyboard.Q, true, true)
			.onPress(function() {
				var enabled = !listening;
				setEnabled(enabled);
				try {
					sys.io.File.saveContent(ctx.data + "/compass-enabled.json", haxe.Json.stringify({enabled: enabled}));
				} catch (error:Dynamic) {
					ctx.log("Could not save the on/off state: " + Std.string(error));
				}
			});
		var enabled = true;
		var enabledFile = ctx.data + "/compass-enabled.json";
		try {
			if (sys.FileSystem.exists(enabledFile)) {
				var saved:Dynamic = haxe.Json.parse(sys.io.File.getContent(enabledFile));
				if (saved.enabled == false)
					enabled = false;
			}
		} catch (error:Dynamic) {
			ctx.log("Could not read the on/off state: " + Std.string(error));
		}
		setEnabled(enabled);
	}

	function applyAppearance():Void {
		preferences.flush();
		if (panel == null || controls.length < 7)
			return;
		// Normalized multipliers: 1x matches the approved appearance baseline.
		panel.configure(controls[0].option.value, controls[1].option.value, controls[2].option.value * 1.8, controls[3].option.value * 2,
			controls[4].option.value);
		panel.setLineLength(controls[5].option.value);
		panel.setLineStart(controls[6].option.value);
		appearanceDirty = 0;
	}

	function updateDisplays():Void {
		if (displayFlags.length < 4)
			return;
		var ground = displayFlags[1].value;
		var path = displayFlags[2].value;
		if (!displayFlags[0].value && !ground && !path) {
			stopNavigation();
			return;
		}
		if (panel == null && listening && floorId != 0)
			startNavigation();
		visualMode = ground ? (path ? "ground_line" : "ground") : (path ? "line" : "flat");
		if (panel != null) {
			panel.setDisplayMode(visualMode);
			panel.smooth = displayFlags[3].value;
			panel.setReducedEffects(displayFlags[4].value || displayFlags[5].value);
			if (grid != null)
				grid.lowPower = displayFlags[5].value;
		}
		updateFloating();
		if (floating != null)
			floating.smooth = displayFlags[3].value;
		nextGeometry = 0;
		nextSearch = 0;
		lastCell = -1;
	}

	function updateFloating():Void {
		if (displayFlags[0].value && panel != null) {
			if (floating == null) {
				floating = new FloatingCompass(ctx);
				floating.setThemeColor(themeColor);
				ctx.overlay.addChild(floating);
			}
			floating.visible = panel.visible;
		} else if (floating != null) {
			floating.destroy();
			if (floating.parent != null)
				floating.parent.removeChild(floating);
			floating = null;
		}
	}

	function setEnabled(enabled:Bool):Void {
		if (enabled && !listening) {
			listening = true;
			subscriptions.push(ctx.onFloorEnter(onFloorEnter));
			subscriptions.push(ctx.onFloorExit(function(_) clearFloor()));
			subscriptions.push(ctx.onHeroSpawned(trackHero));
			subscriptions.push(ctx.onHeroDespawned(function(h) {
				if (h == hero) {
					hero = null;
					if (panel != null)
						panel.visible = false;
					if (floating != null)
						floating.visible = false;
					if (panel != null)
						panel.detach();
				}
			}));
			if (ctx.state.floor != null)
				onFloorEnter(ctx.state.floor);
		} else if (!enabled && listening) {
			listening = false;
			for (subscription in subscriptions)
				subscription.cancel();
			subscriptions = [];
			for (subscription in geometrySubscriptions)
				subscription.cancel();
			geometrySubscriptions = [];
			clearFloor();
		}
	}

	function openTools():Void {
		if (tools == null) {
			tools = new CompassTools(ctx, controls, applyAppearance);
			ctx.overlay.addChild(tools);
		}
		tools.setShown(true);
	}

	function startMatchResources():Void {
		updateDisplays();
	}

	function startNavigation():Void {
		palette = new CompassPalette(ctx);
		panel = new Compass(ctx);
		panel.setThemeColor(themeColor);
		applyAppearance();
		grid = new WalkGrid();
		panel.routeGrid = grid;
		grid.lowPower = displayFlags[5].value;
		for (h in ctx.state.heroes)
			trackHero(h);
		geometrySubscriptions.push(ctx.core.onObjectReady(collisionActorChanged));
		geometrySubscriptions.push(ctx.core.onObjectGone(collisionActorChanged));
		geometrySubscriptions.push(ctx.core.onFieldReceived(function(obj, id, name) {
			if (floorId != 0
				&& Std.isOfType(obj, DistributedDungeonFloor)
				&& (cast obj : DistributedDungeonFloor).id == floorId
					&& (StringTools.endsWith(name, ".tiles") || StringTools.endsWith(name, ".tileLibrary"))) {
				geometryDirty = true;
				nextGeometry = 0;
			}
			// Traps are persistent avoidance zones, including their inactive phase.
			// Their trigger cycles do not change collision geometry.
			if (StringTools.endsWith(name, ".triggerState")) {
				var npc = Std.downcast(obj, NPCGameObject);
				if (npc == null || npc.gmNpc == null || npc.gmNpc.Species != "TRAP")
					collisionActorChanged(obj);
			}
			if (floorId != 0 && (StringTools.endsWith(name, ".floorEnding") || StringTools.endsWith(name, ".dungeonEnding"))) {
				var floor = liveFloor();
				if (floor != null && obj == floor.parentArea)
					clearFloor();
			}
		}));
		ctx.overlay.addEventListener(Event.ENTER_FRAME, update);
	}

	function stopNavigation():Void {
		ctx.overlay.removeEventListener(Event.ENTER_FRAME, update);
		for (subscription in geometrySubscriptions)
			subscription.cancel();
		geometrySubscriptions = [];
		if (grid != null) {
			grid.clear();
		}
		grid = null;
		if (floating != null) {
			floating.destroy();
			if (floating.parent != null)
				floating.parent.removeChild(floating);
			floating = null;
		}
		if (panel != null) {
			panel.destroy();
			panel = null;
		}
		hero = null;
		palette = null;
		goal = null;
		gate = null;
		gateId = 0;
		waypoint = null;

		lastSearchRoom = null;
		tileLayout = "";
		geometryDirty = true;
		startupRefresh = 0;
		startupPass = 0;
		lastRegion = "";
		nextGeometry = 0;
		nextSearch = 0;
		nextUpdate = 0;
		lastCell = -1;
		appearanceDirty = 0;
	}

	function trackHero(h:Hero):Void {
		if (h.local)
			hero = h;
	}

	function collisionActorChanged(object:Dynamic):Void {
		if (floorId == 0)
			return;
		var npc = Std.downcast(object, NPCGameObject);
		if (npc != null
			&& npc.distributedDungeonFloor == liveFloor()
			&& npc.gmNpc != null
			&& Std.string(npc.gmNpc.Constant).toUpperCase().indexOf("EXIT") >= 0) {
			geometryDirty = true;
			nextGeometry = 0;
		}
		if (npc != null && npc.isProp && npc.gmNpc != null && npc.gmNpc.IsAttackable && npc.gmNpc.Species != "TRAP")
			return;
		if (npc != null
			&& npc.distributedDungeonFloor == liveFloor()
			&& npc.gmNpc != null
			&& (npc.gmNpc.Species == "DOOR" || npc.gmNpc.Species == "TRAP" || npc.isProp)) {
			geometryDirty = true;
		}
	}

	function onFloorEnter(floor:Floor):Void {
		clearFloor();
		if (!listening || floor == null)
			return;
		floorId = floor.id;
		startMatchResources();
	}

	function clearFloor():Void {
		for (subscription in geometrySubscriptions)
			subscription.cancel();
		geometrySubscriptions = [];
		floorId = 0;
		goal = null;
		gate = null;
		gateId = 0;
		waypoint = null;

		bossRoom = false;
		nextGeometry = 0;
		geometryDirty = true;
		tileLayout = "";
		startupRefresh = 0;
		startupPass = 0;
		nextSearch = 0;
		nextUpdate = 0;
		lastCell = -1;
		lastSearchRoom = null;
		lastRegion = "";
		stopNavigation();

		hero = null;
	}

	function liveFloor():DistributedDungeonFloor {
		var facade = ctx.core.facade;
		var objects = facade == null ? null : facade.gameObjectManager;
		return floorId == 0 || objects == null ? null : Std.downcast(objects.getReferenceFromId(floorId), DistributedDungeonFloor);
	}

	function update(event:Event):Void {
		var now = Lib.getTimer();
		if (lastFrameAt > 0) {
			var step = now - lastFrameAt;
			if (step > 0 && step < 100)
				frameMs += (step - frameMs) * 0.1;
		}
		lastFrameAt = now;
		updateNavigation(event);
	}

	/**
	 * Share of the per-update route budget for one frame. At 160 FPS a frame is about 6 ms, so each frame
	 * gets about 40% of the budget and runs every frame instead of every 16 ms: the same work per second,
	 * without a 1.5 ms chunk landing in a single short frame.
	 */
	public static function frameShare(frameMs:Float, intervalMs:Float):Float
		return Math.min(1., Math.max(0.15, frameMs / intervalMs));

	function updateNavigation(event:Event):Void {
		if (panel == null || grid == null)
			return;
		var now = Lib.getTimer();
		if (appearanceDirty > 0 && now >= appearanceDirty)
			applyAppearance();
		var hasDisplay = displayFlags[0].value || displayFlags[1].value || displayFlags[2].value;
		var facade = ctx.core.facade;
		if (floorId == 0
			|| facade == null
			|| facade.mainStateMachine == null
			|| facade.mainStateMachine.currentStateName != "RunState"
			|| facade.gameObjectManager == null) {
			panel.visible = false;
			if (floating != null)
				floating.visible = false;
			return;
		}
		var floor = liveFloor();
		if (floor == null || floor.isDestroyed) {
			panel.visible = false;
			if (floating != null)
				floating.visible = false;
			return;
		}

		var navigation = facade.menuNavigationController;
		if (navigation != null) {
			var top = navigation.getTopUILayer();
			var depth:Int = navigation.layerDepth;
			if (top != lastLayer || depth != lastLayerDepth) {
				lastLayer = top;
				lastLayerDepth = depth;
				menuPaused = CompassPause.blocked(top, depth > 1 ? navigation.getAllCurrentLayers() : null);
			}
		} else
			menuPaused = false;
		if (menuPaused) {
			panel.visible = false;
			if (floating != null)
				floating.visible = false;
			return;
		}

		// Hidden UI must not keep spending its route-search budget.
		panel.turn(now);
		if (floating != null)
			floating.turn(now);
		var interval = displayFlags[5].value ? 33 : 16;
		if (hasDisplay && hero != null) {
			grid.prioritize(hero.x, hero.y);
			if (grid.advanceField(frameShare(frameMs, interval))) {
				nextSearch = 0;
				lastCell = -1;
			}
		}
		if (now < nextUpdate)
			return;
		nextUpdate = now + interval;

		if (hero != null) {
			var object = Std.downcast(facade.gameObjectManager.getReferenceFromId(hero.id), HeroGameObject);
			if (object != null && object.heroView != null)
				panel.attach(object.heroView);
		}
		if (!hasDisplay) {
			panel.visible = false;
			return;
		}
		if (!panel.visible)
			panel.showIdle();
		if (floating != null)
			floating.visible = displayFlags[0].value;
		if (now >= nextGeometry) {
			if (hero == null)
				for (h in ctx.state.heroes)
					trackHero(h);
			if (refreshGeometry(floor, now)) {
				lastCell = -1;
				nextSearch = 0;
			}
			nextGeometry = now + (goal == null || floor.box2DWorld == null ? 120 : 300);
		}
		if (!NavigationGoal.verified(goal, gate != null) || hero == null) {
			panel.hideRoute();
			panel.visible = false;
			if (floating != null)
				floating.visible = false;
			return;
		}

		var x = hero.x;
		var y = hero.y;
		if (bossRoom && gate == null && goal.contains(x, y)) {
			panel.hideRoute();
			panel.showBoss();
			if (floating != null && displayFlags[0].value)
				floating.showBoss();
			return;
		}
		var movedSinceSearch = Math.abs(x - lastSearchX) + Math.abs(y - lastSearchY) >= 1;
		var nearWaypoint = movedSinceSearch && waypoint != null && waypoint != gate
			&& (waypoint.x - x) * (waypoint.x - x) + (waypoint.y - y) * (waypoint.y - y) <= 18 * 18;
		if (movedSinceSearch
			&& waypoint != null
			&& waypoint != gate
			&& (nearWaypoint || passedWaypoint(lastSearchX, lastSearchY, x, y, waypoint))) {
			// The hero crossed the target between route searches. Keep the
			// current heading until a forward waypoint is available.
			grid.invalidateRoute();
			waypoint = null;

			lastCell = -1;
			nextSearch = 0;
		}

		var cell = grid.cellAt(x, y);
		var room = grid.roomAtCell(cell);
		var enteredRoom = room != null && room != lastSearchRoom;
		var region = grid.regionAt(x, y);
		var movedWhileIdle = waypoint == null && (Math.abs(x - lastSearchX) >= 8 || Math.abs(y - lastSearchY) >= 8);
		// Resample the cached route while moving, including within one cell.
		// The normal cooldown still applies to movement inside a room.
		// A doorway crossing gets a fresh target immediately.
		var urgentSearch = RouteClock.urgent(x - lastSearchX, y - lastSearchY, nearWaypoint, enteredRoom);
		if (urgentSearch
			|| (now >= nextSearch && (movedSinceSearch || cell != lastCell || movedWhileIdle || nearWaypoint || waypoint == null))) {
			if (enteredRoom)
				grid.invalidateRoute();
			lastRegion = region;
			lastSearchRoom = room;
			lastSearchX = x;
			lastSearchY = y;
			nextSearch = now + RouteClock.interval(displayFlags[5].value);
			lastCell = cell;
			waypoint = grid.waypoint(x, y, goal, gate, gateId);
			if (waypoint == null)
				nextSearch = now + 250;
		}
		// A cached line remains drawable even if the current tangent cannot
		// be sampled while crossing a cell or awaiting another anchor.
		if (grid.visualRoute.length > 1)
			panel.setRoute(grid.visualRoute);
		else
			panel.hideRoute();
		if (waypoint == null) {
			panel.showIdle();
			if (floating != null && displayFlags[0].value)
				floating.showIdle();
			return;
		}
		panel.aim(grid.routeDirection.x, grid.routeDirection.y);
		if (floating != null && displayFlags[0].value)
			floating.aim(grid.routeDirection.x, grid.routeDirection.y);
	}

	static function passedWaypoint(fromX:Float, fromY:Float, x:Float, y:Float, target:Point):Bool {
		var dx = target.x - fromX;
		var dy = target.y - fromY;
		return (dx != 0 || dy != 0) && (target.x - x) * dx + (target.y - y) * dy <= 0;
	}

	function refreshGeometry(floor:DistributedDungeonFloor, now:Int):Bool {
		var current = ctx.state.floor;
		if (current == null || current.id != floorId || floor.box2DWorld == null)
			return false;
		if (!geometryDirty && tileLayout != "" && (startupRefresh <= 0 || now < startupRefresh))
			return false;
		var oldGoal = goal;
		var oldGate = gate;
		var oldGateId = gateId;
		var tiles = [for (tile in current.tiles) if (tile.category != "FILLER_TILE") tile];
		var parts = [
			for (tile in tiles)
				tile.id + ":" + tile.x + ":" + tile.y + ":" + tile.category + ":" + tile.exits.join(",")
		];
		parts.sort(Reflect.compare);
		var layout = parts.join("|");
		var delayedRefresh = startupRefresh > 0 && now >= startupRefresh;
		if (tileLayout == layout && geometryDirty && !delayedRefresh && now - lastObstacleRefresh < 1000)
			return false;
		if (!geometryDirty && tileLayout == layout && !delayedRefresh)
			return false;
		if (tileLayout == "" && layout != "")
			startupRefresh = now + 650;
		if (delayedRefresh) {
			startupPass++;
			startupRefresh = startupPass < 3 ? now + 900 : -1;
		}
		var obstaclesChanged = geometryDirty || delayedRefresh;
		tileLayout = layout;
		geometryDirty = false;
		goal = null;
		gate = null;
		gateId = 0;
		bossRoom = false;
		goal = NavigationGoal.choose(tiles);
		if (goal == null) {
			grid.clear();
			waypoint = null;
			return oldGoal != null;
		}

		// These two authored exit rooms complete the floor through the boss life trigger.
		bossRoom = NavigationGoal.boss(goal);
		var gateScore = 0;
		if (floor.remoteActors != null)
			for (object in floor.remoteActors.toArray()) {
				var npc = Std.downcast(object, NPCGameObject);
				if (npc == null || npc.isDestroyed || npc.gmNpc == null || npc.position == null)
					continue;
				var p = npc.position;
				if (!goal.contains(p.x, p.y))
					continue;
				var kind = Std.string(npc.gmNpc.Constant).toUpperCase();
				var type:Int = npc.type;
				var suffix = type % 10000;
				var score = kind == "JASONS_DUNGEON_EXIT" ? 3 : kind.indexOf("EXIT") >= 0
					&& (kind.indexOf("GATE") >= 0 || suffix == 101 || suffix == 201) ? 2 : !bossRoom
						&& type >= 2000000
						&& type < 3000000
						&& (suffix == 101 || suffix == 201) ? 1 : 0;
				if (score > gateScore) {
					gate = new Point(p.x, p.y);
					gateId = npc.id;
					gateScore = score;
				}
			}
		if (palette != null) {
			themeColor = palette.detect(ctx);
			panel.setThemeColor(themeColor);
			if (floating != null)
				floating.setThemeColor(themeColor);
		}
		lastObstacleRefresh = now;
		grid.refresh(floor, tiles);
		if (NavigationGoal.verified(goal, gate != null))
			grid.prepareField(goal, gate, gateId);
		else
			grid.forgetGoal();
		// Thin collision shapes can change the edges without changing any cell center.
		waypoint = null;

		var gateChanged = oldGateId != gateId || (oldGate == null ? gate != null : (gate == null || !oldGate.equals(gate)));
		if (!gateChanged)
			gate = oldGate;
		return true;
	}

	override public function dispose():Void {
		if (preferences != null)
			preferences.flush();
		for (subscription in appearanceSubscriptions)
			subscription.cancel();
		appearanceSubscriptions = [];

		if (toggleSetting != null)
			toggleSetting.cancel();
		toggleSetting = null;
		if (listening)
			setEnabled(false);
		if (tools != null) {
			tools.destroy();
			tools = null;
		}
	}
}
