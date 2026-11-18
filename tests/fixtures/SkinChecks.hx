import mods.gate_compass.CompassSkin;
import mods.api.Context;
import openfl.display.Sprite;
import brain.assetRepository.AssetLoadingComponent;
class SkinChecks {
 static function main() {
  var ctx:Context=Type.createEmptyInstance(Context);ctx.core=Type.createEmptyInstance(mods.api.Context.Core);ctx.core.facade=Type.createEmptyInstance(facade.DBFacade);
  var skin=new CompassSkin(ctx);var panel=new Sprite();var button=new Sprite();
  skin.board(panel,540,350);skin.button(button,160,38);var header=new Sprite();skin.banner(header,"Compass settings",460);
  var cb=AssetLoadingComponent.callbacks.pop();cb(new brain.assetRepository.SwfAsset());
  var back:Sprite=cast panel.getChildAt(0);var bback:Sprite=cast button.getChildAt(0);
  if(button.graphics.rects.length!=1||button.graphics.rects[0].width!=160||!button.mouseEnabled||button.mouseChildren)throw "button lost own hit area after native loading";
  if(back.numChildren!=1||bback.numChildren!=1)throw "native artwork not attached";
  var clip:openfl.display.MovieClip=cast bback.getChildAt(0);
  if(clip.getChildByName("label").visible)throw "scaled native caption visible";
  if((cast header.getChildAt(0):Sprite).numChildren!=1)throw "native title ribbon missing";
  skin.destroy();
  var late=new CompassSkin(ctx);var abandoned=new Sprite();late.board(abandoned,100,100);late.destroy();
  AssetLoadingComponent.callbacks.pop()(new brain.assetRepository.SwfAsset());
  var deadBack:Sprite=cast abandoned.getChildAt(0);
  if(deadBack.numChildren!=0)throw "late callback attached after destruction";
  trace("PASS: native town board/button artwork, separate captions and late-load cancellation");
 }
}