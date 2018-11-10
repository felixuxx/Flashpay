# This Makefile.am is in the public domain
AM_CPPFLAGS = -I$(top_srcdir)/src/include

if USE_COVERAGE
  AM_CFLAGS = --coverage -O0
  XLIB = -lgcov
endif

lib_LTLIBRARIES = \
  libtalerauditor.la \
  libtalerauditortesting.la

libtalerauditor_la_LDFLAGS = \
  -version-info 0:0:0 \
  -no-undefined
libtalerauditor_la_SOURCES = \
  curl_defaults.c \
  auditor_api_handle.c auditor_api_handle.h \
  auditor_api_deposit_confirmation.c \
  auditor_api_exchanges.c
libtalerauditor_la_LIBADD = \
  $(top_builddir)/src/json/libtalerjson.la \
  $(top_builddir)/src/util/libtalerutil.la \
  -lgnunetcurl \
  -lgnunetjson \
  -lgnunetutil \
  -ljansson \
  $(XLIB)

if HAVE_LIBCURL
libtalerauditor_la_LIBADD += -lcurl
else
if HAVE_LIBGNURL
libtalerauditor_la_LIBADD += -lgnurl
endif
endif


libtalerauditortesting_la_LDFLAGS = \
  -version-info 0:0:0 \
  -no-undefined
libtalerauditortesting_la_SOURCES = \
  testing_auditor_api_helpers.c 
libtalerauditortesting_la_LIBADD = \
  libtalerauditor.la \
  $(top_builddir)/src/exchange-lib/libtalerexchange.la \
  $(top_builddir)/src/exchange-lib/libtalertesting.la \
  $(top_builddir)/src/wire/libtalerwire.la \
  $(top_builddir)/src/json/libtalerjson.la \
  $(top_builddir)/src/util/libtalerutil.la \
  -lgnunetcurl \
  -lgnunetjson \
  -lgnunetutil \
  -ljansson \
  $(XLIB)


check_PROGRAMS = \
  test_auditor_api

AM_TESTS_ENVIRONMENT=export TALER_PREFIX=$${TALER_PREFIX:-@libdir@};export PATH=$${TALER_PREFIX:-@prefix@}/bin:$$PATH;

TESTS = \
  $(check_PROGRAMS)

test_auditor_api_SOURCES = \
  test_auditor_api.c
test_auditor_api_LDADD = \
  libtalerauditortesting.la \
  libtalerauditor.la \
  $(top_builddir)/src/exchange-lib/libtalertesting.la \
  $(top_builddir)/src/exchange-lib/libtalerexchange.la \
  $(LIBGCRYPT_LIBS) \
  $(top_builddir)/src/bank-lib/libtalerfakebank.la \
  $(top_builddir)/src/bank-lib/libtalerbank.la \
  $(top_builddir)/src/json/libtalerjson.la \
  $(top_builddir)/src/util/libtalerutil.la \
  -lgnunetcurl \
  -lgnunetutil \
  -ljansson


EXTRA_DIST = \
  test_auditor_api.conf
