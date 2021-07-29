# This Makefile.am is in the public domain
AM_CPPFLAGS = -I$(top_srcdir)/src/include

if USE_COVERAGE
  AM_CFLAGS = --coverage -O0
  XLIB = -lgcov
endif

lib_LTLIBRARIES = \
  libtalerjson.la

libtalerjson_la_SOURCES = \
  i18n.c \
  json.c \
  json_helper.c \
  json_pack.c \
  json_wire.c
libtalerjson_la_LDFLAGS = \
  -version-info 1:0:1 \
  -no-undefined
libtalerjson_la_LIBADD = \
  $(top_builddir)/src/util/libtalerutil.la \
  -lgnunetjson \
  -lgnunetutil \
  -ljansson \
  -lm \
  $(XLIB)

TESTS = \
  test_json \
  test_json_wire

check_PROGRAMS= \
  test_json \
  test_json_wire

test_json_SOURCES = \
  test_json.c
test_json_LDADD = \
  $(top_builddir)/src/json/libtalerjson.la \
  -lgnunetjson \
  $(top_builddir)/src/util/libtalerutil.la \
  -lgnunetutil \
  -ljansson


test_json_wire_SOURCES = \
  test_json_wire.c
test_json_wire_LDADD = \
  $(top_builddir)/src/json/libtalerjson.la \
  -lgnunetjson \
  $(top_builddir)/src/util/libtalerutil.la \
  -lgnunetutil \
  -ljansson
