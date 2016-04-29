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

EXTRA_DIST = \
  exchangedb.conf \
  exchangedb-postgres.conf \
  plugin_exchangedb_common.c \
  test-exchange-db-postgres.conf


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
  -lgnunetutil $(XLIB)

lib_LTLIBRARIES = \
  libtalerexchangedb.la

libtalerexchangedb_la_SOURCES = \
  exchangedb_keyio.c \
  exchangedb_plugin.c

libtalerexchangedb_la_LIBADD = \
  $(top_builddir)/src/util/libtalerutil.la \
  -lgnunetutil  $(XLIB)

libtalerexchangedb_la_LDFLAGS = \
  $(POSTGRESQL_LDFLAGS) \
  -version-info 0:0:0 \
  -no-undefined


check_PROGRAMS = \
  test-exchangedb-deposits \
  test-exchangedb-keyio \
  test-exchangedb-postgres \
  test-perf-taler-exchangedb \
  perf-exchangedb

AM_TESTS_ENVIRONMENT=export TALER_PREFIX=$${TALER_PREFIX:-@libdir@};export PATH=$${TALER_PREFIX:-@prefix@}/bin:$$PATH;
TESTS = \
  test-exchangedb-postgres \
  test-perf-taler-exchangedb

test_exchangedb_deposits_SOURCES = \
  test_exchangedb_deposits.c
test_exchangedb_deposits_LDADD = \
  libtalerexchangedb.la \
  $(top_srcdir)/src/util/libtalerutil.la \
  $(top_srcdir)/src/pq/libtalerpq.la \
  -lgnunetutil \
  -ljansson \
  -lpq

test_exchangedb_keyio_SOURCES = \
  test_exchangedb_keyio.c
test_exchangedb_keyio_LDADD = \
  libtalerexchangedb.la \
  $(top_srcdir)/src/util/libtalerutil.la \
  $(top_srcdir)/src/pq/libtalerpq.la \
  -lgnunetutil

test_exchangedb_postgres_SOURCES = \
  test_exchangedb.c
test_exchangedb_postgres_LDADD = \
  libtalerexchangedb.la \
  $(top_builddir)/src/json/libtalerjson.la \
  $(top_srcdir)/src/util/libtalerutil.la \
  $(top_srcdir)/src/pq/libtalerpq.la \
  -lgnunetutil -ljansson

test_perf_taler_exchangedb_SOURCES = \
  test_perf_taler_exchangedb.c \
  perf_taler_exchangedb_init.c perf_taler_exchangedb_init.h \
  perf_taler_exchangedb_interpreter.c perf_taler_exchangedb_interpreter.h
test_perf_taler_exchangedb_LDADD = \
  libtalerexchangedb.la \
  $(top_srcdir)/src/util/libtalerutil.la \
  $(top_srcdir)/src/pq/libtalerpq.la \
  -ljansson \
  -lgnunetutil

perf_exchangedb_SOURCES = \
  perf_taler_exchangedb.c \
  perf_taler_exchangedb_init.c perf_taler_exchangedb_init.h \
  perf_taler_exchangedb_interpreter.c perf_taler_exchangedb_interpreter.h
perf_exchangedb_LDADD = \
  libtalerexchangedb.la \
  $(top_srcdir)/src/util/libtalerutil.la \
  $(top_srcdir)/src/pq/libtalerpq.la \
  -ljansson \
  -lgnunetutil


EXTRA_test_exchangedb_postgres_DEPENDENCIES = \
  libtaler_plugin_exchangedb_postgres.la
