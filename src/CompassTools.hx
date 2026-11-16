package mods.gate_compass;
import mods.api.Context;
import mods.api.settings.Flag;
import openfl.display.Sprite;
import brain.assetRepository.SwfAsset;
import facade.DBFacade;
import openfl.display.MovieClip;
import openfl.display.BitmapData;
import openfl.events.MouseEvent;
import openfl.text.TextField;
import openfl.text.TextFormat;
import openfl.geom.Point;
import openfl.filters.ColorMatrixFilter;
class CompassTools extends Sprite {
 var switches:Array<Sprite>=[];var flags:Array<Flag>=[];var popupHeight=365.;
 var ctx:Context;var controls:Array<CompassControl>;var button=new Sprite();var popup=new Sprite();
 var tracks:Array<Sprite>=[];var labels:Array<TextField>=[];var active=-1;var moving=false;var offset=new Point();var icon:BitmapData;
 var layoutReady=false;var pressTime=0.;var closeButton=new Sprite();
 var iconHolder=new Sprite();var disposed=false;
 var buttonGrip=new Sprite();var popupGrip=new Sprite();var layoutKind=0;var origin=new Point();var initial=new Point();var initialScale=1.;var suppressClick=false;
 public function new(ctx:Context,controls:Array<CompassControl>,?flags:Array<Flag>){super();this.ctx=ctx;this.controls=controls;if(flags!=null)this.flags=flags;popupHeight=365+this.flags.length*36;
  button.graphics.lineStyle(2,0x38230D);button.graphics.beginFill(0x084A0C);button.graphics.drawRoundRect(0,0,36,36,10,10);button.graphics.endFill();button.graphics.lineStyle(1,0x25B52B);button.graphics.beginFill(0x008D0A);button.graphics.drawRoundRect(3,3,30,30,7,7);button.graphics.endFill();button.graphics.lineStyle(0,0,0);button.graphics.beginFill(0x13B81E,.6);button.graphics.drawRoundRect(5,5,26,11,5,5);button.graphics.endFill();
  iconHolder.mouseEnabled=false;iconHolder.mouseChildren=false;button.addChild(iconHolder);
  fallbackGear();
  var facade=ctx.core.facade;
  if(facade!=null&&facade.assetLoadingComponent!=null)
   facade.assetLoadingComponent.getSwfAsset(DBFacade.buildFullDownloadPath("Resources/Art2D/UI/db_UI_town.swf"),loadGear);

  button.buttonMode=true;button.mouseChildren=false;button.addEventListener(MouseEvent.CLICK,toggle);button.addEventListener(MouseEvent.MOUSE_DOWN,buttonDown);addChild(button);
  grip(buttonGrip,button,25,25);grip(popupGrip,popup,304,popupHeight-16);
  popup.graphics.beginFill(0x17271D,.98);popup.graphics.lineStyle(2,0x69865A);popup.graphics.drawRoundRect(0,0,320,popupHeight,18,18);popup.graphics.endFill();
  var header=new Sprite();header.graphics.beginFill(0,0);header.graphics.drawRect(0,0,278,48);header.graphics.endFill();var title=label("Compass settings",17);title.x=20;title.y=14;title.mouseEnabled=false;header.addChild(title);header.buttonMode=true;header.addEventListener(MouseEvent.MOUSE_DOWN,drag);popup.addChild(header);
  closeButton.graphics.beginFill(0x314D37);closeButton.graphics.drawRoundRect(0,0,28,28,8,8);closeButton.graphics.endFill();closeButton.graphics.lineStyle(2,0xFFFFFF);closeButton.graphics.moveTo(8,8);closeButton.graphics.lineTo(20,20);closeButton.graphics.moveTo(20,8);closeButton.graphics.lineTo(8,20);closeButton.x=276;closeButton.y=12;closeButton.buttonMode=true;closeButton.addEventListener(MouseEvent.CLICK,close);popup.addChild(closeButton);
  var reset=new Sprite();reset.graphics.beginFill(0x236D2B);reset.graphics.drawRoundRect(0,0,104,30,10,10);reset.graphics.endFill();var caption=label("Reset",14);caption.width=104;caption.height=24;caption.x=0;caption.y=6;caption.autoSize=openfl.text.TextFieldAutoSize.NONE;var resetFormat=new TextFormat("_sans",14,0xFFFFFF,true);resetFormat.align=openfl.text.TextFormatAlign.CENTER;caption.setTextFormat(resetFormat);caption.mouseEnabled=false;reset.addChild(caption);reset.x=20;reset.y=316+this.flags.length*36;reset.buttonMode=true;reset.addEventListener(MouseEvent.CLICK,resetDefaults);popup.addChild(reset);
  var names=["2D","3D","Pathfinder","Smooth Compass"];
  for(i in 0...this.flags.length){var row=new Sprite();var name=label(names[i],14);name.mouseEnabled=false;row.addChild(name);var toggle=new Sprite();toggle.x=236;toggle.y=0;row.addChild(toggle);switches.push(toggle);row.x=20;row.y=54+i*36;row.buttonMode=true;row.addEventListener(MouseEvent.CLICK,function(e){e.stopPropagation();this.flags[i].value=!this.flags[i].value;refresh();});popup.addChild(row);}
  for(i in 0...controls.length){var text=label("",14);text.x=20;text.y=57+this.flags.length*36+i*50;labels.push(text);popup.addChild(text);var track=new Sprite();track.x=20;track.y=88+this.flags.length*36+i*50;track.buttonMode=true;tracks.push(track);popup.addChild(track);track.addEventListener(MouseEvent.MOUSE_DOWN,function(e){e.stopPropagation();active=tracks.indexOf(cast e.currentTarget);listen();slide(e);});}
  popup.setChildIndex(popupGrip,popup.numChildren-1);popup.addEventListener(MouseEvent.MOUSE_DOWN,block);popup.x=44;popup.visible=false;addChild(popup);refresh();defaultLayout();
 }
 function fallbackGear():Void{
  var g=iconHolder.graphics;g.clear();g.beginFill(0xFFFFFF);
  for(i in 0...64){var angle=i*Math.PI/32;var radius=(i%8<4)?13.:10.;var px=18+Math.cos(angle)*radius;var py=18+Math.sin(angle)*radius;if(i==0)g.moveTo(px,py);else g.lineTo(px,py);}
  g.endFill();g.beginFill(0x126D16);g.drawCircle(18,18,5);g.endFill();
 }
 function loadGear(asset:SwfAsset):Void{
  if(disposed||asset==null)return;
  var type=asset.getClass("options_panel_button");if(type==null)return;
  var art=Std.downcast(ASCompat.createInstance(type,[]),MovieClip);if(art==null)return;
  art.gotoAndStop(1);art.mouseEnabled=false;art.mouseChildren=false;
  var bounds=art.getBounds(art);if(bounds.width<=0||bounds.height<=0)return;
  var factor=28/Math.max(bounds.width,bounds.height);
  art.scaleX=art.scaleY=factor;art.x=18-(bounds.x+bounds.width/2)*factor;art.y=18-(bounds.y+bounds.height/2)*factor;
  art.filters=[new ColorMatrixFilter([0,0,0,0,240,0,0,0,0,255,0,0,0,0,238,0,0,0,1,0])];
  iconHolder.graphics.clear();iconHolder.addChild(art);
 }
 function label(text:String,size:Int):TextField{var t=new TextField();t.defaultTextFormat=new TextFormat("_sans",size,0xF2F8EF,true);t.width=300;t.height=27;t.selectable=false;t.text=text;return t;}
 function block(e:MouseEvent):Void{e.stopPropagation();}
 function toggle(e:MouseEvent):Void{e.stopPropagation();if(suppressClick){suppressClick=false;return;}popup.visible=!popup.visible;clampPopup();refresh();}
 function close(e:MouseEvent):Void{e.stopPropagation();popup.visible=false;save();}
 function defaultLayout():Void{button.scaleX=button.scaleY=1.5833333333;popup.scaleX=popup.scaleY=1;x=ctx.viewWidth/2+392.6;y=ctx.viewHeight-75;popup.x=-3.36;popup.y=-popupHeight-10;clampPopup();}
 function resetDefaults(e:MouseEvent):Void{e.stopPropagation();for(c in controls)c.option.value=c.label=="Arrow distance"?0:1;for(i in 0...flags.length)flags[i].value=i!=0;defaultLayout();refresh();save();}
 function grip(handle:Sprite,parent:Sprite,hx:Float,hy:Float):Void{handle.graphics.beginFill(0x90B985,1);handle.graphics.drawRect(0,0,16,16);handle.graphics.endFill();var marks=new Sprite();marks.mouseEnabled=false;marks.visible=false;handle.addChild(marks);handle.graphics.beginFill(0,0);handle.graphics.drawRect(0,0,16,16);handle.graphics.endFill();marks.graphics.lineStyle(1,0xFFFFFF);marks.graphics.moveTo(3,12);marks.graphics.lineTo(12,3);marks.graphics.moveTo(8,12);marks.graphics.lineTo(12,8);handle.addEventListener(MouseEvent.ROLL_OVER,function(e){marks.visible=true;});handle.addEventListener(MouseEvent.ROLL_OUT,function(e){marks.visible=false;});handle.alpha=1;handle.graphics.clear();handle.graphics.beginFill(0,0);handle.graphics.drawRect(0,0,16,16);handle.graphics.endFill();handle.x=hx;handle.y=hy;handle.buttonMode=true;parent.addChild(handle);handle.addEventListener(MouseEvent.MOUSE_DOWN,resize);if(parent==button){button.mouseChildren=true;handle.addEventListener(MouseEvent.CLICK,block);}}
 function resize(e:MouseEvent):Void{e.stopPropagation();layoutKind=e.currentTarget==buttonGrip?2:3;origin.x=e.stageX;origin.y=e.stageY;initialScale=layoutKind==2?button.scaleX:popup.scaleX;listen();}
 function buttonDown(e:MouseEvent):Void{e.stopPropagation();layoutKind=1;pressTime=haxe.Timer.stamp();suppressClick=false;origin.x=e.stageX;origin.y=e.stageY;initial.x=x;initial.y=y;listen();}
 function clampPopup():Void{popup.x=Math.max(-x,Math.min(ctx.viewWidth-x-320*popup.scaleX,popup.x));popup.y=Math.max(-y,Math.min(ctx.viewHeight-y-popupHeight*popup.scaleY,popup.y));}
 function drag(e:MouseEvent):Void{e.stopPropagation();var p=popup.globalToLocal(new Point(e.stageX,e.stageY));moving=true;var at=globalToLocal(new Point(e.stageX,e.stageY));offset.x=at.x-popup.x;offset.y=at.y-popup.y;listen();}
 function listen():Void{if(stage!=null){stage.addEventListener(MouseEvent.MOUSE_MOVE,slide);stage.addEventListener(MouseEvent.MOUSE_UP,finish);}}
 function slide(e:MouseEvent):Void{
  if(layoutKind==1){var dx=e.stageX-origin.x;var dy=e.stageY-origin.y;if(haxe.Timer.stamp()-pressTime>=.5&&Math.abs(dx)+Math.abs(dy)>4){suppressClick=true;x=Math.max(0,Math.min(ctx.viewWidth-38*button.scaleX,initial.x+dx));y=Math.max(0,Math.min(ctx.viewHeight-38*button.scaleY,initial.y+dy));clampPopup();}}
  if(layoutKind==2){var value=Math.max(.6,Math.min(3,initialScale+(e.stageX-origin.x+e.stageY-origin.y)/72));button.scaleX=button.scaleY=value;}
  if(layoutKind==3){var value=Math.max(.65,Math.min(2,initialScale+(e.stageX-origin.x+e.stageY-origin.y)/645));popup.scaleX=popup.scaleY=value;clampPopup();}
  if(moving){var at=globalToLocal(new Point(e.stageX,e.stageY));popup.x=Math.max(-x,Math.min(ctx.viewWidth-x-320*popup.scaleX,at.x-offset.x));popup.y=Math.max(-y,Math.min(ctx.viewHeight-y-popupHeight*popup.scaleY,at.y-offset.y));}if(active>=0){var p=tracks[active].globalToLocal(new Point(e.stageX,e.stageY));var c=controls[active];var value=c.minimum+Math.max(0,Math.min(1,p.x/280))*(c.maximum-c.minimum);c.option.value=Math.round(value*100)/100;refresh();}}
 function finish(e:MouseEvent):Void{active=-1;moving=false;layoutKind=0;if(stage!=null){stage.removeEventListener(MouseEvent.MOUSE_MOVE,slide);stage.removeEventListener(MouseEvent.MOUSE_UP,finish);}save();}
 function refresh():Void{for(i in 0...switches.length){var g=switches[i].graphics;g.clear();g.beginFill(flags[i].value?0x43B750:0x526159);g.drawRoundRect(0,0,44,22,22,22);g.endFill();g.beginFill(0xFFFFFF);g.drawCircle(flags[i].value?33:11,11,8);g.endFill();}for(i in 0...controls.length){var c=controls[i];labels[i].text=c.label+": "+Math.round(c.option.value*100)/100;var g=tracks[i].graphics;g.clear();g.beginFill(0,0);g.drawRect(-6,-12,292,24);g.endFill();g.lineStyle(6,0x405347);g.moveTo(0,0);g.lineTo(280,0);var at=(c.option.value-c.minimum)/(c.maximum-c.minimum)*280;g.lineStyle(6,0x72CE65);g.moveTo(0,0);g.lineTo(at,0);g.beginFill(0xFFFFFF);g.drawCircle(at,0,8);g.endFill();}}
 public function setShown(value:Bool):Void{if(value&&!layoutReady&&ctx.viewWidth>0&&ctx.viewHeight>0){defaultLayout();load();layoutReady=true;}if(!value&&visible)finish(null);visible=value;}
 function load():Void{try{var p:Dynamic=haxe.Json.parse(sys.io.File.getContent(ctx.data+"/compass-tools.json"));if(p.layoutVersion!=3&&p.layoutVersion!=4)return;if(p.buttonY==0&&p.y>0)return;if(p.x!=null)popup.x=p.x;if(p.y!=null)popup.y=p.y;
 if(p.buttonX!=null)x=p.buttonX;if(p.buttonY!=null)y=p.buttonY;
 if(p.buttonScale!=null)button.scaleX=button.scaleY=Math.max(.6,Math.min(3,p.buttonScale));
 if(p.popupScale!=null)popup.scaleX=popup.scaleY=Math.max(.65,Math.min(2,p.popupScale));
 x=Math.max(0,Math.min(ctx.viewWidth-38*button.scaleX,x));y=Math.max(0,Math.min(ctx.viewHeight-38*button.scaleY,y));clampPopup();}catch(_:Dynamic){}}
 function save():Void{if(!layoutReady||ctx.viewWidth<=0||ctx.viewHeight<=0)return;try{sys.io.File.saveContent(ctx.data+"/compass-tools.json",haxe.Json.stringify({layoutVersion:4,x:popup.x,y:popup.y,buttonX:x,buttonY:y,buttonScale:button.scaleX,popupScale:popup.scaleX}));}catch(_:Dynamic){}}
 public function destroy():Void{disposed=true;finish(null);button.removeEventListener(MouseEvent.CLICK,toggle);button.removeEventListener(MouseEvent.MOUSE_DOWN,buttonDown);popup.removeEventListener(MouseEvent.MOUSE_DOWN,block);if(parent!=null)parent.removeChild(this);if(icon!=null)icon.dispose();}
}
