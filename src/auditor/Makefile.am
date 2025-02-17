# This Makefile.am is in the public domain
AM_CPPFLAGS = -I$(top_srcdir)/src/include

if USE_COVERAGE
  AM_CFLAGS = --coverage -O0
  XLIB = -lgcov
endif

pkgcfgdir = $(prefix)/share/taler-auditor/config.d/

pkgcfg_DATA = \
  auditor.conf

clean-local:
	rm -rf revocation-tmp-*

bin_PROGRAMS = \
  taler-auditor-dbinit \
  taler-auditor-httpd \
  taler-auditor-sync \
  taler-helper-auditor-aggregation \
  taler-helper-auditor-coins \
  taler-helper-auditor-deposits \
  taler-helper-auditor-purses \
  taler-helper-auditor-reserves \
  taler-helper-auditor-transfer \
  taler-helper-auditor-wire-credit \
  taler-helper-auditor-wire-debit

bin_SCRIPTS = \
  taler-helper-auditor-render.py

lib_LTLIBRARIES = \
  libauditorreport.la

libauditorreport_la_SOURCES = \
  report-lib.c report-lib.h
libauditorreport_la_LIBADD = \
  $(top_builddir)/src/util/libtalerutil.la \
  $(top_builddir)/src/pq/libtalerpq.la \
  $(top_builddir)/src/auditordb/libtalerauditordb.la \
  $(top_builddir)/src/exchangedb/libtalerexchangedb.la \
  -lgnunetutil \
  -ljansson \
  $(XLIB)

taler_auditor_dbinit_SOURCES = \
  taler-auditor-dbinit.c
taler_auditor_dbinit_LDADD = \
  $(top_builddir)/src/auditordb/libtalerauditordb.la \
  $(top_builddir)/src/pq/libtalerpq.la \
  $(top_builddir)/src/util/libtalerutil.la \
  -lgnunetutil \
  $(LIBGCRYPT_LIBS) \
  $(XLIB)
taler_auditor_dbinit_CPPFLAGS = \
  -I$(top_srcdir)/src/include \
  -I$(top_srcdir)/src/pq/ \
  $(POSTGRESQL_CPPFLAGS)

taler_helper_auditor_coins_SOURCES = \
  taler-helper-auditor-coins.c
taler_helper_auditor_coins_LDADD = \
  $(LIBGCRYPT_LIBS) \
  $(top_builddir)/src/util/libtalerutil.la \
  $(top_builddir)/src/json/libtalerjson.la \
  $(top_builddir)/src/bank-lib/libtalerbank.la \
  $(top_builddir)/src/exchangedb/libtalerexchangedb.la \
  $(top_builddir)/src/auditordb/libtalerauditordb.la \
  libauditorreport.la \
  -ljansson \
  -lgnunetjson \
  -lgnunetutil \
  $(XLIB)

taler_helper_auditor_aggregation_SOURCES = \
  taler-helper-auditor-aggregation.c
taler_helper_auditor_aggregation_LDADD = \
  $(LIBGCRYPT_LIBS) \
  $(top_builddir)/src/util/libtalerutil.la \
  $(top_builddir)/src/json/libtalerjson.la \
  $(top_builddir)/src/bank-lib/libtalerbank.la \
  $(top_builddir)/src/exchangedb/libtalerexchangedb.la \
  $(top_builddir)/src/auditordb/libtalerauditordb.la \
  libauditorreport.la \
  -ljansson \
  -lgnunetjson \
  -lgnunetutil \
  $(XLIB)

taler_helper_auditor_deposits_SOURCES = \
  taler-helper-auditor-deposits.c
taler_helper_auditor_deposits_LDADD = \
  $(LIBGCRYPT_LIBS) \
  $(top_builddir)/src/util/libtalerutil.la \
  $(top_builddir)/src/json/libtalerjson.la \
  $(top_builddir)/src/bank-lib/libtalerbank.la \
  $(top_builddir)/src/exchangedb/libtalerexchangedb.la \
  $(top_builddir)/src/auditordb/libtalerauditordb.la \
  libauditorreport.la \
  -ljansson \
  -lgnunetjson \
  -lgnunetutil \
  $(XLIB)

taler_helper_auditor_purses_SOURCES = \
  taler-helper-auditor-purses.c
taler_helper_auditor_purses_LDADD = \
  $(LIBGCRYPT_LIBS) \
  $(top_builddir)/src/util/libtalerutil.la \
  $(top_builddir)/src/json/libtalerjson.la \
  $(top_builddir)/src/bank-lib/libtalerbank.la \
  $(top_builddir)/src/exchangedb/libtalerexchangedb.la \
  $(top_builddir)/src/auditordb/libtalerauditordb.la \
  libauditorreport.la \
  -ljansson \
  -lgnunetjson \
  -lgnunetutil \
  $(XLIB)

taler_helper_auditor_reserves_SOURCES = \
  taler-helper-auditor-reserves.c
taler_helper_auditor_reserves_LDADD = \
  $(LIBGCRYPT_LIBS) \
  $(top_builddir)/src/util/libtalerutil.la \
  $(top_builddir)/src/json/libtalerjson.la \
  $(top_builddir)/src/bank-lib/libtalerbank.la \
  $(top_builddir)/src/exchangedb/libtalerexchangedb.la \
  $(top_builddir)/src/auditordb/libtalerauditordb.la \
  libauditorreport.la \
  -ljansson \
  -lgnunetjson \
  -lgnunetutil \
  $(XLIB)

taler_helper_auditor_transfer_SOURCES = \
  taler-helper-auditor-transfer.c
taler_helper_auditor_transfer_LDADD = \
  $(LIBGCRYPT_LIBS) \
  $(top_builddir)/src/util/libtalerutil.la \
  $(top_builddir)/src/json/libtalerjson.la \
  $(top_builddir)/src/exchangedb/libtalerexchangedb.la \
  $(top_builddir)/src/auditordb/libtalerauditordb.la \
  libauditorreport.la \
  -ljansson \
  -lgnunetjson \
  -lgnunetutil \
  $(XLIB)

taler_helper_auditor_wire_credit_SOURCES = \
  taler-helper-auditor-wire-credit.c
taler_helper_auditor_wire_credit_LDADD = \
  $(LIBGCRYPT_LIBS) \
  $(top_builddir)/src/json/libtalerjson.la \
  $(top_builddir)/src/util/libtalerutil.la \
  $(top_builddir)/src/bank-lib/libtalerbank.la \
  $(top_builddir)/src/exchangedb/libtalerexchangedb.la \
  $(top_builddir)/src/auditordb/libtalerauditordb.la \
  libauditorreport.la \
  -ljansson \
  -lgnunetjson \
  -lgnunetcurl \
  -lgnunetutil \
  $(XLIB)

taler_helper_auditor_wire_debit_SOURCES = \
  taler-helper-auditor-wire-debit.c
taler_helper_auditor_wire_debit_LDADD = \
  $(LIBGCRYPT_LIBS) \
  $(top_builddir)/src/json/libtalerjson.la \
  $(top_builddir)/src/util/libtalerutil.la \
  $(top_builddir)/src/bank-lib/libtalerbank.la \
  $(top_builddir)/src/exchangedb/libtalerexchangedb.la \
  $(top_builddir)/src/auditordb/libtalerauditordb.la \
  libauditorreport.la \
  -ljansson \
  -lgnunetjson \
  -lgnunetcurl \
  -lgnunetutil \
  $(XLIB)

# MARK: CRUD

taler_auditor_httpd_SOURCES = \
  taler-auditor-httpd.c taler-auditor-httpd.h \
  taler-auditor-httpd_spa.c taler-auditor-httpd_spa.h \
  taler-auditor-httpd_deposit-confirmation.c taler-auditor-httpd_deposit-confirmation.h \
  taler-auditor-httpd_deposit-confirmation-get.c taler-auditor-httpd_deposit-confirmation-get.h \
  taler-auditor-httpd_amount-arithmetic-inconsistency-get.c taler-auditor-httpd_amount-arithmetic-inconsistency-get.h \
  taler-auditor-httpd_coin-inconsistency-get.c taler-auditor-httpd_coin-inconsistency-get.h \
  taler-auditor-httpd_row-inconsistency-get.c taler-auditor-httpd_row-inconsistency-get.h \
  taler-auditor-httpd_emergency-get.c taler-auditor-httpd_emergency-get.h \
  taler-auditor-httpd_emergency-by-count-get.c taler-auditor-httpd_emergency-by-count-get.h \
  taler-auditor-httpd_denomination-key-validity-withdraw-inconsistency-get.c taler-auditor-httpd_denomination-key-validity-withdraw-inconsistency-get.h \
  taler-auditor-httpd_purse-not-closed-inconsistencies-get.c taler-auditor-httpd_purse-not-closed-inconsistencies-get.h \
  taler-auditor-httpd_reserve-balance-insufficient-inconsistency-get.c taler-auditor-httpd_reserve-balance-insufficient-inconsistency-get.h \
  taler-auditor-httpd_patch_generic_suppressed.c taler-auditor-httpd_patch_generic_suppressed.h \
  taler-auditor-httpd_delete_generic.c taler-auditor-httpd_delete_generic.h \
  taler-auditor-httpd_bad-sig-losses-get.c taler-auditor-httpd_bad-sig-losses-get.h \
  taler-auditor-httpd_closure-lags-get.c taler-auditor-httpd_closure-lags-get.h \
  taler-auditor-httpd_progress-get.c taler-auditor-httpd_progress-get.h \
  taler-auditor-httpd_refreshes-hanging-get.c taler-auditor-httpd_refreshes-hanging-get.h \
  taler-auditor-httpd_reserve-in-inconsistency-get.c taler-auditor-httpd_reserve-in-inconsistency-get.h \
  taler-auditor-httpd_reserve-not-closed-inconsistency-get.c taler-auditor-httpd_reserve-not-closed-inconsistency-get.h \
  taler-auditor-httpd_denominations-without-sigs-get.c taler-auditor-httpd_denominations-without-sigs-get.h \
  taler-auditor-httpd_misattribution-in-inconsistency-get.c taler-auditor-httpd_misattribution-in-inconsistency-get.h \
  taler-auditor-httpd_reserves-get.c taler-auditor-httpd_reserves-get.h \
  taler-auditor-httpd_purses-get.c taler-auditor-httpd_purses-get.h \
  taler-auditor-httpd_historic-denomination-revenue-get.c taler-auditor-httpd_historic-denomination-revenue-get.h \
  taler-auditor-httpd_denomination-pending-get.c taler-auditor-httpd_denomination-pending-get.h \
  taler-auditor-httpd_historic-reserve-summary-get.c taler-auditor-httpd_historic-reserve-summary-get.h \
  taler-auditor-httpd_wire-format-inconsistency-get.c taler-auditor-httpd_wire-format-inconsistency-get.h \
  taler-auditor-httpd_wire-out-inconsistency-get.c taler-auditor-httpd_wire-out-inconsistency-get.h \
  taler-auditor-httpd_reserve-balance-summary-wrong-inconsistency-get.c taler-auditor-httpd_reserve-balance-summary-wrong-inconsistency-get.h \
  taler-auditor-httpd_row-minor-inconsistencies-get.c taler-auditor-httpd_row-minor-inconsistencies-get.h \
  taler-auditor-httpd_fee-time-inconsistency-get.c taler-auditor-httpd_fee-time-inconsistency-get.h \
  taler-auditor-httpd_balances-get.c taler-auditor-httpd_balances-get.h \
  taler-auditor-httpd_mhd.c taler-auditor-httpd_mhd.h
taler_auditor_httpd_LDADD = \
  $(LIBGCRYPT_LIBS) \
  $(top_builddir)/src/mhd/libtalermhd.la \
  $(top_builddir)/src/util/libtalerutil.la \
  $(top_builddir)/src/json/libtalerjson.la \
  $(top_builddir)/src/auditordb/libtalerauditordb.la \
  $(top_builddir)/src/exchangedb/libtalerexchangedb.la \
  -lmicrohttpd \
  -ljansson \
  -lgnunetjson \
  -lgnunetutil \
  -lz \
  $(XLIB)

taler_auditor_sync_SOURCES = \
  taler-auditor-sync.c
taler_auditor_sync_LDADD = \
  $(top_builddir)/src/exchangedb/libtalerexchangedb.la \
  $(top_builddir)/src/pq/libtalerpq.la \
  $(top_builddir)/src/json/libtalerjson.la \
  $(top_builddir)/src/util/libtalerutil.la \
  -lgnunetjson \
  -lgnunetutil \
  $(LIBGCRYPT_LIBS) \
  $(XLIB)
taler_auditor_sync_CPPFLAGS = \
  -I$(top_srcdir)/src/include \
  -I$(top_srcdir)/src/pq/ \
  $(POSTGRESQL_CPPFLAGS)


check_SCRIPTS = \
  test-auditor.sh \
  test-kyc.sh \
  test-revocation.sh \
  test-sync.sh

AM_TESTS_ENVIRONMENT=export TALER_EXCHANGE_PREFIX=$${TALER_EXCHANGE_PREFIX:-@libdir@};export PATH=$${TALER_EXCHANGE_PREFIX:-@prefix@}/bin:$$PATH;export TALER_AUDITOR_PREFIX=$${TALER_AUDITOR_PREFIX:-@libdir@};

TESTS = \
  test-revocation.sh \
  test-sync.sh \
  test-auditor.sh


EXTRA_DIST = \
  taler-helper-auditor-render.py \
  auditor.conf \
  setup.sh \
  test-sync-in.conf \
  test-sync-out.conf \
  generate-auditor-basedb.sh \
  generate-auditor-basedb.conf \
  generate-kyc-basedb.conf \
  generate-revoke-basedb.sh \
  $(check_SCRIPTS)
