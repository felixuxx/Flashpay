# This Makefile.am is in the public domain
AM_CPPFLAGS = -I$(top_srcdir)/src/include

if USE_COVERAGE
  AM_CFLAGS = --coverage -O0
  XLIB = -lgcov
endif

bin_PROGRAMS = \
  taler-wire-gateway-client \
  taler-fakebank-run

taler_fakebank_run_SOURCES = \
  taler-fakebank-run.c
taler_fakebank_run_LDADD = \
  libtalerfakebank.la \
  $(top_builddir)/src/util/libtalerutil.la \
  -lgnunetutil

taler_wire_gateway_client_SOURCES = \
  taler-wire-gateway-client.c
taler_wire_gateway_client_LDADD = \
  $(LIBGCRYPT_LIBS) \
  $(top_builddir)/src/util/libtalerutil.la \
  $(top_builddir)/src/json/libtalerjson.la \
  libtalerbank.la \
  -lgnunetcurl \
  -lgnunetutil \
  -ljansson $(XLIB)

lib_LTLIBRARIES = \
  libtalerbank.la \
  libtalerfakebank.la

libtalerbank_la_LDFLAGS = \
  -version-info 1:0:0 \
  -no-undefined
libtalerbank_la_SOURCES = \
  bank_api_admin.c \
  bank_api_common.c bank_api_common.h \
  bank_api_credit.c \
  bank_api_debit.c \
  bank_api_transfer.c \
  bank_api_parse.c
libtalerbank_la_LIBADD = \
  $(top_builddir)/src/json/libtalerjson.la \
  $(top_builddir)/src/curl/libtalercurl.la \
  $(top_builddir)/src/util/libtalerutil.la \
  -lgnunetcurl \
  -lgnunetjson \
  -lgnunetutil \
  -ljansson \
  $(LIBGNURLCURL_LIBS) \
  $(XLIB)

libtalerfakebank_la_LDFLAGS = \
  -version-info 0:0:0 \
  -no-undefined
libtalerfakebank_la_SOURCES = \
  fakebank.c
libtalerfakebank_la_LIBADD = \
  $(top_builddir)/src/json/libtalerjson.la \
  $(top_builddir)/src/mhd/libtalermhd.la \
  $(top_builddir)/src/util/libtalerutil.la \
  -lgnunetjson \
  -lgnunetutil \
  -ljansson \
  $(LIBGNURLCURL_LIBS) \
  -lmicrohttpd \
  $(XLIB)
