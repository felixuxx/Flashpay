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
  libtalertesting.la

if HAVE_TWISTER
lib_LTLIBRARIES += libtalertwistertesting.la
libtalertwistertesting_la_SOURCES = \
  testing_api_twister_helpers.c \
  testing_api_cmd_twister_exec_client.c
libtalertwistertesting_la_LIBADD = \
  -lgnunetutil \
  libtalertesting.la \
  -ltalertwister \
  $(XLIB)
libtalertwistertesting_la_LDFLAGS = \
  $(GN_LIB_LDFLAGS) $(WINFLAGS) \
  -version-info 0:0:0
endif

libtalertesting_la_LDFLAGS = \
  -version-info 0:0:0 \
  -no-undefined
libtalertesting_la_SOURCES = \
  testing_api_cmd_auditor_add_denom_sig.c \
  testing_api_cmd_auditor_add.c \
  testing_api_cmd_auditor_del.c \
  testing_api_cmd_auditor_deposit_confirmation.c \
  testing_api_cmd_auditor_exchanges.c \
  testing_api_cmd_auditor_exec_auditor.c \
  testing_api_cmd_auditor_exec_auditor_dbinit.c \
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
  testing_api_cmd_deposits_get.c \
  testing_api_cmd_exec_aggregator.c \
  testing_api_cmd_exec_closer.c \
  testing_api_cmd_exec_transfer.c \
  testing_api_cmd_exec_wirewatch.c \
  testing_api_cmd_insert_deposit.c \
  testing_api_cmd_offline_sign_fees.c \
  testing_api_cmd_offline_sign_keys.c \
  testing_api_cmd_set_wire_fee.c \
  testing_api_cmd_recoup.c \
  testing_api_cmd_refund.c \
  testing_api_cmd_refresh.c \
  testing_api_cmd_revoke.c \
  testing_api_cmd_revoke_denom_key.c \
  testing_api_cmd_revoke_sign_key.c \
  testing_api_cmd_rewind.c \
  testing_api_cmd_serialize_keys.c \
  testing_api_cmd_signal.c \
  testing_api_cmd_sleep.c \
  testing_api_cmd_stat.c \
  testing_api_cmd_status.c \
  testing_api_cmd_transfer_get.c \
  testing_api_cmd_wait.c \
  testing_api_cmd_wire.c \
  testing_api_cmd_wire_add.c \
  testing_api_cmd_wire_del.c \
  testing_api_cmd_withdraw.c \
  testing_api_helpers_auditor.c \
  testing_api_helpers_bank.c \
  testing_api_helpers_exchange.c \
  testing_api_loop.c \
  testing_api_traits.c \
  testing_api_trait_amount.c \
  testing_api_trait_blinding_key.c \
  testing_api_trait_cmd.c \
  testing_api_trait_coin_priv.c \
  testing_api_trait_contract.c \
  testing_api_trait_denom_pub.c \
  testing_api_trait_denom_sig.c \
  testing_api_trait_exchange_pub.c \
  testing_api_trait_exchange_sig.c \
  testing_api_trait_fresh_coin.c \
  testing_api_trait_json.c \
  testing_api_trait_merchant_key.c \
  testing_api_trait_number.c \
  testing_api_trait_process.c \
  testing_api_trait_reserve_history.c \
  testing_api_trait_reserve_pub.c \
  testing_api_trait_reserve_priv.c \
  testing_api_trait_string.c \
  testing_api_trait_time.c \
  testing_api_trait_uuid.c \
  testing_api_trait_wtid.c
libtalertesting_la_LIBADD = \
  $(top_builddir)/src/lib/libtalerauditor.la \
  $(top_builddir)/src/lib/libtalerexchange.la \
  $(top_builddir)/src/json/libtalerjson.la \
  $(top_builddir)/src/util/libtalerutil.la \
  $(top_builddir)/src/bank-lib/libtalerbank.la \
  $(top_builddir)/src/bank-lib/libtalerfakebank.la \
  -lgnunetcurl \
  -lgnunetjson \
  -lgnunetutil \
  -ljansson \
  $(XLIB)


# Test cases

AM_TESTS_ENVIRONMENT=export TALER_PREFIX=$${TALER_PREFIX:-@libdir@};export PATH=$${TALER_PREFIX:-@prefix@}/bin:$$PATH;

.NOTPARALLEL:
check_PROGRAMS = \
  test_auditor_api \
  test_auditor_api_version \
  test_bank_api_with_fakebank \
  test_bank_api_with_pybank \
  test_bank_api_with_nexus \
  test_exchange_api \
  test_exchange_api_keys_cherry_picking \
  test_exchange_api_revocation \
  test_exchange_api_overlapping_keys_bug \
  test_exchange_management_api \
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
  $(top_builddir)/src/lib/libtalerauditor.la \
  libtalertesting.la \
  $(top_builddir)/src/lib/libtalerexchange.la \
  $(LIBGCRYPT_LIBS) \
  $(top_builddir)/src/bank-lib/libtalerfakebank.la \
  $(top_builddir)/src/bank-lib/libtalerbank.la \
  $(top_builddir)/src/json/libtalerjson.la \
  $(top_builddir)/src/util/libtalerutil.la \
  -lgnunetcurl \
  -lgnunetutil \
  -ljansson \
  $(XLIB)

test_auditor_api_version_SOURCES = \
  test_auditor_api_version.c
test_auditor_api_version_LDADD = \
  libtalertesting.la \
  $(top_builddir)/src/lib/libtalerauditor.la \
  $(LIBGCRYPT_LIBS) \
  $(top_builddir)/src/util/libtalerutil.la \
  -lgnunetcurl \
  -lgnunetutil \
  -ljansson \
  $(XLIB)

test_bank_api_with_nexus_SOURCES = \
  test_bank_api.c
test_bank_api_with_nexus_LDADD = \
  libtalertesting.la \
  -ltalerexchange \
  -lgnunetutil \
  $(top_builddir)/src/bank-lib/libtalerbank.la \
  $(XLIB)

test_bank_api_with_fakebank_SOURCES = \
  test_bank_api.c
test_bank_api_with_fakebank_LDADD = \
  libtalertesting.la \
  -ltalerexchange \
  -lgnunetutil \
  $(top_builddir)/src/bank-lib/libtalerbank.la \
  $(XLIB)

test_bank_api_with_pybank_SOURCES = \
  test_bank_api.c
test_bank_api_with_pybank_LDADD = \
  libtalertesting.la \
  $(top_builddir)/src/lib/libtalerexchange.la \
  -lgnunetutil \
  $(top_builddir)/src/bank-lib/libtalerbank.la \
  $(XLIB)

test_exchange_api_SOURCES = \
  test_exchange_api.c
test_exchange_api_LDADD = \
  libtalertesting.la \
  $(top_builddir)/src/lib/libtalerexchange.la \
  $(LIBGCRYPT_LIBS) \
  $(top_builddir)/src/bank-lib/libtalerfakebank.la \
  $(top_builddir)/src/bank-lib/libtalerbank.la \
  $(top_builddir)/src/json/libtalerjson.la \
  $(top_builddir)/src/util/libtalerutil.la \
  -lgnunetcurl \
  -lgnunetutil \
  -ljansson \
  $(XLIB)

test_exchange_management_api_SOURCES = \
  test_exchange_management_api.c
test_exchange_management_api_LDADD = \
  libtalertesting.la \
  $(top_builddir)/src/lib/libtalerexchange.la \
  $(top_builddir)/src/util/libtalerutil.la \
  -lgnunetutil \
  $(XLIB)

test_exchange_api_revocation_SOURCES = \
  test_exchange_api_revocation.c
test_exchange_api_revocation_LDADD = \
  libtalertesting.la \
  $(top_builddir)/src/lib/libtalerexchange.la \
  $(LIBGCRYPT_LIBS) \
  $(top_builddir)/src/bank-lib/libtalerfakebank.la \
  $(top_builddir)/src/bank-lib/libtalerbank.la \
  $(top_builddir)/src/json/libtalerjson.la \
  $(top_builddir)/src/util/libtalerutil.la \
  -lgnunetcurl \
  -lgnunetutil \
  -ljansson \
  $(XLIB)

test_exchange_api_keys_cherry_picking_SOURCES = \
  test_exchange_api_keys_cherry_picking.c
test_exchange_api_keys_cherry_picking_LDADD = \
  libtalertesting.la \
  $(top_builddir)/src/lib/libtalerexchange.la \
  $(LIBGCRYPT_LIBS) \
  $(top_builddir)/src/json/libtalerjson.la \
  $(top_builddir)/src/util/libtalerutil.la \
  $(top_builddir)/src/bank-lib/libtalerbank.la \
  -lgnunetcurl \
  -lgnunetutil \
  -ljansson \
  $(XLIB)

test_exchange_api_overlapping_keys_bug_SOURCES = \
  test_exchange_api_overlapping_keys_bug.c
test_exchange_api_overlapping_keys_bug_LDADD = \
  libtalertesting.la \
  $(top_builddir)/src/lib/libtalerexchange.la \
  $(LIBGCRYPT_LIBS) \
  $(top_builddir)/src/json/libtalerjson.la \
  $(top_builddir)/src/util/libtalerutil.la \
  $(top_builddir)/src/bank-lib/libtalerbank.la \
  -lgnunetcurl \
  -lgnunetutil \
  -ljansson \
  $(XLIB)

test_taler_exchange_aggregator_postgres_SOURCES = \
  test_taler_exchange_aggregator.c
test_taler_exchange_aggregator_postgres_LDADD = \
  $(LIBGCRYPT_LIBS) \
  $(top_builddir)/src/exchangedb/libtalerexchangedb.la \
  $(top_builddir)/src/bank-lib/libtalerfakebank.la \
  $(top_builddir)/src/json/libtalerjson.la \
  $(top_builddir)/src/util/libtalerutil.la \
  libtalertesting.la \
  -lmicrohttpd \
  -lgnunetutil \
  -lgnunetjson \
  -ljansson \
  -lpthread \
  $(XLIB)

test_taler_exchange_wirewatch_postgres_SOURCES = \
  test_taler_exchange_wirewatch.c
test_taler_exchange_wirewatch_postgres_LDADD = \
  $(LIBGCRYPT_LIBS) \
  $(top_builddir)/src/exchangedb/libtalerexchangedb.la \
  $(top_builddir)/src/bank-lib/libtalerfakebank.la \
  $(top_builddir)/src/json/libtalerjson.la \
  $(top_builddir)/src/util/libtalerutil.la \
  libtalertesting.la \
  -lmicrohttpd \
  -lgnunetutil \
  -lgnunetjson \
  -lgnunetpq \
  -ljansson \
  -lpthread \
  $(XLIB)

test_exchange_api_twisted_SOURCES = \
  test_exchange_api_twisted.c
test_exchange_api_twisted_LDADD = \
  $(LIBGCRYPT_LIBS) \
  libtalertesting.la \
  libtalertwistertesting.la \
  $(top_builddir)/src/lib/libtalerexchange.la \
  $(top_builddir)/src/bank-lib/libtalerfakebank.la \
  $(top_builddir)/src/bank-lib/libtalerbank.la \
  $(top_builddir)/src/json/libtalerjson.la \
  $(top_builddir)/src/util/libtalerutil.la \
  -lgnunetjson \
  -lgnunetcurl \
  -lgnunetutil \
  -ljansson \
  $(XLIB)

test_bank_api_with_fakebank_twisted_SOURCES = \
  test_bank_api_twisted.c
test_bank_api_with_fakebank_twisted_LDADD = \
  libtalertesting.la \
  $(top_builddir)/src/bank-lib/libtalerbank.la \
  $(top_builddir)/src/bank-lib/libtalerfakebank.la \
  $(top_builddir)/src/lib/libtalerexchange.la \
  $(top_builddir)/src/json/libtalerjson.la \
  libtalertwistertesting.la \
  -lgnunetjson \
  -lgnunetcurl \
  -lgnunetutil \
  -ljansson \
  $(XLIB)

test_bank_api_with_pybank_twisted_SOURCES = \
  test_bank_api_twisted.c
test_bank_api_with_pybank_twisted_LDADD = \
  libtalertesting.la \
  $(top_builddir)/src/bank-lib/libtalerbank.la \
  $(top_builddir)/src/bank-lib/libtalerfakebank.la \
  $(top_builddir)/src/lib/libtalerexchange.la \
  $(top_builddir)/src/json/libtalerjson.la \
  libtalertwistertesting.la \
  -lgnunetjson \
  -lgnunetcurl \
  -lgnunetutil \
  -ljansson  \
  $(XLIB)


# Distribution

EXTRA_DIST = \
  test_bank_api_fakebank.conf \
  test_bank_api_fakebank_twisted.conf \
  test_bank_api_pybank.conf \
  test_bank_api_pybank_twisted.conf \
  test_auditor_api.conf \
  test_auditor_api_expire_reserve_now.conf \
  test_taler_exchange_httpd_home/.config/taler/account-1.json \
  test_taler_exchange_httpd_home/.local/share/taler/exchange/offline-keys/master.priv \
  test_taler_exchange_httpd_home/.local/share/taler/exchange/wirefees/x-taler-bank.fee \
  test_exchange_api_home/.config/taler/account-2.json \
  test_exchange_api_home/.local/share/taler/exchange/offline-keys/master.priv \
  test_exchange_api_home/.local/share/taler/exchange/wirefees/x-taler-bank.fee \
  test_exchange_api_keys_cherry_picking_home/.config/taler/x-taler-bank.json \
  test_exchange_api_keys_cherry_picking_home/.local/share/taler/exchange/offline-keys/master.priv \
  test_exchange_api_keys_cherry_picking_home/.local/share/taler/exchange/wirefees/x-taler-bank.fee \
  test_exchange_api.conf \
  test_exchange_api_twisted.conf \
  test_exchange_api_keys_cherry_picking.conf \
  test_exchange_api_expire_reserve_now.conf \
  test-taler-exchange-aggregator-postgres.conf \
  test-taler-exchange-wirewatch-postgres.conf
