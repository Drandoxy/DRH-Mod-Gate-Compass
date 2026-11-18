import mods.gate_compass.*;
import mods.api.Context;
import openfl.display.Sprite;
@:access(mods.gate_compass.CapacityDialog)
class RenderUiChecks {
 static function check(ok:Bool,m:String){if(!ok)throw m;}
 static function main(){
  var ctx:Context=Type.createEmptyInstance(Context);ctx.viewWidth=1000;ctx.viewHeight=800;
  ctx.core=Type.createEmptyInstance(mods.api.Context.Core);ctx.core.overlay=new Sprite();ctx.core.overlay.stage=new Sprite();
  var yes=0;var no=0;
  var dialog=new CapacityDialog(ctx,"Results","Apply recommended settings?",function(){yes++;},function(){no++;});ctx.overlay.addChild(dialog);
  dialog.key(new openfl.events.KeyboardEvent(13));check(yes==0&&no==0,"enter selected Yes without deliberate choice");
  dialog.key(new openfl.events.KeyboardEvent(39));dialog.key(new openfl.events.KeyboardEvent(13));check(no==1&&yes==0&&dialog.parent==null,"first navigation did not select No");
  var apply=new CapacityDialog(ctx,"Results","Apply?",function(){yes++;},function(){no++;});apply.finish(true);apply.finish(true);check(yes==1,"Yes applied more than once");
  var hud=new CapacityHud(ctx,function(){});hud.show("8 s left");hud.destroy();
  var benchmark=new LineBenchmark(0,1.8,300,false);var parent=new starling.display.Sprite();parent.addChild(benchmark);
  for(i in 0...480)benchmark.tick(i/60.,16.667);
  check(benchmark.count==32&&starling.display.Mesh.living==64,"staged native test did not draw 32 two-layer lines");
  benchmark.destroy();check(starling.display.Mesh.living==0&&benchmark.parent==null,"test meshes retained after completion/cancel");
  trace("PASS: result Yes/No ownership, no automatic Yes selection, HUD lifecycle, 32 staged real ribbons, native mesh cleanup");
 }
}
