#!/bin/bash
set -exuo pipefail

ARTIFACT_PATH="/artifacts/exchange/${CI_COMMIT_REF}/*.deb"

RSYNC_HOST="taler.host.internal"
RSYNC_PORT=424242
RSYNC_PATH="incoming_packages/trixie-taler-ci/"
RSYNC_DEST=${RSYNC_DEST:-"rsync://${RSYNC_HOST}/${RSYNC_PATH}"}

rsync -vP \
  --port ${RSYNC_PORT} \
  ${ARTIFACT_PATH} ${RSYNC_DEST}
