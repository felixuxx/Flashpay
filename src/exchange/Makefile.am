# This Makefile.am is in the public domain
AM_CPPFLAGS = \
 -I$(top_srcdir)/src/include \
 $(LIBGCRYPT_CFLAGS) \
 $(POSTGRESQL_CPPFLAGS)

if USE_COVERAGE
  AM_CFLAGS = --coverage -O0
  XLIB = -lgcov
endif

pkgcfgdir = $(prefix)/share/taler/config.d/

pkgcfg_DATA = \
  exchange.conf

# Programs

bin_PROGRAMS = \
  taler-exchange-aggregator \
  taler-exchange-closer \
  taler-exchange-httpd \
  taler-exchange-transfer \
  taler-exchange-wirewatch

taler_exchange_aggregator_SOURCES = \
  taler-exchange-aggregator.c
taler_exchange_aggregator_LDADD = \
  $(LIBGCRYPT_LIBS) \
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

taler_exchange_httpd_SOURCES = \
  taler-exchange-httpd.c taler-exchange-httpd.h \
  taler-exchange-httpd_auditors.c taler-exchange-httpd_auditors.h \
  taler-exchange-httpd_db.c taler-exchange-httpd_db.h \
  taler-exchange-httpd_deposit.c taler-exchange-httpd_deposit.h \
  taler-exchange-httpd_deposits_get.c taler-exchange-httpd_deposits_get.h \
  taler-exchange-httpd_keys.c taler-exchange-httpd_keys.h \
  taler-exchange-httpd_link.c taler-exchange-httpd_link.h \
  taler-exchange-httpd_loop.c taler-exchange-httpd_loop.h \
  taler-exchange-httpd_management.h \
  taler-exchange-httpd_management_auditors.c \
  taler-exchange-httpd_management_auditors_AP_disable.c \
  taler-exchange-httpd_management_denominations_HDP_revoke.c \
  taler-exchange-httpd_management_post_keys.c \
  taler-exchange-httpd_management_signkey_EP_revoke.c \
  taler-exchange-httpd_management_wire.c \
  taler-exchange-httpd_management_wire_disable.c \
  taler-exchange-httpd_management_wire_fees.c \
  taler-exchange-httpd_melt.c taler-exchange-httpd_melt.h \
  taler-exchange-httpd_mhd.c taler-exchange-httpd_mhd.h \
  taler-exchange-httpd_recoup.c taler-exchange-httpd_recoup.h \
  taler-exchange-httpd_refreshes_reveal.c taler-exchange-httpd_refreshes_reveal.h \
  taler-exchange-httpd_refund.c taler-exchange-httpd_refund.h \
  taler-exchange-httpd_reserves_get.c taler-exchange-httpd_reserves_get.h \
  taler-exchange-httpd_responses.c taler-exchange-httpd_responses.h \
  taler-exchange-httpd_terms.c taler-exchange-httpd_terms.h \
  taler-exchange-httpd_transfers_get.c taler-exchange-httpd_transfers_get.h \
  taler-exchange-httpd_wire.c taler-exchange-httpd_wire.h \
  taler-exchange-httpd_withdraw.c taler-exchange-httpd_withdraw.h

#  taler-exchange-httpd_management_post_keys.c


taler_exchange_httpd_LDADD = \
  $(LIBGCRYPT_LIBS) \
  $(top_builddir)/src/bank-lib/libtalerbank.la \
  $(top_builddir)/src/mhd/libtalermhd.la \
  $(top_builddir)/src/json/libtalerjson.la \
  $(top_builddir)/src/exchangedb/libtalerexchangedb.la \
  $(top_builddir)/src/util/libtalerutil.la \
  -lmicrohttpd \
  -lgnunetcurl \
  -lgnunetutil \
  -lgnunetjson \
  -ljansson \
  -lz \
  -lpthread \
  $(XLIB)

# Testcases

AM_TESTS_ENVIRONMENT=export TALER_PREFIX=$${TALER_PREFIX:-@libdir@};export PATH=$${TALER_PREFIX:-@prefix@}/bin:$$PATH;

check_SCRIPTS = \
  test_taler_exchange_httpd.sh \
  test_taler_exchange_httpd_restart.sh
if HAVE_EXPENSIVE_TESTS
check_SCRIPTS += \
  test_taler_exchange_httpd_afl.sh
endif

.NOTPARALLEL:
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
  $(check_SCRIPTS)
