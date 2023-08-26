#!/bin/bash
set -exuo pipefail
# This file is in the public domain.
# Helper script to build the latest DEB packages in the container.

unset LD_LIBRARY_PATH


git apply ./ci/jobs/2-deb-package/install-fix.patch

# Get current version from debian/control file.
DEB_VERSION=$(dpkg-parsechangelog -S Version)

# Install build-time dependencies.
mk-build-deps --install --tool='apt-get -o Debug::pkgProblemResolver=yes --no-install-recommends --yes' debian/control

# We do a sparse checkout, so we need to hint
# the version to the build system.
echo $DEB_VERSION > .version
./bootstrap
dpkg-buildpackage -rfakeroot -b -uc -us

ls ../*.deb
mv ../*.deb /artifacts/
