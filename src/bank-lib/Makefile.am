# This Makefile.am is in the public domain
AM_CPPFLAGS = -I$(top_srcdir)/src/include

if USE_COVERAGE
  AM_CFLAGS = --coverage -O0
  XLIB = -lgcov
endif

bin_PROGRAMS = \
  taler-bank-transfer

noinst_PROGRAMS = \
  taler-fakebank-run

taler_fakebank_run_SOURCES = \
  taler-fakebank-run.c
taler_fakebank_run_LDADD = \
  libtalerfakebank.la \
  -lgnunetutil

taler_bank_transfer_SOURCES = \
  taler-bank-transfer.c
taler_bank_transfer_LDADD = \
  $(LIBGCRYPT_LIBS) \
  $(top_builddir)/src/util/libtalerutil.la \
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
  bank_api_config.c \
  bank_api_credit.c \
  bank_api_debit.c \
  bank_api_transfer.c \
  bank_api_parse.c
libtalerbank_la_LIBADD = \
  $(top_builddir)/src/json/libtalerjson.la \
  $(top_builddir)/src/curl/libtalercurl.la \
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
  -lgnunetjson \
  -lgnunetutil \
  -ljansson \
  -lmicrohttpd \
  $(XLIB)
