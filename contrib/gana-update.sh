#!/bin/sh
# Helper script to recompute error codes based on submodule
# Run from exchange/ main directory.
set -eu

# Generate taler-error-codes.h in gana and copy it to
# src/include/taler_error_codes.h
cd contrib/gana/gnu-taler-error-codes
make
cd ../../..
if ! diff contrib/gana/gnu-taler-error-codes/taler_error_codes.h src/include/taler_error_codes.h > /dev/null
then
  cp contrib/gana/gnu-taler-error-codes/taler_error_codes.h src/include/taler_error_codes.h
fi
if ! diff contrib/gana/gnu-taler-error-codes/taler_error_codes.c src/util/taler_error_codes.c > /dev/null
then
  cp contrib/gana/gnu-taler-error-codes/taler_error_codes.c src/util/taler_error_codes.c
fi
