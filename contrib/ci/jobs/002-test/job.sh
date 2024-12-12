#!/bin/bash
set -exuo pipefail

job_dir=$(dirname "${BASH_SOURCE[0]}")

. "${job_dir}"/1-build.sh
. "${job_dir}"/2-install.sh
. "${job_dir}"/3-startdb.sh
. "${job_dir}"/4-test.sh
