# This Makefile.am is in the public domain
AM_CPPFLAGS = -I$(top_srcdir)/src/include -I$(top_srcdir)/src/bank-lib

if USE_COVERAGE
  AM_CFLAGS = --coverage -O0
  XLIB = -lgcov
endif

lib_LTLIBRARIES = \
  libtalerauditor.la \
  libtalerexchange.la \
  libtalertesting.la \
  libtalerauditortesting.la

libtalerexchange_la_LDFLAGS = \
  -version-info 4:0:0 \
  -no-undefined
libtalerexchange_la_SOURCES = \
  exchange_api_curl_defaults.c exchange_api_curl_defaults.h \
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
  exchange_api_wire.c \
  teah_common.c
libtalerexchange_la_LIBADD = \
  libtalerauditor.la \
  $(top_builddir)/src/json/libtalerjson.la \
  $(top_builddir)/src/util/libtalerutil.la \
  -lgnunetcurl \
  -lgnunetjson \
  -lgnunetutil \
  -ljansson \
  $(XLIB)


libtalerauditor_la_LDFLAGS = \
  -version-info 0:0:0 \
  -no-undefined
libtalerauditor_la_SOURCES = \
  auditor_api_curl_defaults.c auditor_api_curl_defaults.h \
  auditor_api_handle.c auditor_api_handle.h \
  auditor_api_deposit_confirmation.c \
  auditor_api_exchanges.c \
  teah_common.c
libtalerauditor_la_LIBADD = \
  $(top_builddir)/src/json/libtalerjson.la \
  $(top_builddir)/src/util/libtalerutil.la \
  -lgnunetcurl \
  -lgnunetjson \
  -lgnunetutil \
  -ljansson \
  $(XLIB)

if HAVE_LIBCURL
libtalerauditor_la_LIBADD += -lcurl
else
if HAVE_LIBGNURL
libtalerauditor_la_LIBADD += -lgnurl
endif
endif


libtalertesting_la_LDFLAGS = \
  -version-info 0:0:0 \
  -no-undefined
libtalertesting_la_SOURCES = \
  exchange_api_curl_defaults.c \
  testing_api_cmd_exec_aggregator.c \
  testing_api_cmd_exec_wirewatch.c \
  testing_api_cmd_exec_keyup.c \
  testing_api_cmd_exec_auditor-sign.c \
  testing_api_cmd_fakebank_transfer.c \
  testing_api_cmd_withdraw.c \
  testing_api_cmd_wire.c \
  testing_api_cmd_refund.c \
  testing_api_cmd_status.c \
  testing_api_cmd_deposit.c \
  testing_api_cmd_sleep.c \
  testing_api_cmd_refresh.c \
  testing_api_cmd_track.c \
  testing_api_cmd_bank_check.c \
  testing_api_cmd_payback.c \
  testing_api_cmd_signal.c \
  testing_api_cmd_check_keys.c \
  testing_api_cmd_batch.c \
  testing_api_cmd_serialize_keys.c \
  testing_api_helpers.c \
  testing_api_loop.c \
  testing_api_traits.c \
  testing_api_trait_blinding_key.c \
  testing_api_trait_coin_priv.c \
  testing_api_trait_denom_pub.c \
  testing_api_trait_denom_sig.c \
  testing_api_trait_exchange_pub.c \
  testing_api_trait_exchange_sig.c \
  testing_api_trait_json.c \
  testing_api_trait_process.c \
  testing_api_trait_reserve_priv.c \
  testing_api_trait_number.c \
  testing_api_trait_fresh_coin.c \
  testing_api_trait_string.c \
  testing_api_trait_key_peer.c \
  testing_api_trait_wtid.c \
  testing_api_trait_amount.c \
  testing_api_trait_cmd.c \
  testing_api_trait_time.c
libtalertesting_la_LIBADD = \
  libtalerexchange.la \
  $(top_builddir)/src/wire/libtalerwire.la \
  $(top_builddir)/src/json/libtalerjson.la \
  $(top_builddir)/src/util/libtalerutil.la \
  $(top_builddir)/src/bank-lib/libtalerbank.la \
  $(top_builddir)/src/bank-lib/libtalerfakebank.la \
  -lgnunetcurl \
  -lgnunetjson \
  -lgnunetutil \
  -ljansson \
  $(XLIB)

libtalerauditortesting_la_LDFLAGS = \
  -version-info 0:0:0 \
  -no-undefined
libtalerauditortesting_la_SOURCES = \
  testing_auditor_api_helpers.c \
  testing_auditor_api_cmd_deposit_confirmation.c \
  testing_auditor_api_cmd_exchanges.c \
  testing_auditor_api_cmd_exec_auditor.c \
  testing_auditor_api_cmd_exec_auditor_dbinit.c \
  testing_auditor_api_cmd_exec_wire_auditor.c
libtalerauditortesting_la_LIBADD = \
  libtalerauditor.la \
  libtalerexchange.la \
  libtalertesting.la \
  $(top_builddir)/src/wire/libtalerwire.la \
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
  test_exchange_api_keys_cherry_picking \
  test_exchange_api_overlapping_keys_bug \
  test_exchange_api \
  test_exchange_api_revocation \
  test_auditor_api_version \
  test_auditor_api

if HAVE_TWISTER
  check_PROGRAMS += \
    test_exchange_api_twisted

test_exchange_api_twisted_SOURCES = \
  test_exchange_api_twisted.c
test_exchange_api_twisted_LDADD = \
  $(LIBGCRYPT_LIBS) \
  libtalertesting.la \
  libtalerexchange.la \
  $(top_builddir)/src/bank-lib/libtalerfakebank.la \
  $(top_builddir)/src/bank-lib/libtalerbank.la \
  $(top_builddir)/src/json/libtalerjson.la \
  $(top_builddir)/src/util/libtalerutil.la \
  -ltalertwistertesting \
  -lgnunetjson \
  -lgnunetcurl \
  -lgnunetutil \
  -ljansson

endif

AM_TESTS_ENVIRONMENT=export TALER_PREFIX=$${TALER_PREFIX:-@libdir@};export PATH=$${TALER_PREFIX:-@prefix@}/bin:$$PATH;

TESTS = \
  $(check_PROGRAMS)

# expected to fail for now: test incomplete, feature not implemented!
#XFAIL_TESTS = \
#  test_exchange_api_revocation

test_exchange_api_SOURCES = \
  test_exchange_api.c
test_exchange_api_LDADD = \
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

test_exchange_api_revocation_SOURCES = \
  test_exchange_api_revocation.c
test_exchange_api_revocation_LDADD = \
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

test_exchange_api_overlapping_keys_bug_SOURCES = \
  test_exchange_api_overlapping_keys_bug.c
test_exchange_api_overlapping_keys_bug_LDADD = \
  libtalertesting.la \
  libtalerexchange.la \
  $(LIBGCRYPT_LIBS) \
  $(top_builddir)/src/json/libtalerjson.la \
  $(top_builddir)/src/util/libtalerutil.la \
  $(top_builddir)/src/bank-lib/libtalerbank.la \
  -lgnunetcurl \
  -lgnunetutil \
  -ljansson

test_exchange_api_keys_cherry_picking_SOURCES = \
  test_exchange_api_keys_cherry_picking.c
test_exchange_api_keys_cherry_picking_LDADD = \
  libtalertesting.la \
  libtalerexchange.la \
  $(LIBGCRYPT_LIBS) \
  $(top_builddir)/src/json/libtalerjson.la \
  $(top_builddir)/src/util/libtalerutil.la \
  $(top_builddir)/src/bank-lib/libtalerbank.la \
  -lgnunetcurl \
  -lgnunetutil \
  -ljansson

test_auditor_api_SOURCES = \
  test_auditor_api.c
test_auditor_api_LDADD = \
  libtalerauditortesting.la \
  libtalerauditor.la \
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


test_auditor_api_version_SOURCES = \
  test_auditor_api_version.c
test_auditor_api_version_LDADD = \
  libtalerauditor.la \
  $(LIBGCRYPT_LIBS) \
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
  test_exchange_api_keys_cherry_picking_extended.conf \
  test_auditor_api.conf \
  test_auditor_api_expire_reserve_now.conf
