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

sql_DATA = \
  exchange-0000.sql \
  exchange-0001.sql \
  drop0001.sql

EXTRA_DIST = \
  exchangedb.conf \
  exchangedb-postgres.conf \
  plugin_exchangedb_common.c \
  test-exchange-db-postgres.conf \
  $(sql_DATA)

plugindir = $(libdir)/taler

if HAVE_POSTGRESQL
plugin_LTLIBRARIES = \
  libtaler_plugin_exchangedb_postgres.la
endif

libtaler_plugin_exchangedb_postgres_la_SOURCES = \
  plugin_exchangedb_postgres.c
libtaler_plugin_exchangedb_postgres_la_LIBADD = \
  $(LTLIBINTL)
libtaler_plugin_exchangedb_postgres_la_LDFLAGS = \
  $(TALER_PLUGIN_LDFLAGS) \
  $(top_builddir)/src/pq/libtalerpq.la \
  $(top_builddir)/src/util/libtalerutil.la \
  -lpq \
  -lgnunetpq \
  -lgnunetutil \
  $(XLIB)

lib_LTLIBRARIES = \
  libtalerexchangedb.la

libtalerexchangedb_la_SOURCES = \
  exchangedb_accounts.c \
  exchangedb_auditorkeys.c \
  exchangedb_denomkeys.c \
  exchangedb_fees.c \
  exchangedb_plugin.c \
  exchangedb_signkeys.c \
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
  test-exchangedb-auditors \
  test-exchangedb-denomkeys \
  test-exchangedb-fees \
  test-exchangedb-signkeys \
  test-exchangedb-postgres

AM_TESTS_ENVIRONMENT=export TALER_PREFIX=$${TALER_PREFIX:-@libdir@};export PATH=$${TALER_PREFIX:-@prefix@}/bin:$$PATH;
TESTS = \
  test-exchangedb-auditors \
  test-exchangedb-denomkeys \
  test-exchangedb-fees \
  test-exchangedb-postgres \
  test-exchangedb-signkeys

test_exchangedb_auditors_SOURCES = \
  test_exchangedb_auditors.c
test_exchangedb_auditors_LDADD = \
  libtalerexchangedb.la \
  $(top_srcdir)/src/util/libtalerutil.la \
  -lgnunetutil \
  $(XLIB)

test_exchangedb_denomkeys_SOURCES = \
  test_exchangedb_denomkeys.c
test_exchangedb_denomkeys_LDADD = \
  libtalerexchangedb.la \
  $(top_srcdir)/src/util/libtalerutil.la \
  -lgnunetutil \
  $(XLIB)

test_exchangedb_fees_SOURCES = \
  test_exchangedb_fees.c
test_exchangedb_fees_LDADD = \
  libtalerexchangedb.la \
  $(top_srcdir)/src/util/libtalerutil.la \
  -lgnunetutil \
  $(XLIB)

test_exchangedb_signkeys_SOURCES = \
  test_exchangedb_signkeys.c
test_exchangedb_signkeys_LDADD = \
  libtalerexchangedb.la \
  $(top_srcdir)/src/util/libtalerutil.la \
  -lgnunetutil \
  $(XLIB)

test_exchangedb_postgres_SOURCES = \
  test_exchangedb.c
test_exchangedb_postgres_LDADD = \
  libtalerexchangedb.la \
  $(top_builddir)/src/json/libtalerjson.la \
  $(top_srcdir)/src/util/libtalerutil.la \
  $(top_srcdir)/src/pq/libtalerpq.la \
  -ljansson \
  -lgnunetutil \
  $(XLIB)

EXTRA_test_exchangedb_postgres_DEPENDENCIES = \
  libtaler_plugin_exchangedb_postgres.la
