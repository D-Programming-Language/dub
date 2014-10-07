dub package manager
===================

Package and build manager for [D](http://dlang.org/) applications and libraries.

There is a central [package registry](https://github.com/D-Programming-Language/dub-registry/) located at <http://code.dlang.org>.

[![Build Status](https://travis-ci.org/D-Programming-Language/dub.png)](https://travis-ci.org/D-Programming-Language/dub)
[![Coverage Status](https://coveralls.io/repos/D-Programming-Language/dub/badge.png?branch=master)](https://coveralls.io/r/D-Programming-Language/dub)

Introduction
------------

DUB emerged as a more general replacement for [vibe.d's](http://vibed.org/) package manager. It does not imply a dependecy to vibe.d for packages and was extended to not only directly build projects, but also to generate project files (currently [VisualD](https://github.com/rainers/visuald)).
[Mono-D](http://mono-d.alexanderbothe.com/) also support the use of dub.json (dub's package description) as project file.

The project's philosophy is to keep things as simple as possible. All that is needed to make a project a dub package is to write a short [dub.json](http://code.dlang.org/publish) file and put the source code into a `source` subfolder. It *can* then be registered on the public [package registry](http://code.dlang.org) to be made available for everyone. Any dependencies specified in `dub.json` are automatically downloaded and made available to the project during the build process.


Key features
------------

 - Simple package and build description not getting in your way

 - Integrated with Git, avoiding maintainance tasks such as incrementing version numbers or uploading new project releases

 - Generates VisualD project/solution files, integrated into MonoD

 - Support for DMD, GDC and LDC (common DMD flags are translated automatically)

 - Supports development workflows by optionally using local directories as a package source


Future direction
----------------

To make things as flexible as they need to be for certain projects, it is planned to gradually add more options to the [package file format](http://code.dlang.org/package-format) and eventually to add the possibility to specify an external build tool along with the path of it's output files. The idea is that DUB provides a convenient build management that suffices for 99% of projects, but is also usable as a bare package manager that doesn't get in your way if needed.


Installation
------------

DUB comes [precompiled](http://code.dlang.org/download) for Windows, Mac OS, Linux and FreeBSD. It needs to have libcurl with SSL support installed (except on Windows).

The `dub` executable then just needs to be accessible from `PATH` and can be invoked from the root folder of any DUB enabled project to build and run it.

If you want to build for yourself, just install [DMD](http://dlang.org/download.html) and libcurl development headers and run `./build.sh`. On Windows you can simply run `build.cmd` without installing anything besides DMD.

### Arch Linux

Михаил Страшун (Dicebot) maintains a dub package of the latest release in `Community`, for [x86_64](https://www.archlinux.org/packages/community/x86_64/dub/) and [i686](https://www.archlinux.org/packages/community/i686/dub/).
Moritz Maxeiner has created a PKGBUILD file for GIT master: <https://aur.archlinux.org/packages/dub-git/>

### Debian/Ubuntu Linux

Jordi Sayol maintains a DEB package as part of his [D APT repository](http://d-apt.sourceforge.net). Run `sudo apt-get install dub` to install.

### Mac OS

Chris Molozian has added DUB to [Homebrew](http://mxcl.github.io/homebrew/). Use `brew install dub` or `brew install dub --HEAD` to install the stable or the git HEAD version respectively.


Using DUB as a library
----------------------

The [DUB package of DUB](http://code.dlang.org/packages/dub) can be used as a library to load or manipulate packages, or to resemble any functionality of the command line tool. The former task can be achieved by using the [Package class](https://github.com/D-Programming-Language/dub/blob/master/source/dub/package_.d#L40). For examples on how to replicate the command line functionality, see [commandline.d](https://github.com/D-Programming-Language/dub/blob/master/source/dub/commandline.d).
