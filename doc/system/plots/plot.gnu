set terminal pdf monochrome

set nokey
set output 'speed.pdf'
set ylabel "coins per second"
set xlabel "parallel clients"
plot "speed.data" with lines lw 1

set key top left Left reverse
set output 'cpu.pdf'
set ylabel "CPU time (us)"
set xlabel "parallel clients"
plot "time_real.data" with lines lw 1 title "wall clock", \
     "time_bench_cpu.data" with lines lw 1 title "benchmark CPU / 96", \
     "time_exchange_cpu.data" with lines lw 1 title "exchange CPU / 96", \
     "time_bench_ops_only.data" with lines lw 1 title "exchange crypto / 96"
set nokey


set output 'latencies.pdf'
set multiplot layout 2, 3
set xlabel "delay" font ",10"
set ylabel "latency" font ",10"
set xtics font ",10"
set ytics font ",10"
set title "/refresh/melt"
plot "latency-refresh-melt.data" with lines lw 1
set title "/refresh/reveal"
plot "latency-refresh-reveal.data" with lines lw 1
set title "/keys"
plot "latency-keys.data" with lines lw 1
set title "/reserve/withdraw"
plot "latency-withdraw.data" with lines lw 1
set title "/deposit"
plot "latency-deposit.data" with lines lw 1
