#!/bin/bash
set -exuo pipefail

job_dir=$(dirname "${BASH_SOURCE[0]}")
skip=$(cat $job_dir/skip.txt)

codespell -d -I "${job_dir}"/dictionary.txt -S ${skip//$'\n'/,}
