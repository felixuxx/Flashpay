#/usr/bin/env bash

# This is intended to be run with SSH agent forwarding,
# so we can log in as root to adjust artificial delay.

set -eu

echo "setting latency to $1"

# check that we can log in at least!
ssh root@gv.taler.net true
ssh root@firefly.gnunet.org true

ssh root@gv.taler.net tc qdisc delete dev enp4s0f0 root || true
ssh root@firefly.gnunet.org tc qdisc delete dev eno2 root || true

ssh root@gv.taler.net tc qdisc add dev enp4s0f0 root netem delay "${1}ms"
ssh root@firefly.gnunet.org tc qdisc add dev eno2 root netem delay "${1}ms"

