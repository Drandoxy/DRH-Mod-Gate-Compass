import mods.gate_compass.RouteClock;
class ClockChecks {
 static function main():Void {
  var next=0;var calls=0;
  for(now in 0...1000)if(now>=next){calls++;next=now+RouteClock.interval(false);}
  if(calls!=10)throw "normal route clock is not ten hertz";
  if(!RouteClock.urgent(200,0,false,false)||RouteClock.urgent(10,0,false,false))throw "movement urgency incorrect";
  if(!RouteClock.urgent(0,0,true,false)||!RouteClock.urgent(0,0,false,true))throw "corner or doorway delayed";
  if(RouteClock.interval(true)<100)throw "low power clock increases work";
  trace("PASS: ten normal samples per second, immediate large-jump/corner/room overrides");
 }
}
