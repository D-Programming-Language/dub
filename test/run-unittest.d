#!/usr/bin/env dub
/+dub.sdl:
	name: run_unittest
	targetName: run-unittest
+/
module run_unittest;

/// Name of the log file
enum logFile = "test.log";

/// has true if some test fails
bool any_errors = false;

/// prints (non error) message to standard output and log file
void log(Args...)(Args args)
	if (Args.length)
{
	import std.conv : text;
	import std.stdio : File, stdout;

	const str = text("[INFO] ", args);
	version(Windows) stdout.writeln(str);
	else stdout.writeln("\033[0;33m", str, "\033[0m");
	stdout.flush;
	File(logFile, "a").writeln(str);
}

/// prints error message to standard error stream and log file
/// and set any_errors var to true value to indicate that some
/// test fails
void logError(Args...)(Args args)
{
	import std.conv : text;
	import std.stdio : File, stderr;

	const str = text("[ERROR] ", args);
	version(Windows) stderr.writeln(str);
	else stderr.writeln("\033[0;31m", str, "\033[0m");
	stderr.flush;
	File(logFile, "a").writeln(str);
	any_errors = true;
}

int main(string[] args)
{
	import std.algorithm : among;
	import std.file : dirEntries, DirEntry, exists, getcwd, readText, SpanMode;
	import std.format : format;
	import std.stdio : File, writeln;
	import std.path : absolutePath, buildNormalizedPath, baseName, dirName;
	import std.process : environment, spawnProcess, wait;

	//** if [ -z ${DUB:-} ]; then
	//**     die $LINENO 'Variable $DUB must be defined to run the tests.'
	//** fi
	auto dub = environment.get("DUB", "");
	writeln("DUB: ", dub);
	if (dub == "")
	{
		logError(`Environment variable "DUB" must be defined to run the tests.`);
		return 1;
	}

	//** if [ -z ${DC:-} ]; then
	//**     log '$DC not defined, assuming dmd...'
	//**     DC=dmd
	//** fi
	auto dc = environment.get("DC", "");
	if (dc == "")
	{
		log(`Environment variable "DC" not defined, assuming dmd...`);
		dc = "dmd";
	}

	// Clear log file
	{
		File(logFile, "w");
	}

	//** DC_BIN=$(basename "$DC")
	//** CURR_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
	//** FRONTEND="${FRONTEND:-}"
	const dc_bin = baseName(dc);
	const curr_dir = args[0].absolutePath.dirName.buildNormalizedPath;
	const frontend = environment.get("FRONTEND", "");

	//** if [ "$#" -gt 0 ]; then FILTER=$1; else FILTER=".*"; fi
	auto filter = (args.length > 1) ? args[1] : "*";

	version(linux)
	{
		//** for script in $(ls $CURR_DIR/*.sh); do
		//**     if [[ ! "$script" =~ $FILTER ]]; then continue; fi
		//**     if [ "$script" = "$(gnureadlink ${BASH_SOURCE[0]})" ] || [ "$(basename $script)" = "common.sh" ]; then continue; fi
		//**     if [ -e $script.min_frontend ] && [ ! -z "$FRONTEND" ] && [ ${FRONTEND} \< $(cat $script.min_frontend) ]; then continue; fi
		//**     log "Running $script..."
		//**     DUB=$DUB DC=$DC CURR_DIR="$CURR_DIR" $script || logError "Script failure."
		//** done
		foreach(DirEntry script; dirEntries(curr_dir, (args.length > 1) ? args[1] : "*.sh", SpanMode.shallow))
		{
			if (baseName(script.name).among("run-unittest.sh", "common.sh")) continue;
			const min_frontend = script.name ~ ".min_frontend";
			if (exists(min_frontend) && frontend.length && frontend < min_frontend.readText) continue;
			log("Running " ~ script ~ "...");
			if (spawnProcess(script.name, ["DUB":dub, "DC":dc, "CURR_DIR":curr_dir]).wait)
				logError("Script failure.");
		}
	}

	return any_errors;
}
