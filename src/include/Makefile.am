# This Makefile.am is in the public domain
talerincludedir = $(includedir)/taler

if WALLET_ONLY
talerinclude_HEADERS = \
  platform.h \
  taler_amount_lib.h \
  taler_crypto_lib.h \
  taler_util_wallet.h

else

talerinclude_HEADERS = \
  platform.h \
  taler_amount_lib.h \
  taler_crypto_lib.h \
  taler_json_lib.h \
  taler_util.h \
  taler_mint_service.h \
  taler_mintdb_lib.h \
  taler_mintdb_plugin.h \
  taler_pq_lib.h \
  taler_signatures.h

endif
