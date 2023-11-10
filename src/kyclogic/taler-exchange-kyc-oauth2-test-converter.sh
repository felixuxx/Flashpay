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
J=$(jq '{"id":.data.id,"first":.data.first_name,"last":.data.last_name,"birthdate":.data.birthdate,"status":.status}')

# Next, combine some fields into larger values.
STATUS=$(echo "$J" | jq -r '.status')
if [ "$STATUS" != "success" ]
then
  exit 1
fi

FULLNAME=$(echo "$J" | jq -r '[.first,.last]|join(" ")')

echo $J | jq \
   --arg full_name "${FULLNAME}" \
  '{$full_name,"birthdate":.birthdate,"id":.id}'

exit 0
