#!/bin/bash
# This file is in the public domain.
#
# This code converts (some of) the JSON output from KYCAID into the GNU Taler
# specific KYC attribute data (again in JSON format).  We may need to download
# and inline file data in the process, for authorization pass "-a" with the
# respective bearer token.
#

# Die if anything goes wrong.
set -eu

# Parse command-line options
while getopts ':a:' OPTION; do
    case "$OPTION" in
        a)
            TOKEN="$OPTARG"
            ;;
        ?)
        echo "Unrecognized command line option"
        exit 1
        ;;
    esac
done

# First, extract everything from stdin.
J=$(jq '{"type":.type,"email":.email,"phone":.phone,"first_name":.first_name,"name-middle":.middle_name,"last_name":.last_name,"dob":.dob,"residence_country":.residence_country,"gender":.gender,"pep":.pep,"addresses":.addresses,"documents":.documents,"company_name":.company_name,"business_activity_id":.business_activity_id,"registration_country":.registration_country}')

# TODO:
# log_failure (json_object_get (j, "decline_reasons"));

TYPE=$(echo "$J" | jq -r '.person')

if [ "person" = "${TYPE}" ]
then

  # Next, combine some fields into larger values.
  FULLNAME=$(echo "$J" | jq -r '[.first_name,.middle_name,.last_name]|join(" ")')
#  STREET=$(echo $J | jq -r '[."street-1",."street-2"]|join(" ")')
#  CITY=$(echo $J | jq -r '[.postcode,.city,."address-subdivision,.cc"]|join(" ")')

  # Combine into final result for individual.
  # FIXME: does jq tolerate 'pep = NULL' here?
  echo "$J" | jq \
    --arg full_name "${FULLNAME}" \
    '{$full_name,"birthdate":.dob,"pep":.pep,"phone":."phone","email",.email,"residences":.residence_country}'

else
  # Combine into final result for business.
  echo "$J" | jq \
    --arg full_name "${FULLNAME}" \
    '{"company_name":.company_name,"phone":.phone,"email":.email,"registration_country":.registration_country}'
fi

exit 0
