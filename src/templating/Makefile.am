# This Makefile.am is in the public domain
AM_CPPFLAGS = -I$(top_srcdir)/src/include $(LIBGCRYPT_CFLAGS)

if USE_COVERAGE
  AM_CFLAGS = --coverage -O0
  XLIB = -lgcov
endif

noinst_PROGRAMS = \
  taler-mustach-tool

taler_mustach_tool_SOURCES = \
  mustach-tool.c \
  mustach-jansson.h
taler_mustach_tool_LDADD = \
  libmustach.la \
  -ljansson

lib_LTLIBRARIES = \
  libtalertemplating.la

noinst_LTLIBRARIES = \
  libmustach.la

libtalertemplating_la_SOURCES = \
  mustach.c mustach.h \
  mustach-wrap.c mustach-wrap.h \
  mustach-jansson.c mustach-jansson.h \
  templating_api.c
libtalertemplating_la_LIBADD = \
  $(top_builddir)/src/mhd/libtalermhd.la \
  $(top_builddir)/src/util/libtalerutil.la \
  -ljansson \
  -lmicrohttpd \
  -lgnunetutil \
  $(XLIB)
libtalertemplating_la_LDFLAGS = \
  -version-info 0:0:0 \
  -no-undefined


libmustach_la_SOURCES = \
  mustach.c mustach.h \
  mustach-wrap.c mustach-wrap.h \
  mustach-jansson.c mustach-jansson.h

test_mustach_jansson_SOURCES = \
  test_mustach_jansson.c
test_mustach_jansson_LDADD = \
  -lgnunetutil \
  -ljansson \
  -lmustach \
  $(XLIB)

check_PROGRAMS = \
  test_mustach_jansson

check_SCRIPTS = \
  run-original-tests.sh

TESTS = $(check_SCRIPTS) $(check_PROGRAMS)

EXTRA_DIST = \
  $(check_SCRIPTS)
