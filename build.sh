#!/bin/sh
LIBS=`pkg-config --libs libcurl 2>/dev/null || echo "-lcurl"`" -lphobos2"
LIBS=`echo "$LIBS" | sed 's/^-L/-L-L/; s/ -L/ -L-L/g; s/^-l/-L-l/; s/ -l/ -L-l/g'`
rdmd --build-only -ofdub -g -debug -w -property -Isource $LIBS $* source/app.d
