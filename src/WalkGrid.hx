package mods.gate_compass;

import box2D.collision.shapes.B2CircleShape;
import box2D.collision.shapes.B2PolygonShape;
import box2D.common.math.B2Vec2;
import box2D.dynamics.B2Fixture;
import dBGlobals.DBGlobal;
import distributedObjects.DistributedDungeonFloor;
import distributedObjects.NPCGameObject;
import mods.api.dungeon.Tile;
import openfl.geom.Point;

class WalkGrid {
    public var routeLine:Array<Point> = [];
    public var routeDirection = new Point(1,0);
    var anchorRoutes:Map<String,Array<Array<Point>>> = new Map();
    var anchorTiles:Array<Tile> = [];
    var anchorCursor = 0;
    var knownLines:Array<Array<Point>> = [];
    var hazards:Array<Bool> = [];
    var clearance:Array<Int> = [];
    var markingHazard = false;
    var field:RouteField;
    var focusCell = -1;
    var focusAnnounced = false;
    var anchorsOrdered = false;
    var cachedQueries = false;
    var routeGoal = "";
    var routeGateId:UInt = 0;
    var shapeKey = "";
    var shapeParts:Array<String> = [];
    var cells:Array<Bool> = [];
    var rooms:Array<Tile> = [];
    var tilesByPosition:Map<String, Tile> = new Map();
    var nearCollider:Array<Bool> = [];
    var floor:DistributedDungeonFloor;
    var edgeChecks:Map<Int, Bool> = new Map();
    var gentleTarget:Point;
    var gentleOrigin:Point;
    var left:Float;
    var top:Float;
    var step:Float;
    var width:Int;
    var height:Int;

    public function new() {}

    public function refresh(floor:DistributedDungeonFloor, tiles:Array<Tile>):Void {
        this.floor = floor;
        var previousLine = routeLine;
        var previousField = field;
        var previousEdges = edgeChecks;
        field = null;
        routeLine = [];
        shapeParts = [for (tile in tiles) tile.id + ":" + tile.x + ":" + tile.y];
        edgeChecks = new Map();
        invalidateRoute();
        cells = [];
        rooms = [];
        tilesByPosition = new Map();
        nearCollider = [];
        if (tiles.length == 0 || floor.box2DWorld == null) return;

        left = Math.POSITIVE_INFINITY;
        top = Math.POSITIVE_INFINITY;
        var right = Math.NEGATIVE_INFINITY;
        var bottom = Math.NEGATIVE_INFINITY;
        for (tile in tiles) {
            left = Math.min(left, tile.x);
            top = Math.min(top, tile.y);
            right = Math.max(right, tile.x + Tile.SIZE);
            bottom = Math.max(bottom, tile.y + Tile.SIZE);
        }
        var subdivisions = Std.int(Math.max(1, Math.min(25,
            Math.floor(256 * Tile.SIZE / Math.max(right - left, bottom - top)))));
        step = Tile.SIZE / subdivisions;
        width = Std.int(Math.ceil((right - left) / step));
        height = Std.int(Math.ceil((bottom - top) / step));

        cells = [for (i in 0...width * height) false];
        hazards = [for (i in 0...width * height) false];
        nearCollider = [for (i in 0...width * height) false];
        for (tile in tiles) {
            tilesByPosition.set(tileKey(tile.x, tile.y), tile);
            var col = Math.round((tile.x - left) / step);
            var row = Math.round((tile.y - top) / step);
            for (y in row...row + subdivisions) for (x in col...col + subdivisions) {
                var i = y * width + x;
                rooms[i] = tile;
                cells[i] = true;
            }
        }

        forEachCollision(markPolygon, markCircle);
        buildClearance();
        var key = shapeParts.join(";");
        if (key == shapeKey) { routeLine = previousLine; field = previousField; edgeChecks = previousEdges; }
        shapeKey = key;
        shapeParts = [];
    }

    function buildClearance():Void {
        clearance = [for (i in 0...cells.length) 1000];
        var queue:Array<Int> = [];
        for (i in 0...cells.length) {
            var col = i % width; var row = Std.int(i / width);
            if (!cells[i] || col == 0 || row == 0 || col == width - 1 || row == height - 1) {
                clearance[i] = 0; queue.push(i);
            }
        }
        var head = 0;
        while (head < queue.length) {
            var i = queue[head++];
            var col = i % width; var row = Std.int(i / width);
            for (next in [index(col - 1, row), index(col + 1, row), index(col, row - 1), index(col, row + 1)]) {
                if (next < 0 || next >= cells.length || clearance[next] <= clearance[i] + 1) continue;
                clearance[next] = clearance[i] + 1; queue.push(next);
            }
        }
    }

    function corridorClear(x:Float, y:Float, target:Point, ignoredGate:UInt = 0):Bool {
        if (cachedQueries) return clearGridLine(x, y, target);
        if (!canAim(x, y, target, ignoredGate) || !clearGridLine(x, y, target)) return false;
        var dx = target.x - x; var dy = target.y - y;
        var length = Math.sqrt(dx * dx + dy * dy);
        if (length < 0.001) return true;
        var radius = 16.;
        var nx = -dy / length * radius; var ny = dx / length * radius;
        for (side in [-1, 1]) {
            var end = new Point(target.x + nx * side, target.y + ny * side);
            // The center grid already includes the agent radius. Side rays
            // check actual shapes without inflating that radius a second time.
            if (!canAim(x + nx * side, y + ny * side, end, ignoredGate)) return false;
        }
        return true;
    }

    function forEachCollision(polygonFound:Array<Point>->Void, circleFound:Float->Float->Float->Void):Void {
        if (floor == null || floor.box2DWorld == null) return;
        var body = floor.box2DWorld.GetBodyList();
        while (body != null) {
            var actorData=body.GetUserData();
            var actor=actorData==null||floor.remoteActors==null?null:Std.downcast(floor.remoteActors.itemFor(actorData),NPCGameObject);
            var persistentTrap=actor!=null&&actor.gmNpc!=null&&actor.gmNpc.Species=="TRAP";
            if (body.IsActive() || persistentTrap) {
                var fixture = body.GetFixtureList();
                while (fixture != null) {
                    var data = body.GetUserData();
                    var npc = data == null || floor.remoteActors == null ? null
                        : Std.downcast(floor.remoteActors.itemFor(data), NPCGameObject);
                    markingHazard = npc != null && npc.gmNpc != null && npc.gmNpc.Species == "TRAP";
                    if (markingHazard || blocksMovement(fixture)) {
                        var polygon = Std.downcast(fixture.GetShape(), B2PolygonShape);
                        var circle = Std.downcast(fixture.GetShape(), B2CircleShape);
                        if (polygon != null && polygon.GetVertexCount() >= 3) {
                            var vertices = polygon.GetVertices();
                            var points = [];
                            for (i in 0...polygon.GetVertexCount()) {
                                var vertex = body.GetWorldPoint(cast vertices[i]);
                                points.push(new Point(vertex.x * 50, vertex.y * 50));
                            }
                            polygonFound(points);
                        } else if (circle != null) {
                            var center = body.GetWorldPoint(circle.GetLocalPosition());
                            circleFound(center.x * 50, center.y * 50, circle.GetRadius() * 50);
                        }
                    }
                    markingHazard = false;
                    fixture = fixture.GetNext();
                }
            }
            body = body.GetNext();
        }
    }

    // Keep a small clearance around static collision shapes without sealing narrow doors.
    static inline final CLEARANCE = 20.;

    function markCircle(cx:Float, cy:Float, radius:Float):Void {
        shapeParts.push((markingHazard ? "H" : "C") + cx + ":" + cy + ":" + radius);
        var extent = radius + CLEARANCE;
        markCells(cx - extent, cy - extent, cx + extent, cy + extent, function(x, y) {
            var dx = x - cx;
            var dy = y - cy;
            return dx * dx + dy * dy <= extent * extent;
        });
    }

    function markPolygon(points:Array<Point>):Void {
        shapeParts.push((markingHazard ? "H" : "P") + [for (p in points) p.x + ":" + p.y].join(","));
        var minX = Math.POSITIVE_INFINITY;
        var minY = Math.POSITIVE_INFINITY;
        var maxX = Math.NEGATIVE_INFINITY;
        var maxY = Math.NEGATIVE_INFINITY;
        for (p in points) {
            minX = Math.min(minX, p.x);
            minY = Math.min(minY, p.y);
            maxX = Math.max(maxX, p.x);
            maxY = Math.max(maxY, p.y);
        }
        markCells(minX - CLEARANCE, minY - CLEARANCE, maxX + CLEARANCE, maxY + CLEARANCE, function(x, y) {
            var inside = false;
            var a = points[points.length - 1];
            for (b in points) {
                var dx = b.x - a.x;
                var dy = b.y - a.y;
                var lengthSquared = dx * dx + dy * dy;
                if (lengthSquared > 0) {
                    var t = Math.max(0, Math.min(1, ((x - a.x) * dx + (y - a.y) * dy) / lengthSquared));
                    var ex = x - a.x - t * dx;
                    var ey = y - a.y - t * dy;
                    if (ex * ex + ey * ey <= CLEARANCE * CLEARANCE) return true;
                }
                if ((a.y > y) != (b.y > y) && x < a.x + (y - a.y) * dx / dy) inside = !inside;
                a = b;
            }
            return inside;
        });
    }

    function markCells(minX:Float, minY:Float, maxX:Float, maxY:Float, contains:Float->Float->Bool):Void {
        var x0 = Std.int(Math.max(0, Math.floor((minX - left) / step) - 1));
        var y0 = Std.int(Math.max(0, Math.floor((minY - top) / step) - 1));
        var x1 = Std.int(Math.min(width, Math.ceil((maxX - left) / step) + 1));
        var y1 = Std.int(Math.min(height, Math.ceil((maxY - top) / step) + 1));
        for (y in y0...y1) for (x in x0...x1) {
            var i = y * width + x;
            nearCollider[i] = true;
            if (contains(left + (x + 0.5) * step, top + (y + 0.5) * step)) {
                if (markingHazard) hazards[i] = true;
                else cells[i] = false;
            }
        }
    }

    public function clear():Void {
        field = null;
        knownLines = [];
        routeLine = [];
        hazards = [];
        shapeKey = "";
        edgeChecks = new Map();
        invalidateRoute();
        cells = [];
        rooms = [];
        tilesByPosition = new Map();
        nearCollider = [];
        floor = null;
    }

    public function cellAt(x:Float, y:Float):Int {
        if (cells.length == 0) return -1;
        var col = Math.floor((x - left) / step);
        var row = Math.floor((y - top) / step);
        return index(col, row);
    }

    public function roomAtCell(cell:Int):Tile {
        return cell < 0 || cell >= cells.length ? null : rooms[cell];
    }

    function index(x:Int, y:Int):Int {
        return x < 0 || y < 0 || x >= width || y >= height ? -1 : y * width + x;
    }

    function walkable(i:Int):Bool {
        return i >= 0 && i < cells.length && cells[i];
    }

    function blocksMovement(fixture:B2Fixture, ignoredGate:UInt = 0):Bool {
        if (fixture.IsSensor() || !fixture.GetBody().IsActive()) return false;
        var bits = fixture.GetFilterData().categoryBits;
        var data = fixture.GetBody().GetUserData();
        if (ignoredGate != 0 && data == ignoredGate) return false;
        var npc = data == null || floor.remoteActors == null ? null
            : Std.downcast(floor.remoteActors.itemFor(data), NPCGameObject);
        // A closed, authored door is still a route passage. Its surrounding
        // wall fixtures remain blockers; only the door actor is traversable in
        // this guidance cache, so it can lead to an unlockable exit.
        if (npc != null && npc.gmNpc != null && npc.gmNpc.Species == "DOOR") return false;
        if (npc != null && npc.isProp && npc.gmNpc != null && npc.gmNpc.IsAttackable
            && npc.gmNpc.Species != "TRAP") return false;
        if (npc != null && npc.gmNpc != null && npc.gmNpc.Species == "TRAP"
            && npc.team == DBGlobal.TEAM_3) return false;
        if (npc != null && npc.gmNpc != null && npc.gmNpc.Species == "TRAP") {
            var kind = Std.string(npc.gmNpc.Constant).toUpperCase();
            // Spike strips count as a route even while their damage is active.
            if (kind.indexOf("SPIKE") >= 0) return false;
        }
        return (bits & DBGlobal.B2D_ENVIRONMENT_MASK) != 0
            || (npc != null && npc.isProp && !npc.isNavigable && bits != DBGlobal.B2D_COMBAT_MASK);
    }

    public function canAim(x:Float, y:Float, target:Point, ignoredGate:UInt = 0, smallObstacle:Bool = false):Bool {
        if (floor == null || floor.box2DWorld == null || target == null
            || !Math.isFinite(x) || !Math.isFinite(y)
            || !Math.isFinite(target.x) || !Math.isFinite(target.y)) return false;
        if (x == target.x && y == target.y) return true;
        var from = new B2Vec2(x / 50, y / 50);
        var to = new B2Vec2(target.x / 50, target.y / 50);
        for (hit in floor.box2DWorld.RayCastAll(from, to)) {
            var fixture = Std.downcast(hit, B2Fixture);
            if (fixture == null || !blocksMovement(fixture, ignoredGate)) continue;
            var circle = Std.downcast(fixture.GetShape(), B2CircleShape);
            if (!smallObstacle || circle == null || circle.GetRadius() * 50 > 55) return false;
        }
        return true;
    }

    function canCross(from:Int, to:Int):Bool {
        if (!walkable(from) || !walkable(to)
            || Math.abs(from % width - to % width)
                + Math.abs(Std.int(from / width) - Std.int(to / width)) != 1) return false;
        var a = rooms[from];
        var b = rooms[to];
        if (a == null || b == null) return false;
        if (a == b && !nearCollider[from] && !nearCollider[to]) return true;
        var lower = Std.int(Math.min(from, to));
        var key = lower * 2 + (Math.abs(from - to) == 1 ? 0 : 1);
        var cached = edgeChecks.get(key);
        if (cached != null) return cached;
        if (cachedQueries) return false;
        // Authored exit flags are incomplete on some floors. Confirm the seam in the live world.
        var start = point(from);
        var end = point(to);
        var open = canAim(start.x, start.y, end);
        edgeChecks.set(key, open);
        return open;
    }

    function point(i:Int):Point {
        return new Point(left + (i % width + 0.5) * step, top + (Std.int(i / width) + 0.5) * step);
    }

    public function regionAt(x:Float, y:Float):String {
        var tile = roomAtCell(cellAt(x, y));
        if (tile == null) return "";
        return tile.x + ":" + tile.y + ":" + Math.floor((x - tile.x) / 150)
            + ":" + Math.floor((y - tile.y) / 150);
    }

    public function prepareField(goal:Tile, gate:Point, gateId:UInt):Void {
        var key = goal.id + ":" + goal.x + ":" + goal.y + ":" + gateId
            + (gate == null ? "" : ":" + gate.x + ":" + gate.y);
        if (field != null && field.key == key) return;
        routeLine = [];
        anchorRoutes = new Map(); anchorTiles = [for(tile in tilesByPosition) tile]; anchorCursor=0;focusAnnounced=false;anchorsOrdered=false;
        field = new RouteField(goal, gate, gateId, key, cells.length);
        routeGoal = key; routeGateId = gateId;
    }

    /** One reverse search fills the next step for every reachable cell. */
    public function prioritize(x:Float,y:Float):Void { focusCell=cellAt(x,y); }

    public function advanceField():Bool {
        if (field == null) return false;
        if (field.phase == 2) {
            if(!anchorsOrdered){
                anchorsOrdered=true;
                var priority:Array<Tile>=[];var current=focusCell;var guard=0;
                while(current>=0&&current<cells.length&&field.next[current]>=0&&guard++<cells.length){
                    var tile=rooms[current];if(tile!=null&&priority.indexOf(tile)<0)priority.push(tile);
                    if(priority.length>=3||field.next[current]==current)break;current=field.next[current];
                }
                for(tile in anchorTiles)if(priority.indexOf(tile)<0)priority.push(tile);
                anchorTiles=priority;
            }
            var deadline=haxe.Timer.stamp()+0.001;var count=0;
            while(anchorCursor<anchorTiles.length*36 && count++<8 && haxe.Timer.stamp()<deadline) {
                var tile=anchorTiles[Std.int(anchorCursor/36)];var part=anchorCursor%36;anchorCursor++;
                var x=tile.x+(part%6+0.5)*150;var y=tile.y+(Std.int(part/6)+0.5)*150;
                var cell=cellAt(x,y);var best=-1;var distance=Math.POSITIVE_INFINITY;
                if(cell>=0)for(dy in -2...3)for(dx in -2...3){
                    var candidate=index(cell%width+dx,Std.int(cell/width)+dy);
                    if(!walkable(candidate)||!field.settled[candidate]||rooms[candidate]!=tile)continue;
                    var p=point(candidate);var d=(p.x-x)*(p.x-x)+(p.y-y)*(p.y-y);
                    if(d<distance){distance=d;best=candidate;}
                }
                var route=best<0?[]:cachedLine(best,point(best));
                var key=tileKey(tile.x,tile.y);var routes=anchorRoutes.get(key);
                if(routes==null){routes=[];anchorRoutes.set(key,routes);}routes.push(route);
            }
            return false;
        }
        var f = field;
        var deadline = haxe.Timer.stamp() + (focusCell>=0 && focusCell<f.settled.length && !f.settled[focusCell] ? 0.003 : 0.001);
        var work = 0;
        while (work++ < 1536 && haxe.Timer.stamp() < deadline) {
            if (f.phase == 0) {
                var side = Math.round(Tile.SIZE / step);
                if (f.scan < side * side) {
                    var offset = f.scan++;
                    var cell = index(Math.round((f.goal.x-left)/step) + offset%side,
                        Math.round((f.goal.y-top)/step) + Std.int(offset/side));
                    if (!walkable(cell)) continue;
                    var p = point(cell);
                    if (!f.goal.contains(p.x, p.y)) continue;
                    var end = f.gate == null ? new Point(f.goal.x + Tile.SIZE/2, f.goal.y + Tile.SIZE/2) : f.gate;
                    var dx = p.x-end.x;var dy=p.y-end.y;var distance=dx*dx+dy*dy;
                    if (f.gate != null && canAim(p.x,p.y,f.gate,f.gateId) && hazardFree(p.x,p.y,f.gate)) {
                        // Closed gates can split the nearest cells into separate
                        // islands. Cache every visible approach, on either side.
                        f.seeds.push(cell);
                        f.scores[cell]=Math.sqrt(distance)/step;
                        f.next[cell]=cell;
                    }
                    if (distance < f.distance && (f.gate == null || canAim(p.x,p.y,f.gate,f.gateId))) {
                        f.seed=cell;f.distance=distance;
                    }
                    continue;
                }
                if (f.seed < 0) { f.phase=2; return true; }
                if (f.seeds.length == 0) {
                    f.scores[f.seed]=0; f.next[f.seed]=f.seed; f.seeds.push(f.seed);
                }
                for (seed in f.seeds) fieldPush(f.heap,new RouteNode(seed,f.scores[seed]));
                f.phase=1;
            }
            if (f.heap.length==0) { f.phase=2; return true; }
            var current=heapPop(f.heap,f.scores);
            if (f.settled[current]) continue;
            f.settled[current]=true;
            var col=current%width;var row=Std.int(current/width);
            for (next in [index(col-1,row),index(col+1,row),index(col,row-1),index(col,row+1)]) {
                if (!walkable(next) || f.settled[next] || !canCross(current,next)) continue;
                var score=f.scores[current]+1+(hazards[current]?24:0)+3./(clearance[current]+1);
                if(score>=f.scores[next])continue;
                f.scores[next]=score;f.next[next]=current;
                // Reverse Dijkstra uses immutable costs, with no per-hero search.
                fieldPush(f.heap,new RouteNode(next,score));
            }
            if(!focusAnnounced&&current==focusCell){
                focusAnnounced=true;
                routeLine=cachedLine(current,point(current),true);
                // Publish the main spawn-to-gate line immediately, before
                // warming all 36 starts in the first three tiles and beyond.
                return true;
            }
        }
        return false;
    }

    public function waypoint(x:Float,y:Float,goal:Tile,gate:Point,gateId:UInt=0):Point {
        prepareField(goal,gate,gateId);
        // Keep a valid branch stable instead of swapping nearby anchors on
        // every small movement or as additional anchors finish warming.
        var existing=followLine(x,y);
        if(existing!=null)return existing;
        var tile=roomAtCell(cellAt(x,y));
        var routes=tile==null?null:anchorRoutes.get(tileKey(tile.x,tile.y));
        var chosen:Array<Point>=null;var closest=Math.POSITIVE_INFINITY;
        cachedQueries=true;
        if(routes!=null)for(line in routes)for(i in 0...line.length-1){
            var a=line[i];var b=line[i+1];var dx=b.x-a.x;var dy=b.y-a.y;
            var length=dx*dx+dy*dy;
            var t=length==0?0.:Math.max(0,Math.min(1,((x-a.x)*dx+(y-a.y)*dy)/length));
            var p=new Point(a.x+dx*t,a.y+dy*t);var distance=(p.x-x)*(p.x-x)+(p.y-y)*(p.y-y);
            if(distance<closest && clearGridLine(x,y,p)){closest=distance;chosen=line;}
        }
        cachedQueries=false;
        if(chosen!=null)routeLine=chosen;
        var retained=followLine(x,y);if(retained!=null)return retained;
        var start=cellAt(x,y);
        if(start<0||field==null||!field.settled[start]||field.next[start]<0)return null;
        // Initial guidance uses the already-built field while anchor lines fill.
        routeLine=cachedLine(start,new Point(x,y));
        return followLine(x,y);
    }

    function cachedLine(start:Int,origin:Point,validateInitial:Bool=false):Array<Point> {
        var raw=[origin];var current=start;var guard=0;
        while(guard++<cells.length){
            raw.push(point(current));
            if(field.next[current]==current)break;
            var next=field.next[current];if(next<0)return [];current=next;
        }
        if(field.gate!=null)raw.push(field.gate);
        cachedQueries=!validateInitial;var line=naturalLine(raw,field.gateId);cachedQueries=false;
        return line;
    }

    public function invalidateRoute():Void {
        gentleTarget = null;
        gentleOrigin = null;
    }

    function hazardFree(x:Float, y:Float, target:Point):Bool {
        var count = Std.int(Math.ceil(Point.distance(new Point(x, y), target) / (step / 2)));
        for (i in 0...count + 1) {
            var t = count == 0 ? 0. : i / count;
            var cell = cellAt(x + (target.x - x) * t, y + (target.y - y) * t);
            if (cell >= 0 && hazards[cell]) return false;
        }
        return true;
    }

    function naturalLine(raw:Array<Point>, gateId:UInt):Array<Point> {
        var result = [raw[0]];
        var at = 0;
        while (at < raw.length - 1) {
            var next = at + 1;
            for (offset in 0...raw.length - at - 2) {
                var i = raw.length - 1 - offset;
                if (corridorClear(raw[at].x, raw[at].y, raw[i], i == raw.length - 1 ? gateId : 0) && hazardFree(raw[at].x, raw[at].y, raw[i])) { next = i; break; }
            }
            result.push(raw[next]);
            at = next;
        }
        return roundCorners(result);
    }

    function roundCorners(points:Array<Point>):Array<Point> {
        if (points.length < 3) return points;
        var rounded = [points[0]];
        for (i in 1...points.length - 1) {
            var a = points[i - 1]; var b = points[i]; var c = points[i + 1];
            var ab = Point.distance(a, b); var bc = Point.distance(b, c);
            var radius = Math.min(140., Math.min(ab, bc) * 0.4);
            var accepted=false;
            for(attempt in 0...5){
                if(radius<2)break;
                var enter=new Point(b.x+(a.x-b.x)*radius/ab,b.y+(a.y-b.y)*radius/ab);
                var leave=new Point(b.x+(c.x-b.x)*radius/bc,b.y+(c.y-b.y)*radius/bc);
                var arc=[enter];
                for(j in 1...13){var t=j/12.;var u=1-t;arc.push(new Point(u*u*enter.x+2*u*t*b.x+t*t*leave.x,u*u*enter.y+2*u*t*b.y+t*t*leave.y));}
                var safe=true;var from=rounded[rounded.length-1];
                for(p in arc){if(!corridorClear(from.x,from.y,p)||!hazardFree(from.x,from.y,p))safe=false;from=p;}
                if(safe){for(p in arc)rounded.push(p);accepted=true;break;}
                radius*=0.5;
            }
            if(!accepted)rounded.push(b);
        }
        rounded.push(points[points.length - 1]);
        return rounded;
    }

    function followLine(x:Float, y:Float):Point {
        if (routeLine.length < 2) return null;
        var best = Math.POSITIVE_INFINITY;
        var segment = -1;
        var projection:Point = null;
        for (i in 0...routeLine.length - 1) {
            var a = routeLine[i]; var b = routeLine[i + 1];
            var dx = b.x - a.x; var dy = b.y - a.y;
            var length = dx * dx + dy * dy;
            var t = length == 0 ? 0. : Math.max(0, Math.min(1, ((x - a.x) * dx + (y - a.y) * dy) / length));
            var p = new Point(a.x + dx * t, a.y + dy * t);
            var distance = Point.distance(new Point(x, y), p);
            if (distance < best) { best = distance; segment = i; projection = p; }
        }
        if (segment < 0 || best > 95) return null;
        var remaining = 192.;
        var from = projection;
        var target = routeLine[segment + 1];
        for (i in segment + 1...routeLine.length) {
            var p = routeLine[i];
            var distance = Point.distance(from, p);
            if(distance>0.001)routeDirection=new Point((p.x-from.x)/distance*100,(p.y-from.y)/distance*100);
            if (distance >= remaining) {
                target = new Point(from.x + (p.x - from.x) * remaining / distance, from.y + (p.y - from.y) * remaining / distance);
                break;
            }
            target = p; remaining -= distance; from = p;
        }
        var ignoredGate = segment == routeLine.length - 2 ? routeGateId : 0;
        if (!clearGridLine(x,y,target)) target=routeLine[segment+1];
        if (!clearGridLine(x,y,target) && segment!=routeLine.length-2) return null;
        return target;
    }

    static function fieldPush(heap:Array<RouteNode>,node:RouteNode):Void {
        heap.push(node);var i=heap.length-1;
        while(i>0){var parent=Std.int((i-1)/2);if(heap[parent].cost<=node.cost)break;heap[i]=heap[parent];i=parent;}
        heap[i]=node;
    }

    static function heapPop(heap:Array<RouteNode>, scores:Array<Float>):Int {
        var result = heap[0].cell; var last = heap.pop();
        if (heap.length == 0) return result;
        var i = 0;
        while (i * 2 + 1 < heap.length) {
            var child = i * 2 + 1;
            if (child + 1 < heap.length && heap[child + 1].cost < heap[child].cost) child++;
            if (last.cost <= heap[child].cost) break;
            heap[i] = heap[child]; i = child;
        }
        heap[i] = last;
        return result;
    }

    static function tileKey(x:Int, y:Int):String {
        return x + ":" + y;
    }

    public function isGentleDirection(x:Float, y:Float, target:Point):Bool {
        return target == gentleTarget && gentleOrigin != null
            && Math.abs(x - gentleOrigin.x) < step && Math.abs(y - gentleOrigin.y) < step
            && canAim(x, y, target, 0, true);
    }

    function clearGridLine(x:Float, y:Float, target:Point):Bool {
        var dx = target.x - x;
        var dy = target.y - y;
        var samples = Std.int(Math.ceil(Math.max(Math.abs(dx), Math.abs(dy)) * 4 / step));
        var previous = cellAt(x, y);
        if (previous < 0) return false;
        for (i in 1...samples + 1) {
            var next = cellAt(x + dx * i / samples, y + dy * i / samples);
            if (next == previous) continue;
            if (!walkable(next)) return false;
            var col = next % width - previous % width;
            var row = Std.int(next / width) - Std.int(previous / width);
            if (col != 0 && row != 0) {
                var horizontal = previous + col;
                var vertical = previous + row * width;
                if ((rooms[previous] != rooms[next]
                    && rooms[previous] != rooms[horizontal] && rooms[previous] != rooms[vertical])
                    || !walkable(horizontal) || !walkable(vertical)
                    || !canCross(previous, horizontal)
                    || !canCross(previous, vertical)
                    || !canCross(horizontal, next)
                    || !canCross(vertical, next)) return false;
            } else {
                if (!canCross(previous, next)) return false;
            }
            previous = next;
        }
        return true;
    }
}
