import openfl.geom.Point;
import mods.gate_compass.WalkGrid;
@:access(mods.gate_compass.WalkGrid)
class OriginalCurveOracle {
 var grid:WalkGrid;public function new(grid:WalkGrid){this.grid=grid;}
 function corridorClear(x:Float,y:Float,p:Point):Bool{return grid.clearGridLine(x,y,p);}
 function hazardFree(x:Float,y:Float,p:Point):Bool{return grid.hazardFree(x,y,p);}
    public function naturalLine(raw:Array<Point>, gateId:UInt):Array<Point> {
        var result = [raw[0]];
        var at = 0;
        while (at < raw.length - 1) {
            var next = at + 1;
            for (offset in 0...raw.length - at - 2) {
                var i = raw.length - 1 - offset;
                if (corridorClear(raw[at].x, raw[at].y, raw[i]) && hazardFree(raw[at].x, raw[at].y, raw[i])) { next = i; break; }
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

}
