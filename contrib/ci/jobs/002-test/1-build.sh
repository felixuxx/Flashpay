#!/bin/bash
set -evux

apt-get update
apt-get upgrade -yqq

./bootstrap
./configure CFLAGS="-ggdb -O0" \
	    --enable-logging=verbose \
	    --disable-doc

nump=$(grep processor /proc/cpuinfo | wc -l)
make clean
make -j$(( $nump / 2 ))
cd src/templating/
./run-original-tests.sh
make clean
cd -
make -j$(( $nump / 2 ))

