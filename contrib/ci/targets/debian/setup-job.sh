#!/bin/bash
set -eax
# Variables passed in:
# - CI_DIR: Path to contrib/ci
# - DISTRO: Distro Name (debian)
# - CODENAME: Codename to target
# - ARCH: Architecture to use
# - OCI_IMAGE: The OCI image we're expected to target
# - DISTRO_TARGET: The TARGET dir of the current distro (targets/debian)
# - CONTAINERFILE: Our input Containerfile
# Helper Scripts:
# - mktarget: Makes a target for us

# Generate the build target
cd "${CI_DIR}/jobs/$(mktarget 0 build)"
sed "1s|FROM .*|FROM ${OCI_IMAGE}|" "$CONTAINERFILE" > Containerfile
cp "$DISTRO_TARGET/build/build.sh" ./
cp "$DISTRO_TARGET/build/job.sh" ./

if [[ "$ARCH" != "amd64" ]]; then
  echo '[build]
HALT_ON_FAILURE = True
WARN_ON_FAILURE = True
CONTAINER_BUILD = True
CONTAINER_NAME = exchange:'"$ARCH"'
CONTAINER_ARCH = '"$ARCH"'
' > config.ini
fi;

# Generate the deb-package target
cd "${CI_DIR}/jobs/$(mktarget 1 deb-package)"
sed "1s|FROM .*|FROM ${OCI_IMAGE}|" "$CONTAINERFILE" > Containerfile
cp "$DISTRO_TARGET/deb-package/version.sh" ./
cp "$DISTRO_TARGET/deb-package/job.sh" ./
cp "$DISTRO_TARGET/deb-package/install-fix.patch" ./

if [[ "$ARCH" != "amd64" ]]; then
  echo '[build]
HALT_ON_FAILURE = True
WARN_ON_FAILURE = True
CONTAINER_BUILD = True
CONTAINER_NAME = exchange:'"$ARCH"'
CONTAINER_ARCH = '"$ARCH"'
' > config.ini
fi;

# Generate the deploy-package target
cd "${CI_DIR}/jobs/$(mktarget 2 deploy-package)"
cp "$DISTRO_TARGET/deploy-package/config.ini" ./
sed "s|bookworm|$CODENAME|g" "$DISTRO_TARGET/deploy-package/job.sh" > ./
