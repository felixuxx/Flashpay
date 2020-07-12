#/usr/bin/env bash

# This is intended to be run with SSH agent forwarding,
# so we can log in as root to adjust artificial delay.

set -eu

which taler-exchange-benchmark

# check that we can log in at least!
ssh root@gv.taler.net true
ssh root@firefly.gnunet.org true

ssh root@gv.taler.net tc qdisc delete dev enp4s0f0 root || true
ssh root@firefly.gnunet.org tc qdisc delete dev eno2 root || true

ssh root@gv.taler.net "echo 3 > /proc/sys/net/ipv4/tcp_fastopen"
ssh root@firefly.gnunet.org "echo 3 > /proc/sys/net/ipv4/tcp_fastopen"

# warm up TCP fast open cookies
taler-exchange-benchmark -c benchmark-remote-gv.conf -m client -p 1 -n 5 >> benchmark-latency.log 2>&1

export GNUNET_BENCHMARK_DIR=$(readlink -f ./stats)

for x in 0 50 100 150 200; do
	echo running with one-sided delay of $x
	result_dir="results/latency-$x"
	if [[ -d "$result_dir" ]]; then
		echo "skipping because results exist"
		continue
	fi

	ssh root@gv.taler.net tc qdisc add dev enp4s0f0 root netem delay "${x}ms"
	ssh root@firefly.gnunet.org tc qdisc add dev eno2 root netem delay "${x}ms"

	rm -rf stats
	taler-exchange-benchmark -c benchmark-remote-gv.conf -m client -p 1 -n 200 >> benchmark-latency.log 2>&1
	echo "### Finished latency run for ${x}ms" >> benchmark-latency.log
	mkdir -p "$result_dir"
	cp -a stats "$result_dir/"

	ssh root@gv.taler.net tc qdisc delete dev enp4s0f0 root
	ssh root@firefly.gnunet.org tc qdisc delete dev eno2 root
done
