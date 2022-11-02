#!/bin/sh
# This file is in the public domain.
#
# Instantiates pg_template for a particular function.

for n in $*
do
    NCAPS=`echo $n | tr a-z A-Z`
    cat pg_template.c | sed -e s/template/$n/g -e s/TEMPLATE/$NCAPS/g > pg_$n.c
    cat pg_template.h | sed -e s/template/$n/g -e s/TEMPLATE/$NCAPS/g > pg_$n.h
    echo "\#include \"pg_$n.h\"" >> hdr.h
done
