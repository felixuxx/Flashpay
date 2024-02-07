# This Makefile.am is in the public domain

AM_CPPFLAGS = \
  -I$(top_srcdir)/src/include \
  $(LIBGCRYPT_CFLAGS) \
  $(POSTGRESQL_CPPFLAGS)

if USE_COVERAGE
  AM_CFLAGS = --coverage -O0
  XLIB = -lgcov
endif

# Age restriction as extension library

plugindir = $(libdir)/taler

plugin_LTLIBRARIES = \
  libtaler_extension_age_restriction.la

libtaler_extension_age_restriction_la_LDFLAGS = \
  -version-info 0:0:0 \
  -no-undefined

libtaler_extension_age_restriction_la_SOURCES = \
  age_restriction.c
libtaler_extension_age_restriction_la_LDFLAGS = \
  $(TALER_PLUGIN_LDFLAGS)
libtaler_extension_age_restriction_la_LIBADD = \
  $(top_builddir)/src/json/libtalerjson.la \
  $(top_builddir)/src/util/libtalerutil.la \
  -lgnunetjson \
  -lgnunetutil \
  -ljansson \
  $(XLIB)
