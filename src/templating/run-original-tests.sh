#!/bin/bash
set -eu
# The build fails if libjson-c-dev is not installed.
# That's OK, we don't otherwise need it and don't
# even bother testing for it in configure.ac.
# However, in that case, skip the test suite.

make -f Makefile.orig mustach || exit 77
make -f Makefile.orig test
make -f Makefile.orig clean || true
