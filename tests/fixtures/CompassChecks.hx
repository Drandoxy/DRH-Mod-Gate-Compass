import mods.gate_compass.CompassPreferences;
import mods.gate_compass.CompassTools;
import mods.gate_compass.WalkGrid;
import mods.api.dungeon.Tile;
import distributedObjects.DistributedDungeonFloor;
@:access(mods.gate_compass.WalkGrid)
class CompassChecks {
 static function main(){
  var root=Sys.getEnv("TEMP")+"/compass-prefs-"+Std.random(1000000);sys.FileSystem.createDirectory(root);
  var old="{\"options\":{\"show2D\":true,\"show3D\":false,\"circleScaleV3\":2.5,\"arrowOffsetV2\":999}}";
  sys.io.File.saveContent(root+"/settings.json",old);
  var prefs=new CompassPreferences(root);var flag=prefs.flag("show2D",false);var ground=prefs.flag("show3D",true);var size=prefs.slider("circleScaleV3",1,.5,4);var offset=prefs.slider("arrowOffsetV2",0,-20,100);
  if(!flag.value||ground.value||size.value!=2.5||offset.value!=100)throw "migration/clamp failed";
  var calls=0;var sub=flag.onChange(function(_){calls++;});flag.value=false;flag.value=false;sub.cancel();flag.value=true;if(calls!=1)throw "change notification/cancel failed";size.value=3.;prefs.flush();
  if(sys.io.File.getContent(root+"/settings.json")!=old)throw "API settings overwritten";
  if(new CompassPreferences(root).slider("circleScaleV3",1,.5,4).value!=3.)throw "preferences not persisted";
  var grid=new WalkGrid();var floor=new DistributedDungeonFloor();var tile=new Tile("room",0,0);grid.refresh(floor,[tile]);while(grid.geometryPending())grid.advanceGeometry(100);var cells=grid.cells;var clearance=grid.clearance;var route=[new openfl.geom.Point(10,10),new openfl.geom.Point(90,90)];grid.routeLine=route;
  grid.refresh(floor,[tile]);while(grid.geometryPending())grid.advanceGeometry(100);if(grid.cells!=cells||grid.clearance!=clearance||grid.routeLine!=route)throw "identical geometry rebuilt";
  tile.x=100;grid.refresh(floor,[tile]);while(grid.geometryPending())grid.advanceGeometry(100);if(grid.cells==cells)throw "changed layout ignored";
  grid.clear();if(grid.cells.length!=0||grid.floor!=null)throw "grid disposal failed";
  trace("PASS: legacy preferences preserved, clamping, persistence, notification cleanup, identical-grid reuse, changed-layout rebuild");
 }
}