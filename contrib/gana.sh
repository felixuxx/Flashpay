#!/bin/sh
# Helper script to update to latest GANA
# Run from exchange/ main directory.
set -eu

git submodule update --init

cd contrib/gana
git pull origin master
cd ../..

./contrib/gana-update.sh
