# This Makefile.am is in the public domain
AM_CPPFLAGS = -I$(top_srcdir)/src/include -I$(top_srcdir)/src/pq/ $(POSTGRESQL_CPPFLAGS)

if USE_COVERAGE
  AM_CFLAGS = --coverage -O0
  XLIB = -lgcov
endif

plugindir = $(libdir)/taler

if HAVE_POSTGRESQL
plugin_LTLIBRARIES = \
  libtaler_plugin_mintdb_postgres.la
endif

EXTRA_DIST = \
  plugin_mintdb_common.c \
  test-mint-db-postgres.conf

libtaler_plugin_mintdb_postgres_la_SOURCES = \
  plugin_mintdb_postgres.c
libtaler_plugin_mintdb_postgres_la_LIBADD = \
  $(LTLIBINTL)
libtaler_plugin_mintdb_postgres_la_LDFLAGS = \
  $(TALER_PLUGIN_LDFLAGS) \
  -lpq \
  -lgnunetutil $(XLIB)

lib_LTLIBRARIES = \
  libtalermintdb.la

libtalermintdb_la_SOURCES = \
  mintdb_keyio.c \
  mintdb_plugin.c

libtalermintdb_la_LIBADD = \
  $(top_builddir)/src/util/libtalerutil.la \
  -lgnunetutil  $(XLIB)

libtalermintdb_la_LDFLAGS = \
  $(POSTGRESQL_LDFLAGS) \
  -version-info 0:0:0 \
  -no-undefined


check_PROGRAMS = \
  test-mintdb-deposits \
  test-mintdb-keyio \
  test-mintdb-postgres \
	perf-mintdb

TESTS = \
  test-mintdb-postgres

test_mintdb_deposits_SOURCES = \
  test_mintdb_deposits.c
test_mintdb_deposits_LDADD = \
  libtalermintdb.la \
  $(top_srcdir)/src/util/libtalerutil.la \
  $(top_srcdir)/src/pq/libtalerpq.la \
  -lgnunetutil \
  -ljansson \
  -lpq

test_mintdb_keyio_SOURCES = \
  test_mintdb_keyio.c
test_mintdb_keyio_LDADD = \
  libtalermintdb.la \
  $(top_srcdir)/src/util/libtalerutil.la \
  $(top_srcdir)/src/pq/libtalerpq.la \
  -lgnunetutil

test_mintdb_postgres_SOURCES = \
  test_mintdb.c
test_mintdb_postgres_LDADD = \
  libtalermintdb.la \
  $(top_srcdir)/src/util/libtalerutil.la \
  $(top_srcdir)/src/pq/libtalerpq.la \
  -lgnunetutil -ljansson

perf_mintdb_SOURCES = \
	perf_taler_mintdb.c \
	perf_taler_mintdb_init.c \
	perf_taler_mintdb_interpreter.c

perf_mintdb_LDADD = \
	libtalermintdb.la \
  $(top_srcdir)/src/util/libtalerutil.la \
	-lgnunetutil


EXTRA_test_mintdb_postgres_DEPENDENCIES = \
  libtaler_plugin_mintdb_postgres.la
