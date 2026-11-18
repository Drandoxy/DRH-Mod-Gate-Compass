import mods.gate_compass.ButtonHover;
import openfl.display.Sprite;
@:access(mods.gate_compass.ButtonHover)
class HoverChecks {
 static function main() {
  var facade:facade.DBFacade=Type.createEmptyInstance(facade.DBFacade);
  facade.mouseCursorManager=new brain.mouseCursor.MouseCursorManager();
  var button=new Sprite();var original:Dynamic={effect:"existing"};button.filters=[original];
  var hover=new ButtonHover(button,facade);
  hover.enter(null);hover.enter(null);
  if(facade.mouseCursorManager.pushes!=1||button.filters.length!=2)throw "duplicate cursor or missing native hover filter";
  button.handlers.get("removedFromStage")(new openfl.events.Event());
  if(facade.mouseCursorManager.pops!=1||button.filters.length!=1||button.filters[0]!=original)throw "removal left cursor/filter active";
  hover.leave(null);
  if(facade.mouseCursorManager.pops!=1)throw "cursor popped twice";
  hover.enter(null);hover.destroy();
  if(facade.mouseCursorManager.pops!=2||button.filters.length!=1)throw "destroy retained hover state";
  trace("PASS: native hover filter/POINT cursor ownership, removal reset, repeated events and disposal");
 }
}
