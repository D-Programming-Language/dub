/**
	...

	Copyright: © 2012 Matthias Dondorff
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
	Authors: Matthias Dondorff
*/
module dub.internal.utils;

import dub.internal.vibecompat.core.file;
import dub.internal.vibecompat.core.log;
import dub.internal.vibecompat.data.json;
import dub.internal.vibecompat.data.sdl;
import dub.internal.vibecompat.inet.url;
import dub.version_;

// todo: cleanup imports.
import std.algorithm : startsWith;
import std.array;
import std.conv;
import std.exception;
import std.file;
import std.process;
import std.string;
import std.typecons;
import std.zip;
version(DubUseCurl) import std.net.curl;


enum PackageFileFormat { sdl, json }

PackageFileFormat getFormat(Path file)
{
	string extension = file.ext();
	if(extension.empty) throw new Exception(format("Package file '%s' has no extension, cannot determine file format"));
	if(extension == ".sdl") {
		return PackageFileFormat.sdl;
	} else if(extension == ".json") {
		return PackageFileFormat.json;
	} else {
		throw new Exception(format("Package file '%s' has an unknown extension, expected .sdl or .json"));
	}
}

Path getTempDir()
{
	auto tmp = environment.get("TEMP");
	if( !tmp.length ) tmp = environment.get("TMP");
	if( !tmp.length ){
		version(Posix) tmp = "/tmp/";
		else tmp = "./";
	}
	return Path(tmp);
}

bool isEmptyDir(Path p) {
	foreach(DirEntry e; dirEntries(p.toNativeString(), SpanMode.shallow))
		return false;
	return true;
}

bool isWritableDir(Path p, bool create_if_missing = false)
{
	import std.random;
	auto fname = p ~ format("__dub_write_test_%08X", uniform(0, uint.max));
	if (create_if_missing && !exists(p.toNativeString())) mkdirRecurse(p.toNativeString());
	try openFile(fname, FileMode.CreateTrunc).close();
	catch return false;
	remove(fname.toNativeString());
	return true;
}

Json jsonFromFile(Path file, bool silent_fail = false) {
	if( silent_fail && !existsFile(file) ) return Json.emptyObject;
	
	PackageFileFormat fileFormat = file.getFormat();
	
	auto f = openFile(file.toNativeString(), FileMode.Read);
	scope(exit) f.close();
	auto text = stripUTF8Bom(cast(string)f.readAll());
	
	final switch(fileFormat)
	{
		case PackageFileFormat.sdl: return parseSdlString(text);
		case PackageFileFormat.json: return parseJsonString(text);
	}
}

Json jsonFromZip(Path zip, string filename) {
	auto f = openFile(zip, FileMode.Read);
	ubyte[] b = new ubyte[cast(size_t)f.size];
	f.rawRead(b);
	f.close();
	auto archive = new ZipArchive(b);
	auto text = stripUTF8Bom(cast(string)archive.expand(archive.directory[filename]));
	return parseJsonString(text);
}

// TODO: change this to writePackageFile
void writeJsonFile(Path path, Json json)
{
	PackageFileFormat fileFormat = path.getFormat();
	
	auto f = openFile(path, FileMode.CreateTrunc);
	scope(exit) f.close();	
	
	final switch(fileFormat)
	{
		case PackageFileFormat.sdl: f.writePrettySdlString(json); break;
		case PackageFileFormat.json: f.writePrettyJsonString(json); break;
	}
	
}

bool isPathFromZip(string p) {
	enforce(p.length > 0);
	return p[$-1] == '/';
}

bool existsDirectory(Path path) {
	if( !existsFile(path) ) return false;
	auto fi = getFileInfo(path);
	return fi.isDirectory;
}

void runCommands(in string[] commands, string[string] env = null)
{
	foreach(cmd; commands){
		logDiagnostic("Running %s", cmd);
		Pid pid;
		if( env !is null ) pid = spawnShell(cmd, env);
		else pid = spawnShell(cmd);
		auto exitcode = pid.wait();
		enforce(exitcode == 0, "Command failed with exit code "~to!string(exitcode));
	}
}

/**
	Downloads a file from the specified URL.

	Any redirects will be followed until the actual file resource is reached or if the redirection
	limit of 10 is reached. Note that only HTTP(S) is currently supported.
*/
void download(string url, string filename)
{
	version(DubUseCurl) {
		auto conn = HTTP();
		setupHTTPClient(conn);
		logDebug("Storing %s...", url);
		std.net.curl.download(url, filename, conn);
		enforce(conn.statusLine.code < 400,
			format("Failed to download %s: %s %s",
				url, conn.statusLine.code, conn.statusLine.reason));
	} else version (Have_vibe_d) {
		import vibe.inet.urltransfer;
		vibe.inet.urltransfer.download(url, filename);
	} else assert(false);
}
/// ditto
void download(URL url, Path filename)
{
	download(url.toString(), filename.toNativeString());
}
/// ditto
ubyte[] download(string url)
{
	version(DubUseCurl) {
		auto conn = HTTP();
		setupHTTPClient(conn);
		logDebug("Getting %s...", url);
		auto ret = cast(ubyte[])get(url, conn);
		enforce(conn.statusLine.code < 400,
			format("Failed to GET %s: %s %s",
				url, conn.statusLine.code, conn.statusLine.reason));
		return ret;
	} else version (Have_vibe_d) {
		import vibe.inet.urltransfer;
		import vibe.stream.operations;
		ubyte[] ret;
		download(url, (scope input) { ret = input.readAll(); });
		return ret;
	} else assert(false);
}
/// ditto
ubyte[] download(URL url)
{
	return download(url.toString());
}

/// Returns the current DUB version in semantic version format
string getDUBVersion()
{
	import dub.version_;
	// convert version string to valid SemVer format
	auto verstr = dubVersion;
	if (verstr.startsWith("v")) verstr = verstr[1 .. $];
	auto parts = verstr.split("-");
	if (parts.length >= 3) {
		// detect GIT commit suffix
		if (parts[$-1].length == 8 && parts[$-1][1 .. $].isHexNumber() && parts[$-2].isNumber())
			verstr = parts[0 .. $-2].join("-") ~ "+" ~ parts[$-2 .. $].join("-");
	}
	return verstr;
}

version(DubUseCurl) {
	void setupHTTPClient(ref HTTP conn)
	{
		static if( is(typeof(&conn.verifyPeer)) )
			conn.verifyPeer = false;

		auto proxy = environment.get("http_proxy", null);
		if (proxy.length) conn.proxy = proxy;

		conn.addRequestHeader("User-Agent", "dub/"~getDUBVersion()~" (std.net.curl; +https://github.com/rejectedsoftware/dub)");
	}
}

private string stripUTF8Bom(string str)
{
	if( str.length >= 3 && str[0 .. 3] == [0xEF, 0xBB, 0xBF] )
		return str[3 ..$];
	return str;
}

private bool isNumber(string str) {
	foreach (ch; str)
		switch (ch) {
			case '0': .. case '9': break;
			default: return false;
		}
	return true;
}

private bool isHexNumber(string str) {
	foreach (ch; str)
		switch (ch) {
			case '0': .. case '9': break;
			case 'a': .. case 'f': break;
			case 'A': .. case 'F': break;
			default: return false;
		}
	return true;
}

/**
	Get the closest match of $(D input) in the $(D array), where $(D distance)
	is the maximum levenshtein distance allowed between the compared strings.
	Returns $(D null) if no closest match is found.
*/
string getClosestMatch(string[] array, string input, size_t distance)
{
	import std.algorithm : countUntil, map, levenshteinDistance;
	import std.uni : toUpper;

	auto distMap = array.map!(elem =>
		levenshteinDistance!((a, b) => toUpper(a) == toUpper(b))(elem, input));
	auto idx = distMap.countUntil!(a => a <= distance);
	return (idx == -1) ? null : array[idx];
}
