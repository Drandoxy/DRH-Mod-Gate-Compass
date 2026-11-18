import mods.gate_compass.RouteVisibility;
import openfl.geom.Point;
class VisibilityChecks {
 static function main(){
  var long=[for(i in 0...301)new Point(i*10,0)];
  if(!RouteVisibility.drawable(RouteVisibility.mask(long,0,0,184,2200)))throw "usable replacement rejected";
  var short=[for(i in 0...11)new Point(i*10,0)];
  if(RouteVisibility.drawable(RouteVisibility.mask(short,0,0,184,2200)))throw "fade-hidden replacement accepted";
  if(!RouteVisibility.drawable(RouteVisibility.mask(long,900,0,184,2200)))throw "fast movement lost visible range";
  if(RouteVisibility.drawable(RouteVisibility.mask([],0,0,184,2200)))throw "empty geometry accepted";
  if(RouteVisibility.START_DISTANCE!=135||!RouteVisibility.drawable(RouteVisibility.mask(long,0,0,RouteVisibility.START_DISTANCE,2200)))throw "line head no longer uses requested 135-unit gap";trace("PASS: replacement preflight rejects blank geometry and preserves visible masks during fast movement");
 }
}