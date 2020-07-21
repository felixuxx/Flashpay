#!/bin/sh
# Helper script to update to latest GANA
# Run from exchange/ main directory; make sure you have
# no uncommitted changes at the time of running the script.
set -eu
cd contrib/gana
git pull origin master
cd ../..
git commit -a -S -m "synchronize with latest GANA"
./bootstrap
cd src/include
make install
cd ../..
