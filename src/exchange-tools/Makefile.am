# This Makefile.am is in the public domain
AM_CPPFLAGS = -I$(top_srcdir)/src/include

pkgcfgdir = $(prefix)/share/taler/config.d/

pkgcfg_DATA = \
  coins.conf \
  exchange-offline.conf

if USE_COVERAGE
  AM_CFLAGS = --coverage -O0
  XLIB = -lgcov
endif

bin_PROGRAMS = \
  taler-auditor-offline \
  taler-exchange-offline \
  taler-exchange-dbinit

taler_exchange_offline_SOURCES = \
  taler-exchange-offline.c
taler_exchange_offline_LDADD = \
  $(LIBGCRYPT_LIBS) \
  $(top_builddir)/src/lib/libtalerexchange.la \
  $(top_builddir)/src/json/libtalerjson.la \
  $(top_builddir)/src/util/libtalerutil.la \
  -lgnunetjson \
  -lgnunetcurl \
  -ljansson \
  -lgnunetutil \
  $(XLIB)

taler_auditor_offline_SOURCES = \
  taler-auditor-offline.c
taler_auditor_offline_LDADD = \
  $(LIBGCRYPT_LIBS) \
  $(top_builddir)/src/lib/libtalerexchange.la \
  $(top_builddir)/src/json/libtalerjson.la \
  $(top_builddir)/src/util/libtalerutil.la \
  -lgnunetjson \
  -lgnunetcurl \
  -ljansson \
  -lgnunetutil \
  $(XLIB)

taler_exchange_dbinit_SOURCES = \
  taler-exchange-dbinit.c
taler_exchange_dbinit_LDADD = \
  $(LIBGCRYPT_LIBS) \
  $(top_builddir)/src/util/libtalerutil.la \
  $(top_builddir)/src/pq/libtalerpq.la \
  $(top_builddir)/src/exchangedb/libtalerexchangedb.la \
  -lgnunetutil \
  $(XLIB)
taler_exchange_dbinit_LDFLAGS = \
  $(POSTGRESQL_LDFLAGS)
taler_exchange_dbinit_CPPFLAGS = \
  -I$(top_srcdir)/src/include \
  -I$(top_srcdir)/src/pq/ \
  $(POSTGRESQL_CPPFLAGS)


# Testcases

AM_TESTS_ENVIRONMENT=export TALER_PREFIX=$${TALER_PREFIX:-@libdir@};export PATH=$${TALER_PREFIX:-@prefix@}/bin:$$PATH;

# Distribution

EXTRA_DIST = \
  $(pkgcfg_DATA)
