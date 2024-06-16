#!/bin/bash
set -evux

apt-get update
apt-get upgrade -yqq

./bootstrap
./configure CFLAGS="-ggdb -O0" \
	    --enable-logging=verbose \
	    --disable-doc

nump=$(grep processor /proc/cpuinfo | wc -l)
make clean
make -j$(( $nump / 2 ))
cd src/templating/
./run-original-tests.sh
make clean
cd -
make -j$(( $nump / 2 ))
make install

sudo -u postgres /usr/lib/postgresql/15/bin/pg_ctl start -D /etc/postgresql/15/main -o '-h localhost -p 5432'
sudo -u postgres createuser -p 5432 root
sudo -u postgres createdb -p 5432 -O root talercheck

check_command()
{
	# Set LD_LIBRARY_PATH so tests can find the installed libs
	LD_LIBRARY_PATH=/usr/local/lib PGPORT=5432 make check
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
