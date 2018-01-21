# This Makefile.am is in the public domain
AM_CPPFLAGS = -I$(top_srcdir)/src/include -I$(top_srcdir)/src/bank-lib

if USE_COVERAGE
  AM_CFLAGS = --coverage -O0
  XLIB = -lgcov
endif

lib_LTLIBRARIES = \
  libtalerexchange.la \
  libtalertesting.la

libtalerexchange_la_LDFLAGS = \
  -version-info 4:0:0 \
  -no-undefined
libtalerexchange_la_SOURCES = \
  exchange_api_common.c \
  exchange_api_handle.c exchange_api_handle.h \
  exchange_api_deposit.c \
  exchange_api_payback.c \
  exchange_api_refresh.c \
  exchange_api_refresh_link.c \
  exchange_api_refund.c \
  exchange_api_reserve.c \
  exchange_api_track_transaction.c \
  exchange_api_track_transfer.c \
  exchange_api_wire.c
libtalerexchange_la_LIBADD = \
  $(top_builddir)/src/json/libtalerjson.la \
  $(top_builddir)/src/util/libtalerutil.la \
  -lgnunetcurl \
  -lgnunetjson \
  -lgnunetutil \
  -ljansson \
  $(XLIB)


libtalertesting_la_LDFLAGS = \
  -version-info 0:0:0 \
  -no-undefined
libtalertesting_la_SOURCES = \
  testing_api_cmd_fakebank_transfer.c \
  testing_api_cmd_withdraw.c \
  testing_api_helpers.c \
  testing_api_loop.c \
  testing_api_traits.c \
  testing_api_trait_blinding_key.c \
  testing_api_trait_coin_priv.c \
  testing_api_trait_denom_pub.c \
  testing_api_trait_denom_sig.c \
  testing_api_trait_process.c \
  testing_api_trait_reserve_priv.c

libtalertesting_la_LIBADD = \
  $(top_builddir)/src/json/libtalerjson.la \
  $(top_builddir)/src/util/libtalerutil.la \
  -lgnunetcurl \
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
  test_exchange_api \
  test_exchange_api_keys_cherry_picking \
  test_exchange_api_new

AM_TESTS_ENVIRONMENT=export TALER_PREFIX=$${TALER_PREFIX:-@libdir@};export PATH=$${TALER_PREFIX:-@prefix@}/bin:$$PATH;

TESTS = \
  test_exchange_api \
  test_exchange_api_keys_cherry_picking

test_exchange_api_SOURCES = \
  test_exchange_api.c
test_exchange_api_LDADD = \
  libtalerexchange.la \
  $(LIBGCRYPT_LIBS) \
  $(top_builddir)/src/bank-lib/libtalerfakebank.la \
  $(top_builddir)/src/bank-lib/libtalerbank.la \
  $(top_builddir)/src/json/libtalerjson.la \
  $(top_builddir)/src/util/libtalerutil.la \
  -lgnunetcurl \
  -lgnunetutil \
  -ljansson

test_exchange_api_new_SOURCES = \
  test_exchange_api_new.c
test_exchange_api_new_LDADD = \
  libtalertesting.la \
  libtalerexchange.la \
  $(LIBGCRYPT_LIBS) \
  $(top_builddir)/src/bank-lib/libtalerfakebank.la \
  $(top_builddir)/src/bank-lib/libtalerbank.la \
  $(top_builddir)/src/json/libtalerjson.la \
  $(top_builddir)/src/util/libtalerutil.la \
  -lgnunetcurl \
  -lgnunetutil \
  -ljansson

test_exchange_api_keys_cherry_picking_SOURCES = \
  test_exchange_api_keys_cherry_picking.c
test_exchange_api_keys_cherry_picking_LDADD = \
  libtalerexchange.la \
  $(LIBGCRYPT_LIBS) \
  $(top_builddir)/src/json/libtalerjson.la \
  $(top_builddir)/src/util/libtalerutil.la \
  -lgnunetcurl \
  -lgnunetutil \
  -ljansson

EXTRA_DIST = \
  test_exchange_api_home/.local/share/taler/exchange/offline-keys/master.priv \
  test_exchange_api_home/.config/taler/test.json \
  test_exchange_api_home/.config/taler/sepa.json \
  test_exchange_api.conf \
  test_exchange_api_keys_cherry_picking.conf \
  test_exchange_api_keys_cherry_picking_extended.conf
