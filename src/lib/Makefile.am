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
  -version-info 4:0:0 \
  -no-undefined
libtalerexchange_la_SOURCES = \
  exchange_api_curl_defaults.c exchange_api_curl_defaults.h \
  exchange_api_common.c \
  exchange_api_handle.c exchange_api_handle.h \
  exchange_api_deposit.c \
  exchange_api_deposits_get.c \
  exchange_api_link.c \
  exchange_api_melt.c \
  exchange_api_recoup.c \
  exchange_api_refresh_common.c exchange_api_refresh_common.h \
  exchange_api_refreshes_reveal.c \
  exchange_api_refund.c \
  exchange_api_reserves_get.c \
  exchange_api_transfers_get.c \
  exchange_api_withdraw.c \
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
