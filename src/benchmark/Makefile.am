# This Makefile.am is in the public domain
AM_CPPFLAGS = -I$(top_srcdir)/src/include

clean-blobs:
	rm -fr exchange_benchmark_home/.local/share/taler/auditor*/ exchange_benchmark_home/.local/share/taler/exchange/wirefees/ exchange_benchmark_home/.local/share/taler/exchange/live-keys/ auditor.in


if USE_COVERAGE
  AM_CFLAGS = --coverage -O0
  XLIB = -lgcov
endif

bin_PROGRAMS = \
  taler-aggregator-benchmark \
  taler-bank-benchmark \
  taler-exchange-benchmark


taler_aggregator_benchmark_SOURCES = \
  taler-aggregator-benchmark.c
taler_aggregator_benchmark_LDADD = \
  $(LIBGCRYPT_LIBS) \
  $(top_builddir)/src/exchangedb/libtalerexchangedb.la \
  $(top_builddir)/src/json/libtalerjson.la \
  $(top_builddir)/src/util/libtalerutil.la \
  -lgnunetjson \
  -ljansson \
  -lgnunetutil \
  $(XLIB)

taler_bank_benchmark_SOURCES = \
  taler-bank-benchmark.c
taler_bank_benchmark_LDADD = \
  $(LIBGCRYPT_LIBS) \
  $(top_builddir)/src/testing/libtalertesting.la \
  $(top_builddir)/src/lib/libtalerexchange.la \
  $(top_builddir)/src/bank-lib/libtalerfakebank.la \
  $(top_builddir)/src/bank-lib/libtalerbank.la \
  $(top_builddir)/src/exchangedb/libtalerexchangedb.la \
  $(top_builddir)/src/json/libtalerjson.la \
  $(top_builddir)/src/util/libtalerutil.la \
  $(top_builddir)/src/extensions/libtalerextensions.la \
  -lgnunetjson \
  -lgnunetcurl \
  -lgnunetutil \
  -ljansson \
  $(XLIB)

taler_exchange_benchmark_SOURCES = \
  taler-exchange-benchmark.c
taler_exchange_benchmark_LDADD = \
  $(LIBGCRYPT_LIBS) \
  $(top_builddir)/src/lib/libtalerexchange.la \
  $(top_builddir)/src/exchangedb/libtalerexchangedb.la \
  $(top_builddir)/src/testing/libtalertesting.la \
  $(top_builddir)/src/bank-lib/libtalerfakebank.la \
  $(top_builddir)/src/bank-lib/libtalerbank.la \
  $(top_builddir)/src/json/libtalerjson.la \
  $(top_builddir)/src/util/libtalerutil.la \
  $(top_builddir)/src/extensions/libtalerextensions.la \
  -lgnunetjson \
  -lgnunetcurl \
  -lgnunetutil \
  -ljansson \
  $(XLIB)

EXTRA_DIST = \
  benchmark-common.conf \
  benchmark-cs.conf \
  benchmark-rsa.conf \
  bank-benchmark-cs.conf \
  bank-benchmark-rsa.conf \
  coins-cs.conf \
  coins-rsa.conf
