import mods.gate_compass.*;
import mods.api.dungeon.Tile;
import openfl.geom.Point;
private class WallChordGrid extends WalkGrid {
 override public function canAim(x:Float,y:Float,target:Point,ignoredGate:UInt=0,smallObstacle:Bool=false):Bool {
  return false;
 }
}
@:access(mods.gate_compass.WalkGrid)
class HeadingChecks{static function main(){var g=new WalkGrid();g.width=30;g.height=30;g.left=0;g.top=0;g.step=10;var t=new Tile("room",0,0);g.cells=[for(i in 0...900)true];g.rooms=[for(i in 0...900)t];g.nearCollider=[for(i in 0...900)false];g.routeLine=[new Point(0.,0.),new Point(100.,0.),new Point(100.,250.)];var target=g.followLine(0,0);if(target==null||g.routeDirection.x<30||g.routeDirection.y<80)throw "compass used distant line heading instead of hero+30 averaged";g.followLine(80,0);if(g.routeDirection.y<40)throw "30-unit lookahead did not anticipate near corner";g.followLine(98,0);if(g.routeDirection.x<0||g.routeDirection.y<95)throw "30-unit chord failed across corner";g.followLine(100,248);if(Math.abs(g.routeDirection.y-100)>.001)throw "end-of-line heading lost";g.routeLine=[new Point(0.,0.),new Point(4.,0.),new Point(4.,1.),new Point(8.,1.),new Point(8.,0.),new Point(30.,0.)];g.followLine(0,0);if(g.routeDirection.x<99||Math.abs(g.routeDirection.y)>.001)throw "tiny segments changed averaged heading";g.routeDirection=new Point(100.,0.);g.routeLine=[new Point(100.,100.),new Point(0.,100.),new Point(0.,0.)];for(row in 0...30)g.cells[row*30+9]=false;if(g.followLine(100,100)!=null)throw "blocked candidate accepted";if(g.routeDirection.x!=100||g.routeDirection.y!=0)throw "rejected candidate overwrote the active heading";var temporary = new WalkGrid();temporary.width=4;temporary.height=1;temporary.left=0;temporary.top=0;temporary.step=100;
 temporary.cells=[true,true,true,true];temporary.rooms=[t,t,t,t];temporary.hazards=[false,false,false,false];temporary.nearCollider=[false,false,false,false];
 temporary.field=new RouteField(t,null,0,"test",4);temporary.field.next=[1,2,3,3];temporary.cachedQueries=true;
 temporary.routeLine=temporary.cachedLine(0,new Point(90,50));temporary.followLine(90,50);
 if(temporary.routeDirection.x<99)throw "temporary line pointed back to current cell centre";
 temporary.field.next=[0,0,1,2];temporary.routeLine=temporary.cachedLine(1,new Point(190,50));temporary.followLine(190,50);
 if(temporary.routeDirection.x>-99)throw "legitimate reversal suppressed";
 var direct=new WalkGrid();
 direct.width=70;direct.height=70;direct.left=0;direct.top=0;direct.step=10;
 direct.cells=[for(i in 0...4900)true];direct.rooms=[for(i in 0...4900)t];direct.nearCollider=[for(i in 0...4900)false];direct.hazards=[for(i in 0...4900)false];
 var detour=[new Point(100,500),new Point(400,500),new Point(400,100),new Point(100,100)];
 var shortened=direct.shortenLiveLine(detour);
 if(shortened.length!=2||shortened[1].x!=100||shortened[1].y!=100)throw "open-space sideways detour was retained";
 for(row in 20...40)direct.cells[row*70+10]=false;
 var blocked=direct.shortenLiveLine(detour);
 if(blocked.length==2)throw "shortcut crossed a wall";
 var approach=new WalkGrid();
 approach.width=100;approach.height=100;approach.left=0;approach.top=0;approach.step=10;
 approach.cells=[for(i in 0...10000)true];approach.rooms=[for(i in 0...10000)t];approach.nearCollider=[for(i in 0...10000)false];approach.hazards=[for(i in 0...10000)false];
 approach.routeLine=[new Point(800,500),new Point(100,500)];
 // Too short for a 300-unit connector at this projection: the fallback
 // must still aim from the hero toward the path instead of its tangent.
 approach.followLine(220,430);
 if(approach.routeDirection.y<=0)throw "off-route fallback ignored the hero's lateral approach";
 var bend=new WalkGrid();
 bend.width=100;bend.height=100;bend.left=0;bend.top=0;bend.step=10;
 bend.cells=[for(i in 0...10000)true];bend.rooms=[for(i in 0...10000)t];bend.nearCollider=[for(i in 0...10000)false];bend.hazards=[for(i in 0...10000)false];
 bend.routeLine=[new Point(600,600),new Point(576,600),new Point(576,200)];
 bend.followLine(600,600);
 if(bend.routeDirection.y>-90||bend.routeDirection.x < -40)throw "short side segment dominated the forward corridor";
 var wall=new WallChordGrid();
 wall.width=100;wall.height=100;wall.left=0;wall.top=0;wall.step=10;
 wall.cells=[for(i in 0...10000)true];wall.rooms=[for(i in 0...10000)t];wall.nearCollider=[for(i in 0...10000)false];wall.hazards=[for(i in 0...10000)false];
 wall.floor=new distributedObjects.DistributedDungeonFloor();
 wall.routeLine=[new Point(400,400),new Point(700,400)];wall.routeDirection=new Point(0,100);
 if(wall.followLine(410,403)!=null)throw "final segment bypassed exact wall-chord validation";
 if(wall.routeDirection.x!=0||wall.routeDirection.y!=100)throw "rejected wall chord overwrote heading";
 if(wall.canConnectRouteHead(new Point(410,403),new Point(600,400)))throw "curved head crossed a sub-cell wall";
 trace("PASS: reachable forward steering, short side-step rejection, corner crossing and terminal direction");}}
