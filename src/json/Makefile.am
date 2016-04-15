# This Makefile.am is in the public domain
AM_CPPFLAGS = -I$(top_srcdir)/src/include

if USE_COVERAGE
  AM_CFLAGS = --coverage -O0
  XLIB = -lgcov
endif

lib_LTLIBRARIES = \
  libtalerjson.la

libtalerjson_la_SOURCES = \
  json.c \
  json_helper.c
libtalerjson_la_LDFLAGS = \
  -version-info 0:0:0 \
  -export-dynamic -no-undefined
libtalerjson_la_LIBADD = \
  -lgnunetjson \
  $(top_builddir)/src/util/libtalerutil.la \
  -lgnunetutil \
  -ljansson \
  $(XLIB)

TESTS = \
  test_json

check_PROGRAMS= \
  test_json

test_json_SOURCES = \
  test_json.c
test_json_LDADD = \
  -ltalerjson \
  -lgnunetjson \
  $(top_builddir)/src/util/libtalerutil.la \
  -lgnunetutil \
  -ljansson
