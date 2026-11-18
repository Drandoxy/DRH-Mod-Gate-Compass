class ASCompat {public static function createInstance(type:Dynamic,args:Array<Dynamic>):Dynamic {
 var clip=new openfl.display.MovieClip();
 if(type=="popup") {var base=new openfl.display.Sprite();base.name="popup_base";clip.addChild(base);var banner=new openfl.display.Sprite();banner.name="banner_title_label";clip.addChild(banner);}
 else {var label=new openfl.text.TextField();label.name="label";clip.addChild(label);}
 return clip;
}}