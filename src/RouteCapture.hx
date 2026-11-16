package mods.gate_compass;

class RouteCapture {
    static inline final MAX_FILES = 16;
    var directory:String;
    var sequence = 0;

    public function new(dataDirectory:String) {
        directory = dataDirectory + "/route-captures";
    }

    public function save(snapshot:Dynamic):String {
        if (!sys.FileSystem.exists(directory)) sys.FileSystem.createDirectory(directory);
        var date = DateTools.format(Date.now(), "%Y%m%d-%H%M%S");
        var name:String;
        var path:String;
        do {
            name = "route-" + date + "-" + StringTools.lpad(Std.string(sequence++), "0", 4) + ".json";
            path = directory + "/" + name;
        } while (sys.FileSystem.exists(path));

        sys.io.File.saveContent(path + ".tmp", haxe.Json.stringify(snapshot));
        sys.FileSystem.rename(path + ".tmp", path);

        var pattern = ~/^route-[0-9]{8}-[0-9]{6}-[0-9]+\.json$/;
        var files = [for (file in sys.FileSystem.readDirectory(directory)) if (pattern.match(file)) file];
        files.sort(Reflect.compare);
        for (i in 0...files.length - MAX_FILES) {
            var old = directory + "/" + files[i];
            if (!sys.FileSystem.isDirectory(old)) sys.FileSystem.deleteFile(old);
        }
        return name;
    }
}
