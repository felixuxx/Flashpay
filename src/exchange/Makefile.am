# This Makefile.am is in the public domain
AM_CPPFLAGS = -I$(top_srcdir)/src/include

if USE_COVERAGE
  AM_CFLAGS = --coverage -O0
  XLIB = -lgcov
endif

bin_PROGRAMS = \
  taler-exchange-aggregator \
  taler-exchange-httpd

taler_exchange_aggregator_SOURCES = \
  taler-exchange-aggregator.c
taler_exchange_aggregator_LDADD = \
  $(LIBGCRYPT_LIBS) \
  $(top_builddir)/src/json/libtalerjson.la \
  $(top_builddir)/src/util/libtalerutil.la \
  $(top_builddir)/src/wire/libtalerwire.la \
  $(top_builddir)/src/exchangedb/libtalerexchangedb.la \
  -ljansson \
  -lgnunetutil

taler_exchange_httpd_SOURCES = \
  taler-exchange-httpd.c taler-exchange-httpd.h \
  taler-exchange-httpd_admin.c taler-exchange-httpd_admin.h \
  taler-exchange-httpd_db.c taler-exchange-httpd_db.h \
  taler-exchange-httpd_deposit.c taler-exchange-httpd_deposit.h \
  taler-exchange-httpd_keystate.c taler-exchange-httpd_keystate.h \
  taler-exchange-httpd_mhd.c taler-exchange-httpd_mhd.h \
  taler-exchange-httpd_parsing.c taler-exchange-httpd_parsing.h \
  taler-exchange-httpd_refresh.c taler-exchange-httpd_refresh.h \
  taler-exchange-httpd_reserve.c taler-exchange-httpd_reserve.h \
  taler-exchange-httpd_responses.c taler-exchange-httpd_responses.h \
  taler-exchange-httpd_tracking.c taler-exchange-httpd_tracking.h \
  taler-exchange-httpd_wire.c taler-exchange-httpd_wire.h \
  taler-exchange-httpd_validation.c taler-exchange-httpd_validation.h
taler_exchange_httpd_LDADD = \
  $(LIBGCRYPT_LIBS) \
  $(top_builddir)/src/json/libtalerjson.la \
  $(top_builddir)/src/util/libtalerutil.la \
  $(top_builddir)/src/exchangedb/libtalerexchangedb.la \
  -lmicrohttpd \
  -lgnunetutil \
  -lgnunetjson \
  -ljansson \
  -lpthread

if HAVE_DEVELOPER
taler_exchange_httpd_SOURCES += \
  taler-exchange-httpd_test.c taler-exchange-httpd_test.h
endif

check_SCRIPTS = \
  test_taler_exchange_httpd.sh

if HAVE_EXPENSIVE_TESTS
check_SCRIPTS += \
  test_taler_exchange_httpd_afl.sh
endif

TESTS = $(check_SCRIPTS)
