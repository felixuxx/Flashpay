# This Makefile.am is in the public domain
AM_CPPFLAGS = -I$(top_srcdir)/src/include

if USE_COVERAGE
  AM_CFLAGS = --coverage -O0
  XLIB = -lgcov
endif

lib_LTLIBRARIES = \
  libtalerbank.la

libtalerbank_la_LDFLAGS = \
  -version-info 0:0:0 \
  -no-undefined

libtalerbank_la_SOURCES = \
  bank_api_context.c bank_api_context.h \
  bank_api_admin.c

libtalerbank_la_LIBADD = \
  $(top_builddir)/src/json/libtalerjson.la \
  -lgnunetjson \
  -lgnunetutil \
  -ljansson \
  $(XLIB)

if HAVE_LIBCURL
libtalerbank_la_LIBADD += -lcurl
else
if HAVE_LIBGNURL
libtalerbank_la_LIBADD += -lgnurl
endif
endif

check_PROGRAMS = \
  test_bank_api

TESTS = \
  $(check_PROGRAMS)

test_bank_api_SOURCES = \
  test_bank_api.c
test_bank_api_LDADD = \
  libtalerbank.la \
  $(top_builddir)/src/util/libtalerutil.la \
  -lgnunetutil
