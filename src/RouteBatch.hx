package mods.gate_compass;
import starling.display.Mesh;
import starling.styles.MeshStyle;
import starling.rendering.VertexData;
import starling.rendering.IndexData;
class RouteBatch {
    public var mesh:Mesh;
    var indices:IndexData;
    var source:VertexData;
    var active:VertexData;
    var maskKey = "";
    var lengths:Array<Float>;
    public function new(vertices:VertexData, opacity:Float, ?lengths:Array<Float>) {
        this.lengths=lengths;
        source=vertices;
        active=new VertexData(MeshStyle.VERTEX_FORMAT,vertices.numVertices);
        source.copyTo(active);
        indices = new IndexData();
        // Initialize native mesh/style state with real geometry. Starting with
        // an empty index buffer can leave the native batch treated as empty.
        var count = Std.int(vertices.numVertices / 8);
        for (i in 0...count) {
            var v=i*8;for(j in 0...3){indices.addTriangle(v+j,v+j+1,v+4+j);indices.addTriangle(v+j+1,v+5+j,v+4+j);}
        }
        mesh = new Mesh(active, indices, new MeshStyle()); mesh.alpha = opacity; mesh.touchable = false;
    }
    public function show(mask:Array<Bool>):Void {
        var key = [for (shown in mask) shown ? "1" : "0"].join("");
        if (key == maskKey) return;
        maskKey = key; indices.clear(); active.clear();
        var starts:Array<Float>=[];var ends:Array<Float>=[];var distance=0.;
        for(i in 0...mask.length){if(!mask[i])distance=0;starts[i]=distance;if(mask[i])distance+=lengths==null?5:lengths[i];}
        distance=0.;var n=mask.length;for(k in 0...n){var i=n-1-k;if(!mask[i])distance=0;ends[i]=distance;if(mask[i])distance+=lengths==null?5:lengths[i];}
        var target=0;
        for (i in 0...mask.length) if (mask[i]) {
            source.copyTo(active,target,null,i*8,8);
            var v=target;target+=8;
            var len=lengths==null?5:lengths[i];
            for(side in 0...2){var d=Math.min(starts[i]+side*len,ends[i]+(1-side)*len);var fade=Math.min(1.,Math.max(0.,d/25));fade=fade*fade*(3-2*fade);
                // Rounded cap silhouette plus a complete 25-world-unit fade.
                var cap=Math.sqrt(Math.max(0.,1-Math.pow(1-Math.min(1.,d/6),2)));
                var a=side==0?i*8:i*8+4;var p0=new openfl.geom.Point();var p3=new openfl.geom.Point();source.getPoint(a,"position",p0);source.getPoint(a+3,"position",p3);var cx=(p0.x+p3.x)/2;var cy=(p0.y+p3.y)/2;
                for(j in 0...4){var at=v+side*4+j;var p=new openfl.geom.Point();source.getPoint(a+j,"position",p);active.setPoint(at,"position",cx+(p.x-cx)*cap,cy+(p.y-cy)*cap);active.setAlpha(at,"color",(j==0||j==3?0.:1.)*fade);}
            }
            for(j in 0...3){indices.addTriangle(v+j,v+j+1,v+4+j);indices.addTriangle(v+j+1,v+5+j,v+4+j);}
        }
        mesh.setVertexDataChanged();
        mesh.setIndexDataChanged();
    }
    public function destroy():Void { mesh.removeFromParent(); mesh.dispose(); source.clear();active.clear();indices.clear();lengths=null; }
}
