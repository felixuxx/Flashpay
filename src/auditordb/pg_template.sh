#!/bin/sh
# This file is in the public domain.
#
# Instantiates pg_template for a particular function.

for n in $*
do
    NCAPS=`echo $n | tr a-z A-Z`
    if test ! -e pg_$n.c
    then
        cat pg_template.c | sed -e s/template/$n/g -e s/TEMPLATE/$NCAPS/g > pg_$n.c
        cat pg_template.h | sed -e s/template/$n/g -e s/TEMPLATE/$NCAPS/g > pg_$n.h
        echo "  plugin->$n\n    = &TAH_PG_$n;" >> tmpl.c
        echo "#include \"pg_$n.h\"" >> tmpl.inc
        echo "  pg_$n.h pg_$n.c \\" >> tmpl.am
    fi
done

echo "Add lines from tmpl.am to Makefile.am"
echo "Add lines from tmpl.inc to plugin_auditordb_postgres.c at the beginning"
echo "Add lines from tmpl.c to plugin_auditordb_postgres.c at the end"
