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
import mods.api._internal.Hub;
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
	var setting:Subscription;
	var toggleSetting:Subscription;
	var listening = false;
	var modeSetting:Subscription;
	var visualMode = "ground_line";
	var displayFlags:Array<CompassOption<Bool>> = [];
	var floating:FloatingCompass;
	var sizeSetting:Subscription;
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
	var lastCell = -1;
	var lastSearchRoom:Tile;
	var lastSearchX = 0.;
	var lastSearchY = 0.;
	var checkedWaypoint:Point;
	var checkedX = 0.;
	var checkedY = 0.;

	override public function init(context:Context):Void {
		ctx = context;
		preferences = new CompassPreferences(context.data);
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
		appearanceSubscriptions.push(context.settings.button("openCompassSettings", "Compass settings", "Settings").onPress(openTools));
		appearanceSubscriptions.push(context.keys.action("openCompassPanel", "Open compass settings", "Open the live compass settings panel.", Keyboard.G,
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
				} catch (_:Dynamic) {}
			});
		var enabled = true;
		try {
			var saved:Dynamic = haxe.Json.parse(sys.io.File.getContent(ctx.data + "/compass-enabled.json"));
			if (saved.enabled == false)
				enabled = false;
		} catch (_:Dynamic) {}
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
			tools = new CompassTools(ctx, controls, [
				displayFlags[0],
				displayFlags[1],
				displayFlags[2],
				displayFlags[3],
				displayFlags[5]
			], applyAppearance);
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
		panel.stats = grid.stats;
		panel.routeGrid = grid;
		grid.lowPower = displayFlags[5].value;
		for (h in ctx.state.heroes)
			trackHero(h);
		geometrySubscriptions.push(ctx.core.onObjectReady(collisionActorChanged));
		geometrySubscriptions.push(ctx.core.onObjectGone(collisionActorChanged));
		geometrySubscriptions.push(ctx.core.onFieldReceived(function(obj, id, name) {
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
		checkedWaypoint = null;
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
		checkedWaypoint = null;
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
		updateNavigation(event);
	}

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
		if (now < nextUpdate)
			return;
		nextUpdate = now + (displayFlags[5].value ? 33 : 16);
		if (hasDisplay && hero != null) {
			grid.prioritize(hero.x, hero.y);
			if (grid.advanceField()) {
				nextSearch = 0;
				lastCell = -1;
			}
		}

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
			var geometryStarted = haxe.Timer.stamp();
			if (refreshGeometry(floor, now)) {
				var elapsed = (haxe.Timer.stamp() - geometryStarted) * 1000;
				grid.stats.geometryMs += elapsed;
				grid.stats.maximumGeometryMs = Math.max(grid.stats.maximumGeometryMs, elapsed);
				lastCell = -1;
				nextSearch = 0;
			}
			nextGeometry = now + (goal == null || floor.box2DWorld == null ? 120 : 300);
		}
		if (goal == null || hero == null) {
			panel.visible = false;
			if (floating != null)
				floating.visible = false;
			return;
		}

		var x = hero.x;
		var y = hero.y;
		if (bossRoom && gate == null && goal.contains(x, y)) {
			panel.showBoss();
			if (floating != null && displayFlags[0].value)
				floating.showBoss();
			return;
		}
		var movedSinceSearch = Math.abs(x - lastSearchX) + Math.abs(y - lastSearchY) >= 1;
		var nearWaypoint = movedSinceSearch && waypoint != null && waypoint != gate && Point.distance(new Point(x, y), waypoint) <= 18;
		if (movedSinceSearch
			&& waypoint != null
			&& waypoint != gate
			&& (nearWaypoint || passedWaypoint(lastSearchX, lastSearchY, x, y, waypoint))) {
			// The hero crossed the target between route searches. Keep the
			// current heading until a forward waypoint is available.
			grid.invalidateRoute();
			waypoint = null;
			checkedWaypoint = null;
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
		if (grid.stats.firstCompassDelayMs < 0 && grid.stats.initialSearchStarted >= 0)
			grid.stats.firstCompassDelayMs = (haxe.Timer.stamp() - grid.stats.initialSearchStarted) * 1000;
		panel.aim(grid.routeDirection.x, grid.routeDirection.y);
		if (floating != null && displayFlags[0].value)
			floating.aim(grid.routeDirection.x, grid.routeDirection.y);
	}

	static function passedWaypoint(fromX:Float, fromY:Float, x:Float, y:Float, target:Point):Bool {
		var dx = target.x - fromX;
		var dy = target.y - fromY;
		return (dx != 0 || dy != 0) && (target.x - x) * dx + (target.y - y) * dy <= 0;
	}

	function canDisplayWaypoint(x:Float, y:Float):Bool {
		if (waypoint == checkedWaypoint && x == checkedX && y == checkedY)
			return true;
		if (!grid.isGentleDirection(x, y, waypoint) && !grid.canAim(x, y, waypoint, waypoint == gate ? gateId : 0))
			return false;
		checkedWaypoint = waypoint;
		checkedX = x;
		checkedY = y;
		return true;
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
		for (tile in tiles) {
			if (tile.category == "EXIT_TILE")
				goal = tile;
			else if (goal == null && tile.category == "BOSS_TILE")
				goal = tile;
		}
		if (goal == null) {
			grid.clear();
			waypoint = null;
			return oldGoal != null;
		}

		// These two authored exit rooms complete the floor through the boss life trigger.
		bossRoom = goal.category == "BOSS_TILE" || goal.id == "454.1334956026168" || goal.id == "271.1333708475942";
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
		grid.prepareField(goal, gate, gateId);
		// Thin collision shapes can change the edges without changing any cell center.
		waypoint = null;
		checkedWaypoint = null;
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
		if (modeSetting != null)
			modeSetting.cancel();
		modeSetting = null;
		if (sizeSetting != null)
			sizeSetting.cancel();
		sizeSetting = null;
		if (setting != null)
			setting.cancel();
		setting = null;
		if (listening)
			setEnabled(false);
		if (tools != null) {
			tools.destroy();
			tools = null;
		}
	}
}
