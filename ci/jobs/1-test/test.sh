#!/bin/bash
set -evu

./bootstrap
./configure CFLAGS="-ggdb -O0" \
	    --enable-logging=verbose \
	    --disable-doc
make
make install

check_command()
{
	make check
}

print_logs()
{
	for i in src/*/test-suite.log
	do
		FAILURE="$(grep '^FAIL:' ${i} | cut -d' ' -f2)"
		if [ ! -z "${FAILURE}" ]; then
			echo "Printing ${FAILURE}.log"
			tail "$(dirname $i)/${FAILURE}.log"
		fi
	done
}

if ! check_command ; then
	print_logs
	exit 1
fi
