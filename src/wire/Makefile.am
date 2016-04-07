# This Makefile.am is in the public domain
AM_CPPFLAGS = -I$(top_srcdir)/src/include

if USE_COVERAGE
  AM_CFLAGS = --coverage -O0
  XLIB = -lgcov
endif

plugindir = $(libdir)/taler

plugin_LTLIBRARIES = \
  libtaler_plugin_wire_sepa.la \
  libtaler_plugin_wire_test.la

noinst_LTLIBRARIES = \
  libtaler_plugin_wire_template.la

lib_LTLIBRARIES = \
  libtalerwire.la


libtaler_plugin_wire_test_la_SOURCES = \
  plugin_wire_test.c
libtaler_plugin_wire_test_la_LIBADD = \
  $(LTLIBINTL)
libtaler_plugin_wire_test_la_LDFLAGS = \
  $(TALER_PLUGIN_LDFLAGS) \
  $(top_builddir)/src/bank-lib/libtalerbank.la \
  $(top_builddir)/src/util/libtalerutil.la \
  -lgnunetutil $(XLIB)


libtaler_plugin_wire_sepa_la_SOURCES = \
  plugin_wire_sepa.c
libtaler_plugin_wire_sepa_la_LIBADD = \
  $(LTLIBINTL)
libtaler_plugin_wire_sepa_la_LDFLAGS = \
  $(TALER_PLUGIN_LDFLAGS) \
  $(top_builddir)/src/json/libtalerjson.la \
  $(top_builddir)/src/util/libtalerutil.la \
  -lgnunetjson \
  -lgnunetutil $(XLIB)


libtaler_plugin_wire_template_la_SOURCES = \
  plugin_wire_template.c
libtaler_plugin_wire_template_la_LIBADD = \
  $(LTLIBINTL)
libtaler_plugin_wire_template_la_LDFLAGS = \
  $(TALER_PLUGIN_LDFLAGS) \
  $(top_builddir)/src/util/libtalerutil.la \
  -lgnunetutil $(XLIB)


libtalerwire_la_SOURCES = \
  wire.c
libtalerwire_la_LIBADD = \
  -lgnunetutil \
  $(XLIB)
libtalerwire_la_LDFLAGS = \
  -version-info 0:0:0 \
  -export-dynamic -no-undefined


AM_TESTS_ENVIRONMENT=export TALER_PREFIX=$${TALER_PREFIX:-@libdir@};export PATH=$${TALER_PREFIX:-@prefix@}/bin:$$PATH;

TESTS = \
 test_sepa_wireformat

check_PROGRAMS= \
 test_sepa_wireformat



test_sepa_wireformat_SOURCES = \
  test_sepa_wireformat.c
test_sepa_wireformat_LDADD = \
  -lgnunetutil \
  -ljansson \
  libtalerwire.la \
  $(top_builddir)/src/util/libtalerutil.la
