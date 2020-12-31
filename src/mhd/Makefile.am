# This Makefile.am is in the public domain
AM_CPPFLAGS = -I$(top_srcdir)/src/include

if USE_COVERAGE
  AM_CFLAGS = --coverage -O0
  XLIB = -lgcov
endif

lib_LTLIBRARIES = \
  libtalermhd.la

libtalermhd_la_SOURCES = \
  mhd_config.c \
  mhd_legal.c \
  mhd_parsing.c \
  mhd_responses.c
libtalermhd_la_LDFLAGS = \
  -version-info 0:0:0 \
  -export-dynamic -no-undefined
libtalermhd_la_LIBADD = \
  -lgnunetjson \
  $(top_builddir)/src/json/libtalerjson.la \
  $(top_builddir)/src/util/libtalerutil.la \
  -lgnunetutil \
  -lmicrohttpd \
  -ljansson \
  -lz \
  $(XLIB)
