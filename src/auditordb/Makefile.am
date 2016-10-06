# This Makefile.am is in the public domain
AM_CPPFLAGS = -I$(top_srcdir)/src/include -I$(top_srcdir)/src/pq/ $(POSTGRESQL_CPPFLAGS)

if USE_COVERAGE
  AM_CFLAGS = --coverage -O0
  XLIB = -lgcov
endif

pkgcfgdir = $(prefix)/share/taler/config.d/

pkgcfg_DATA = \
  auditordb-postgres.conf

EXTRA_DIST = \
  auditordb-postgres.conf 

plugindir = $(libdir)/taler

if HAVE_POSTGRESQL
plugin_LTLIBRARIES = \
  libtaler_plugin_auditordb_postgres.la
endif

libtaler_plugin_auditordb_postgres_la_SOURCES = \
  plugin_auditordb_postgres.c
libtaler_plugin_auditordb_postgres_la_LIBADD = \
  $(LTLIBINTL)
libtaler_plugin_auditordb_postgres_la_LDFLAGS = \
  $(TALER_PLUGIN_LDFLAGS) \
  $(top_builddir)/src/pq/libtalerpq.la \
  $(top_builddir)/src/util/libtalerutil.la \
  -lpq \
  -lgnunetpq \
  -lgnunetutil $(XLIB)

lib_LTLIBRARIES = \
  libtalerauditordb.la

libtalerauditordb_la_SOURCES = \
  auditordb_plugin.c

libtalerauditordb_la_LIBADD = \
  $(top_builddir)/src/util/libtalerutil.la \
  -lgnunetutil  $(XLIB)

libtalerauditordb_la_LDFLAGS = \
  $(POSTGRESQL_LDFLAGS) \
  -version-info 0:0:0 \
  -no-undefined


EXTRA_test_auditordb_postgres_DEPENDENCIES = \
  libtaler_plugin_auditordb_postgres.la
