# This Makefile.am is in the public domain
AM_CPPFLAGS = -I$(top_srcdir)/src/include -I$(top_srcdir)/src/pq/ $(POSTGRESQL_CPPFLAGS)

plugindir = $(libdir)/taler

plugin_LTLIBRARIES = \
  libtaler_plugin_mintdb_postgres.la

EXTRA_DIST = plugin_mintdb_common.c

libtaler_plugin_mintdb_postgres_la_SOURCES = \
  plugin_mintdb_postgres.c
libtaler_plugin_mintdb_postgres_la_LIBADD = \
  $(LTLIBINTL)
libtaler_plugin_mintdb_postgres_la_LDFLAGS = \
  $(TALER_PLUGIN_LDFLAGS) \
  -lpq \
  -lgnunetutil

lib_LTLIBRARIES = \
  libtalermintdb.la

libtalermintdb_la_SOURCES = \
  mintdb_keyio.c \
  mintdb_plugin.c

libtalermintdb_la_LIBADD = \
  $(top_builddir)/src/util/libtalerutil.la \
  -lgnunetutil

libtalermintdb_la_LDFLAGS = \
  $(POSTGRESQL_LDFLAGS) \
  -version-info 0:0:0 \
  -no-undefined


check_PROGRAMS = \
  test-mintdb-deposits \
  test-mintdb-keyio \
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
EXTRA_test_mintdb_postgres_DEPENDENCIES = \
  libtaler_plugin_mintdb_postgres.la
