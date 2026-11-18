import mods.gate_compass.*;
import mods.api.dungeon.Tile;
@:access(mods.gate_compass.FloorMeasurement)
class CalibrationChecks{
 static function check(ok:Bool,m:String){if(!ok)throw m;}
 static function main(){
  check(CapacityAdvice.recommend(36,1200,600,2,9)==36,"long routes incorrectly forced a minimum count");
  check(CapacityAdvice.recommend(36,1200,600,4,34)==36,"isolated slice peak changed compatible count");
  check(CapacityAdvice.recommend(36,120,480,2,20)<36,"sustained CPU overhead not recognized");
  check(CapacityAdvice.recommend(36,120,60,8,20)<36,"repeated long slices not recognized");
  check(CapacityAdvice.recommend(36,1200,20,1,1)==0,"warm cache invented a confident recommendation");
  check(CapacityAdvice.percentile([0,0,98,0,0,0,0,0,0,2])==1,"one-off tail used instead of percentile");
  var m=new FloorMeasurement(Sys.getEnv("TEMP"));m.enter(3);var g=new WalkGrid();m.start(g,0,0);m.tick(g,1,0,0);
  check(m.manualStarted<0&&m.manual==null,"test clock began on click");
  var room=new Tile("test",0,0);var grid=new RouteGrid([true,true],[false,false],[room,room],[false,false],new Map(),2,1,0,0,10);
  var cache=new RouteCache(grid,[1,1],grid.point(1),g.stats);cache.requestTest(0);m.tick(g,1,0,0);
  check(m.manualStarted<0,"test clock began on job allocation");
  cache.advance(room,10,false);m.tick(g,1,0,0);
  check(m.manualStarted==g.stats.manualWork.time && m.manual.started==m.manualStarted,"test did not anchor to actual first job work");
  var trial=new DrawingTrial(100.);
  for(i in 0...481){var now=100+i/60.;var n=trial.target(now);trial.sample(now,n<=8?16.667:30.,n,false);}
  var result:Dynamic=trial.result();check(trial.done&&result.valid&&result.stableAdditionalLines==8,"drawing stages or relative performance assessment");
  check(trial.remaining(108)==0&&new DrawingTrial(100).remaining(100)==8,"countdown wrong");
  var severe=new DrawingTrial(0);for(i in 0...3)severe.sample(i*.3,300,1,false);check(severe.done&&severe.stopped!="","severe frame slowdown did not stop load");
  check(RouteVisibility.startDistance(135,2200)==135 && RouteVisibility.startDistance(500,300)==250 && RouteVisibility.startDistance(-10,2200)==0,"line-start clamp");
  trace("PASS: calibrated 36 preserved, recurring workload reduction, actual-work clock, drawing stages/countdown, slow-frame stop, start-distance clamp");
 }
}
