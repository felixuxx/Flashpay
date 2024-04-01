#!/bin/bash
# This file is in the public domain.
set -eux

export CFLAGS="-g"

function build()
{
    make clean
    make
}

# Install rebuild-on-exit handler (except for kill -9)
trap build EXIT

echo "Ensuring clean state on entry to upstream tests ..."
make clean

# The build fails if libjson-c-dev is not installed.
# That's OK, we don't otherwise need it and don't
# even bother testing for it in configure.ac.
# However, in that case, skip the test suite.
make -f mustach-original-Makefile mustach mustach-json-c.o || exit 77
make -f mustach-original-Makefile clean || true
make -f mustach-original-Makefile basic-tests
make -f mustach-original-Makefile clean || true

exit 0
