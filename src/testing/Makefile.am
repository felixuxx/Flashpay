# This Makefile.am is in the public domain

AM_CPPFLAGS = \
  -I$(top_srcdir)/src/include \
  $(LIBGCRYPT_CFLAGS) \
  $(POSTGRESQL_CPPFLAGS)

if USE_COVERAGE
  AM_CFLAGS = --coverage -O0
  XLIB = -lgcov
endif

clean-local:
	rm -rf report*

bin_SCRIPTS = \
  taler-unified-setup.sh

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
  testing_api_cmd_age_withdraw.c \
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
  testing_api_cmd_batch_deposit.c \
  testing_api_cmd_batch_withdraw.c \
  testing_api_cmd_check_aml_decision.c \
  testing_api_cmd_check_aml_decisions.c \
  testing_api_cmd_coin_history.c \
  testing_api_cmd_common.c \
  testing_api_cmd_contract_get.c \
  testing_api_cmd_deposit.c \
  testing_api_cmd_deposits_get.c \
  testing_api_cmd_exec_aggregator.c \
  testing_api_cmd_exec_auditor-offline.c \
  testing_api_cmd_exec_closer.c \
  testing_api_cmd_exec_expire.c \
  testing_api_cmd_exec_router.c \
  testing_api_cmd_exec_transfer.c \
  testing_api_cmd_exec_wget.c \
  testing_api_cmd_exec_wirewatch.c \
  testing_api_cmd_get_auditor.c \
  testing_api_cmd_get_exchange.c \
  testing_api_cmd_insert_deposit.c \
  testing_api_cmd_kyc_check_get.c \
  testing_api_cmd_kyc_proof.c \
  testing_api_cmd_kyc_wallet_get.c \
  testing_api_cmd_oauth.c \
  testing_api_cmd_offline_sign_global_fees.c \
  testing_api_cmd_offline_sign_wire_fees.c \
  testing_api_cmd_offline_sign_keys.c \
  testing_api_cmd_offline_sign_extensions.c \
  testing_api_cmd_purse_create_deposit.c \
  testing_api_cmd_purse_delete.c \
  testing_api_cmd_purse_deposit.c \
  testing_api_cmd_purse_get.c \
  testing_api_cmd_purse_merge.c \
  testing_api_cmd_recoup.c \
  testing_api_cmd_recoup_refresh.c \
  testing_api_cmd_refund.c \
  testing_api_cmd_refresh.c \
  testing_api_cmd_reserve_attest.c \
  testing_api_cmd_reserve_close.c \
  testing_api_cmd_reserve_get.c \
  testing_api_cmd_reserve_get_attestable.c \
  testing_api_cmd_reserve_history.c \
  testing_api_cmd_reserve_open.c \
  testing_api_cmd_reserve_purse.c \
  testing_api_cmd_revoke.c \
  testing_api_cmd_revoke_denom_key.c \
  testing_api_cmd_revoke_sign_key.c \
  testing_api_cmd_run_fakebank.c \
  testing_api_cmd_set_officer.c \
  testing_api_cmd_set_wire_fee.c \
  testing_api_cmd_signal.c \
  testing_api_cmd_sleep.c \
  testing_api_cmd_stat.c \
  testing_api_cmd_system_start.c \
  testing_api_cmd_take_aml_decision.c \
  testing_api_cmd_transfer_get.c \
  testing_api_cmd_wait.c \
  testing_api_cmd_wire_add.c \
  testing_api_cmd_wire_del.c \
  testing_api_cmd_withdraw.c \
  testing_api_loop.c \
  testing_api_misc.c \
  testing_api_traits.c


libtalertesting_la_LIBADD = \
  $(top_builddir)/src/lib/libtalerauditor.la \
  $(top_builddir)/src/lib/libtalerexchange.la \
  $(top_builddir)/src/exchangedb/libtalerexchangedb.la \
  $(top_builddir)/src/json/libtalerjson.la \
  $(top_builddir)/src/mhd/libtalermhd.la \
  $(top_builddir)/src/util/libtalerutil.la \
  $(top_builddir)/src/extensions/libtalerextensions.la \
  $(top_builddir)/src/bank-lib/libtalerbank.la \
  $(top_builddir)/src/bank-lib/libtalerfakebank.la \
  -lgnunetcurl \
  -lgnunetjson \
  -lgnunetutil \
  -ljansson \
  -lmicrohttpd \
  $(XLIB)


# Test cases

AM_TESTS_ENVIRONMENT=export TALER_PREFIX=$${TALER_PREFIX:-@libdir@};export PATH=$${TALER_PREFIX:-@prefix@}/bin:$$PATH;


.NOTPARALLEL:
check_PROGRAMS = \
  test_auditor_api_cs \
  test_auditor_api_rsa \
  test_auditor_api_version \
  test_bank_api_with_fakebank \
  test_bank_api_with_nexus \
  test_exchange_api_cs \
  test_exchange_api_rsa \
  test_exchange_api_age_restriction_cs \
  test_exchange_api_age_restriction_rsa \
  test_exchange_api_keys_cherry_picking_cs \
  test_exchange_api_keys_cherry_picking_rsa \
  test_exchange_api_revocation_cs \
  test_exchange_api_revocation_rsa \
  test_exchange_api_overlapping_keys_bug_cs \
  test_exchange_api_overlapping_keys_bug_rsa \
  test_exchange_management_api_cs \
  test_exchange_management_api_rsa \
  test_kyc_api \
  test_taler_exchange_aggregator-postgres \
  test_taler_exchange_wirewatch-postgres \
  test_exchange_p2p_cs \
  test_exchange_p2p_rsa
if HAVE_TWISTER
  check_PROGRAMS += \
    test_exchange_api_twisted_cs \
    test_exchange_api_twisted_rsa \
    test_bank_api_with_fakebank_twisted
endif



TESTS = \
  $(check_PROGRAMS)

test_auditor_api_cs_SOURCES = \
  test_auditor_api.c
test_auditor_api_cs_LDADD = \
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

test_auditor_api_rsa_SOURCES = \
  test_auditor_api.c
test_auditor_api_rsa_LDADD = \
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
  $(top_builddir)/src/lib/libtalerexchange.la \
  -lgnunetutil \
  $(top_builddir)/src/bank-lib/libtalerbank.la \
  $(XLIB)

test_bank_api_with_fakebank_SOURCES = \
  test_bank_api.c
test_bank_api_with_fakebank_LDADD = \
  libtalertesting.la \
  $(top_builddir)/src/lib/libtalerexchange.la \
  -lgnunetutil \
  $(top_builddir)/src/bank-lib/libtalerbank.la \
  $(XLIB)

test_exchange_api_cs_SOURCES = \
  test_exchange_api.c
test_exchange_api_cs_LDADD = \
  libtalertesting.la \
  $(top_builddir)/src/lib/libtalerexchange.la \
  $(LIBGCRYPT_LIBS) \
  $(top_builddir)/src/bank-lib/libtalerfakebank.la \
  $(top_builddir)/src/bank-lib/libtalerbank.la \
  $(top_builddir)/src/json/libtalerjson.la \
  $(top_builddir)/src/util/libtalerutil.la \
  $(top_builddir)/src/extensions/libtalerextensions.la \
  -lgnunetcurl \
  -lgnunetutil \
  -ljansson \
  $(XLIB)

test_exchange_api_rsa_SOURCES = \
  test_exchange_api.c
test_exchange_api_rsa_LDADD = \
  libtalertesting.la \
  $(top_builddir)/src/lib/libtalerexchange.la \
  $(LIBGCRYPT_LIBS) \
  $(top_builddir)/src/bank-lib/libtalerfakebank.la \
  $(top_builddir)/src/bank-lib/libtalerbank.la \
  $(top_builddir)/src/json/libtalerjson.la \
  $(top_builddir)/src/util/libtalerutil.la \
  $(top_builddir)/src/extensions/libtalerextensions.la \
  -lgnunetcurl \
  -lgnunetutil \
  -ljansson \
  $(XLIB)

test_exchange_api_age_restriction_cs_SOURCES = \
  test_exchange_api_age_restriction.c
test_exchange_api_age_restriction_cs_LDADD = \
  libtalertesting.la \
  $(top_builddir)/src/lib/libtalerexchange.la \
  $(LIBGCRYPT_LIBS) \
  $(top_builddir)/src/bank-lib/libtalerfakebank.la \
  $(top_builddir)/src/bank-lib/libtalerbank.la \
  $(top_builddir)/src/json/libtalerjson.la \
  $(top_builddir)/src/util/libtalerutil.la \
  $(top_builddir)/src/extensions/libtalerextensions.la \
  -lgnunetcurl \
  -lgnunetutil \
  -ljansson \
  $(XLIB)

test_exchange_api_age_restriction_rsa_SOURCES = \
  test_exchange_api_age_restriction.c
test_exchange_api_age_restriction_rsa_LDADD = \
  libtalertesting.la \
  $(top_builddir)/src/lib/libtalerexchange.la \
  $(LIBGCRYPT_LIBS) \
  $(top_builddir)/src/bank-lib/libtalerfakebank.la \
  $(top_builddir)/src/bank-lib/libtalerbank.la \
  $(top_builddir)/src/json/libtalerjson.la \
  $(top_builddir)/src/util/libtalerutil.la \
  $(top_builddir)/src/extensions/libtalerextensions.la \
  -lgnunetcurl \
  -lgnunetutil \
  -ljansson \
  $(XLIB)

test_exchange_p2p_cs_SOURCES = \
  test_exchange_p2p.c
test_exchange_p2p_cs_LDADD = \
  libtalertesting.la \
  $(top_builddir)/src/lib/libtalerexchange.la \
  $(LIBGCRYPT_LIBS) \
  $(top_builddir)/src/bank-lib/libtalerfakebank.la \
  $(top_builddir)/src/bank-lib/libtalerbank.la \
  $(top_builddir)/src/json/libtalerjson.la \
  $(top_builddir)/src/util/libtalerutil.la \
  $(top_builddir)/src/extensions/libtalerextensions.la \
  -lgnunetcurl \
  -lgnunetutil \
  -ljansson \
  $(XLIB)

test_exchange_p2p_rsa_SOURCES = \
  test_exchange_p2p.c
test_exchange_p2p_rsa_LDADD = \
  libtalertesting.la \
  $(top_builddir)/src/lib/libtalerexchange.la \
  $(LIBGCRYPT_LIBS) \
  $(top_builddir)/src/bank-lib/libtalerfakebank.la \
  $(top_builddir)/src/bank-lib/libtalerbank.la \
  $(top_builddir)/src/json/libtalerjson.la \
  $(top_builddir)/src/util/libtalerutil.la \
  $(top_builddir)/src/extensions/libtalerextensions.la \
  -lgnunetcurl \
  -lgnunetutil \
  -ljansson \
  $(XLIB)


test_exchange_api_keys_cherry_picking_cs_SOURCES = \
  test_exchange_api_keys_cherry_picking.c
test_exchange_api_keys_cherry_picking_cs_LDADD = \
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

test_exchange_api_keys_cherry_picking_rsa_SOURCES = \
  test_exchange_api_keys_cherry_picking.c
test_exchange_api_keys_cherry_picking_rsa_LDADD = \
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

test_exchange_api_revocation_cs_SOURCES = \
  test_exchange_api_revocation.c
test_exchange_api_revocation_cs_LDADD = \
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

test_exchange_api_revocation_rsa_SOURCES = \
  test_exchange_api_revocation.c
test_exchange_api_revocation_rsa_LDADD = \
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


test_exchange_api_overlapping_keys_bug_cs_SOURCES = \
  test_exchange_api_overlapping_keys_bug.c
test_exchange_api_overlapping_keys_bug_cs_LDADD = \
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

test_exchange_api_overlapping_keys_bug_rsa_SOURCES = \
  test_exchange_api_overlapping_keys_bug.c
test_exchange_api_overlapping_keys_bug_rsa_LDADD = \
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

test_exchange_management_api_cs_SOURCES = \
  test_exchange_management_api.c
test_exchange_management_api_cs_LDADD = \
  libtalertesting.la \
  $(top_builddir)/src/lib/libtalerexchange.la \
  $(top_builddir)/src/util/libtalerutil.la \
  -lgnunetutil \
  $(XLIB)

test_exchange_management_api_rsa_SOURCES = \
  test_exchange_management_api.c
test_exchange_management_api_rsa_LDADD = \
  libtalertesting.la \
  $(top_builddir)/src/lib/libtalerexchange.la \
  $(top_builddir)/src/util/libtalerutil.la \
  -lgnunetutil \
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

test_exchange_api_twisted_cs_SOURCES = \
  test_exchange_api_twisted.c
test_exchange_api_twisted_cs_LDADD = \
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

test_exchange_api_twisted_rsa_SOURCES = \
  test_exchange_api_twisted.c
test_exchange_api_twisted_rsa_LDADD = \
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

test_kyc_api_SOURCES = \
  test_kyc_api.c
test_kyc_api_LDADD = \
  libtalertesting.la \
  $(top_builddir)/src/lib/libtalerauditor.la \
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

# Distribution

EXTRA_DIST = \
  $(bin_SCRIPTS) \
  valgrind.h \
  coins-cs.conf \
  coins-rsa.conf \
  test_auditor_api-cs.conf \
  test_auditor_api-rsa.conf \
  test_auditor_api_expire_reserve_now-cs.conf \
  test_auditor_api_expire_reserve_now-rsa.conf \
  test_bank_api.conf \
  test_bank_api_fakebank.conf \
  test_bank_api_fakebank_twisted.conf \
  test_bank_api_nexus.conf \
  test_exchange_api_home/taler/auditor/offline-keys/auditor.priv \
  test_exchange_api_home/.local/share/taler/exchange-offline/master.priv \
  test_exchange_api.conf \
  test_exchange_api-cs.conf \
  test_exchange_api-rsa.conf \
  test_exchange_api_age_restriction.conf \
  test_exchange_api_age_restriction-cs.conf \
  test_exchange_api_age_restriction-rsa.conf \
  test_exchange_api-twisted.conf \
  test_exchange_api_twisted-cs.conf \
  test_exchange_api_twisted-rsa.conf \
  test_exchange_api_keys_cherry_picking.conf \
  test_exchange_api_keys_cherry_picking-cs.conf \
  test_exchange_api_keys_cherry_picking-rsa.conf \
  test_exchange_api_expire_reserve_now-cs.conf \
  test_exchange_api_expire_reserve_now-rsa.conf \
  test-taler-exchange-aggregator-postgres.conf \
  test-taler-exchange-wirewatch-postgres.conf \
  test_kyc_api.conf
