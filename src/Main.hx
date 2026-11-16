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
import distributedObjects.HeroGameObject;
import openfl.geom.Point;

class Main extends Mod {
    var ctx:Context;
    var setting:Subscription;
    var modeSetting:Subscription;
    var visualMode = "ground_line";
    var floating:FloatingCompass;
    var sizeSetting:Subscription;
    var compassSize = 1.;
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
        var mode = context.settings.choice("compassMode", "Compass mode",
            "Choose the display. All modes follow the same cached route, even when the line is hidden.",
            [{value:"flat",label:"Original 2D"},{value:"ground",label:"3D"},
             {value:"ground_line",label:"3D + Line"},{value:"line",label:"Line only"}],"ground_line");
        visualMode = mode.value;
        modeSetting = mode.onChange(function(value) {
            visualMode = value;
            if (panel != null) panel.setDisplayMode(value);
            updateFloating();
        });
        var size = context.settings.slider("groundCompassSize", "Compass size",
            "Size of the direction ring beneath your hero.", 0.5, 2, 0.1, 1, 1);
        compassSize = size.value;
        sizeSetting = size.onChange(function(value) {
            compassSize = value;
            if (panel != null) panel.setSize(value);
        });
        var enabled = context.settings.flag("enableCompass", "Enable Gate Compass", "Show directions to the dungeon exit.", true);
        setting = enabled.onChange(setEnabled);
        setEnabled(enabled.value);
    }

    function updateFloating():Void {
        if(visualMode=="flat"&&panel!=null){
            if(floating==null){floating=new FloatingCompass(ctx);ctx.overlay.addChild(floating);}
            floating.visible=panel.visible;
        }else if(floating!=null){
            floating.destroy();if(floating.parent!=null)floating.parent.removeChild(floating);floating=null;
        }
    }

    function setEnabled(enabled:Bool):Void {
        if (enabled && panel == null) {
            panel = new Compass(ctx);
            panel.setSize(compassSize);
            panel.setDisplayMode(visualMode);
            updateFloating();
            grid = new WalkGrid();
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
                if (h == hero) {
                    hero = null;
                    panel.visible = false;
                    if (floating != null) floating.visible = false;
                    panel.detach();
                }
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
            panel.destroy();
            panel = null;
            if (floating != null) {
                floating.destroy();
                if (floating.parent != null) floating.parent.removeChild(floating);
                floating = null;
            }
        }
    }

    function trackHero(h:Hero):Void {
        if (h.local) hero = h;
    }

    function collisionActorChanged(object:Dynamic):Void {
        if (floorId == 0) return;
        var npc = Std.downcast(object, NPCGameObject);
        if (npc != null && npc.isProp && npc.gmNpc != null && npc.gmNpc.IsAttackable
            && npc.gmNpc.Species != "TRAP") return;
        if (npc != null && npc.distributedDungeonFloor == liveFloor() && npc.gmNpc != null
            && (npc.gmNpc.Species == "DOOR" || npc.gmNpc.Species == "TRAP" || npc.isProp)) {
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
        startupPass = 0;
        nextSearch = 0;
        nextUpdate = 0;
        lastCell = -1;
        lastSearchRoom = null;
        lastRegion = "";
        if (grid != null) grid.clear();
        if (panel != null) {
            panel.visible = false;
            if (floating != null) floating.visible = false;
            panel.resetHeading();
            if (floating != null) floating.resetHeading();
            panel.detach();
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
        if (floating != null) floating.turn(now);
        if (now < nextUpdate) {
            return;
        }
        nextUpdate = now + 16;
        if (grid != null && hero != null) grid.prioritize(hero.x,hero.y);
        if (grid != null && grid.advanceField()) { nextSearch = 0; lastCell = -1; }
        var facade = ctx.core.facade;
        if (floorId == 0 || facade == null || facade.mainStateMachine == null
            || facade.mainStateMachine.currentStateName != "RunState" || facade.gameObjectManager == null) {
            panel.visible = false;
            if (floating != null) floating.visible = false;
            return;
        }
        var floor = liveFloor();
        if (floor == null || floor.isDestroyed) {
            panel.visible = false;
            if (floating != null) floating.visible = false;
            return;
        }

        var navigation = facade.menuNavigationController;
        if (navigation != null && (navigation.getTopUILayer() == "EXIT_DUNGEON"
            || navigation.getTopUILayer() == "SETTINGS_MENU"
            || (navigation.layerDepth > 1 && (navigation.getAllCurrentLayers().indexOf("EXIT_DUNGEON, ") >= 0
                || navigation.getAllCurrentLayers().indexOf("SETTINGS_MENU, ") >= 0)))) {
            panel.visible = false;
            if (floating != null) floating.visible = false;
            return;
        }

        if (hero != null) {
            var object = Std.downcast(facade.gameObjectManager.getReferenceFromId(hero.id), HeroGameObject);
            if (object != null && object.heroView != null) panel.attach(object.heroView);
        }
        if (!panel.visible) panel.showIdle();
        if (floating != null) floating.visible = visualMode == "flat";
        if (now >= nextGeometry) {
            if (hero == null) for (h in ctx.state.heroes) trackHero(h);
            if (refreshGeometry(floor, now)) {
                lastCell = -1;
                nextSearch = 0;
            }
            nextGeometry = now + (goal == null || floor.box2DWorld == null ? 120 : 300);
        }
        if (goal == null || hero == null) {
            panel.visible = false;
            if (floating != null) floating.visible = false;
            return;
        }

        var x = hero.x;
        var y = hero.y;
        if (bossRoom && gate == null && goal.contains(x, y)) {
            panel.showBoss();
            if (floating != null && visualMode == "flat") floating.showBoss();
            return;
        }
        var nearWaypoint = waypoint != null && waypoint != gate
            && Point.distance(new Point(x, y), waypoint) <= 18;
        if (waypoint != null && waypoint != gate
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
        var enteredRegion = region != "" && region != lastRegion;
        var movedWhileIdle = waypoint == null
            && (Math.abs(x - lastSearchX) >= 8 || Math.abs(y - lastSearchY) >= 8);
        // The normal cooldown still applies to movement inside a room.
        // A doorway crossing gets a fresh target immediately.
        if (enteredRoom || enteredRegion || (now >= nextSearch && (cell != lastCell || movedWhileIdle || nearWaypoint || waypoint == null))) {
            if (enteredRoom || enteredRegion) grid.invalidateRoute();
            lastRegion = region;
            lastSearchRoom = room;
            lastSearchX = x;
            lastSearchY = y;
            nextSearch = now + 80;
            lastCell = cell;
            waypoint = grid.waypoint(x, y, goal, gate, gateId);
            if (waypoint == null) nextSearch = now + 250;
        }
        // A cached line remains drawable even if the current tangent cannot
        // be sampled while crossing a cell or awaiting another anchor.
        if (grid.routeLine.length > 1) panel.setRoute(grid.routeLine);
        if (waypoint == null) {
            panel.showIdle();
            if (floating != null && visualMode == "flat") floating.showIdle();
            return;
        }
        panel.aim(grid.routeDirection.x, grid.routeDirection.y);
        if (floating != null && visualMode == "flat") floating.aim(grid.routeDirection.x, grid.routeDirection.y);
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

    function refreshGeometry(floor:DistributedDungeonFloor, now:Int):Bool {
        var current = ctx.state.floor;
        if (current == null || current.id != floorId || floor.box2DWorld == null) return false;
        var oldGoal = goal;
        var oldGate = gate;
        var oldGateId = gateId;
        var tiles = [for (tile in current.tiles) if (tile.category != "FILLER_TILE") tile];
        var parts = [for (tile in tiles)
            tile.id + ":" + tile.x + ":" + tile.y + ":" + tile.category + ":" + tile.exits.join(",")];
        parts.sort(Reflect.compare);
        var layout = parts.join("|");
        var delayedRefresh = startupRefresh > 0 && now >= startupRefresh;
        if (tileLayout == layout && geometryDirty && !delayedRefresh && now - lastObstacleRefresh < 1000) return false;
        if (!geometryDirty && tileLayout == layout && !delayedRefresh) return false;
        if (tileLayout == "" && layout != "") startupRefresh = now + 650;
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
        var gateScore = 0;
        if (floor.remoteActors != null) for (object in floor.remoteActors.toArray()) {
            var npc = Std.downcast(object, NPCGameObject);
            if (npc == null || npc.isDestroyed || npc.gmNpc == null || npc.position == null) continue;
            var p = npc.position;
            if (!goal.contains(p.x, p.y)) continue;
            var kind = Std.string(npc.gmNpc.Constant).toUpperCase();
            var type:Int = npc.type;
            var suffix = type % 10000;
            var score = kind == "JASONS_DUNGEON_EXIT" ? 3
                : kind.indexOf("EXIT") >= 0 && (kind.indexOf("GATE") >= 0 || suffix == 101 || suffix == 201) ? 2
                : !bossRoom && type >= 2000000 && type < 3000000 && (suffix == 101 || suffix == 201) ? 1 : 0;
            if (score > gateScore) {
                gate = new Point(p.x, p.y);
                gateId = npc.id;
                gateScore = score;
            }
        }
        lastObstacleRefresh = now;
        grid.refresh(floor, tiles);
        grid.prepareField(goal, gate, gateId);
        // Thin collision shapes can change the edges without changing any cell center.
        waypoint = null;
        checkedWaypoint = null;
        var gateChanged = oldGateId != gateId
            || (oldGate == null ? gate != null : (gate == null || !oldGate.equals(gate)));
        if (!gateChanged) gate = oldGate;
        return true;
    }

    override public function dispose():Void {
        if (modeSetting != null) modeSetting.cancel();
        modeSetting = null;
        if (sizeSetting != null) sizeSetting.cancel();
        sizeSetting = null;
        if (setting != null) setting.cancel();
        setting = null;
        if (panel != null) setEnabled(false);
    }
}
