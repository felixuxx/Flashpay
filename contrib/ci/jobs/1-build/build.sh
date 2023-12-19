#!/bin/bash
set -exuo pipefail

apt-get update
apt-get upgrade -yqq

./bootstrap
./configure CFLAGS="-ggdb -O0" \
	    --enable-logging=verbose \
	    --disable-doc

make
