# This Makefile.am is in the public domain
AM_CPPFLAGS = -I$(top_srcdir)/src/include

if USE_COVERAGE
  AM_CFLAGS = --coverage -O0
  XLIB = -lgcov
endif

lib_LTLIBRARIES = \
  libtalerbank.la \
  libtalerfakebank.la

libtalerbank_la_LDFLAGS = \
  -version-info 0:0:0 \
  -no-undefined

libtalerbank_la_SOURCES = \
  bank_api_admin.c \
  bank_api_common.c bank_api_common.h \
  bank_api_history.c

libtalerbank_la_LIBADD = \
  $(top_builddir)/src/json/libtalerjson.la \
  -lgnunetcurl \
  -lgnunetjson \
  -lgnunetutil \
  -ljansson \
  $(XLIB)


libtalerfakebank_la_LDFLAGS = \
  -version-info 0:0:0 \
  -no-undefined

libtalerfakebank_la_SOURCES = \
  fakebank.c

libtalerfakebank_la_LIBADD = \
  $(top_builddir)/src/json/libtalerjson.la \
  -lgnunetjson \
  -lgnunetutil \
  -ljansson \
  -lmicrohttpd \
  $(XLIB)


if HAVE_LIBCURL
libtalerbank_la_LIBADD += -lcurl
else
if HAVE_LIBGNURL
libtalerbank_la_LIBADD += -lgnurl
endif
endif

check_PROGRAMS = \
  test_bank_api \
  test_bank_api_with_fakebank

TESTS = \
  $(check_PROGRAMS)

test_bank_api_SOURCES = \
  test_bank_interpreter.c test_bank_interpreter.h \
  test_bank_api.c
test_bank_api_LDADD = \
  libtalerbank.la \
  libtalerfakebank.la \
  $(top_builddir)/src/util/libtalerutil.la \
  -lgnunetcurl \
  -lgnunetutil \
  -ljansson


test_bank_api_with_fakebank_SOURCES = \
  test_bank_interpreter.c test_bank_interpreter.h \
  test_bank_api_with_fakebank.c
test_bank_api_with_fakebank_LDADD = \
  libtalerbank.la \
  libtalerfakebank.la \
  $(top_builddir)/src/util/libtalerutil.la \
  -lgnunetcurl \
  -lgnunetutil \
  -ljansson
