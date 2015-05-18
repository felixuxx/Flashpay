#!/bin/sh
# Run from 'taler-mint/' top-level directory to generate
# code coverage data.
TOP=`pwd`
mkdir -p doc/coverage/
lcov -d $TOP -z
make check
lcov -d $TOP -c -o doc/coverage/coverage.info
cd doc/coverage/
genhtml coverage.info
