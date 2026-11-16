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
import openfl.events.Event;
import openfl.events.MouseEvent;
import openfl.geom.Point;

class Main extends Mod {
    var ctx:Context;
    var setting:Subscription;
    var subscriptions:Array<Subscription> = [];
    var geometrySubscriptions:Array<ModSubscription> = [];
    var geometryDirty = true;
    var tileLayout = "";
    var startupRefresh = 0;
    var nextSearch = 0;
    var panel:Compass;
    var captures:RouteCapture;
    var blankSince = -1;
    var autoCaptured = false;
    var nextManualCapture = 0;
    var hero:Hero;
    var floorId:UInt = 0;
    var grid:WalkGrid;
    var goal:Tile;
    var gate:Point;
    var gateId:UInt = 0;
    var waypoint:Point;
    var bossRoom = false;
    var nextGeometry = 0;
    var nextUpdate = 0;
    var lastCell = -1;
    var lastSearchRoom:Tile;
    var lastSearchX = 0.;
    var lastSearchY = 0.;
    var checkedWaypoint:Point;
    var checkedX = 0.;
    var checkedY = 0.;
    var reportedRouteStates:Map<String, Bool> = new Map();

    override public function init(context:Context):Void {
        ctx = context;
        captures = new RouteCapture(context.data);
        var enabled = context.settings.flag("enableCompass", "Enable Gate Compass", "Show directions to the dungeon exit.", true);
        setting = enabled.onChange(setEnabled);
        setEnabled(enabled.value);
    }

    function setEnabled(enabled:Bool):Void {
        if (enabled && panel == null) {
            panel = new Compass(ctx);
            panel.addEventListener(MouseEvent.RIGHT_CLICK, captureManually);
            grid = new WalkGrid();
            ctx.overlay.addChild(panel);
            subscriptions.push(ctx.onFloorEnter(onFloorEnter));
            subscriptions.push(ctx.onFloorExit(function(_) clearFloor()));
            subscriptions.push(ctx.onHeroSpawned(trackHero));
            geometrySubscriptions.push(ctx.core.onObjectReady(collisionActorChanged));
            geometrySubscriptions.push(ctx.core.onObjectGone(collisionActorChanged));
            geometrySubscriptions.push(ctx.core.onFieldReceived(function(obj, id, name) {
                if (StringTools.endsWith(name, ".triggerState")) collisionActorChanged(obj);
                if (floorId != 0 && (StringTools.endsWith(name, ".floorEnding")
                    || StringTools.endsWith(name, ".dungeonEnding"))) {
                    var floor = liveFloor();
                    if (floor != null && obj == floor.parentArea) clearFloor();
                }
            }));
            subscriptions.push(ctx.onHeroDespawned(function(h) {
                if (h == hero) hero = null;
            }));
            for (h in ctx.state.heroes) trackHero(h);
            if (ctx.state.floor != null) onFloorEnter(ctx.state.floor);
            ctx.overlay.addEventListener(Event.ENTER_FRAME, update);
        } else if (!enabled && panel != null) {
            ctx.overlay.removeEventListener(Event.ENTER_FRAME, update);
            for (subscription in subscriptions) subscription.cancel();
            subscriptions = [];
            for (subscription in geometrySubscriptions) subscription.cancel();
            geometrySubscriptions = [];
            clearFloor();
            hero = null;
            grid = null;
            panel.removeEventListener(MouseEvent.RIGHT_CLICK, captureManually);
            panel.destroy();
            ctx.overlay.removeChild(panel);
            panel = null;
        }
    }

    function trackHero(h:Hero):Void {
        if (h.local) hero = h;
    }

    function collisionActorChanged(object:Dynamic):Void {
        if (floorId == 0) return;
        var npc = Std.downcast(object, NPCGameObject);
        if (npc != null && npc.gmNpc != null
            && (npc.gmNpc.Species == "DOOR" || (npc.gmNpc.Species != "TRAP" && npc.isProp))) {
            geometryDirty = true;
        }
    }

    function onFloorEnter(floor:Floor):Void {
        clearFloor();
        floorId = floor.id;
    }

    function clearFloor():Void {
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
        nextSearch = 0;
        nextUpdate = 0;
        lastCell = -1;
        lastSearchRoom = null;
        reportedRouteStates = new Map();
        blankSince = -1;
        autoCaptured = false;
        if (grid != null) grid.clear();
        if (panel != null) {
            panel.visible = false;
            panel.resetHeading();
        }
    }

    function liveFloor():DistributedDungeonFloor {
        var facade = ctx.core.facade;
        var objects = facade == null ? null : facade.gameObjectManager;
        return floorId == 0 || objects == null ? null
            : Std.downcast(objects.getReferenceFromId(floorId), DistributedDungeonFloor);
    }

    function update(event:Event):Void {
        var now = Lib.getTimer();
        panel.turn(now);
        if (now < nextUpdate) return;
        nextUpdate = now + 65;
        var facade = ctx.core.facade;
        if (floorId == 0 || facade == null || facade.mainStateMachine == null
            || facade.mainStateMachine.currentStateName != "RunState" || facade.gameObjectManager == null) {
            panel.visible = false;
            return;
        }
        var floor = liveFloor();
        if (floor == null || floor.isDestroyed) {
            panel.visible = false;
            return;
        }

        var navigation = facade.menuNavigationController;
        if (navigation != null && (navigation.getTopUILayer() == "EXIT_DUNGEON"
            || (navigation.layerDepth > 1 && navigation.getAllCurrentLayers().indexOf("EXIT_DUNGEON, ") >= 0))) {
            panel.visible = false;
            blankSince = -1;
            return;
        }

        if (!panel.visible) panel.showIdle();
        if (now >= nextGeometry) {
            if (hero == null) for (h in ctx.state.heroes) trackHero(h);
            if (refreshGeometry(floor, now)) {
                lastCell = -1;
                nextSearch = 0;
            }
            nextGeometry = now + (goal == null || floor.box2DWorld == null ? 120 : 300);
        }
        if (goal == null || hero == null) {
            var reason = goal == null ? "waiting for exit tile or collision world" : "waiting for local hero";
            reportRouteState(reason);
            panel.showIdle();
            captureIfBlank(now, reason);
            return;
        }

        var x = hero.x;
        var y = hero.y;
        if (bossRoom && gate == null && goal.contains(x, y)) {
            blankSince = -1;
            panel.showBoss();
            return;
        }
        if (waypoint != null && waypoint != gate
            && passedWaypoint(lastSearchX, lastSearchY, x, y, waypoint)) {
            // The hero crossed the target between route searches. Keep the
            // current heading until a forward waypoint is available.
            waypoint = null;
            checkedWaypoint = null;
            lastCell = -1;
        }

        var cell = grid.cellAt(x, y);
        var room = grid.roomAtCell(cell);
        var enteredRoom = room != null && room != lastSearchRoom;
        var movedWhileIdle = waypoint == null
            && (Math.abs(x - lastSearchX) >= 8 || Math.abs(y - lastSearchY) >= 8);
        // The normal cooldown still applies to movement inside a room.
        // A doorway crossing gets a fresh target immediately.
        if (enteredRoom || (now >= nextSearch && (cell != lastCell || movedWhileIdle))) {
            lastSearchRoom = room;
            lastSearchX = x;
            lastSearchY = y;
            nextSearch = now + 180;
            lastCell = cell;
            waypoint = grid.waypoint(x, y, goal, gate, gateId);
            if (waypoint == null) reportRouteState(grid.routeStatus);
        }
        if (waypoint == null || !canDisplayWaypoint(x, y)) {
            var reason = waypoint == null ? grid.routeStatus : "display segment blocked";
            if (waypoint != null) {
                reportRouteState("display segment blocked");
                lastCell = -1;
                waypoint = null;
                grid.invalidateRoute();
            }
            panel.showIdle();
            captureIfBlank(now, reason);
            return;
        }
        blankSince = -1;
        panel.aim(waypoint.x - x, waypoint.y - y);
    }

    static function passedWaypoint(fromX:Float, fromY:Float, x:Float, y:Float, target:Point):Bool {
        var dx = target.x - fromX;
        var dy = target.y - fromY;
        return (dx != 0 || dy != 0) && (target.x - x) * dx + (target.y - y) * dy <= 0;
    }

    function canDisplayWaypoint(x:Float, y:Float):Bool {
        if (waypoint == checkedWaypoint && x == checkedX && y == checkedY) return true;
        if (!grid.isGentleDirection(x, y, waypoint)
            && !grid.canAim(x, y, waypoint, waypoint == gate ? gateId : 0)) return false;
        checkedWaypoint = waypoint;
        checkedX = x;
        checkedY = y;
        return true;
    }

    function captureIfBlank(now:Int, reason:String):Void {
        if (autoCaptured) return;
        if (blankSince < 0) blankSince = now;
        if (now - blankSince < 2000) return;
        autoCaptured = true;
        saveCapture(panel.displayedHeading() == null ? "blank-arrow" : "held-heading", reason);
    }

    function captureManually(event:MouseEvent):Void {
        event.stopPropagation();
        var now = Lib.getTimer();
        if (now < nextManualCapture) return;
        nextManualCapture = now + 1000;
        saveCapture("manual", grid == null ? "grid unavailable" : grid.routeStatus);
    }

    function saveCapture(kind:String, reason:String):Void {
        var floor = ctx.state.floor;
        if (panel == null || !panel.visible || floor == null || floor.id != floorId) return;
        try {
            var name = captures.save({
                schema: 1,
                kind: kind,
                reason: reason,
                map: floor.map,
                floor: floor.number,
                hero: hero == null ? null : {x: hero.x, y: hero.y},
                exit: goal == null ? null : {id: goal.id, x: goal.x, y: goal.y, category: goal.category},
                gate: gate == null ? null : {x: gate.x, y: gate.y},
                waypoint: waypoint == null ? null : {x: waypoint.x, y: waypoint.y},
                displayedHeading: panel.displayedHeading(),
                tiles: [for (tile in floor.tiles) {id: tile.id, x: tile.x, y: tile.y,
                    category: tile.category, exits: tile.exits}],
                geometry: grid.captureGeometry()
            });
            ctx.log("Gate Compass saved route capture " + name);
        } catch (error:Dynamic) {
            ctx.log("Gate Compass could not save route capture: " + Std.string(error));
        }
    }

    function reportRouteState(state:String):Void {
        if (reportedRouteStates.exists(state)) return;
        reportedRouteStates.set(state, true);
        var floor = ctx.state.floor;
        ctx.log("Gate Compass route: " + state + (floor == null ? "" : " on " + floor.map + " floor " + floor.number));
    }

    function refreshGeometry(floor:DistributedDungeonFloor, now:Int):Bool {
        var current = ctx.state.floor;
        if (current == null || current.id != floorId || floor.box2DWorld == null) return false;
        var oldGoal = goal;
        var oldGate = gate;
        var oldGateId = gateId;
        var tiles = [for (tile in current.tiles) if (tile.category != "FILLER_TILE") tile];
        var layout = [for (tile in tiles) tile.id + ":" + tile.x + ":" + tile.y + ":" + tile.category].join("|");
        var delayedRefresh = startupRefresh > 0 && now >= startupRefresh;
        if (!geometryDirty && tileLayout == layout && !delayedRefresh) return false;
        if (tileLayout == "" && layout != "") startupRefresh = now + 650;
        if (delayedRefresh) startupRefresh = -1;
        tileLayout = layout;
        geometryDirty = false;
        goal = null;
        gate = null;
        gateId = 0;
        bossRoom = false;
        for (tile in tiles) {
            if (tile.category == "EXIT_TILE") goal = tile;
            else if (goal == null && tile.category == "BOSS_TILE") goal = tile;
        }
        if (goal == null) {
            grid.clear();
            waypoint = null;
            return oldGoal != null;
        }

        // These two authored exit rooms complete the floor through the boss life trigger.
        bossRoom = goal.category == "BOSS_TILE" || goal.id == "454.1334956026168" || goal.id == "271.1333708475942";
        if (floor.remoteActors != null) for (object in floor.remoteActors.toArray()) {
            var npc = Std.downcast(object, NPCGameObject);
            if (npc == null || npc.isDestroyed || npc.gmNpc == null || npc.position == null) continue;
            var p = npc.position;
            if (!goal.contains(p.x, p.y)) continue;
            var kind = Std.string(npc.gmNpc.Constant).toUpperCase();
            var type:Int = npc.type;
            var suffix = type % 10000;
            if (kind == "JASONS_DUNGEON_EXIT" || (kind.indexOf("EXIT") >= 0 && (kind.indexOf("GATE") >= 0 || suffix == 101 || suffix == 201))) {
                gate = new Point(p.x, p.y);
                gateId = npc.id;
                break;
            }
            if (gate == null && !bossRoom && type >= 2000000 && type < 3000000 && (suffix == 101 || suffix == 201)) {
                gate = new Point(p.x, p.y);
                gateId = npc.id;
            }
        }
        grid.refresh(floor, tiles);
        // Thin collision shapes can change the edges without changing any cell center.
        waypoint = null;
        checkedWaypoint = null;
        var gateChanged = oldGateId != gateId
            || (oldGate == null ? gate != null : (gate == null || !oldGate.equals(gate)));
        if (!gateChanged) gate = oldGate;
        return true;
    }

    override public function dispose():Void {
        if (setting != null) setting.cancel();
        setting = null;
        if (panel != null) setEnabled(false);
    }
}
