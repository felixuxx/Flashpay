# This Makefile.am is in the public domain

AM_CPPFLAGS = \
  -I$(top_srcdir)/src/include \
  $(LIBGCRYPT_CFLAGS) \
  $(POSTGRESQL_CPPFLAGS)

if USE_COVERAGE
  AM_CFLAGS = --coverage -O0
  XLIB = -lgcov
endif


# Basic extension handling library

lib_LTLIBRARIES = \
  libtalerextensions.la

libtalerextensions_la_LDFLAGS = \
  -version-info 0:0:0 \
  -no-undefined

libtalerextensions_la_SOURCES = \
  extensions.c \
  age_restriction_helper.c

libtalerextensions_la_LIBADD = \
  $(top_builddir)/src/json/libtalerjson.la \
  $(top_builddir)/src/util/libtalerutil.la \
  -lgnunetjson \
  -lgnunetutil \
  -ljansson \
  $(XLIB)

