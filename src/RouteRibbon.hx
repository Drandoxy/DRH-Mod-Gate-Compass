package mods.gate_compass;

import openfl.geom.Point;
import starling.display.Mesh;
import starling.rendering.VertexData;
import starling.rendering.IndexData;
import starling.styles.MeshStyle;

/** Shared cross sections keep adjacent ribbon pieces gap-free without overlap. */
class RouteRibbon {
    public static function batch(points:Array<Point>, color:UInt, width:Float = 2.5, opacity:Float = 0.65, fadeEnds:Bool=true):RouteBatch {
        var normals:Array<Point> = [];
        for (i in 0...points.length) {
            var before = points[i == 0 ? 0 : i - 1];
            var after = points[i == points.length - 1 ? i : i + 1];
            var center = points[i];
            var ax = center.x - before.x; var ay = center.y - before.y;
            var bx = after.x - center.x; var by = after.y - center.y;
            var al = Math.sqrt(ax * ax + ay * ay); var bl = Math.sqrt(bx * bx + by * by);
            if (al < 0.001) { ax = bx; ay = by; al = bl; }
            if (bl < 0.001) { bx = ax; by = ay; bl = al; }
            al = Math.max(0.001, al); bl = Math.max(0.001, bl);
            var nx = -ay / al - by / bl; var ny = ax / al + bx / bl;
            var nl = Math.sqrt(nx * nx + ny * ny);
            if (nl < 0.001) { nx = -by / bl; ny = bx / bl; nl = 1; }
            nx /= nl; ny /= nl;
            var scale = Math.min(width, (width / 2) / Math.max(0.5, nx * (-by / bl) + ny * bx / bl));
            normals.push(new Point(nx * scale, ny * scale));
        }
        var vertices = new VertexData(MeshStyle.VERTEX_FORMAT, Std.int(Math.max(0, points.length - 1)) * 8);
        for (i in 0...points.length - 1) {
            var a=points[i];var b=points[i+1];var na=normals[i];var nb=normals[i+1];var v=i*8;
            var inner=Math.max(0.,1-2.2/width);
            var factors=[1.,inner,-inner,-1.];
            for(j in 0...4){
                vertices.setPoint(v+j,"position",a.x+na.x*factors[j],a.y+na.y*factors[j]);
                vertices.setPoint(v+4+j,"position",b.x+nb.x*factors[j],b.y+nb.y*factors[j]);
                var alpha=j==0||j==3?0.:1.;
                vertices.setColor(v+j,"color",color);vertices.setAlpha(v+j,"color",alpha);
                vertices.setColor(v+4+j,"color",color);vertices.setAlpha(v+4+j,"color",alpha);
            }
        }
        return new RouteBatch(vertices, opacity, [for(i in 0...points.length-1) Point.distance(points[i],points[i+1])],fadeEnds);
    }
}
