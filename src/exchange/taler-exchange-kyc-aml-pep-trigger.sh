#!/bin/sh
# This file is in the public domain.
# This is an example of how to trigger AML if the
# KYC attributes include '{"pep":true}'
#
# To be used as a script for the KYC_AML_TRIGGER.
test "false" = $(jq .pep -)
