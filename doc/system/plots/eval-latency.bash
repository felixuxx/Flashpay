#/usr/bin/env bash

set -eu

mkdir -p plots

do_eval() {
	e=$1
	out=$2
	for x in 0 50 100 150 200; do
		awk -f ~/repos/gnunet/contrib/benchmark/collect.awk results/latency-$x/stats/gnunet-benchmark-urls-*.txt \
			| fgrep "$1" | fgrep "status 200" | awk -v x=$x '{ print x, $10/1000 }' 
	done | sort -n > plots/latency-$out.data
}


awk -f ~/repos/gnunet/contrib/benchmark/collect.awk results/latency-0/stats/gnunet-benchmark-urls-*.txt \
	| fgrep "status 200" | awk '{ print $2, $10/1000 }'  > plots/latency-summary-0.data

awk -f ~/repos/gnunet/contrib/benchmark/collect.awk results/latency-100/stats/gnunet-benchmark-urls-*.txt \
	| fgrep "status 200" | awk '{ print $2, $10/1000 }'  > plots/latency-summary-100.data

do_eval '/refresh/melt' 'refresh-melt'
do_eval '/refresh/reveal' 'refresh-reveal'
do_eval '/deposit' 'deposit'
do_eval '/reserve/withdraw' 'withdraw'
do_eval '/keys' 'keys'

awk -f ~/repos/gnunet/contrib/benchmark/collect.awk results/latency-*/stats/gnunet-benchmark-urls-*.txt \
	| fgrep "status 200" | awk '{ print $2, $16/1000 }' \
	> plots/req-sent.data

awk -f ~/repos/gnunet/contrib/benchmark/collect.awk results/latency-*/stats/gnunet-benchmark-urls-*.txt \
	| fgrep "status 200" | awk '{ print $2, $18/1000 }' \
	> plots/req-received.data
