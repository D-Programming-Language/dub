/**
	Stuff with dependencies.

	Copyright: © 2012 Matthias Dondorff
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
	Authors: Matthias Dondorff
*/
module dub.package_;

import dub.compilers.compiler;
import dub.dependency;
import dub.internal.vibecompat.core.log;
import dub.internal.vibecompat.core.file;
import dub.internal.vibecompat.data.json;
import dub.internal.vibecompat.inet.url;
import dub.utils;

import std.algorithm;
import std.array;
import std.conv;
import std.exception;
import std.file;
import std.range;
import std.string;
import std.traits : EnumMembers;

enum PackageJsonFilename = "package.json";


/// Indicates where a package has been or should be installed to.
enum InstallLocation {
	/// Packages installed with 'local' will be placed in the current folder 
	/// using the package name as destination.
	local,
	/// Packages with 'projectLocal' will be placed in a folder managed by
	/// dub (i.e. inside the .dub subfolder). 
	projectLocal,
	/// Packages with 'userWide' will be placed in a folder accessible by
	/// all of the applications from the current user.
	userWide,
	/// Packages installed with 'systemWide' will be placed in a shared folder,
	/// which can be accessed by all users of the system.
	systemWide
}

/// Representing an installed package, usually constructed from a json object.
/// 
/// Json file example:
/// {
/// 	"name": "MetalCollection",
/// 	"author": "VariousArtists",
/// 	"version": "1.0.0",
///		"url": "https://github.org/...",
///		"keywords": "a,b,c",
///		"category": "music.best",
/// 	"dependencies": {
/// 		"black-sabbath": ">=1.0.0",
/// 		"CowboysFromHell": "<1.0.0",
/// 		"BeneathTheRemains": {"version": "0.4.1", "path": "./beneath-0.4.1"}
/// 	}
///		"licenses": {
///			...
///		}
///		"configurations": [
// TODO: what and how?
///		]
// TODO: plain like this or packed together?
///			"
///			"dflags-X"
///			"lflags-X"
///			"libs-X"
///			"files-X"
///			"copyFiles-X"
///			"versions-X"
///			"importPaths-X"
///			"stringImportPaths-X"	
///			"sourcePath"
/// 	}
///	}
///
/// TODO: explain configurations
class Package {
	static struct LocalPackageDef { string name; Version version_; Path path; }

	private {
		InstallLocation m_location;
		Path m_path;
		PackageInfo m_info;
	}

	this(InstallLocation location, Path root)
	{
		this(jsonFromFile(root ~ PackageJsonFilename), location, root);
	}

	this(Json packageInfo, InstallLocation location = InstallLocation.local, Path root = Path())
	{
		m_location = location;
		m_path = root;

		// check for default string import folders
		foreach(defvf; ["views"]){
			auto p = m_path ~ defvf;
			if( existsFile(p) )
				m_info.buildSettings.stringImportPaths[""] ~= defvf;
		}

		string[] app_files;
		auto pkg_name = packageInfo.name.get!string();

		// check for default source folders
		foreach(defsf; ["source", "src"]){
			auto p = m_path ~ defsf;
			if( existsFile(p) ){
				m_info.buildSettings.sourcePaths[""] ~= defsf;
				m_info.buildSettings.importPaths[""] ~= defsf;
				if( existsFile(p ~ "app.d") ) app_files ~= Path(defsf ~ "/app.d").toNativeString();
				else if( existsFile(p ~ (pkg_name~".d")) ) app_files ~= Path(defsf ~ "/"~pkg_name~".d").toNativeString();
			}
		}

		// parse the JSON description
		{
			scope(failure) logError("Failed to parse package description in %s", root.toNativeString());
			m_info.parseJson(packageInfo);
		}

		// generate default configurations if none are defined
		if( m_info.configurations.length == 0 ){
			if( m_info.buildSettings.targetType == TargetType.executable ){
				BuildSettingsTemplate app_settings;
				app_settings.targetType = TargetType.executable;
				m_info.configurations ~= ConfigurationInfo("application", app_settings);
			} else {
				if( m_info.buildSettings.targetType == TargetType.autodetect ){
					if( app_files.length ){
						BuildSettingsTemplate app_settings;
						app_settings.targetType = TargetType.executable;
						m_info.configurations ~= ConfigurationInfo("application", app_settings);
					}
				}

				BuildSettingsTemplate lib_settings;
				lib_settings.targetType = TargetType.library;
				lib_settings.excludedSourceFiles[""] = app_files;
				m_info.configurations ~= ConfigurationInfo("library", lib_settings);
			}
		}
	}
	
	@property string name() const { return m_info.name; }
	@property string vers() const { return m_info.version_; }
	@property Version ver() const { return Version(m_info.version_); }
	@property const(PackageInfo) info() const { return m_info; }
	@property installLocation() const { return m_location; }
	@property Path path() const { return m_path; }
	@property Path packageInfoFile() const { return m_path ~ "package.json"; }
	@property const(Dependency[string]) dependencies() const { return m_info.dependencies; }
	
	@property string[] configurations()
	const {
		auto ret = appender!(string[])();
		foreach( ref config; m_info.configurations )
			ret.put(config.name);
		return ret.data;
	}

	void warnOnSpecialCompilerFlags()
	{
		// warn about use of special flags
		m_info.buildSettings.warnOnSpecialCompilerFlags(m_info.name, null);
		foreach (ref config; m_info.configurations)
			config.buildSettings.warnOnSpecialCompilerFlags(m_info.name, config.name);
	}

	/// Returns all BuildSettings for the given platform and config.
	BuildSettings getBuildSettings(in BuildPlatform platform, string config)
	const {
		logDebug("Using config %s for %s", config, this.name);
		foreach(ref conf; m_info.configurations){
			if( conf.name != config ) continue;
			BuildSettings ret;
			m_info.buildSettings.getPlatformSettings(ret, platform, this.path);
			conf.buildSettings.getPlatformSettings(ret, platform, this.path);
			if( ret.targetName.empty ) ret.targetName = this.name;
			return ret;
		}
		assert(false, "Unknown configuration for "~m_info.name~": "~config);
	}

	string getSubConfiguration(string config, in Package dependency, in BuildPlatform platform)
	const {
		bool found = false;
		foreach(ref c; m_info.configurations){
			if( c.name == config ){
				if( auto pv = dependency.name in c.buildSettings.subConfigurations ) return *pv;
				found = true;
				break;
			}
		}
		assert(found, "Invliad configuration \""~config~"\" for "~this.name);
		if( auto pv = dependency.name in m_info.buildSettings.subConfigurations ) return *pv;
		return null;
	}

	/// Returns the default configuration to build for the given platform
	string getDefaultConfiguration(in BuildPlatform platform, bool is_main_package = false)
	const {
		foreach(ref conf; m_info.configurations){
			if( !conf.matchesPlatform(platform) ) continue;
		// FIXME Is this really necessary? What about application dependencies?
		//	if( !is_main_package && conf.buildSettings.targetType == TargetType.executable ) continue;
			return conf.name;
		}
		throw new Exception(format("Found no suitable configuration for %s on this platform.", this.name));
	}

	/// Human readable information of this package and its dependencies.
	string generateInfoString() const {
		string s;
		s ~= m_info.name ~ ", version '" ~ m_info.version_ ~ "'";
		s ~= "\n  Dependencies:";
		foreach(string p, ref const Dependency v; m_info.dependencies)
			s ~= "\n    " ~ p ~ ", version '" ~ to!string(v) ~ "'";
		return s;
	}
	
	/// Writes the json file back to the filesystem
	void writeJson(Path path) {
		auto dstFile = openFile((path~PackageJsonFilename).toString(), FileMode.CreateTrunc);
		scope(exit) dstFile.close();
		dstFile.writePrettyJsonString(m_info.toJson());
		assert(false);
	}

	/// Adds an dependency, if the package is already a dependency and it cannot be
	/// merged with the supplied dependency, an exception will be generated.
	void addDependency(string packageId, const Dependency dependency) {
		Dependency dep = new Dependency(dependency);
		if(packageId in m_info.dependencies) { 
			dep = dependency.merge(m_info.dependencies[packageId]);
			if(!dep.valid()) throw new Exception("Cannot merge with existing dependency.");
		}
		m_info.dependencies[packageId] = dep;
	}

	/// Removes a dependecy.
	void removeDependency(string packageId) {
		if (packageId in m_info.dependencies)
			m_info.dependencies.remove(packageId);
	}
} 

struct PackageInfo {
	string name;
	string version_;
	string description;
	string homepage;
	string[] authors;
	string copyright;
	string license;
	string[] ddoxFilterArgs;
	Dependency[string] dependencies;
	BuildSettingsTemplate buildSettings;
	ConfigurationInfo[] configurations;

	void parseJson(Json json)
	{
		foreach( string field, value; json ){
			switch(field){
				default: break;
				case "name": this.name = value.get!string; break;
				case "version": this.version_ = value.get!string; break;
				case "description": this.description = value.get!string; break;
				case "homepage": this.homepage = value.get!string; break;
				case "authors": this.authors = deserializeJson!(string[])(value); break;
				case "copyright": this.copyright = value.get!string; break;
				case "license": this.license = value.get!string; break;
				case "-ddoxFilterArgs": this.ddoxFilterArgs = deserializeJson!(string[])(value); break;
				case "dependencies":
					foreach( string pkg, verspec; value ) {
						enforce(pkg !in this.dependencies, "The dependency '"~pkg~"' is specified more than once." );
						Dependency dep;
						if( verspec.type == Json.Type.Object ){
							auto ver = verspec["version"].get!string;
							if( auto pp = "path" in verspec ){
								dep = new Dependency(Version(ver));
								dep.path = Path(verspec.path.get!string());
							} else dep = new Dependency(ver);
						} else {
							// canonical "package-id": "version"
							dep = new Dependency(verspec.get!string());
						}
						this.dependencies[pkg] = dep;
					}
					break;
				case "configurations":
					TargetType deftargettp = TargetType.library;
					if (this.buildSettings.targetType != TargetType.autodetect)
						deftargettp = this.buildSettings.targetType;

					foreach( settings; value ){
						ConfigurationInfo ci;
						ci.parseJson(settings, deftargettp);
						this.configurations ~= ci;
					}
					break;
			}
		}

		// parse build settings
		this.buildSettings.parseJson(json);

		enforce(this.name.length > 0, "The package \"name\" field is missing or empty.");
	}

	Json toJson()
	const {
		auto ret = buildSettings.toJson();
		ret.name = this.name;
		if( !this.version_.empty ) ret["version"] = this.version_;
		if( !this.description.empty ) ret.description = this.description;
		if( !this.homepage.empty ) ret.homepage = this.homepage;
		if( !this.authors.empty ) ret.authors = serializeToJson(this.authors);
		if( !this.copyright.empty ) ret.copyright = this.copyright;
		if( !this.license.empty ) ret.license = this.license;
		if( !this.ddoxFilterArgs.empty ) ret["-ddoxFilterArgs"] = this.ddoxFilterArgs.serializeToJson();
		if( this.dependencies ){
			auto deps = Json.EmptyObject;
			foreach( pack, d; this.dependencies ){
				if( d.path.empty ){
					deps[pack] = d.toString();
				} else deps[pack] = serializeToJson(["version": d.version_.toString(), "path": d.path.toString()]);
			}
			ret.dependencies = deps;
		}
		if( this.configurations ){
			Json[] configs;
			foreach(config; this.configurations)
				configs ~= config.toJson();
			ret.configurations = configs;
		}
		return ret;
	}
}

struct ConfigurationInfo {
	string name;
	string[] platforms;
	BuildSettingsTemplate buildSettings;

	this(string name, BuildSettingsTemplate build_settings)
	{
		this.name = name;
		this.buildSettings = build_settings;
	}

	void parseJson(Json json, TargetType default_target_type = TargetType.library)
	{
		this.buildSettings.targetType = default_target_type;

		foreach(string name, value; json){
			switch(name){
				default: break;
				case "name":
					this.name = value.get!string();
					enforce(!this.name.empty, "Configurations must have a non-empty name.");
					break;
				case "platforms": this.platforms = deserializeJson!(string[])(value); break;
			}
		}

		enforce(!this.name.empty, "Configuration is missing a name.");

		BuildSettingsTemplate bs;
		this.buildSettings.parseJson(json);
	}

	Json toJson()
	const {
		auto ret = buildSettings.toJson();
		ret.name = name;
		if( this.platforms.length ) ret.platforms = serializeToJson(platforms);
		return ret;
	}

	bool matchesPlatform(in BuildPlatform platform)
	const {
		if( platforms.empty ) return true;
		foreach(p; platforms)
			if( platform.matchesSpecification("-"~p) )
				return true;
		return false;
	}
}

struct BuildSettingsTemplate {
	TargetType targetType = TargetType.autodetect;
	string targetPath;
	string targetName;
	string[string] subConfigurations;
	string[][string] dflags;
	string[][string] lflags;
	string[][string] libs;
	string[][string] sourceFiles;
	string[][string] sourcePaths;
	string[][string] excludedSourceFiles;
	string[][string] copyFiles;
	string[][string] versions;
	string[][string] importPaths;
	string[][string] stringImportPaths;
	string[][string] preGenerateCommands;
	string[][string] postGenerateCommands;
	string[][string] preBuildCommands;
	string[][string] postBuildCommands;
	BuildRequirements[string] buildRequirements;

	void parseJson(Json json)
	{
		foreach(string name, value; json)
		{
			auto idx = std.string.indexOf(name, "-");
			string basename, suffix;
			if( idx >= 0 ) basename = name[0 .. idx], suffix = name[idx .. $];
			else basename = name;
			switch(basename){
				default: break;
				case "targetType":
					enforce(suffix.empty, "targetType does not support platform customization.");
					targetType = value.get!string().to!TargetType();
					break;
				case "targetPath":
					enforce(suffix.empty, "targetPath does not support platform customization.");
					this.targetPath = value.get!string;
					break;
				case "targetName":
					enforce(suffix.empty, "targetName does not support platform customization.");
					this.targetName = value.get!string;
					break;
				case "subConfigurations":
					enforce(suffix.empty, "subConfigurations does not support platform customization.");
					this.subConfigurations = deserializeJson!(string[string])(value);
					break;
				case "dflags": this.dflags[suffix] = deserializeJson!(string[])(value); break;
				case "lflags": this.lflags[suffix] = deserializeJson!(string[])(value); break;
				case "libs": this.libs[suffix] = deserializeJson!(string[])(value); break;
				case "files":
				case "sourceFiles": this.sourceFiles[suffix] = deserializeJson!(string[])(value); break;
				case "sourcePaths": this.sourcePaths[suffix] = deserializeJson!(string[])(value); break;
				case "sourcePath": this.sourcePaths[suffix] ~= [value.get!string()]; break; // deprecated
				case "excludedSourceFiles": this.excludedSourceFiles[suffix] = deserializeJson!(string[])(value); break;
				case "copyFiles": this.copyFiles[suffix] = deserializeJson!(string[])(value); break;
				case "versions": this.versions[suffix] = deserializeJson!(string[])(value); break;
				case "importPaths": this.importPaths[suffix] = deserializeJson!(string[])(value); break;
				case "stringImportPaths": this.stringImportPaths[suffix] = deserializeJson!(string[])(value); break;
				case "preGenerateCommands": this.preGenerateCommands[suffix] = deserializeJson!(string[])(value); break;
				case "postGenerateCommands": this.postGenerateCommands[suffix] = deserializeJson!(string[])(value); break;
				case "preBuildCommands": this.preBuildCommands[suffix] = deserializeJson!(string[])(value); break;
				case "postBuildCommands": this.postBuildCommands[suffix] = deserializeJson!(string[])(value); break;
				case "buildRequirements":
					BuildRequirements reqs;
					foreach (req; deserializeJson!(string[])(value))
						reqs |= to!BuildRequirements(req);
					this.buildRequirements[suffix] = reqs;
					break;
			}
		}
	}

	Json toJson()
	const {
		auto ret = Json.EmptyObject;
		if (targetType != TargetType.autodetect) ret["targetType"] = targetType.to!string();
		if (!targetPath.empty) ret["targetPath"] = targetPath;
		if (!targetName.empty) ret["targetName"] = targetPath;
		foreach (suffix, arr; dflags) ret["dflags"~suffix] = serializeToJson(arr);
		foreach (suffix, arr; lflags) ret["lflags"~suffix] = serializeToJson(arr);
		foreach (suffix, arr; libs) ret["libs"~suffix] = serializeToJson(arr);
		foreach (suffix, arr; sourceFiles) ret["sourceFiles"~suffix] = serializeToJson(arr);
		foreach (suffix, arr; sourcePaths) ret["sourcePaths"~suffix] = serializeToJson(arr);
		foreach (suffix, arr; excludedSourceFiles) ret["excludedSourceFiles"~suffix] = serializeToJson(arr);
		foreach (suffix, arr; copyFiles) ret["copyFiles"~suffix] = serializeToJson(arr);
		foreach (suffix, arr; versions) ret["versions"~suffix] = serializeToJson(arr);
		foreach (suffix, arr; importPaths) ret["importPaths"~suffix] = serializeToJson(arr);
		foreach (suffix, arr; stringImportPaths) ret["stringImportPaths"~suffix] = serializeToJson(arr);
		foreach (suffix, arr; preGenerateCommands) ret["preGenerateCommands"~suffix] = serializeToJson(arr);
		foreach (suffix, arr; postGenerateCommands) ret["postGenerateCommands"~suffix] = serializeToJson(arr);
		foreach (suffix, arr; preBuildCommands) ret["preBuildCommands"~suffix] = serializeToJson(arr);
		foreach (suffix, arr; postBuildCommands) ret["postBuildCommands"~suffix] = serializeToJson(arr);
		foreach (suffix, arr; buildRequirements) {
			string[] val;
			foreach (i; [EnumMembers!BuildRequirements])
				if (arr & i) val ~= to!string(i);
			ret["buildRequirements"~suffix] = serializeToJson(val);
		}
		return ret;
	}

	void getPlatformSettings(ref BuildSettings dst, in BuildPlatform platform, Path base_path)
	const {
		dst.targetType = this.targetType;
		if (!this.targetPath.empty) dst.targetPath = this.targetPath;
		if (!this.targetName.empty) dst.targetName = this.targetName;

		// collect source files from all source folders
		foreach(suffix, paths; sourcePaths){
			if( !platform.matchesSpecification(suffix) )
				continue;

			foreach(spath; paths){
				auto path = base_path ~ spath;
				if( !existsFile(path) || !isDir(path.toNativeString()) ){
					logWarn("Invalid source path: %s", path.toNativeString());
					continue;
				}

				foreach(d; dirEntries(path.toNativeString(), "*.d", SpanMode.depth)){
					if (isDir(d.name)) continue;
					auto src = Path(d.name).relativeTo(base_path);
					dst.addSourceFiles(src.toNativeString());
				}
			}
		}

		getPlatformSetting!("dflags", "addDFlags")(dst, platform);
		getPlatformSetting!("lflags", "addLFlags")(dst, platform);
		getPlatformSetting!("libs", "addLibs")(dst, platform);
		getPlatformSetting!("sourceFiles", "addSourceFiles")(dst, platform);
		getPlatformSetting!("excludedSourceFiles", "removeSourceFiles")(dst, platform);
		getPlatformSetting!("copyFiles", "addCopyFiles")(dst, platform);
		getPlatformSetting!("versions", "addVersions")(dst, platform);
		getPlatformSetting!("importPaths", "addImportPaths")(dst, platform);
		getPlatformSetting!("stringImportPaths", "addStringImportPaths")(dst, platform);
		getPlatformSetting!("preGenerateCommands", "addPreGenerateCommands")(dst, platform);
		getPlatformSetting!("postGenerateCommands", "addPostGenerateCommands")(dst, platform);
		getPlatformSetting!("preBuildCommands", "addPreBuildCommands")(dst, platform);
		getPlatformSetting!("postBuildCommands", "addPostBuildCommands")(dst, platform);
		getPlatformSetting!("buildRequirements", "addRequirements")(dst, platform);
	}

	void getPlatformSetting(string name, string addname)(ref BuildSettings dst, in BuildPlatform platform)
	const {
		foreach(suffix, values; __traits(getMember, this, name)){
			if( platform.matchesSpecification(suffix) )
				__traits(getMember, dst, addname)(values);
		}
	}

	void warnOnSpecialCompilerFlags(string package_name, string config_name)
	{
		string[] all_dflags;
		foreach (flags; this.dflags)
			all_dflags ~= flags;
		.warnOnSpecialCompilerFlags(all_dflags, package_name, config_name);
	}
}


