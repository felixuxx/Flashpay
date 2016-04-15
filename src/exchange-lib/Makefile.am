# This Makefile.am is in the public domain
AM_CPPFLAGS = -I$(top_srcdir)/src/include

if USE_COVERAGE
  AM_CFLAGS = --coverage -O0
  XLIB = -lgcov
endif

lib_LTLIBRARIES = \
  libtalerexchange.la

libtalerexchange_la_LDFLAGS = \
  -version-info 0:0:0 \
  -no-undefined

libtalerexchange_la_SOURCES = \
  exchange_api_common.c exchange_api_common.h \
  exchange_api_context.c exchange_api_context.h \
  exchange_api_handle.c exchange_api_handle.h \
  exchange_api_admin.c \
  exchange_api_deposit.c \
  exchange_api_deposit_wtid.c \
  exchange_api_refresh.c \
  exchange_api_refresh_link.c \
  exchange_api_reserve.c \
  exchange_api_wire.c \
  exchange_api_wire_deposits.c

libtalerexchange_la_LIBADD = \
  $(top_builddir)/src/json/libtalerjson.la \
  $(top_builddir)/src/util/libtalerutil.la \
  -lgnunetjson \
  -lgnunetutil \
  -ljansson \
  $(XLIB)

if HAVE_LIBCURL
libtalerexchange_la_LIBADD += -lcurl
else
if HAVE_LIBGNURL
libtalerexchange_la_LIBADD += -lgnurl
endif
endif

check_PROGRAMS = \
  test_exchange_api

AM_TESTS_ENVIRONMENT=export TALER_PREFIX=$${TALER_PREFIX:-@libdir@};export PATH=$${TALER_PREFIX:-@prefix@}/bin:$$PATH;

TESTS = \
  $(check_PROGRAMS)

test_exchange_api_SOURCES = \
  test_exchange_api.c
test_exchange_api_LDADD = \
  libtalerexchange.la \
  $(LIBGCRYPT_LIBS) \
  $(top_builddir)/src/json/libtalerjson.la \
  $(top_builddir)/src/util/libtalerutil.la \
  -lgnunetutil \
  -ljansson

EXTRA_DIST = \
  test_taler_exchange_api_home/.local/share/taler/exchange/offline-keys/master.priv \
  test_taler_exchange_api_home/.config/taler/test.json \
  test_taler_exchange_api_home/.config/taler/sepa.json \
  test_taler_exchange_api.conf
