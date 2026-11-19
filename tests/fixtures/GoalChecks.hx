import mods.gate_compass.NavigationGoal;
import mods.api.dungeon.Tile;
class GoalChecks {
 static function check(ok:Bool,m:String) {if(!ok) throw m;}
 static function main() {
  var exit=new Tile("ordinary-exit",0,0);
  var boss=new Tile("435.1327521552662",0,100);boss.category="BOSS_TILE";
  check(NavigationGoal.choose([exit,boss])==boss,"Papa Yeti overridden by exit");
  check(NavigationGoal.choose([boss,exit])==boss,"Boss selection order");
  check(!NavigationGoal.verified(exit,false),"Unknown exit became random target");
  check(NavigationGoal.verified(exit,true),"Known gate rejected");
  check(NavigationGoal.verified(boss,false),"Boss requires nonexistent gate");
  check(!NavigationGoal.verified(null,false),"Missing goal accepted");
  trace("PASS: Papa Yeti boss priority; unknown gate withheld; boss without gate supported");
 }
}