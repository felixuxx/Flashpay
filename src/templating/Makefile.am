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
taler_mustach_tool_CFLAGS = \
  -DTOOL=MUSTACH_TOOL_JANSSON \
  -DMUSTACH_SAFE=1 \
  -DMUSTACH_LOAD_TEMPLATE=0

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
  -lmicrohttpd \
  -lgnunetjson \
  -lgnunetutil \
  -ljansson \
  $(XLIB)
libtalertemplating_la_LDFLAGS = \
  -version-info 0:0:0 \
  -no-undefined
libtalertemplating_la_CFLAGS = \
  -DMUSTACH_SAFE=1 \
  -DMUSTACH_LOAD_TEMPLATE=0

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
  $(check_SCRIPTS) \
  mustach-original-Makefile \
  mustach.1.gz \
  mustach.1.scd \
  meson.build \
  LICENSE.txt \
  ORIGIN \
  pkgcfgs \
  README.md \
  dotest.sh \
  AUTHORS \
  CHANGELOG.md \
  mustach-json-c.h \
  mustach-json-c.c \
  mustach-cjson-c.h \
  mustach-cjson-c.c \
  test1/json \
  test1/Makefile \
  test1/must \
  test1/resu.ref \
  test1/vg.ref \
  test2/json \
  test2/Makefile \
  test2/must \
  test2/resu.ref \
  test2/vg.ref \
  test3/json \
  test3/Makefile \
  test3/must \
  test3/resu.ref \
  test3/vg.ref \
  test4/json \
  test4/Makefile \
  test4/must \
  test4/resu.ref \
  test4/vg.ref \
  test5/json \
  test5/Makefile \
  test5/must \
  test5/must2 \
  test5/must2.mustache \
  test5/must3.mustache \
  test5/resu.ref \
  test5/vg.ref \
  test6/json \
  test6/Makefile \
  test6/must \
  test6/resu.ref \
  test6/test-custom-write.c \
  test6/vg.ref \
  test7/base.mustache \
  test7/json \
  test7/Makefile \
  test7/node.mustache \
  test7/resu.ref \
  test7/vg.ref \
  test8/json \
  test8/Makefile \
  test8/must \
  test8/resu.ref \
  test8/vg.ref
