# This Makefile.am is in the public domain
AM_CPPFLAGS = -I$(top_srcdir)/src/include -I$(top_srcdir)/src/pq/ $(POSTGRESQL_CPPFLAGS)

if USE_COVERAGE
  AM_CFLAGS = --coverage -O0
  XLIB = -lgcov
endif

pkgcfgdir = $(prefix)/share/taler/config.d/

pkgcfg_DATA = \
  exchangedb.conf \
  exchangedb-postgres.conf

sqldir = $(prefix)/share/taler/sql/exchange/

sqlinputs = \
  common-0001.sql \
  exchange-0001.sql.in \
  exchange-0001-part.sql \
  shard-0001-part.sql \
  shard-0001.sql.in

sql_DATA = \
  benchmark-0001.sql \
  versioning.sql \
  exchange-0001.sql \
  drop.sql \
  procedures.sql \
  shard-0001.sql

BUILT_SOURCES = \
  shard-0001.sql \
  exchange-0001.sql \
  drop.sql \
  procedures.sql

CLEANFILES = \
  shard-0001.sql \
  exchange-0001.sql

exchange-0001.sql: common-0001.sql exchange-0001-part.sql exchange-0001.sql.in
	chmod +w $@ || true
	gcc -E -P -undef - < exchange-0001.sql.in 2>/dev/null | sed -e "s/--.*//" | awk 'NF' - >$@
	chmod ugo-w $@

shard-0001.sql: common-0001.sql shard-0001-part.sql exchange-0001.sql.in
	chmod +w $@ || true
	gcc -E -P -undef - < shard-0001.sql.in 2>/dev/null | sed -e "s/--.*//" | awk 'NF' - >$@
	chmod ugo-w $@

EXTRA_DIST = \
  exchangedb.conf \
  exchangedb-postgres.conf \
  plugin_exchangedb_common.c \
  irbt_callbacks.c \
  lrbt_callbacks.c \
  bench-db-postgres.conf \
  test-exchange-db-postgres.conf \
  $(sqlinputs) \
  $(sql_DATA)

plugindir = $(libdir)/taler

if HAVE_POSTGRESQL
plugin_LTLIBRARIES = \
  libtaler_plugin_exchangedb_postgres.la
endif

libtaler_plugin_exchangedb_postgres_la_SOURCES = \
  plugin_exchangedb_postgres.c pg_helper.h \
  pg_insert_close_request.c pg_insert_close_request.h \
  pg_insert_reserve_open_deposit.c pg_insert_reserve_open_deposit.h
libtaler_plugin_exchangedb_postgres_la_LIBADD = \
  $(LTLIBINTL)
libtaler_plugin_exchangedb_postgres_la_LDFLAGS = \
  $(TALER_PLUGIN_LDFLAGS) \
  $(top_builddir)/src/pq/libtalerpq.la \
  $(top_builddir)/src/json/libtalerjson.la \
  $(top_builddir)/src/util/libtalerutil.la \
  -lpq \
  -lpthread \
  -lgnunetpq \
  -lgnunetutil \
  -ljansson \
  $(XLIB)

lib_LTLIBRARIES = \
  libtalerexchangedb.la

libtalerexchangedb_la_SOURCES = \
  exchangedb_accounts.c \
  exchangedb_plugin.c \
  exchangedb_transactions.c
libtalerexchangedb_la_LIBADD = \
  $(top_builddir)/src/bank-lib/libtalerbank.la \
  $(top_builddir)/src/util/libtalerutil.la \
  -lgnunetutil \
  $(XLIB)
libtalerexchangedb_la_LDFLAGS = \
  $(POSTGRESQL_LDFLAGS) \
  -version-info 1:0:0 \
  -no-undefined


check_PROGRAMS = \
  test-exchangedb-postgres \
  bench-db-postgres

AM_TESTS_ENVIRONMENT=export TALER_PREFIX=$${TALER_PREFIX:-@libdir@};export PATH=$${TALER_PREFIX:-@prefix@}/bin:$$PATH;
TESTS = \
  test-exchangedb-postgres

test_exchangedb_postgres_SOURCES = \
  test_exchangedb.c
test_exchangedb_postgres_LDADD = \
  libtalerexchangedb.la \
  $(top_builddir)/src/json/libtalerjson.la \
  $(top_builddir)/src/util/libtalerutil.la \
  $(top_builddir)/src/pq/libtalerpq.la \
  -ljansson \
  -lgnunetjson \
  -lgnunetutil \
  $(XLIB)

bench_db_postgres_SOURCES = \
  bench_db.c
bench_db_postgres_LDADD = \
  libtalerexchangedb.la \
  $(top_builddir)/src/util/libtalerutil.la \
  $(top_builddir)/src/pq/libtalerpq.la \
  -lgnunetpq \
  -lgnunetutil \
  $(XLIB)

EXTRA_test_exchangedb_postgres_DEPENDENCIES = \
  libtaler_plugin_exchangedb_postgres.la
