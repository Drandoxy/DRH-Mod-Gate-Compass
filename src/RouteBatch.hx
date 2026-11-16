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
    public function new(vertices:VertexData, opacity:Float) {
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
        var target=0;
        for (i in 0...mask.length) if (mask[i]) {
            source.copyTo(active,target,null,i*8,8);
            var v=target;target+=8;
            for(j in 0...3){indices.addTriangle(v+j,v+j+1,v+4+j);indices.addTriangle(v+j+1,v+5+j,v+4+j);}
        }
        mesh.setVertexDataChanged();
        mesh.setIndexDataChanged();
    }
    public function destroy():Void { mesh.removeFromParent(); mesh.dispose(); source.clear(); }
}
