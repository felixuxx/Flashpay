#!/bin/bash
set -exuo pipefail

./bootstrap
./configure --enable-only-doc

pushd ./doc/doxygen/

make full

popd
