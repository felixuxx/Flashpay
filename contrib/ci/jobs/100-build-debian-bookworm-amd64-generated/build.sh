#!/bin/bash
set -exuo pipefail

apt-get update
apt-get upgrade -yqq

./bootstrap
./configure CFLAGS="-ggdb -O0" \
	    --enable-logging=verbose \
	    --disable-doc

nump=$(grep processor /proc/cpuinfo | wc -l)
make -j$(( $nump / 2 ))
make
