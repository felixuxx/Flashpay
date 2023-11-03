#!/bin/bash
# This file is in the public domain.
#
# This code converts (some of) the JSON output from
# Challenger into the GNU Taler
# specific KYC attribute data (again in JSON format).
#

# Die if anything goes wrong.
set -eu


# First, extract everything from stdin.
J=$(jq '{"first":.first_name,"last".last_name"}')

# Next, combine some fields into larger values.
FULLNAME=$(echo "$J" | jq -r '[.first,.last]|join(" ")')

jq \
   --arg full_name "${FULLNAME}" \
  '{$full_name}'

exit 0
