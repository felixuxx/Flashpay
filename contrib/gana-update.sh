#!/bin/sh
# Helper script to recompute error codes based on submodule
# Run from exchange/ main directory.
set -eu

# Generate taler-error-codes.h in gana and copy it to
# src/include/taler_error_codes.h
cd contrib/gana/gnu-taler-error-codes
make
cd ../../..
for n in taler_error_codes.c
do
    if ! diff contrib/gana/gnu-taler-error-codes/${n} src/util/${n} > /dev/null
    then
        cp contrib/gana/gnu-taler-error-codes/$n src/util/$n
    fi
done
for n in taler_error_codes.h
do
    if ! diff contrib/gana/gnu-taler-error-codes/${n} src/include/${n} > /dev/null
    then
        cp contrib/gana/gnu-taler-error-codes/$n src/include/$n
    fi
done
cd contrib/gana/gnu-taler-db-events
make
cd ../../..
for n in taler_dbevents.h
do
    if ! diff contrib/gana/gnu-taler-db-events/${n} src/include/${n} > /dev/null
    then
        cp contrib/gana/gnu-taler-db-events/$n src/include/$n
    fi
done
