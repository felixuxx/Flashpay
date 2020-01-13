# This Makefile.am is in the public domain
AM_CPPFLAGS = -I$(top_srcdir)/src/include

pkgcfgdir = $(prefix)/share/taler/config.d/

pkgcfg_DATA = \
  coins.conf

if USE_COVERAGE
  AM_CFLAGS = --coverage -O0
  XLIB = -lgcov
endif

bin_PROGRAMS = \
  taler-exchange-keyup \
  taler-exchange-keycheck \
  taler-exchange-wire \
  taler-exchange-dbinit \
  taler-exchange-tvg \
  taler-wire

taler_wire_SOURCES = \
  taler-wire.c
taler_wire_LDADD = \
  $(top_builddir)/src/util/libtalerutil.la \
  $(top_builddir)/src/bank-lib/libtalerbank.la \
  -lgnunetcurl \
  -lgnunetutil

taler_exchange_keyup_SOURCES = \
  taler-exchange-keyup.c
taler_exchange_keyup_LDADD = \
  $(LIBGCRYPT_LIBS) \
  $(top_builddir)/src/util/libtalerutil.la \
  $(top_builddir)/src/pq/libtalerpq.la \
  $(top_builddir)/src/bank-lib/libtalerbank.la \
  $(top_builddir)/src/exchangedb/libtalerexchangedb.la \
  -lgnunetutil $(XLIB)
taler_exchange_keyup_LDFLAGS = $(POSTGRESQL_LDFLAGS)


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
  -ljansson $(XLIB)
taler_exchange_wire_LDFLAGS = $(POSTGRESQL_LDFLAGS)

taler_exchange_keycheck_SOURCES = \
  taler-exchange-keycheck.c
taler_exchange_keycheck_LDADD = \
  $(LIBGCRYPT_LIBS) \
  $(top_builddir)/src/util/libtalerutil.la \
  $(top_builddir)/src/exchangedb/libtalerexchangedb.la \
  -lgnunetutil  $(XLIB)
taler_exchange_keycheck_LDFLAGS = $(POSTGRESQL_LDFLAGS)

taler_exchange_tvg_SOURCES = \
  taler-exchange-tvg.c
taler_exchange_tvg_LDADD = \
  $(LIBGCRYPT_LIBS) \
  $(top_builddir)/src/util/libtalerutil.la \
  -lgnunetutil  $(XLIB)

taler_exchange_dbinit_SOURCES = \
  taler-exchange-dbinit.c
taler_exchange_dbinit_LDADD = \
  $(LIBGCRYPT_LIBS) \
  $(top_builddir)/src/util/libtalerutil.la \
  $(top_builddir)/src/pq/libtalerpq.la \
  $(top_builddir)/src/exchangedb/libtalerexchangedb.la \
  -lgnunetutil  $(XLIB)
taler_exchange_dbinit_LDFLAGS = \
  $(POSTGRESQL_LDFLAGS)
taler_exchange_dbinit_CPPFLAGS = \
  -I$(top_srcdir)/src/include \
  -I$(top_srcdir)/src/pq/ \
  $(POSTGRESQL_CPPFLAGS)


EXTRA_DIST = \
  $(pkgcfg_DATA)
