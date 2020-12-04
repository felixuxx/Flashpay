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
  taler-exchange-keyup \
  taler-exchange-keycheck \
  taler-exchange-offline \
  taler-exchange-wire \
  taler-exchange-dbinit

taler_exchange_keyup_SOURCES = \
  taler-exchange-keyup.c
taler_exchange_keyup_LDADD = \
  $(LIBGCRYPT_LIBS) \
  $(top_builddir)/src/exchangedb/libtalerexchangedb.la \
  $(top_builddir)/src/bank-lib/libtalerbank.la \
  $(top_builddir)/src/json/libtalerjson.la \
  $(top_builddir)/src/pq/libtalerpq.la \
  $(top_builddir)/src/util/libtalerutil.la \
  -lgnunetutil \
  $(XLIB)
taler_exchange_keyup_LDFLAGS = $(POSTGRESQL_LDFLAGS)


taler_exchange_offline_SOURCES = \
  taler-exchange-offline.c
taler_exchange_offline_LDADD = \
  $(LIBGCRYPT_LIBS) \
  $(top_builddir)/src/lib/libtalerexchange.la \
  $(top_builddir)/src/json/libtalerjson.la \
  $(top_builddir)/src/util/libtalerutil.la \
  -lgnunetcurl \
  -lgnunetutil \
  $(XLIB)


taler_exchange_wire_SOURCES = \
  taler-exchange-wire.c
taler_exchange_wire_LDADD = \
  $(LIBGCRYPT_LIBS) \
  $(top_builddir)/src/json/libtalerjson.la \
  $(top_builddir)/src/exchangedb/libtalerexchangedb.la \
  $(top_builddir)/src/bank-lib/libtalerbank.la \
  $(top_builddir)/src/util/libtalerutil.la \
  -lgnunetjson \
  -lgnunetutil \
  -ljansson \
  $(XLIB)
taler_exchange_wire_LDFLAGS = $(POSTGRESQL_LDFLAGS)

taler_exchange_keycheck_SOURCES = \
  taler-exchange-keycheck.c
taler_exchange_keycheck_LDADD = \
  $(LIBGCRYPT_LIBS) \
  $(top_builddir)/src/util/libtalerutil.la \
  $(top_builddir)/src/exchangedb/libtalerexchangedb.la \
  -lgnunetutil \
  $(XLIB)
taler_exchange_keycheck_LDFLAGS = $(POSTGRESQL_LDFLAGS)

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

check_SCRIPTS = \
  test_taler_exchange_keyup.sh

TESTS = \
  $(check_SCRIPTS)

# Distribution

EXTRA_DIST = \
  test_taler_exchange_httpd_home/.local/share/taler/exchange/offline-keys/master.priv \
  test_taler_exchange_httpd.conf \
  key-helper.c \
  $(check_SCRIPTS) \
  $(pkgcfg_DATA)
