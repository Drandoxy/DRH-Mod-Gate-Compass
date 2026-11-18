import mods.gate_compass.*;
import mods.api.dungeon.Tile;
import distributedObjects.DistributedDungeonFloor;
import distributedObjects.NPCGameObject;
import box2D.dynamics.*;
import box2D.collision.shapes.*;
@:access(mods.gate_compass.WalkGrid)
@:access(GeometryOracle)
class GeometryChecks{
 static function check(ok:Bool,m:String){if(!ok)throw m;}
 static function body(shape:Dynamic,id:Int):Body{var b=new Body();b.data=id;var f=new B2Fixture();f.body=b;f.shape=shape;b.fixture=f;return b;}
 static function drain(g:WalkGrid){var guard=0;while(g.geometryPending()&&guard++<100000)g.advanceGeometry(100,64);check(!g.geometryPending(),"geometry did not finish");}
 static function main(){
  var floor=new DistributedDungeonFloor();var polygon=new B2PolygonShape();polygon.vertices=[{x:.4,y:.4},{x:1.1,y:.4},{x:1.1,y:1.2},{x:.4,y:1.2}];
  var circle=new B2CircleShape();circle.center={x:5.,y:3.};circle.radius=.18;
  var trap=new B2CircleShape();trap.center={x:1.6,y:1.6};trap.radius=.1;
  var a=body(polygon,1);var b=body(circle,2);var c=body(trap,3);a.next=b;b.next=c;c.active=false;floor.box2DWorld.first=a;
  var npc=new NPCGameObject();npc.gmNpc={Species:"TRAP",Constant:"TEST_TRAP"};
  floor.remoteActors={itemFor:function(id:Dynamic){return id==3?npc:null;}};
  var tiles=[new Tile("a",0,0),new Tile("b",200,100)];
  var oracle=new GeometryOracle();oracle.refresh(floor,tiles);
  var g=new WalkGrid();g.refresh(floor,tiles);check(g.cells.length==0,"partial geometry published at request");
  g.advanceGeometry(100,1);check(g.geometryBuild.steps==1&&g.cells.length==0,"geometry step ceiling ignored");drain(g);
  check(g.cells.length==oracle.cells.length,"grid dimensions changed");
  for(i in 0...g.cells.length){check(g.cells[i]==oracle.cells[i],"occupancy "+i);check(g.hazards[i]==oracle.hazards[i],"hazard "+i);check(g.nearCollider[i]==oracle.nearCollider[i],"near collider "+i);check(g.clearance[i]==oracle.clearance[i],"clearance "+i);}
  var held=g.cells;g.refresh(floor,tiles);g.refresh(floor,tiles);drain(g);check(g.cells==held,"unchanged grid discarded");
  circle.radius=.4;g.refresh(floor,tiles);g.advanceGeometry(100,2);check(g.cells==held,"changed partial grid published");drain(g);check(g.cells!=held,"changed geometry ignored");
  g.refresh(floor,tiles);g.clear();check(!g.geometryPending()&&g.floor==null,"clear retained pending native references");
  trace("PASS: original occupancy/hazards/clearance, sparse flood, bounded steps, atomic publication, unchanged reuse, queued refresh and cancellation");
 }
}
