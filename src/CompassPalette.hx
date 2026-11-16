package mods.gate_compass;
import mods.api.Context;
class CompassPalette {
    var catalogue:Map<String,String> = new Map();
    public function new(ctx:Context) {
        try {
            var data:Dynamic=haxe.Json.parse(sys.io.File.getContent(ctx.resources+"/tile_themes.json"));
            for(id in Reflect.fields(data))catalogue.set(id,Std.string(Reflect.field(data,id)));
        }catch(_:Dynamic){}
    }
    public function detect(ctx:Context):Int {
        var floor=ctx.state.floor;if(floor==null)return color("arena");
        var votes:Map<String,Int>=new Map();var selected="arena";var most=0;
        for(tile in floor.tiles){
            if(tile.category=="FILLER_TILE")continue;
            var theme=catalogue.get(tile.id);if(theme==null)continue;
            var count=votes.exists(theme)?votes.get(theme)+1:1;votes.set(theme,count);
            if(count>most){most=count;selected=theme;}
        }
        return color(selected);
    }
    public static function color(theme:String):Int {
        return switch(theme){
            case "arena":0x83ECFF;
            case "prison":0xC7A3FF;
            case "catacombs":0xFFD36E;
            case "tribal":0xFFA5EB;
            case "dino":0xBEB0FF;
            case "aztec":0xFFAF80;
            case "caves":0xFFD36E;
            case "village":0xFFAF80;
            case "temple":0xFFD36E;
            default:0x83ECFF;
        }
    }
}
