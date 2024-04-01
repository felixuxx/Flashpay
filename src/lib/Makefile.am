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
  libtalerexchange.la

libtalerexchange_la_LDFLAGS = \
  -version-info 7:0:1 \
  -no-undefined
libtalerexchange_la_SOURCES = \
  exchange_api_add_aml_decision.c \
  exchange_api_age_withdraw.c \
  exchange_api_age_withdraw_reveal.c \
  exchange_api_auditor_add_denomination.c \
  exchange_api_batch_deposit.c \
  exchange_api_batch_withdraw.c \
  exchange_api_batch_withdraw2.c \
  exchange_api_curl_defaults.c exchange_api_curl_defaults.h \
  exchange_api_coins_history.c \
  exchange_api_common.c exchange_api_common.h \
  exchange_api_contracts_get.c \
  exchange_api_csr_melt.c \
  exchange_api_csr_withdraw.c \
  exchange_api_handle.c exchange_api_handle.h \
  exchange_api_deposits_get.c \
  exchange_api_kyc_check.c \
  exchange_api_kyc_proof.c \
  exchange_api_kyc_wallet.c \
  exchange_api_link.c \
  exchange_api_lookup_aml_decision.c \
  exchange_api_lookup_aml_decisions.c \
  exchange_api_management_add_partner.c \
  exchange_api_management_auditor_disable.c \
  exchange_api_management_auditor_enable.c \
  exchange_api_management_drain_profits.c \
  exchange_api_management_get_keys.c \
  exchange_api_management_post_keys.c \
  exchange_api_management_post_extensions.c \
  exchange_api_management_revoke_denomination_key.c \
  exchange_api_management_revoke_signing_key.c \
  exchange_api_management_set_global_fee.c \
  exchange_api_management_set_wire_fee.c \
  exchange_api_management_update_aml_officer.c \
  exchange_api_management_wire_disable.c \
  exchange_api_management_wire_enable.c \
  exchange_api_melt.c \
  exchange_api_purse_create_with_deposit.c \
  exchange_api_purse_create_with_merge.c \
  exchange_api_purse_delete.c \
  exchange_api_purse_deposit.c \
  exchange_api_purse_merge.c \
  exchange_api_purses_get.c \
  exchange_api_recoup.c \
  exchange_api_recoup_refresh.c \
  exchange_api_refresh_common.c exchange_api_refresh_common.h \
  exchange_api_refreshes_reveal.c \
  exchange_api_refund.c \
  exchange_api_reserves_attest.c \
  exchange_api_reserves_close.c \
  exchange_api_reserves_get.c \
  exchange_api_reserves_get_attestable.c \
  exchange_api_reserves_history.c \
  exchange_api_reserves_open.c \
  exchange_api_stefan.c \
  exchange_api_transfers_get.c
libtalerexchange_la_LIBADD = \
  libtalerauditor.la \
  $(top_builddir)/src/json/libtalerjson.la \
  $(top_builddir)/src/kyclogic/libtalerkyclogic.la \
  $(top_builddir)/src/curl/libtalercurl.la \
  $(top_builddir)/src/util/libtalerutil.la \
  $(top_builddir)/src/extensions/libtalerextensions.la \
  -lgnunetcurl \
  -lgnunetjson \
  -lgnunetutil \
  -ljansson \
  -lm \
  $(LIBGNURLCURL_LIBS) \
  $(XLIB)

libtalerauditor_la_LDFLAGS = \
  -version-info 0:0:0 \
  -no-undefined
libtalerauditor_la_SOURCES = \
  auditor_api_curl_defaults.c auditor_api_curl_defaults.h \
  auditor_api_get_config.c \
  auditor_api_deposit_confirmation.c
libtalerauditor_la_LIBADD = \
  $(top_builddir)/src/curl/libtalercurl.la \
  $(top_builddir)/src/json/libtalerjson.la \
  $(top_builddir)/src/util/libtalerutil.la \
  -lgnunetcurl \
  -lgnunetjson \
  -lgnunetutil \
  -ljansson \
  -lm \
  $(LIBGNURLCURL_LIBS) \
  $(XLIB)


check_PROGRAMS = \
 test_stefan

TESTS = \
 $(check_PROGRAMS)


test_stefan_SOURCES = \
  test_stefan.c
test_stefan_LDADD = \
  $(top_builddir)/src/lib/libtalerexchange.la \
  $(top_builddir)/src/util/libtalerutil.la \
  -lgnunetutil
