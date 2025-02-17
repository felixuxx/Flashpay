# This Makefile.am is in the public domain
AM_CPPFLAGS = \
 -I$(top_srcdir)/src/include \
 $(LIBGCRYPT_CFLAGS) \
 $(POSTGRESQL_CPPFLAGS)

if USE_COVERAGE
  AM_CFLAGS = --coverage -O0
  XLIB = -lgcov
endif

pkgcfgadir = $(prefix)/share/taler-auditor/config.d/
pkgcfgedir = $(prefix)/share/taler-exchange/config.d/

# Auditor also needs to access the exchange config, so we install
# the exchange configuration for it here as well!
pkgcfga_DATA = \
  exchange.conf

pkgcfge_DATA = \
  exchange.conf

# Programs
bin_SCRIPTS = \
  taler-exchange-kyc-aml-pep-trigger.sh

bin_PROGRAMS = \
  taler-exchange-aggregator \
  taler-exchange-closer \
  taler-exchange-drain \
  taler-exchange-expire \
  taler-exchange-httpd \
  taler-exchange-router \
  taler-exchange-transfer \
  taler-exchange-wirewatch

taler_exchange_aggregator_SOURCES = \
  taler-exchange-aggregator.c
taler_exchange_aggregator_LDADD = \
  $(LIBGCRYPT_LIBS) \
  $(top_builddir)/src/kyclogic/libtalerkyclogic.la \
  $(top_builddir)/src/json/libtalerjson.la \
  $(top_builddir)/src/util/libtalerutil.la \
  $(top_builddir)/src/bank-lib/libtalerbank.la \
  $(top_builddir)/src/exchangedb/libtalerexchangedb.la \
  -ljansson \
  -lgnunetcurl \
  -lgnunetutil \
  $(XLIB)


taler_exchange_closer_SOURCES = \
  taler-exchange-closer.c
taler_exchange_closer_LDADD = \
  $(LIBGCRYPT_LIBS) \
  $(top_builddir)/src/json/libtalerjson.la \
  $(top_builddir)/src/util/libtalerutil.la \
  $(top_builddir)/src/bank-lib/libtalerbank.la \
  $(top_builddir)/src/exchangedb/libtalerexchangedb.la \
  -ljansson \
  -lgnunetcurl \
  -lgnunetutil \
  $(XLIB)

taler_exchange_drain_SOURCES = \
  taler-exchange-drain.c
taler_exchange_drain_LDADD = \
  $(LIBGCRYPT_LIBS) \
  $(top_builddir)/src/json/libtalerjson.la \
  $(top_builddir)/src/util/libtalerutil.la \
  $(top_builddir)/src/bank-lib/libtalerbank.la \
  $(top_builddir)/src/exchangedb/libtalerexchangedb.la \
  -ljansson \
  -lgnunetcurl \
  -lgnunetutil \
  $(XLIB)

taler_exchange_expire_SOURCES = \
  taler-exchange-expire.c
taler_exchange_expire_LDADD = \
  $(LIBGCRYPT_LIBS) \
  $(top_builddir)/src/json/libtalerjson.la \
  $(top_builddir)/src/util/libtalerutil.la \
  $(top_builddir)/src/bank-lib/libtalerbank.la \
  $(top_builddir)/src/exchangedb/libtalerexchangedb.la \
  -ljansson \
  -lgnunetcurl \
  -lgnunetutil \
  $(XLIB)

taler_exchange_router_SOURCES = \
  taler-exchange-router.c
taler_exchange_router_LDADD = \
  $(LIBGCRYPT_LIBS) \
  $(top_builddir)/src/json/libtalerjson.la \
  $(top_builddir)/src/util/libtalerutil.la \
  $(top_builddir)/src/bank-lib/libtalerbank.la \
  $(top_builddir)/src/exchangedb/libtalerexchangedb.la \
  -ljansson \
  -lgnunetcurl \
  -lgnunetutil \
  $(XLIB)

taler_exchange_transfer_SOURCES = \
  taler-exchange-transfer.c
taler_exchange_transfer_LDADD = \
  $(LIBGCRYPT_LIBS) \
  $(top_builddir)/src/json/libtalerjson.la \
  $(top_builddir)/src/util/libtalerutil.la \
  $(top_builddir)/src/bank-lib/libtalerbank.la \
  $(top_builddir)/src/exchangedb/libtalerexchangedb.la \
  -ljansson \
  -lgnunetcurl \
  -lgnunetutil \
  $(XLIB)

taler_exchange_wirewatch_SOURCES = \
  taler-exchange-wirewatch.c
taler_exchange_wirewatch_LDADD = \
  $(LIBGCRYPT_LIBS) \
  $(top_builddir)/src/json/libtalerjson.la \
  $(top_builddir)/src/util/libtalerutil.la \
  $(top_builddir)/src/bank-lib/libtalerbank.la \
  $(top_builddir)/src/exchangedb/libtalerexchangedb.la \
  -ljansson \
  -lgnunetcurl \
  -lgnunetutil \
  $(XLIB)


taler_exchange_httpd_SOURCES = \
  taler-exchange-httpd.c taler-exchange-httpd.h \
  taler-exchange-httpd_age-withdraw_reveal.c taler-exchange-httpd_age-withdraw_reveal.h \
  taler-exchange-httpd_aml-attributes-get.c taler-exchange-httpd_aml-attributes-get.h \
  taler-exchange-httpd_aml-decision.c taler-exchange-httpd_aml-decision.h \
  taler-exchange-httpd_aml-decisions-get.c \
  taler-exchange-httpd_aml-statistics-get.c taler-exchange-httpd_aml-statistics-get.h \
  taler-exchange-httpd_aml-measures-get.c taler-exchange-httpd_aml-measures-get.h \
  taler-exchange-httpd_auditors.c taler-exchange-httpd_auditors.h \
  taler-exchange-httpd_batch-deposit.c taler-exchange-httpd_batch-deposit.h \
  taler-exchange-httpd_coins_get.c taler-exchange-httpd_coins_get.h \
  taler-exchange-httpd_common_deposit.c taler-exchange-httpd_common_deposit.h \
  taler-exchange-httpd_common_kyc.c taler-exchange-httpd_common_kyc.h \
  taler-exchange-httpd_config.c taler-exchange-httpd_config.h \
  taler-exchange-httpd_contract.c taler-exchange-httpd_contract.h \
  taler-exchange-httpd_csr.c taler-exchange-httpd_csr.h \
  taler-exchange-httpd_db.c taler-exchange-httpd_db.h \
  taler-exchange-httpd_deposits_get.c taler-exchange-httpd_deposits_get.h \
  taler-exchange-httpd_extensions.c taler-exchange-httpd_extensions.h \
  taler-exchange-httpd_keys.c taler-exchange-httpd_keys.h \
  taler-exchange-httpd_kyc-check.c taler-exchange-httpd_kyc-check.h \
  taler-exchange-httpd_kyc-info.c taler-exchange-httpd_kyc-info.h \
  taler-exchange-httpd_kyc-proof.c taler-exchange-httpd_kyc-proof.h \
  taler-exchange-httpd_kyc-start.c taler-exchange-httpd_kyc-start.h \
  taler-exchange-httpd_kyc-upload.c taler-exchange-httpd_kyc-upload.h \
  taler-exchange-httpd_kyc-wallet.c taler-exchange-httpd_kyc-wallet.h \
  taler-exchange-httpd_kyc-webhook.c taler-exchange-httpd_kyc-webhook.h \
  taler-exchange-httpd_legitimization-measures-get.c taler-exchange-httpd_legitimization-measures-get.h \
  taler-exchange-httpd_link.c taler-exchange-httpd_link.h \
  taler-exchange-httpd_management.h \
  taler-exchange-httpd_management_aml-officers.c \
  taler-exchange-httpd_management_auditors.c \
  taler-exchange-httpd_management_auditors_AP_disable.c \
  taler-exchange-httpd_management_denominations_HDP_revoke.c \
  taler-exchange-httpd_management_drain.c \
  taler-exchange-httpd_management_extensions.c \
  taler-exchange-httpd_management_global_fees.c \
  taler-exchange-httpd_management_partners.c \
  taler-exchange-httpd_management_post_keys.c \
  taler-exchange-httpd_management_signkey_EP_revoke.c \
  taler-exchange-httpd_management_wire_enable.c \
  taler-exchange-httpd_management_wire_disable.c \
  taler-exchange-httpd_management_wire_fees.c \
  taler-exchange-httpd_melt.c taler-exchange-httpd_melt.h \
  taler-exchange-httpd_metrics.c taler-exchange-httpd_metrics.h \
  taler-exchange-httpd_mhd.c taler-exchange-httpd_mhd.h \
  taler-exchange-httpd_purses_create.c taler-exchange-httpd_purses_create.h \
  taler-exchange-httpd_purses_deposit.c taler-exchange-httpd_purses_deposit.h \
  taler-exchange-httpd_purses_delete.c taler-exchange-httpd_purses_delete.h \
  taler-exchange-httpd_purses_get.c taler-exchange-httpd_purses_get.h \
  taler-exchange-httpd_purses_merge.c taler-exchange-httpd_purses_merge.h \
  taler-exchange-httpd_recoup.c taler-exchange-httpd_recoup.h \
  taler-exchange-httpd_recoup-refresh.c taler-exchange-httpd_recoup-refresh.h \
  taler-exchange-httpd_refreshes_reveal.c taler-exchange-httpd_refreshes_reveal.h \
  taler-exchange-httpd_refund.c taler-exchange-httpd_refund.h \
  taler-exchange-httpd_reserves_attest.c taler-exchange-httpd_reserves_attest.h \
  taler-exchange-httpd_reserves_close.c taler-exchange-httpd_reserves_close.h \
  taler-exchange-httpd_reserves_get.c taler-exchange-httpd_reserves_get.h \
  taler-exchange-httpd_reserves_get_attest.c taler-exchange-httpd_reserves_get_attest.h \
  taler-exchange-httpd_reserves_history.c taler-exchange-httpd_reserves_history.h \
  taler-exchange-httpd_reserves_open.c taler-exchange-httpd_reserves_open.h \
  taler-exchange-httpd_reserves_purse.c taler-exchange-httpd_reserves_purse.h \
  taler-exchange-httpd_responses.c taler-exchange-httpd_responses.h \
  taler-exchange-httpd_spa.c taler-exchange-httpd_spa.h \
  taler-exchange-httpd_terms.c taler-exchange-httpd_terms.h \
  taler-exchange-httpd_transfers_get.c taler-exchange-httpd_transfers_get.h \
  taler-exchange-httpd_withdraw.c taler-exchange-httpd_withdraw.h


taler_exchange_httpd_LDADD = \
  $(LIBGCRYPT_LIBS) \
  $(top_builddir)/src/bank-lib/libtalerbank.la \
  $(top_builddir)/src/mhd/libtalermhd.la \
  $(top_builddir)/src/json/libtalerjson.la \
  $(top_builddir)/src/exchangedb/libtalerexchangedb.la \
  $(top_builddir)/src/templating/libtalertemplating.la \
  $(top_builddir)/src/kyclogic/libtalerkyclogic.la \
  $(top_builddir)/src/util/libtalerutil.la \
  $(top_builddir)/src/extensions/libtalerextensions.la \
  -lmicrohttpd \
  -lgnunetcurl \
  -lgnunetjson \
  -lgnunetutil \
  -ljansson \
  -lcurl \
  -lz \
  $(XLIB)

# Testcases

AM_TESTS_ENVIRONMENT=export TALER_PREFIX=$${TALER_PREFIX:-@libdir@};export PATH=$${TALER_PREFIX:-@prefix@}/bin:$$PATH;

check_SCRIPTS = \
  test_taler_exchange_httpd.sh
if HAVE_EXPENSIVE_TESTS
check_SCRIPTS += \
  test_taler_exchange_httpd_afl.sh
endif

TESTS = \
  $(check_SCRIPTS)

# Distribution

EXTRA_DIST = \
  test_taler_exchange_httpd_home/.local/share/taler/exchange/offline-keys/master.priv \
  test_taler_exchange_httpd.conf \
  test_taler_exchange_unix.conf \
  test_taler_exchange_httpd.get \
  test_taler_exchange_httpd.post \
  exchange.conf \
  $(bin_SCRIPTS) \
  $(check_SCRIPTS)
