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
    var cells:Array<Bool> = [];
    var rooms:Array<Tile> = [];
    var tilesByPosition:Map<String, Tile> = new Map();
    var nearCollider:Array<Bool> = [];
    var floor:DistributedDungeonFloor;
    var edgeChecks:Map<Int, Bool> = new Map();
    var cachedRoute:Array<Int> = [];
    var cachedInside = false;
    var gentleTarget:Point;
    var gentleOrigin:Point;
    public var routeStatus(default, null) = "waiting for walkable floor";
    var left:Float;
    var top:Float;
    var step:Float;
    var width:Int;
    var height:Int;

    public function new() {}

    public function refresh(floor:DistributedDungeonFloor, tiles:Array<Tile>):Void {
        this.floor = floor;
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
        var subdivisions = Std.int(Math.max(1, Math.min(37,
            Math.floor(256 * Tile.SIZE / Math.max(right - left, bottom - top)))));
        step = Tile.SIZE / subdivisions;
        width = Std.int(Math.ceil((right - left) / step));
        height = Std.int(Math.ceil((bottom - top) / step));

        cells = [for (i in 0...width * height) false];
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
    }

    function forEachCollision(polygonFound:Array<Point>->Void, circleFound:Float->Float->Float->Void):Void {
        if (floor == null || floor.box2DWorld == null) return;
        var body = floor.box2DWorld.GetBodyList();
        while (body != null) {
            if (body.IsActive()) {
                var fixture = body.GetFixtureList();
                while (fixture != null) {
                    if (blocksMovement(fixture)) {
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
                    fixture = fixture.GetNext();
                }
            }
            body = body.GetNext();
        }
    }

    public function captureGeometry():Dynamic {
        var polygons:Array<Array<Dynamic>> = [];
        var circles:Array<Dynamic> = [];
        var rows:Array<String> = [];
        forEachCollision(function(points) {
            polygons.push([for (p in points) {x: p.x, y: p.y}]);
        }, function(x, y, radius) {
            circles.push({x: x, y: y, radius: radius});
        });
        if (cells.length > 0) for (row in 0...height) {
            var line = new StringBuf();
            for (col in 0...width) line.add(cells[row * width + col] ? "1" : "0");
            rows.push(line.toString());
        }
        return {left: left, top: top, step: step, width: width, height: height,
            walkableRows: rows, polygons: polygons, circles: circles};
    }

    // Keep a small clearance around static collision shapes without sealing narrow doors.
    static inline final CLEARANCE = 5.;

    function markCircle(cx:Float, cy:Float, radius:Float):Void {
        var extent = radius + CLEARANCE;
        markCells(cx - extent, cy - extent, cx + extent, cy + extent, function(x, y) {
            var dx = x - cx;
            var dy = y - cy;
            return dx * dx + dy * dy <= extent * extent;
        });
    }

    function markPolygon(points:Array<Point>):Void {
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
            if (cells[i] && contains(left + (x + 0.5) * step, top + (y + 0.5) * step))
                cells[i] = false;
        }
    }

    public function clear():Void {
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
        return cell < 0 ? null : rooms[cell];
    }

    function index(x:Int, y:Int):Int {
        return x < 0 || y < 0 || x >= width || y >= height ? -1 : y * width + x;
    }

    function walkable(i:Int):Bool {
        return i >= 0 && cells[i];
    }

    function blocksMovement(fixture:B2Fixture, ignoredGate:UInt = 0):Bool {
        if (fixture.IsSensor() || !fixture.GetBody().IsActive()) return false;
        var bits = fixture.GetFilterData().categoryBits;
        var data = fixture.GetBody().GetUserData();
        if (ignoredGate != 0 && data == ignoredGate) return false;
        var npc = data == null || floor.remoteActors == null ? null
            : Std.downcast(floor.remoteActors.itemFor(data), NPCGameObject);
        if (npc != null && npc.gmNpc != null && npc.gmNpc.Species != "DOOR"
            && npc.team == DBGlobal.TEAM_3) return false;
        if (npc != null && npc.gmNpc != null && npc.gmNpc.Species == "TRAP") {
            var kind = Std.string(npc.gmNpc.Constant).toUpperCase();
            // Spike strips count as a route even while their damage is active.
            if (kind.indexOf("SPIKE") >= 0) return false;
        }
        return (bits & DBGlobal.B2D_ENVIRONMENT_MASK) != 0
            || (npc != null && npc.isProp && !npc.isNavigable && bits != DBGlobal.B2D_COMBAT_MASK);
    }

    public function canAim(x:Float, y:Float, target:Point, ignoredGate:UInt = 0):Bool {
        if (floor == null || floor.box2DWorld == null) return false;
        if (x == target.x && y == target.y) return false;
        var from = new B2Vec2(x / 50, y / 50);
        var to = new B2Vec2(target.x / 50, target.y / 50);
        for (hit in floor.box2DWorld.RayCastAll(from, to)) {
            var fixture = Std.downcast(hit, B2Fixture);
            if (fixture != null && blocksMovement(fixture, ignoredGate)) return false;
        }
        return true;
    }

    function canCross(from:Int, to:Int):Bool {
        var a = rooms[from];
        var b = rooms[to];
        if (a == null || b == null) return false;
        if (a == b && !nearCollider[from] && !nearCollider[to]) return true;
        var lower = Std.int(Math.min(from, to));
        var key = lower * 2 + (Math.abs(from - to) == 1 ? 0 : 1);
        var cached = edgeChecks.get(key);
        if (cached != null) return cached;
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

    public function invalidateRoute():Void {
        cachedRoute = [];
    }

    public function waypoint(x:Float, y:Float, goal:Tile, gate:Point, gateId:UInt = 0):Point {
        var start = cellAt(x, y);
        routeStatus = "hero outside the loaded grid";
        if (start < 0 || rooms[start] == null) return null;
        var heroCell = start;
        routeStatus = "no clear step from hero to grid";
        if (!walkable(start)) {
            var snapped = -1;
            var distance = Math.POSITIVE_INFINITY;
            for (dy in -1...2) for (dx in -1...2) {
                var i = index(start % width + dx, Std.int(start / width) + dy);
                if (!walkable(i) || rooms[i] != rooms[start]) continue;
                var p = point(i);
                if (!canAim(x, y, p)) continue;
                var d = (p.x - x) * (p.x - x) + (p.y - y) * (p.y - y);
                if (d < distance) {
                    snapped = i;
                    distance = d;
                }
            }
            if (snapped < 0) return null;
            start = snapped;
        }

        routeStatus = "no walkable connection to exit room";
        var inside = goal.contains(x, y);
        if (inside == cachedInside && cachedRoute.length > 0) {
            var at = cachedRoute.indexOf(start);
            if (at > 0) {
                var ahead = cachedRoute.slice(0, at);
                var next = nextWaypoint(x, y, start, ahead);
                if (next != null) {
                    cachedRoute = ahead;
                    cachedRoute.push(start);
                    return next;
                }
            }
        }

        var target = gate == null ? -1 : cellAt(gate.x, gate.y);
        var parent:Array<Int> = [for (i in 0...cells.length) -1];
        parent[start] = start;
        var queue = [start];
        var head = 0;
        var best = -1;
        var bestDistance = Math.POSITIVE_INFINITY;

        while (head < queue.length) {
            var current = queue[head++];
            var col = current % width;
            var row = Std.int(current / width);
            var px = left + (col + 0.5) * step;
            var py = top + (row + 0.5) * step;

            if (goal.contains(px, py)) {
                if (!inside || current == target) {
                    best = current;
                    break;
                }
                var gx = gate == null ? goal.x + Tile.SIZE / 2 : gate.x;
                var gy = gate == null ? goal.y + Tile.SIZE / 2 : gate.y;
                var d = (gx - px) * (gx - px) + (gy - py) * (gy - py);
                if (d < bestDistance) {
                    best = current;
                    bestDistance = d;
                }
            }

            for (dir in 0...4) {
                var next = switch (dir) {
                    case Tile.UP: index(col, row - 1);
                    case Tile.RIGHT: index(col + 1, row);
                    case Tile.DOWN: index(col, row + 1);
                    default: index(col - 1, row);
                };
                if (!walkable(next) || parent[next] != -1 || !canCross(current, next)) continue;
                if (current == start && !canAim(x, y, point(next))) continue;
                parent[next] = current;
                queue.push(next);
            }
        }

        if (best < 0 && !inside) {
            // A closed gate can disconnect the exit. Guide the hero as far as
            // the reachable approach to the next authored doorway.
            best = reachableApproach(goal, queue);
        }
        if (best < 0) return null;
        if (best == start) {
            if (heroCell != start) return point(start);
            routeStatus = inside ? "inside exit room, no gate approach" : "at blocked doorway approach";
            if (inside && gate != null && (target == start || bestDistance <= 4 * step * step)
                && canAim(x, y, gate, gateId)) return gate;
            return null;
        }
        var route = [];
        var next = best;
        while (next != start) {
            route.push(next);
            next = parent[next];
        }
        cachedRoute = route.copy();
        cachedRoute.push(start);
        cachedInside = inside;
        routeStatus = "first route segment obstructed";
        if (heroCell != start) return point(start);
        return nextWaypoint(x, y, start, route);
    }

    static function tileKey(x:Int, y:Int):String {
        return x + ":" + y;
    }

    function reachableApproach(goal:Tile, reachable:Array<Int>):Int {
        var distances:Map<String, Int> = new Map();
        var openings:Map<String, Point> = new Map();
        var queue = [goal];
        distances.set(tileKey(goal.x, goal.y), 0);
        var head = 0;
        while (head < queue.length) {
            var room = queue[head++];
            var distance = distances.get(tileKey(room.x, room.y));
            for (side in 0...4) {
                if (!room.exits[side]) continue;
                var dx = side == Tile.RIGHT ? Tile.SIZE : side == Tile.LEFT ? -Tile.SIZE : 0;
                var dy = side == Tile.DOWN ? Tile.SIZE : side == Tile.UP ? -Tile.SIZE : 0;
                var key = tileKey(room.x + dx, room.y + dy);
                var neighbor = tilesByPosition.get(key);
                if (neighbor == null || distances.exists(key) || !neighbor.exits[(side + 2) % 4]) continue;
                distances.set(key, distance + 1);
                openings.set(key, new Point(neighbor.x + (Tile.SIZE - dx) / 2,
                    neighbor.y + (Tile.SIZE - dy) / 2));
                queue.push(neighbor);
            }
        }

        var best = -1;
        var bestRoomDistance = 0x7FFFFFFF;
        var bestDoorDistance = Math.POSITIVE_INFINITY;
        var lastRoom:Tile = null;
        var roomDistance = 0x7FFFFFFF;
        var doorway:Point = null;
        for (cell in reachable) {
            var room = rooms[cell];
            if (room != lastRoom) {
                lastRoom = room;
                var key = tileKey(room.x, room.y);
                doorway = openings.get(key);
                if (doorway != null) roomDistance = distances.get(key);
            }
            if (doorway == null || roomDistance > bestRoomDistance) continue;
            var p = point(cell);
            var dx = p.x - doorway.x;
            var dy = p.y - doorway.y;
            var distance = dx * dx + dy * dy;
            if (roomDistance < bestRoomDistance || distance < bestDoorDistance) {
                best = cell;
                bestRoomDistance = roomDistance;
                bestDoorDistance = distance;
            }
        }
        return best;
    }

    public function isGentleDirection(x:Float, y:Float, target:Point):Bool {
        return target == gentleTarget && gentleOrigin != null
            && Math.abs(x - gentleOrigin.x) < step && Math.abs(y - gentleOrigin.y) < step;
    }

    function smallDetour(x:Float, y:Float, start:Int, route:Array<Int>, targetIndex:Int):Bool {
        var target = point(route[targetIndex]);
        var dx = target.x - x;
        var dy = target.y - y;
        var directDistance = Math.sqrt(dx * dx + dy * dy);
        if (directDistance < 1) return false;
        var distance = 0.;
        var previous = new Point(x, y);
        for (i in 0...route.length - targetIndex) {
            var cell = route[route.length - 1 - i];
            // Relax only a local obstacle within one room, preserving doorways.
            if (rooms[cell] != rooms[start]) return false;
            var p = point(cell);
            if (Math.abs((p.x - x) * dy - (p.y - y) * dx) / directDistance > 55) return false;
            distance += Point.distance(previous, p);
            previous = p;
        }
        return distance - directDistance <= 90;
    }

    function nextWaypoint(x:Float, y:Float, start:Int, route:Array<Int>):Point {
        gentleTarget = null;
        gentleOrigin = null;
        // Look as far as the first doorway so equal-length grid routes do not
        // send the player sideways before a reachable doorway.
        var room = rooms[start];
        var farthest = route.length - 1;
        while (farthest > 0 && rooms[route[farthest]] == room) farthest--;

        var crossing = point(route[farthest]);
        var dx = crossing.x - x;
        var dy = crossing.y - y;
        if (rooms[route[farthest]] != room && dx * dx + dy * dy <= 150 * 150) {
            var nextRoom = rooms[route[farthest]];
            var nextDoor = farthest;
            while (nextDoor > 0 && rooms[route[nextDoor]] == nextRoom) nextDoor--;
            var direct = point(route[nextDoor]);
            if (clearGridLine(x, y, direct) && canAim(x, y, direct)) return direct;

            var lookahead = Math.max(0, farthest - 6);
            while (farthest > lookahead && rooms[route[farthest - 1]] == nextRoom) farthest--;
        }

        for (i in farthest...route.length - 1) {
            var candidate = point(route[i]);
            if (clearGridLine(x, y, candidate) && canAim(x, y, candidate)) return candidate;
            if (smallDetour(x, y, start, route, i)) {
                gentleTarget = candidate;
                gentleOrigin = new Point(x, y);
                return candidate;
            }
        }
        // The first edge already follows adjacent walkable cells. A conservative
        // diagonal grid sample can fail near a cell corner, so check the actual step.
        var first = point(route[route.length - 1]);
        return canAim(x, y, first) ? first : null;
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
