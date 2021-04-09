#!/bin/sh
# Helper script to update to latest GANA
# Run from exchange/ main directory.
set -eu

cd contrib/gana
git pull origin master
cd ../..
