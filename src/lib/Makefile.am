# This Makefile.am is in the public domain
AM_CPPFLAGS = \
 -I$(top_srcdir)/src/include \
 $(LIBGCRYPT_CFLAGS) \
 $(POSTGRESQL_CPPFLAGS)

if USE_COVERAGE
  AM_CFLAGS = --coverage -O0
  XLIB = -lgcov
endif

# Libraries

lib_LTLIBRARIES = \
  libtalerauditor.la \
  libtalerexchange.la \
  libtalertesting.la

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
  exchange_api_wire.c
libtalerexchange_la_LIBADD = \
  libtalerauditor.la \
  $(top_builddir)/src/json/libtalerjson.la \
  $(top_builddir)/src/curl/libtalercurl.la \
  $(top_builddir)/src/util/libtalerutil.la \
  -lgnunetcurl \
  -lgnunetjson \
  -lgnunetutil \
  -ljansson \
  $(LIBGNURLCURL_LIBS) \
  $(XLIB)

libtalerauditor_la_LDFLAGS = \
  -version-info 0:0:0 \
  -no-undefined
libtalerauditor_la_SOURCES = \
  auditor_api_curl_defaults.c auditor_api_curl_defaults.h \
  auditor_api_handle.c auditor_api_handle.h \
  auditor_api_deposit_confirmation.c \
  auditor_api_exchanges.c
libtalerauditor_la_LIBADD = \
  $(top_builddir)/src/curl/libtalercurl.la \
  $(top_builddir)/src/json/libtalerjson.la \
  $(top_builddir)/src/util/libtalerutil.la \
  -lgnunetcurl \
  -lgnunetjson \
  -lgnunetutil \
  -ljansson \
  $(LIBGNURLCURL_LIBS) \
  $(XLIB)

libtalertesting_la_LDFLAGS = \
  -version-info 0:0:0 \
  -no-undefined
libtalertesting_la_SOURCES = \
  exchange_api_curl_defaults.c \
  testing_api_cmd_auditor_deposit_confirmation.c \
  testing_api_cmd_auditor_exchanges.c \
  testing_api_cmd_auditor_exec_auditor.c \
  testing_api_cmd_auditor_exec_auditor_dbinit.c \
  testing_api_cmd_auditor_exec_wire_auditor.c \
  testing_api_cmd_bank_admin_add_incoming.c \
  testing_api_cmd_bank_check.c \
  testing_api_cmd_bank_admin_check.c \
  testing_api_cmd_bank_check_empty.c \
  testing_api_cmd_bank_history_credit.c \
  testing_api_cmd_bank_history_debit.c \
  testing_api_cmd_bank_transfer.c \
  testing_api_cmd_batch.c \
  testing_api_cmd_check_keys.c \
  testing_api_cmd_deposit.c \
  testing_api_cmd_exec_aggregator.c \
  testing_api_cmd_exec_wirewatch.c \
  testing_api_cmd_exec_keyup.c \
  testing_api_cmd_exec_auditor-sign.c \
  testing_api_cmd_payback.c \
  testing_api_cmd_refund.c \
  testing_api_cmd_refresh.c \
  testing_api_cmd_serialize_keys.c \
  testing_api_cmd_signal.c \
  testing_api_cmd_sleep.c \
  testing_api_cmd_status.c \
  testing_api_cmd_track.c \
  testing_api_cmd_wire.c \
  testing_api_cmd_withdraw.c \
  testing_api_cmd_insert_deposit.c \
  testing_api_helpers_auditor.c \
  testing_api_helpers_bank.c \
  testing_api_helpers_exchange.c \
  testing_api_loop.c \
  testing_api_traits.c \
  testing_api_trait_amount.c \
  testing_api_trait_blinding_key.c \
  testing_api_trait_cmd.c \
  testing_api_trait_coin_priv.c \
  testing_api_trait_denom_pub.c \
  testing_api_trait_denom_sig.c \
  testing_api_trait_exchange_pub.c \
  testing_api_trait_exchange_sig.c \
  testing_api_trait_fresh_coin.c \
  testing_api_trait_json.c \
  testing_api_trait_key_peer.c \
  testing_api_trait_number.c \
  testing_api_trait_process.c \
  testing_api_trait_reserve_pub.c \
  testing_api_trait_reserve_priv.c \
  testing_api_trait_string.c \
  testing_api_trait_time.c \
  testing_api_trait_wtid.c
libtalertesting_la_LIBADD = \
  libtalerexchange.la \
  $(top_builddir)/src/json/libtalerjson.la \
  $(top_builddir)/src/util/libtalerutil.la \
  $(top_builddir)/src/bank-lib/libtalerbank.la \
  $(top_builddir)/src/bank-lib/libtalerfakebank.la \
  -lgnunetcurl \
  -lgnunetjson \
  -lgnunetutil \
  -ljansson \
  $(XLIB)

# Testcases

AM_TESTS_ENVIRONMENT=export TALER_PREFIX=$${TALER_PREFIX:-@libdir@};export PATH=$${TALER_PREFIX:-@prefix@}/bin:$$PATH;

check_PROGRAMS = \
  test_auditor_api \
  test_auditor_api_version \
  test_bank_api_with_fakebank \
  test_bank_api_with_pybank \
  test_exchange_api \
  test_exchange_api_keys_cherry_picking \
  test_exchange_api_revocation \
  test_exchange_api_overlapping_keys_bug \
  test_taler_exchange_aggregator-postgres \
  test_taler_exchange_wirewatch-postgres
if HAVE_TWISTER
  check_PROGRAMS += \
    test_exchange_api_twisted \
    test_bank_api_with_fakebank_twisted \
    test_bank_api_with_pybank_twisted
endif

TESTS = \
  $(check_PROGRAMS)

test_auditor_api_SOURCES = \
  test_auditor_api.c
test_auditor_api_LDADD = \
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

test_bank_api_with_fakebank_SOURCES = \
  test_bank_api.c
test_bank_api_with_fakebank_LDADD = \
  $(top_builddir)/src/lib/libtalertesting.la \
  -ltalerexchange \
  -lgnunetutil \
  $(top_builddir)/src/bank-lib/libtalerbank.la

test_bank_api_with_pybank_SOURCES = \
  test_bank_api.c
test_bank_api_with_pybank_LDADD = \
  libtalertesting.la \
  libtalerexchange.la \
  -lgnunetutil \
  $(top_builddir)/src/bank-lib/libtalerbank.la

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

test_taler_exchange_aggregator_postgres_SOURCES = \
  test_taler_exchange_aggregator.c
test_taler_exchange_aggregator_postgres_LDADD = \
  $(LIBGCRYPT_LIBS) \
  $(top_builddir)/src/exchangedb/libtalerexchangedb.la \
  $(top_builddir)/src/bank-lib/libtalerfakebank.la \
  $(top_builddir)/src/json/libtalerjson.la \
  $(top_builddir)/src/util/libtalerutil.la \
  $(top_builddir)/src/lib/libtalertesting.la \
  -lmicrohttpd \
  -lgnunetutil \
  -lgnunetjson \
  -ljansson \
  -lpthread

test_taler_exchange_wirewatch_postgres_SOURCES = \
  test_taler_exchange_wirewatch.c
test_taler_exchange_wirewatch_postgres_LDADD = \
  $(LIBGCRYPT_LIBS) \
  $(top_builddir)/src/exchangedb/libtalerexchangedb.la \
  $(top_builddir)/src/bank-lib/libtalerfakebank.la \
  $(top_builddir)/src/json/libtalerjson.la \
  $(top_builddir)/src/util/libtalerutil.la \
  $(top_builddir)/src/lib/libtalertesting.la \
  -lmicrohttpd \
  -lgnunetutil \
  -lgnunetjson \
  -lgnunetpq \
  -ljansson \
  -lpthread

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

test_bank_api_with_fakebank_twisted_SOURCES = \
  test_bank_api_twisted.c
test_bank_api_with_fakebank_twisted_LDADD = \
  $(top_builddir)/src/lib/libtalertesting.la \
  $(top_builddir)/src/bank-lib/libtalerbank.la \
  $(top_builddir)/src/bank-lib/libtalerfakebank.la \
  $(top_builddir)/src/lib/libtalerexchange.la \
  $(top_builddir)/src/json/libtalerjson.la \
  -ltalertwistertesting \
  -lgnunetjson \
  -lgnunetcurl \
  -lgnunetutil \
  -ljansson

test_bank_api_with_pybank_twisted_SOURCES = \
  test_bank_api_twisted.c
test_bank_api_with_pybank_twisted_LDADD = \
  $(top_builddir)/src/lib/libtalertesting.la \
  $(top_builddir)/src/bank-lib/libtalerbank.la \
  $(top_builddir)/src/bank-lib/libtalerfakebank.la \
  $(top_builddir)/src/lib/libtalerexchange.la \
  $(top_builddir)/src/json/libtalerjson.la \
  -ltalertwistertesting \
  -lgnunetjson \
  -lgnunetcurl \
  -lgnunetutil \
  -ljansson


# Distribution

EXTRA_DIST = \
  test_bank_api.conf \
  test_bank_api_bank_twisted.conf \
  test_auditor_api.conf \
  test_auditor_api_expire_reserve_now.conf \
  test_exchange_api_home/.local/share/taler/exchange/offline-keys/master.priv \
  test_exchange_api_home/.config/taler/account-2.json \
  test_exchange_api_keys_cherry_picking_home/.config/taler/x-taler-bank.json \
  test_exchange_api_keys_cherry_picking_home/.local/share/taler/exchange/wirefees/x-taler-bank.fee \
  test_exchange_api_keys_cherry_picking_home/.local/share/taler/exchange/offline-keys/master.priv \
  test_exchange_api_home/.config/taler/test.json \
  test_exchange_api_home/.config/taler/sepa.json \
  test_exchange_api.conf \
  test_exchange_api_twisted.conf \
  test_exchange_api_keys_cherry_picking.conf \
  test_exchange_api_keys_cherry_picking_extended.conf \
  test_exchange_api_keys_cherry_picking_extended_2.conf \
  test_exchange_api_expire_reserve_now.conf \
  test-taler-exchange-aggregator-postgres.conf \
  test-taler-exchange-wirewatch-postgres.conf
