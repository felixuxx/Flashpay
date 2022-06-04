#!/bin/sh
# Helper script to recompute error codes based on submodule
# Run from exchange/ main directory.
set -eu

domake ()
{
    # $1 -- dir under contrib/
    dir="contrib/$1"

    make -C $dir
}

ensure ()
{
    # $1 -- filename
    # $2 -- src dir under contrib/
    # $3 -- dst dir under ./
    fn="$1"
    src="contrib/$2"
    dst="./$3"

    if ! diff $src/$fn $dst/$fn > /dev/null
    then
        cp $src/$fn $dst/$fn
    fi
}

domake                     gana/gnu-taler-error-codes
ensure taler_error_codes.c gana/gnu-taler-error-codes src/util
ensure taler_error_codes.h gana/gnu-taler-error-codes src/include

domake                  gana/gnu-taler-db-events
ensure taler_dbevents.h gana/gnu-taler-db-events src/include
