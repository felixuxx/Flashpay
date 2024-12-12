#!/bin/bash
set -evux

check_command()
{
    # /usr/local is where the install step has put the libararies
    export TALER_EXCHANGE_PREFIX=/usr/local
    export TALER_AUDITOR_PREFIX=/usr/local

    # bank and merchant are from the debian package, having /usr as
    # their installation path's
    export TALER_BANK_PREFIX=/usr
    export TALER_MERCHANT_PREFIX=/usr
    export LD_LIBRARY_PATH=/usr/local/lib:/usr/lib/x86_64-linux-gnu/taler-merchant

    make check
}

print_logs()
{
    set +e
	for i in src/*/test-suite.log
	do
		echo "Printing ${i}"
        cat "$i"
		for FAILURE in $(grep '^FAIL:' ${i} | cut -d' ' -f2)
		do
			echo "Printing $(dirname $i)/${FAILURE}.log"
			cat "$(dirname $i)/${FAILURE}.log"
		done
	done
}

if ! check_command ; then
	print_logs
	exit 1
fi
