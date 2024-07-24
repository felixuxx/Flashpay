# This Makefile.am is in the public domain
AM_CPPFLAGS = -I$(top_srcdir)/src/include

if USE_COVERAGE
  AM_CFLAGS = --coverage -O0
  XLIB = -lgcov
endif

lib_LTLIBRARIES = \
  libtalerjson.la

libtalerjson_la_SOURCES = \
  conversion.c \
  i18n.c \
  json.c \
  json_helper.c \
  json_pack.c \
  json_wire.c
libtalerjson_la_LDFLAGS = \
  -version-info 4:0:0 \
  -no-undefined
libtalerjson_la_LIBADD = \
  $(top_builddir)/src/util/libtalerutil.la \
  -lgnunetjson \
  -lgnunetutil \
  -lunistring \
  -ljansson \
  -lm \
  $(XLIB)

TESTS = \
  test_conversion \
  test_json

check_PROGRAMS= \
  test_conversion \
  test_json

test_json_SOURCES = \
  test_json.c
test_json_LDADD = \
  libtalerjson.la \
  -lgnunetjson \
  $(top_builddir)/src/util/libtalerutil.la \
  -lgnunetutil \
  -ljansson

test_conversion_SOURCES = \
  test_conversion.c
test_conversion_LDADD = \
  libtalerjson.la \
  $(top_builddir)/src/util/libtalerutil.la \
  -lgnunetjson \
  -lgnunetutil \
  -ljansson

EXTRA_DIST = \
  test_conversion.sh
