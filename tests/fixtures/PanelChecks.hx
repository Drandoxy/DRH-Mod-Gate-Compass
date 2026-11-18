import mods.gate_compass.CompassTools;
import mods.gate_compass.CompassControl;
import mods.gate_compass.CompassOption;
import mods.api.Context;
@:access(mods.gate_compass.CompassTools)
class PanelChecks {
 static function main(){
  var ctx:Context=Type.createEmptyInstance(Context);ctx.viewWidth=1920;ctx.viewHeight=1080;ctx.data=Sys.getEnv("TEMP");
  var controls=[for(i in 0...5)new CompassControl("Size",new CompassOption<Float>(1,null),.5,4)];
  controls[4]=new CompassControl("Arrow distance",new CompassOption<Float>(20,null),-20,100,0);
  controls.push(new CompassControl("Line length",new CompassOption<Float>(600,null),300,2200,2200,50));
  controls.push(new CompassControl("Line start distance",new CompassOption<Float>(300,null),0,500,135,5));
  var flags=[for(i in 0...5)new CompassOption<Bool>(false,null)];
  var panel=new CompassTools(ctx,controls,flags);
  if(panel.popupHeight!=624||panel.tracks.length!=7)throw "panel does not include sixth slider";
  if(panel.tracks[5].y+30>=panel.popupHeight-40)throw "slider overlaps bottom buttons";
  panel.resetDefaults(new openfl.events.MouseEvent());
  if(controls[5].option.value!=2200||controls[4].option.value!=0||controls[6].option.value!=135)throw "reset lost control defaults";
  var reset:openfl.display.Sprite=cast panel.popup.getChildByName("reset");
  if(panel.popupHeight-reset.y-38!=24||reset.y-panel.tracks[6].y<30)throw "reset padding missing";
  if(panel.closeButton.x+19!=454||panel.closeButton.y+19!=8)throw "close no longer centred at board corner";
  for(i in 0...reset.numChildren) {
   var child=reset.getChildAt(i);
   if(Std.isOfType(child,openfl.text.TextField)) {
    var caption:openfl.text.TextField=cast child;
    if(caption.width!=198||caption.defaultTextFormat.align!=openfl.text.TextFormatAlign.CENTER)throw "button caption not centred";
   }
  }
  panel.destroy();trace("PASS: seven sliders, five switches, reset and layout after cache/test removal");
 }
}
