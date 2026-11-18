import mods.gate_compass.*;
import mods.api.Context;
import mods.api.dungeon.*;
import openfl.geom.Point;
@:access(mods.gate_compass.Main)
@:access(mods.gate_compass.CapacityDialog)
class CapacityFlowChecks {
 static function check(ok:Bool,m:String){if(!ok)throw m;}
 static function main(){
  var ctx:Context=Type.createEmptyInstance(Context);ctx.viewWidth=1000;ctx.viewHeight=800;ctx.data=Sys.getEnv("TEMP")+"/compass-flow-"+Std.random(1000000);sys.FileSystem.createDirectory(ctx.data);
  ctx.core=Type.createEmptyInstance(mods.api.Context.Core);ctx.core.overlay=new openfl.display.Sprite();ctx.core.overlay.stage=new openfl.display.Sprite();
  ctx.core.facade=Type.createEmptyInstance(facade.DBFacade);ctx.core.facade.mainStateMachine={currentStateName:"RunState"};
  ctx.state=Type.createEmptyInstance(mods.api.Context.LiveState);ctx.state.floor=new Floor();ctx.state.floor.id=7;
  var m=new Main();m.ctx=ctx;m.floorId=7;m.hero=new Hero();m.grid=new WalkGrid();m.panel=new Compass(ctx);
  m.preferences=new CompassPreferences(ctx.data);m.measurement=new FloorMeasurement(ctx.data);m.measurement.enter(7);
  var count=m.preferences.slider("routesPerTile",36,10,81);
  m.controls=[for(i in 0...8)new CompassControl("test",new CompassOption<Float>(1,null),0,500)];m.controls[5].option.value=600;m.controls[7].option.value=135;m.controls[6]=new CompassControl("count",count,10,81,36,1);
  m.displayFlags=[for(i in 0...6)new CompassOption<Bool>(false,null)];
  m.beginCapacityTest();check(m.testRequested&&m.capacityHud!=null,"test did not enter waiting state");m.grid.stats.beginWork(true);m.measurement.tick(m.grid,1,0,0);m.measurement.manualAdvice=24;
  m.tickCapacityTest(m.measurement.manualStarted+.4,16.7);check(m.lineBenchmark!=null,"actual-work marker did not start drawing");m.tickCapacityTest(m.measurement.manualStarted+8.1,16.7);
  check(!m.testRequested&&m.lineBenchmark==null&&m.capacityHud==null&&m.capacityDialog!=null,"results retained stress graphics");m.capacityDialog.finish(false);check(count.value==36,"No changed selected count");
  m.beginCapacityTest();m.grid.stats.beginWork(true);m.measurement.tick(m.grid,1,0,0);m.measurement.manualAdvice=24;m.tickCapacityTest(m.measurement.manualStarted+8.1,16.7);m.capacityDialog.finish(true);
  check(count.value==24&&m.grid.routeLimit==24,"Yes did not apply recommended count");
  var saved:Dynamic=haxe.Json.parse(sys.io.File.getContent(ctx.data+"/compass-appearance.json"));check(saved.routesPerTile==24,"Yes did not save selection");
  m.beginCapacityTest();m.hero.x=100;m.tickCapacityTest(haxe.Timer.stamp(),16.7);check(!m.testRequested&&m.capacityHud==null,"movement did not cancel waiting test");
  if(m.capacityDialog!=null)m.capacityDialog.destroy();m.capacityDialog=null;m.hero.x=0;m.beginCapacityTest();m.menuPaused=true;m.tickCapacityTest(haxe.Timer.stamp(),16.7);check(!m.testRequested,"menu did not cancel test");m.menuPaused=false;
  if(m.capacityDialog!=null)m.capacityDialog.destroy();m.capacityDialog=null;m.beginCapacityTest();m.clearFloor();check(!m.testRequested&&m.capacityHud==null&&m.lineBenchmark==null,"floor exit retained test load");
  check(starling.display.Mesh.living==0,"controller cleanup retained native meshes");
  trace("PASS: Main waits for work, removes test load, No preserves, Yes applies/saves, movement/menu/floor cancellation");
 }
}
