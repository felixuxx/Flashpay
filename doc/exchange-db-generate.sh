#!/bin/sh
taler-exchange-dbinit -r
java -jar schemaSpy_5.0.0.jar -t pgsql -db taler -o taler -host localhost -dp /usr/share/java/postgresql-jdbc3-9.2.jar -u grothoff -p test -s public -hq
