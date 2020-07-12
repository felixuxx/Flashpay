#/usr/bin/env bash

for x in 1 $(seq 10 10 190) $(seq 200 100 2000); do
	cat results/stats-$x/stats/taler-exchange-* | awk -v n=$x '{ print n, int(($3 + $5) / 96) }'
done | sort -n > plots/time_exchange_cpu.data

tail results/stats-*/benchmark.log | awk '/RAW/ { printf "%d %d\n", $4, $5 }' | sort -n > plots/time_real.data

tail results/stats-*/benchmark.log | awk '/RAW/ { printf "%d %f\n", $4, (($4 * 1000)/($5/1000/1000)) }' | sort -n > plots/speed.data

for x in 1 $(seq 10 10 190) $(seq 200 100 2000); do
	tail results/stats-$x/benchmark.log | awk -v n=$x '/cpu time/ { print n, int(($4 + $6) / 96) }'
done | sort -n > plots/time_bench_cpu.data


for x in 1 $(seq 10 10 190) $(seq 200 100 2000); do
	awk -f ~/code/gnunet/contrib/benchmark/collect.awk baseline.txt results/stats-$x/stats/gnunet-benchmark-ops-thread* \
		| grep total_ops_adjusted_ms \
		| awk -v n=$x '{ print n, int($2 / 96) }'
done | sort -n > plots/time_bench_ops_only.data
