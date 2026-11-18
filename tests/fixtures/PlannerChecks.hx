import mods.gate_compass.*;
import mods.api.dungeon.Tile;
import openfl.geom.Point;
@:access(mods.gate_compass.WalkGrid)
@:access(mods.gate_compass.RouteCache)
class PlannerChecks {
 static function check(ok:Bool,message:String){if(!ok)throw message;}
 static function main(){
  var room=new Tile("test",0,0);var width=30;var size=width*width;
  var cells=[for(i in 0...size)true];var hazards=[for(i in 0...size)false];
  var rooms=[for(i in 0...size)room];var near=[for(i in 0...size)false];
  var grid=new RouteGrid(cells,hazards,rooms,near,new Map(),width,width,0,0,10);grid.complete=true;
  var old=new WalkGrid();old.cells=cells;old.hazards=hazards;old.rooms=rooms;old.width=width;old.height=width;old.left=0;old.top=0;old.step=10;old.nearCollider=near;
  // Probe results must match the synchronous collision/hazard oracle.
  for(k in 0...150){var a=grid.point((k*37)%size);var b=grid.point((k*131+7)%size);hazards[400]=k%2==0;
   var probe=new RouteProbe(grid,a,b);var guard=0;while(!probe.done&&guard++<10000)probe.step();
   check(probe.done&&probe.allowed==(old.clearGridLine(a.x,a.y,b)&&old.hazardFree(a.x,a.y,b)),"probe mismatch "+k);
  }
  hazards[400]=false;
  grid.complete=false;near[0]=true;near[1]=true;
  var waiting=new RouteProbe(grid,grid.point(0),grid.point(1));var attempts=0;
  while(!waiting.waiting&&!waiting.done&&attempts++<100)waiting.step();
  check(waiting.waiting&&!waiting.done,"unknown edge was treated as a completed rejection");
  grid.edges.set(0,true);while(!waiting.done&&attempts++<100)waiting.step();
  check(waiting.allowed,"waiting probe did not resume after edge answer");near[0]=false;near[1]=false;grid.complete=true;
  var next=[for(i in 0...size)i%width<width-1?i+1:(i<size-width?i+width:i)];
  var job=new RoutePlanJob(grid,next,0,grid.point(0),grid.point(size-1));
  check(job.runSlice(100,1)==1&&!job.done,"job did not yield after one step");
  var guard=0;while(!job.done&&guard++<100000)job.runSlice(100,7);
  check(job.done&&job.result.length==2,"open room farthest-visible path differs");
  // An L corridor forces original quadratic corner rounding, not just a straight route.
  for(i in 0...size)cells[i]=(i%width<6 || Std.int(i/width)>23);
  var chain=[];for(y in 0...27)chain.push(y*width+2);for(x in 3...28)chain.push(26*width+x);
  var bentNext=[for(i in 0...size)-1];for(i in 0...chain.length)bentNext[chain[i]]=i+1==chain.length?chain[i]:chain[i+1];
  var raw=[grid.point(chain[0])];for(cell in chain)raw.push(grid.point(cell));raw.push(grid.point(chain[chain.length-1]));
  var expected=new OriginalCurveOracle(old).naturalLine(raw,0);
  var bent=new RoutePlanJob(grid,bentNext,chain[0],grid.point(chain[0]),grid.point(chain[chain.length-1]));
  guard=0;while(!bent.done&&guard++<200000)bent.runSlice(100,3);
  check(bent.done&&bent.result.length==expected.length&&expected.length>3,"original corner count differs");
  for(i in 0...expected.length)check(Point.distance(expected[i],bent.result[i])<0.00001,"original curve geometry differs");
  var prefixRaw=[grid.point(chain[0])];var distance=0.;
  for(cell in chain){var p=grid.point(cell);distance+=Point.distance(prefixRaw[prefixRaw.length-1],p);prefixRaw.push(p);if(distance>=400)break;}
  var prefixExpected=new OriginalCurveOracle(old).naturalLine(prefixRaw,0);
  var prefix=new RoutePlanJob(grid,bentNext,chain[0],grid.point(chain[0]),grid.point(chain[chain.length-1]),400);
  guard=0;while(!prefix.done&&guard++<200000)prefix.runSlice(100,3);
  check(prefix.result.length==prefixExpected.length&&prefixExpected.length>3,"short first section lost original curves");
  for(i in 0...prefixExpected.length)check(Point.distance(prefixExpected[i],prefix.result[i])<0.00001,"first section curve geometry differs");
  for(i in 0...size)cells[i]=true;
  var cancelled=new RoutePlanJob(grid,next,0,grid.point(0),grid.point(size-1));cancelled.cancel();check(cancelled.runSlice(10,100)==0&&cancelled.result.length==0,"cancel did work");
  var stats=new NavigationStats();var cache=new RouteCache(grid,next,grid.point(size-1),stats);
  check(cache.limit==36,"default limit");cache.setLimit(3);check(cache.limit==10,"minimum");cache.setLimit(100);check(cache.limit==81,"maximum");cache.setLimit(36);
  var entry=cache.request(0);guard=0;while(entry.line==null&&guard++<10000)cache.advance(room,5,false);
  check(entry.line!=null&&cache.request(0)==entry&&stats.hits>0,"completed plan not reused");
  for(i in 0...5000)cache.advance(room,2,true);
  check(cache.alternatives(room).length<=36,"tile limit exceeded");
  // Moving away from the old path must not erase its visual while a new
  // uncached plan is queued. This is intentionally beyond the 95-unit tangent.
  var nav=new WalkGrid();nav.cells=cells;nav.hazards=hazards;nav.rooms=rooms;nav.width=width;nav.height=width;nav.left=0;nav.top=0;nav.step=10;nav.nearCollider=near;
  nav.prepareField(room,grid.point(size-1),1);nav.field.next=next;
  for(i in 0...size)nav.field.settled[i]=true;nav.field.phase=2;
  var held=[new Point(5.,5.),new Point(295.,5.)];nav.routeLine=held;nav.visualRoute=held;nav.appliedPlan=held;
  nav.prioritize(15,250);nav.waypoint(15,250,room,grid.point(size-1),1);
  check(nav.visualRoute==held,"uncached replacement erased the displayed route");
  check(nav.plans.foreground!=null&&nav.plans.foreground.line==null,"regression did not request an uncached route");
  nav.prepareField(room,grid.point(size-2),2);check(nav.visualRoute.length==0,"changed goal kept stale visual");
  var path=[new Point(0.,0.),new Point(100000.,0.)];var window=RouteWindow.cut(path,50000,0,3200);
  check(window.length==2&&Math.abs(window[1].x-53200)<0.001 && window[0].x>=49499,"mesh window not bounded");
  check(RouteVisibility.drawable(RouteVisibility.mask([for(i in 0...321)new Point(50000+i*10,0)],50000,0,135,2200)),"window invisible");
  trace("PASS: collision/hazard oracle, resumable jobs, cache reuse, 10/36/81 limits, bounded render window");
 }
}
