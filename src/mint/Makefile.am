# This Makefile.am is in the public domain
AM_CPPFLAGS = -I$(top_srcdir)/src/include

if USE_COVERAGE
  AM_CFLAGS = --coverage -O0
  XLIB = -lgcov
endif

bin_PROGRAMS = \
  taler-mint-aggregator \
  taler-mint-httpd

taler_mint_aggregator_SOURCES = \
  taler-mint-aggregator.c
taler_mint_aggregator_LDADD = \
  $(LIBGCRYPT_LIBS) \
  $(top_builddir)/src/util/libtalerutil.la \
  $(top_builddir)/src/mintdb/libtalermintdb.la \
  -ljansson \
  -lgnunetutil

taler_mint_httpd_SOURCES = \
  taler-mint-httpd.c taler-mint-httpd.h \
  taler-mint-httpd_admin.c taler-mint-httpd_admin.h \
  taler-mint-httpd_db.c taler-mint-httpd_db.h \
  taler-mint-httpd_deposit.c taler-mint-httpd_deposit.h \
  taler-mint-httpd_keystate.c taler-mint-httpd_keystate.h \
  taler-mint-httpd_mhd.c taler-mint-httpd_mhd.h \
  taler-mint-httpd_parsing.c taler-mint-httpd_parsing.h \
  taler-mint-httpd_refresh.c taler-mint-httpd_refresh.h \
  taler-mint-httpd_reserve.c taler-mint-httpd_reserve.h \
  taler-mint-httpd_responses.c taler-mint-httpd_responses.h \
  taler-mint-httpd_tracking.c taler-mint-httpd_tracking.h \
  taler-mint-httpd_wire.c taler-mint-httpd_wire.h \
  taler-mint-httpd_validation.c taler-mint-httpd_validation.h
taler_mint_httpd_LDADD = \
  $(LIBGCRYPT_LIBS) \
  $(top_builddir)/src/util/libtalerutil.la \
  $(top_builddir)/src/mintdb/libtalermintdb.la \
  -lmicrohttpd \
  -ljansson \
  -lgnunetutil \
  -lpthread

if HAVE_DEVELOPER
taler_mint_httpd_SOURCES += \
  taler-mint-httpd_test.c taler-mint-httpd_test.h
endif

check_SCRIPTS = \
  test_taler_mint_httpd.sh

if HAVE_EXPENSIVE_TESTS
check_SCRIPTS += \
  test_taler_mint_httpd_afl.sh
endif

TESTS = $(check_SCRIPTS)
