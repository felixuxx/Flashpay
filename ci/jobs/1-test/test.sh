#!/bin/bash
set -exuo pipefail

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
	for i in $(cat src/util/test-suite.log  | grep '^FAIL:' | cut -d' ' -f 2)
	do
		echo Printing $i.log:
		tail src/util/$i.log
	done
}

if ! check_command ; then
	print_logs
	exit 1
fi
