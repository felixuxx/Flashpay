# This Makefile.am is in the public domain
talerincludedir = $(includedir)/taler

if WALLET_ONLY
talerinclude_HEADERS = \
  platform.h \
  taler_amount_lib.h \
  taler_crypto_lib.h \
  taler_util_wallet.h \
  taler_signatures.h
else

talerinclude_HEADERS = \
  platform.h \
  taler_auditor_service.h \
  taler_amount_lib.h \
  taler_auditordb_lib.h \
  taler_auditordb_plugin.h \
  taler_bank_service.h \
  taler_crypto_lib.h \
  taler_curl_lib.h \
  taler_error_codes.h \
  taler_exchange_service.h \
  taler_exchangedb_lib.h \
  taler_exchangedb_plugin.h \
  taler_fakebank_lib.h \
  taler_json_lib.h \
  taler_testing_auditor_lib.h \
  taler_testing_lib.h \
  taler_util.h \
  taler_mhd_lib.h \
  taler_pq_lib.h \
  taler_signatures.h \
  taler_testing_bank_lib.h 

endif

EXTRA_DIST = gauger.h
