import mods.gate_compass.*;
@:access(mods.gate_compass.FloorMeasurement)
class MeasurementChecks {
 static function main() {
  var root = Sys.getEnv("TEMP") + "/compass-measure-" + Std.random(1000000);
  sys.FileSystem.createDirectory(root);
  sys.io.File.saveContent(root + "/local-diagnostics.json", '{"enabled":true,"autoProfile":true}');
  var measurement = new FloorMeasurement(root);
  measurement.start(null, 0, 0);
  if (measurement.status.indexOf("only in a dungeon") < 0) throw "dungeon guard";
  var grid = new WalkGrid();
  for (floor in 1...4) {
   measurement.enter(floor);
   grid.stats.beginWork(false);
   measurement.tick(grid, 7, 10, 20);
   measurement.finish(grid);
  }
  if (sys.FileSystem.exists(root + "/route-capacity.jsonl")) throw "legacy opt-in started automatic logging";
  measurement.enter(4);
  measurement.start(grid, 10, 20);
  measurement.tick(grid, 7, 10, 20);
  if (measurement.manual != null) throw "manual test started before work";
  grid.stats.beginWork(true);
  measurement.tick(grid, 7, 10, 20);
  var window = measurement.manual;
  if (window == null) throw "explicit test missing";
  grid.stats.completed = 20;
  grid.stats.computeMs = 40;
  grid.stats.updateCount = 500;
  grid.stats.updateMs = 100;
  for (i in 0...3) measurement.sample(window, grid, 7, 10 + i, 20, window.started + [3., 5., 8.][i]);
  var rows = sys.io.File.getContent(root + "/route-capacity.jsonl").split("\n");
  if (rows.length != 4) throw "manual snapshots missing";
  measurement.finish(grid);
  measurement.enter(5);
  measurement.tick(grid, 7, 10, 20);
  if (measurement.manual != null) throw "new floor started test";
  trace("PASS: legacy auto-profile disabled, no automatic file writes, explicit manual test and 3/5/8 snapshots");
 }
}
