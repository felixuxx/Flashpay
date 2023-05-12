#!/bin/bash
# This file is in the public domain.
#
# This code converts (some of) the JSON output from Persona into the GNU Taler
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
J=$(jq '{"first":.data.attributes."name-first","middle":.data.attributes."name-middle","last":.data.attributes."name-last","cc":.data.attributes.fields."address-country-code".value,"birthdate":.data.attributes.birthdate,"city":.data.attributes."address-city","postcode":.data.attributes."address-postal-code","street-1":.data.attributes."address-street-1","street-2":.data.attributes."address-street-2","address-subdivision":.data.attributes."address-subdivision","identification-number":.data.attributes."identification-number","photo":.included[]|select(.type=="verification/government-id")|.attributes|select(.status=="passed")|."front-photo-url"}')


# Next, combine some fields into larger values.
FULLNAME=$(echo "$J" | jq -r '[.first,.middle,.last]|join(" ")')
STREET=$(echo $J | jq -r '[."street-1",."street-2"]|join(" ")')
CITY=$(echo $J | jq -r '[.postcode,.city,."address-subdivision,.cc"]|join(" ")')

# Download and base32-encode the photo
PHOTO_URL=$(echo "$J" | jq -r '.photo')
PHOTO_FILE=$(mktemp -t tmp.XXXXXXXXXX)
if [ -z "${TOKEN:-}" ]
then
    wget -q --output-document=- "$PHOTO_URL" | gnunet-base32 > ${PHOTO_FILE}
else
    wget -q --output-document=- --header "Authorization: Bearer $TOKEN" "$PHOTO_URL" | gnunet-base32  > ${PHOTO_FILE}
fi

# Combine into final result.
echo "$J" | jq \
   --arg full_name "${FULLNAME}" \
   --arg street "${STREET}" \
   --arg city "${CITY}" \
   --rawfile photo "${PHOTO_FILE}" \
   '{$full_name,$street,$city,"birthdate":.birthdate,"residences":.cc,"identification_number":."identification-number",$photo}'

exit 0
