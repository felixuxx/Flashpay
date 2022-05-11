#!/bin/sh
# Helper script to recompute error codes based on submodule
# Run from exchange/ main directory.
set -eu

domake ()
{
    # $1 -- dir under contrib/gana/
    dir="contrib/gana/$1"

    make -C $dir
}

ensure ()
{
    # $1 -- filename
    # $2 -- src dir under contrib/gana/
    # $3 -- dst dir under ./
    fn="$1"
    src="contrib/gana/$2"
    dst="./$3"

    if ! diff $src/$fn $dst/$fn > /dev/null
    then
        cp $src/$fn $dst/$fn
    fi
}

domake                     gnu-taler-error-codes
ensure taler_error_codes.c gnu-taler-error-codes src/util
ensure taler_error_codes.h gnu-taler-error-codes src/include

domake                  gnu-taler-db-events
ensure taler_dbevents.h gnu-taler-db-events src/include
