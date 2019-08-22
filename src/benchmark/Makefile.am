# This Makefile.am is in the public domain
AM_CPPFLAGS = -I$(top_srcdir)/src/include

clean-blobs:
	rm -fr exchange_benchmark_home/.local/share/taler/auditor*/ exchange_benchmark_home/.local/share/taler/exchange/wirefees/ exchange_benchmark_home/.local/share/taler/exchange/live-keys/ auditor.in


if USE_COVERAGE
  AM_CFLAGS = --coverage -O0
  XLIB = -lgcov
endif

bin_PROGRAMS = \
  taler-exchange-benchmark

taler_exchange_benchmark_SOURCES = \
  taler-exchange-benchmark.c
taler_exchange_benchmark_LDADD = \
  $(LIBGCRYPT_LIBS) \
  $(top_builddir)/src/wire/libtalerwire.la \
  $(top_builddir)/src/json/libtalerjson.la \
  $(top_builddir)/src/util/libtalerutil.la \
  $(top_builddir)/src/lib/libtalerexchange.la \
  $(top_builddir)/src/lib/libtalertesting.la \
  $(top_builddir)/src/bank-lib/libtalerfakebank.la \
  $(top_builddir)/src/bank-lib/libtalerbank.la \
  $(top_builddir)/src/bank-lib/libtalerbanktesting.la \
  -lgnunetjson \
  -lgnunetcurl \
  -lgnunetutil \
  -ljansson

EXTRA_DIST = \
  taler-exchange-benchmark.conf \
  bank_details.json \
  merchant_details.json \
  test_benchmark_home/.local/share/taler/exchange/offline-keys/master.priv \
  test_benchmark_home/.config/taler/test.json \
  test_benchmark_home/.config/taler/sepa.json
  generate-auditor-basedb.sh \
  generate-auditor-basedb.conf \
  generate-auditor-basedb-template.conf \
  auditor-basedb.sql \
  auditor-basedb.mpub
