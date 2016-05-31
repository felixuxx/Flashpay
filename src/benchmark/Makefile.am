# This Makefile.am is in the public domain
AM_CPPFLAGS = -I$(top_srcdir)/src/include

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
  $(top_builddir)/src/json/libtalerjson.la \
  $(top_builddir)/src/util/libtalerutil.la \
  $(top_builddir)/src/exchange-lib/libtalerexchange.la \
  -lgnunetjson \
  -lgnunetcurl \
  -lgnunetutil \
  -ljansson
