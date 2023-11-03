#!/bin/bash
# This file is in the public domain.
#
# This code converts (some of) the JSON output from NDA into the GNU Taler
# specific KYC attribute data (again in JSON format).
#

# Die if anything goes wrong.
set -eu

# First, extract everything from stdin.
J=$(jq '{"status":.status,"id":.data.id,"last":.data.last_name,"first":.data.first_name,"phone":.data.phone}')

STATUS=$(echo "$J" | jq -r '.status')
if [ "$STATUS" != "success" ]
then
  return 1
fi

# Next, combine some fields into larger values.
FULLNAME=$(echo "$J" | jq -r '[.first_name,.last_name]|join(" ")')

echo "$J" | jq \
  --arg full_name "${FULLNAME}" \
  '{$full_name,"phone":.phone,"id":.id}'

exit 0
