# This Makefile.am is in the public domain
AM_CPPFLAGS = -I$(top_srcdir)/src/include 

if USE_COVERAGE
  AM_CFLAGS = --coverage -O0
  XLIB = -lgcov
endif

lib_LTLIBRARIES = \
  libtalerauditor

libtalerauditor_la_LDFLAGS = \
  -version-info 0:0:0 \
  -no-undefined
libtalerauditor_la_SOURCES = \
  curl_defaults.c \
  auditor_api_handle.c auditor_api_handle.h \
  auditor_api_deposit_confirmation.c
libtalerauditor_la_LIBADD = \
  $(top_builddir)/src/json/libtalerjson.la \
  $(top_builddir)/src/util/libtalerutil.la \
  -lgnunetcurl \
  -lgnunetjson \
  -lgnunetutil \
  -ljansson \
  $(XLIB)

if HAVE_LIBCURL
libtalerauditor_la_LIBADD += -lcurl
else
if HAVE_LIBGNURL
libtalerauditor_la_LIBADD += -lgnurl
endif
endif

