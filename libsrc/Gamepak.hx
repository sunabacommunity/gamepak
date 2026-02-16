package;
import haxe.Json;
import haxe.io.BytesBuffer;
import haxe.io.Bytes;
import haxe.ds.StringMap;
import sys.io.File;
import sys.FileSystem;
#if js
#else
import org.msgpack.MsgPack;
#end
class Gamepak {

    public var snbprojPath: String;
    public var projDirPath: String = "";

    public var jsprojJson: ProjectFile;

    public var zipOutputPath: String = "";

    public var haxePath: String = "haxe"; // Default path to Haxe compiler

    public var markExecutable: Bool = true; // Whether to mark the output as executable

    public var resourceFormats = [
        ".vscn",
        ".vpfb",
        ".vres"
    ];

    public function new() {}

    public var chmodder: (String)->Void;

    public function build(snbprojPath: String): Void {
        Sys.println("Building project at: " + snbprojPath);

        snbprojPath = FileSystem.absolutePath(snbprojPath);

        // Here you would implement the logic to build the project
        // For now, we just print a message
        this.snbprojPath = snbprojPath;
        var snbProjPathArray = snbprojPath.split("/");
        this.projDirPath = snbProjPathArray.slice(0, snbProjPathArray.length - 1).join("/");
        Sys.println("Project directory path: " + this.projDirPath);
        var binPath = this.projDirPath + "/bin";
        if (!FileSystem.exists(binPath)) {
            FileSystem.createDirectory(binPath);
            Sys.println("Created bin directory: " + binPath);
        } else {
            Sys.println("Bin directory already exists: " + binPath);
        }

        // Load the XML project file
        try {
            var json = sys.io.File.getContent(snbprojPath);
            this.jsprojJson = haxe.Json.parse(json);
            Sys.println("Successfully loaded project JSON.");

            Sys.println("Project name: " + this.jsprojJson.name);
            Sys.println("Project version: " + this.jsprojJson.version);
            Sys.println("Project type: " + this.jsprojJson.type);
            Sys.println("Script directory: " + this.jsprojJson.scriptdir);
            Sys.println("Assets directory: " + this.jsprojJson.assetsdir);
            Sys.println("API symbols enabled: " + this.jsprojJson.apisymbols);
            Sys.println("Source map enabled: " + this.jsprojJson.sourcemap);
            Sys.println("Entrypoint: " + this.jsprojJson.entrypoint);
            Sys.println("js binary: " + this.jsprojJson.mainscript);
            Sys.println("Libraries: " + this.jsprojJson.libraries.join(", "));
            Sys.println("Compiler flags: " + this.jsprojJson.compilerFlags.join(", "));

            if (jsprojJson.type == "executable") {
                if (zipOutputPath == "") {
                    zipOutputPath = this.projDirPath + "/bin/" + this.jsprojJson.name + ".snb";
                }
                else if (StringTools.endsWith(zipOutputPath, ".slib")) {
                    Sys.println("Warning: Output path ends with .slib, changing to .snb");
                    zipOutputPath = StringTools.replace(zipOutputPath, ".slib", ".snb");
                }
                else if (StringTools.endsWith(zipOutputPath, ".snb")) {
                    // Do nothing, already correct
                }
                else {
                    zipOutputPath += ".snb";
                }
            }
            else if (jsprojJson.type == "library") {
                if (zipOutputPath == "") {
                    zipOutputPath = this.projDirPath + "/bin/" + this.jsprojJson.name + ".slib";
                }
                else if (StringTools.endsWith(zipOutputPath, ".snb")) {
                    Sys.println("Warning: Output path ends with .snb, changing to .slib");
                    zipOutputPath = StringTools.replace(zipOutputPath, ".snb", ".slib");
                }
                else if (StringTools.endsWith(zipOutputPath, ".slib")) {
                    // Do nothing, already correct
                }
                else {
                    zipOutputPath += ".slib";
                }
            } else {
                Sys.println("Unknown project type: " + this.jsprojJson.type);
                Sys.exit(1);
                return;
            }

            var command = this.generateHaxeBuildCommand();
            Sys.println("Generated Haxe build command: " + command);

            Sys.println("Output path for binary: " + zipOutputPath);

            var hxres = Sys.command("cd \"" + this.projDirPath + "\" && " + command);

            if (hxres != 0) {
                Sys.println("Haxe build command failed with exit code: " + hxres);
                Sys.exit(hxres);
                return;
            }

            Sys.println("Haxe build command executed successfully.");

            var mainjsPath = this.projDirPath + "/" + this.jsprojJson.mainscript;
            if (!FileSystem.exists(mainjsPath)) {
                Sys.println("Main js file does not exist: " + mainjsPath);
                Sys.exit(1);
                return;
            }

            //Sys.println("Reading main js file: " + mainjsPath);
            var mainjsContent = File.getBytes(mainjsPath);

            // Create the zip file using haxe.zip.Writer
            //Sys.println("Creating zip file at: " + zipOutputPath);
            var out = sys.io.File.write(zipOutputPath, true);
            var writer = new haxe.zip.Writer(out);

            // Collect all zip entries in a list
            var entries = new haxe.ds.List<haxe.zip.Entry>();

            //Sys.println("Adding main js file to zip: " + this.snbProjJson.mainscript);
            // Add main js file to the zip
            var entry:haxe.zip.Entry = {
                fileName: this.jsprojJson.mainscript,
                fileTime: Date.now(),
                dataSize: mainjsContent.length,
                fileSize: mainjsContent.length,
                data: mainjsContent,
                crc32: haxe.crypto.Crc32.make(mainjsContent),
                compressed: false
            };
            entries.add(entry);
            FileSystem.deleteFile(mainjsPath);

            if (this.jsprojJson.sourcemap != false) {
                var sourceMapName = this.jsprojJson.mainscript + ".map";
                var sourceMapPath = this.projDirPath + "/" + sourceMapName;
                if (FileSystem.exists(sourceMapPath)) {
                    //Sys.println("Adding source map file: " + sourceMapName);
                    var sourceMapContent = File.getBytes(sourceMapPath);
                    var sourceMapEntry:haxe.zip.Entry = {
                        fileName: sourceMapName,
                        fileSize: sourceMapContent.length,
                        dataSize: sourceMapContent.length,
                        fileTime: Date.now(),
                        data: sourceMapContent,
                        crc32: haxe.crypto.Crc32.make(sourceMapContent),
                        compressed: false
                    };
                    entries.add(sourceMapEntry);
                    FileSystem.deleteFile(sourceMapPath);
                } else {
                    Sys.println("Source map file does not exist, skipping: " + sourceMapName);
                }
            }
            if (this.jsprojJson.apisymbols != false) {
                var typesXmlPath = this.projDirPath + "/types.xml";
                if (FileSystem.exists(typesXmlPath)) {
                    //Sys.println("Adding types XML file: types.xml");
                    var typesXmlContent = File.getBytes(typesXmlPath);
                    var typesXmlEntry:haxe.zip.Entry = {
                        fileName: "types.xml",
                        fileSize: typesXmlContent.length,
                        dataSize: typesXmlContent.length,
                        fileTime: Date.now(),
                        data: typesXmlContent,
                        crc32: haxe.crypto.Crc32.make(typesXmlContent),
                        compressed: false
                    };
                    entries.add(typesXmlEntry);
                    FileSystem.deleteFile(typesXmlPath);
                } else {
                    Sys.println("Types XML file does not exist, skipping.");
                }
            }


            var assetPath = this.projDirPath + "/" + this.jsprojJson.assetsdir;
            if (FileSystem.exists(assetPath)) {
                var assets = this.getAllFiles(assetPath);

                var assetKeys = [];
                for (k in assets.keys()) assetKeys.push(k);
                //Sys.println("Found " + assetKeys.length + " asset files in the project.");

                // Add all asset files to the zip
                for (assetKey in assetKeys) {
                    var newAssetPath = assetKey;
                    var assetContent = assets.get(assetKey);
                    for (resourceFormat in resourceFormats) {
                        if (StringTools.endsWith(assetKey, resourceFormat)) {
                            newAssetPath += ".dat";
                            var assetStr = assetContent.toString();
                            var assetData = Json.parse(assetStr);
#if js
#else
                            assetContent = MsgPack.encode(assetData);
#end
                            break;
                        }
                    }
                    Sys.println("Adding asset file: " + assetKey);
                    var assetEntry:haxe.zip.Entry = {
                        fileName: StringTools.replace(newAssetPath, "assets/", ""),
                        fileSize: assetContent.length,
                        dataSize: assetContent.length,
                        fileTime: Date.now(),
                        data: assetContent,
                        crc32: haxe.crypto.Crc32.make(assetContent),
                        compressed: false
                    };
                    entries.add(assetEntry);
                }
            }
            

            Sys.println("creating header for zip file");

            var header : HeaderFile = {
                name: this.jsprojJson.name,
                version: this.jsprojJson.version,
                rootUrl: this.jsprojJson.rootUrl,
                mainscript: this.jsprojJson.mainscript,
                runtime: "js",
                type: this.jsprojJson.type
            };

            var headerJson = haxe.Json.stringify(header);
            Sys.println("Adding header to zip file: header.json");
            var headerContent = haxe.io.Bytes.ofString(headerJson);
            var headerEntry:haxe.zip.Entry = {
                fileName: "header.json",
                fileSize: headerContent.length,
                dataSize: headerContent.length,
                fileTime: Date.now(),
                data: headerContent,
                crc32: haxe.crypto.Crc32.make(headerContent),
                compressed: false
            };
            entries.add(headerEntry);
            

            writer.write(entries);
            // Close the output stream
            out.close();

            if (this.markExecutable) {
                // Mark the output file as executable
                Sys.println("Marking output file as executable: " + zipOutputPath);
                /*var shebang = "#!/usr/bin/env sunaba\n"; // or "#!/usr/bin/env sh\n"
                var zipBytes = File.getBytes(zipOutputPath);
                var shebangBytes = Bytes.ofString(shebang);
        
                // Combine shebang + zip
                var outputBytes = Bytes.alloc(shebangBytes.length + zipBytes.length);
                outputBytes.blit(0, shebangBytes, 0, shebangBytes.length);
                outputBytes.blit(shebangBytes.length, zipBytes, 0, zipBytes.length);

                // Write to new executable file
                var out = File.write(zipOutputPath, true); // binary mode
                out.write(outputBytes);
                out.close();

                if (jsprojJson.type == "executable") {
                    Sys.println("snb file created successfully at: " + zipOutputPath);
                }
                else if (jsprojJson.type == "library") {
                    Sys.println("slib file created successfully at: " + zipOutputPath);
                }*/
            }

            
            
        } catch (e: Dynamic) {
            Sys.println("Error loading project JSON: " + e);
            Sys.exit(1);
            return;
        }
    }

    private function generateHaxeBuildCommand(): String {

        var hxml = generateHaxeBuildHxml();
        var hxmlPath = "" + projDirPath + "/build.hxml";

        File.saveContent(hxmlPath, hxml);

        var haxePath: String = this.haxePath;

        if (StringTools.contains(haxePath, " ")) {
            haxePath = "\"" + this.haxePath + "\"";
        }

        var command = "" + haxePath + " \"" + hxmlPath + "\"";

        return command;
        /*var command = this.haxePath + " --class-path " + this.projDirPath + "/" + this.snbProjJson.scriptdir + " -main " + this.snbProjJson.entrypoint + " --library sunaba";
        if (this.snbProjJson.apisymbols != false) {
            command += " --xml " + this.projDirPath + "/types.xml";
        }
        if (this.snbProjJson.sourcemap != false) {
            command += " -D source-map";
        }
        command += " -js " + this.projDirPath + "/" + this.snbProjJson.mainscript += " -D js-ver 5.4";

        var librariesStr = "";
        for (lib in this.snbProjJson.libraries) {
            librariesStr += " --library " + lib;
        }
        command += " " + this.snbProjJson.compilerFlags.join(" ");
        return command;*/
    }

    var useExternApi = false;

    private function generateHaxeBuildHxml(): String {
        var command = "--class-path \"" + this.jsprojJson.scriptdir + "\"\n-main " + this.jsprojJson.entrypoint + "\n--library sunaba";
        if (this.jsprojJson.apisymbols != false) {
            command += "\n--xml types.xml";
        }
        if (this.jsprojJson.sourcemap != false) {
            command += "\n-D source-map";
        }
        command += "\n-js \"" + this.jsprojJson.mainscript += "\"\n-D js-es=6";

        var librariesStr = "";
        for (lib in this.jsprojJson.libraries) {
            librariesStr += "\n--library " + lib;
        }
        command += "\n" + this.jsprojJson.compilerFlags.join("\n");
        return command;
    }

    private function getAllFiles(dir:String): StringMap<Bytes> {
        if (!FileSystem.exists(dir)) {
            throw "Directory does not exist: " + dir;
        }

        var vdir = StringTools.replace(dir, this.projDirPath, "");

        var assets = new StringMap<Bytes>();

        for (f in FileSystem.readDirectory(dir)) {
            var filePath = dir + "/" + f;
            if (FileSystem.isDirectory(filePath)) {
                // Recursively get files from subdirectory
                var subAssets = getAllFiles(filePath);
                for (key in subAssets.keys()) {
                    assets.set(key, subAssets.get(key));
                }
            } else {
                // Read file content
                var content = File.getBytes(filePath);
                var vfilePath = StringTools.replace(filePath, this.projDirPath, "");
                if (StringTools.startsWith(vfilePath, "/")) {
                    vfilePath = vfilePath.substr(1);
                }
                //Sys.println("Adding file to assets: " + vfilePath);
                assets.set(vfilePath, content);
            }
        }

        return assets;
    }
}