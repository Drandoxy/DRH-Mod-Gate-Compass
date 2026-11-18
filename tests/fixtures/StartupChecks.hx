import mods.gate_compass.*;
import mods.api.dungeon.Tile;
import openfl.geom.Point;
@:access(mods.gate_compass.WalkGrid)
@:access(mods.gate_compass.RouteCache)
class StartupChecks {
 static function check(ok:Bool,message:String){if(!ok)throw message;}
 static function fixture(focus:Bool):WalkGrid {
  var g=new WalkGrid();var width=40;var count=width*width;
  var tile=new Tile("room",0,0);
  g.width=width;g.height=width;g.left=0;g.top=0;g.step=10;
  g.cells=[for(i in 0...count)true];g.rooms=[for(i in 0...count)tile];
  g.nearCollider=[for(i in 0...count)false];g.hazards=[for(i in 0...count)i%37==0];g.clearance=[for(i in 0...count)2];
  g.prepareField(tile,null,0);g.prioritize(255,255);
  if(!focus)g.focusCell=-1;
  return g;
 }
 static function main(){
  var guided=fixture(true);var reference=fixture(false);var target=25*40+25;
  var count=0;while(!guided.field.settled[target]&&count++<10000)guided.advanceFieldWork(100);
  var guidedEarly=[for(v in guided.field.settled)if(v)true].length;
  check(guided.field.settled[target],"focused search did not reach hero");
  count=0;while(!reference.field.settled[target]&&count++<10000)reference.advanceFieldWork(100);
  var referenceEarly=[for(v in reference.field.settled)if(v)true].length;
  check(guidedEarly<referenceEarly,"focus heuristic did not prioritize initial guidance");
  count=0;while(guided.field.phase!=2&&count++<10000)guided.advanceFieldWork(100);
  count=0;while(reference.field.phase!=2&&count++<10000)reference.advanceFieldWork(100);
  for(i in 0...guided.cells.length)check(Math.abs(guided.field.scores[i]-reference.field.scores[i])<0.0001,"heuristic changed weighted route costs at "+i);
  var snapshot=new RouteGrid([true,true],[false,false],[guided.rooms[0],guided.rooms[0]],[true,true],new Map(),2,1,0,0,10);
  var calls=0;snapshot.checkEdge=function(a,b){calls++;return true;};
  var probe=new RouteProbe(snapshot,new Point(5.,5.),new Point(15.,5.));
  count=0;while(!probe.done&&count++<100)probe.step();
  check(probe.allowed&&calls==1&&!probe.waiting,"probe waited for whole field instead of checking the needed edge");
  check(snapshot.cross(0,1)&&calls==1,"on-demand edge answer not cached");
  guided.field.gate=new Point(50.,50.);check(guided.retryGateSeeds()&&guided.field.fullSeeds,"full gate fallback missing");
  check(!guided.retryGateSeeds(),"fallback loops indefinitely");
  var lineRoom=new Tile("long",0,0);var lineSize=1000;
  var lineGrid=new RouteGrid([for(i in 0...lineSize)true],[for(i in 0...lineSize)false],[for(i in 0...lineSize)lineRoom],[for(i in 0...lineSize)false],new Map(),lineSize,1,0,0,10);
  var lineNext=[for(i in 0...lineSize)i+1==lineSize?i:i+1];
  var first=new RouteCache(lineGrid,lineNext,lineGrid.point(lineSize-1),new NavigationStats());first.request(0);
  count=0;while(first.preview==null&&count++<10000)first.advance(lineRoom,1,false);
  check(first.preview!=null&&first.foreground.line==null&&first.foreground.job.steps==0,"first section waited for full-route calculation");
  check(first.preview[first.preview.length-1].x<=2815,"section incorrectly appended the distant gate");
  check(first.preview[first.preview.length-1].x>2200,"section too short for visible line");
  var work=fixture(true);work.field.phase=1;for(i in 0...work.cells.length)work.field.next[i]=i%40==39?i:i+1;
  work.ensurePlans();work.plans.request(work.focusCell);var scanBefore=work.field.scan;var heapBefore=work.field.heap.length;
  work.advanceField(false);
  check(work.field.scan==scanBefore&&work.field.heap.length==heapBefore&&(work.plans.preview!=null || (work.plans.previewJob!=null && work.plans.previewJob.steps>0)),"optional field work delayed foreground section");
  var fallback=fixture(true);fallback.field.phase=1;fallback.field.gate=new Point(50.,50.);fallback.field.heap=[];
  fallback.advanceField(false);check(fallback.field.fullSeeds&&fallback.plans!=null,"fallback left scheduler with a null planner");
  trace("PASS: earlier hero reach, identical completed weighted costs, cached on-demand edges, bounded gate fallback");
 }
}
