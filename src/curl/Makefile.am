# This Makefile.am is in the public domain
AM_CPPFLAGS = -I$(top_srcdir)/src/include

if USE_COVERAGE
  AM_CFLAGS = --coverage -O0
  XLIB = -lgcov
endif

lib_LTLIBRARIES = \
  libtalercurl.la

libtalercurl_la_LDFLAGS = \
  -version-info 0:0:0 \
  -no-undefined
libtalercurl_la_SOURCES = \
  curl.c
libtalercurl_la_LIBADD = \
  -lgnunetcurl \
  -lgnunetutil \
  $(LIBGNURLCURL_LIBS) \
  -ljansson \
  -lz \
  -lm \
  $(XLIB)
