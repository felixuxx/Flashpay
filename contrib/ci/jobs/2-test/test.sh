#!/bin/bash
set -evu

apt-get update
apt-get upgrade -yqq

./bootstrap
./configure CFLAGS="-ggdb -O0" \
	    --enable-logging=verbose \
	    --disable-doc

nump=$(grep processor /proc/cpuinfo | wc -l)
make clean
make -j$(( $nump / 2 ))
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
		for FAILURE in $(grep '^FAIL:' ${i} | cut -d' ' -f2)
		do
			echo "Printing ${FAILURE}.log"
			cat "$(dirname $i)/${FAILURE}.log"
		done
	done
}

if ! check_command ; then
	print_logs
	exit 1
fi
