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
J=$(jq '{"id":.id,"email":.address,"type":.address_type,"expires":.address_expiration}')

ADDRESS_TYPE=$(echo "$J" | jq -r '.type')
ROWID=$(echo "$J" | jq -r '.id')
if [ "$ADDRESS_TYPE" != "email" ]
then
  return 1
fi

echo "$J" \
  | jq \
   --arg id "${ROWID}" \
  '{$id,"email":.email,"expires",.expires}'

exit 0
