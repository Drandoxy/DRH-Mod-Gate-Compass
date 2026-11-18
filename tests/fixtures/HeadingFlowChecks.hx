import mods.gate_compass.*;
import mods.api.Context;
import mods.api.dungeon.*;
import openfl.geom.Point;
class SamplingGrid extends WalkGrid {
 public var calls=0;
 public var room:Tile;
 override public function cellAt(x:Float,y:Float):Int{return 0;}
 override public function roomAtCell(c:Int):Tile{return room;}
 override public function regionAt(x:Float,y:Float):String{return "same";}
 override public function advanceField():Bool{return false;}
 override public function waypoint(x:Float,y:Float,g:Tile,p:Point,id:UInt=0):Point{calls++;routeDirection=new Point(0,-100);return new Point(x,y-192);}
}
@:access(mods.gate_compass.Main)
class HeadingFlowChecks {
 static function main(){
  var ctx:Context=Type.createEmptyInstance(Context);ctx.viewWidth=1000;ctx.viewHeight=800;
  ctx.core=Type.createEmptyInstance(mods.api.Context.Core);ctx.core.overlay=new openfl.display.Sprite();
  ctx.core.facade=Type.createEmptyInstance(facade.DBFacade);ctx.core.facade.mainStateMachine={currentStateName:"RunState"};
  ctx.state=Type.createEmptyInstance(mods.api.Context.LiveState);ctx.state.floor=new Floor();ctx.state.floor.id=7;
  var floor=new distributedObjects.DistributedDungeonFloor();
  ctx.core.facade.gameObjectManager={getReferenceFromId:function(id:UInt):Dynamic{return id==7?floor:null;}};
  var main=new Main();main.ctx=ctx;main.floorId=7;main.hero=new Hero();main.hero.id=8;main.hero.x=5;main.hero.y=5;
  var grid=new SamplingGrid();grid.room=new Tile("room",0,0);main.grid=grid;main.goal=grid.room;
  main.panel=new Compass(ctx);main.displayFlags=[for(i in 0...6)new CompassOption<Bool>(i==2,null)];
  main.nextGeometry=2147483647;main.lastSearchRoom=grid.room;main.lastRegion="same";main.lastCell=0;
  main.waypoint=new Point(0,-192);main.lastSearchX=0;main.lastSearchY=5;
  openfl.Lib.now=10000;main.nextSearch=9999;main.updateNavigation(null);
  if(grid.calls!=1)throw "same-cell movement did not refresh heading";
  main.hero.x=6;openfl.Lib.now=10020;main.updateNavigation(null);
  if(grid.calls!=1)throw "heading ignored cooldown";
  main.hero.x=10;openfl.Lib.now=10100;main.updateNavigation(null);
  if(grid.calls!=2)throw "continued same-cell movement kept stale heading";
  for(i in 0...9){main.hero.x=11+i;openfl.Lib.now=10110+i*10;main.updateNavigation(null);}
  if(grid.calls!=2)throw "route work ran faster than ten updates per second";
  main.nextSearch=11000;main.hero.x=220;openfl.Lib.now=10210;main.updateNavigation(null);
  if(grid.calls!=3)throw "large jump waited for the normal clock";
  main.panel.destroy();trace("PASS: Main refreshes heading inside a cell and respects the existing cooldown");
 }
}
