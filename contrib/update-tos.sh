#!/bin/sh
# This file is in the public domain

# Should be called with the list of languages to generate, i.e.
# $ ./update-tos.sh en de fr it

# Error checking on
set -eu
echo "Generating TOS for ETag $VERSION"

rm -f sphinx.log sphinx.err
# We process inputs using Makefile in tos/ directory
cd tos
for l in $@
do
    mkdir -p $l
    echo "Generating TOS for language $l"
    cat conf.py.in | sed -e "s/%VERSION%/$VERSION/g" > conf.py
    # 'f' is for the supported formats, note that the 'make' target
    # MUST match the file extension.
    for f in html txt pdf epub xml
    do
        rm -rf _build
        echo "  Generating format $f"
        make -e SPHINXOPTS="-D language='$l'" $f >>sphinx.log 2>>sphinx.err < /dev/null
        if test $f = "html"
        then
            htmlark -o $l/${VERSION}.$f _build/$f/${VERSION}.$f
        else
            mv _build/$f/${VERSION}.$f $l/${VERSION}.$f
        fi
        if test $f = "txt"
        then
            cp $l/${VERSION}.$f $l/${VERSION}.md
        fi
    done
done
cd ..
echo "Success"
