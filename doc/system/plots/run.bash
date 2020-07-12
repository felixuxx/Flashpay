#/usr/bin/env bash

for x in $(seq 10 10 190) $(seq 200 100 2000); do
	echo running with $x clients
	rm -rf stats
	taler-exchange-benchmark -c benchmark-local.conf -p $x -n 1000 >& /dev/shm/benchmark.log
	mkdir -p "results/stats-$x"
	cp -a stats "results/stats-$x"/
	cp /dev/shm/benchmark.log "results/stats-$x/"
done	
