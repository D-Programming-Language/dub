#!/bin/sh

rm -rf main/.dub
rm -rf a/.dub
rm -rf b/.dub
rm -f main/dub.selections.json
${DUB} build --bare --compiler=${DC} main || exit 1


if ! grep -c -e \"b\" main/dub.selections.json; then
	echo "Dependency b not resolved."
	exit 1
fi
