#!/bin/bash
set -evu

./bootstrap
./configure CFLAGS="-ggdb -O0" \
	    --enable-logging=verbose \
	    --disable-doc
make
make install

sudo -u postgres /usr/lib/postgresql/15/bin/postgres -D /etc/postgresql/15/main -h localhost -p 5432 &
sleep 10
sudo -u postgres createuser -p 5432 root
sudo -u postgres createdb -p 5432 -O root talercheck

check_command()
{
	# Set LD_LIBRARY_PATH so tests can find the installed libs
	LD_LIBRARY_PATH=/usr/local/lib PGPORT=5432 make check
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
