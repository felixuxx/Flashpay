# This Makefile.am is in the public domain
AM_CPPFLAGS = -I$(top_srcdir)/src/include

if USE_COVERAGE
  AM_CFLAGS = --coverage -O0
  XLIB = -lgcov
endif

pkgcfgdir = $(prefix)/share/taler/config.d/

EXTRA_DIST = \
  test_wire_plugin.conf \
  test_wire_plugin_transactions_taler-bank.conf

plugindir = $(libdir)/taler

if HAVE_LIBCURL
plugin_LTLIBRARIES = \
 libtaler_plugin_wire_taler_bank.la
else
if HAVE_LIBGNURL
plugin_LTLIBRARIES = \
 libtaler_plugin_wire_taler_bank.la
endif
endif

noinst_LTLIBRARIES = \
  libtaler_plugin_wire_template.la


libtaler_plugin_wire_taler_bank_la_SOURCES = \
  plugin_wire_taler-bank.c
libtaler_plugin_wire_taler_bank_la_LIBADD = \
  $(LTLIBINTL)
libtaler_plugin_wire_taler_bank_la_LDFLAGS = \
  $(TALER_PLUGIN_LDFLAGS) \
  $(top_builddir)/src/bank-lib/libtalerbank.la \
  $(top_builddir)/src/json/libtalerjson.la \
  $(top_builddir)/src/wire/libtalerwire.la \
  $(top_builddir)/src/util/libtalerutil.la \
  -lgnunetcurl \
  -lgnunetutil $(XLIB)


libtaler_plugin_wire_template_la_SOURCES = \
  plugin_wire_template.c
libtaler_plugin_wire_template_la_LIBADD = \
  $(LTLIBINTL)
libtaler_plugin_wire_template_la_LDFLAGS = \
  $(TALER_PLUGIN_LDFLAGS) \
  $(top_builddir)/src/util/libtalerutil.la \
  -lgnunetutil $(XLIB)


AM_TESTS_ENVIRONMENT=export TALER_PREFIX=$${TALER_PREFIX:-@libdir@};export PATH=$${TALER_PREFIX:-@prefix@}/bin:$$PATH;

TESTS = \
 test_wire_plugin \
 test_wire_plugin_transactions_taler_bank

check_PROGRAMS= $(TESTS)


test_wire_plugin_SOURCES = \
  test_wire_plugin.c
test_wire_plugin_LDADD = \
  -lgnunetutil \
  $(top_builddir)/src/wire/libtalerwire.la \
  $(top_builddir)/src/util/libtalerutil.la


test_wire_plugin_transactions_taler_bank_SOURCES = \
  test_wire_plugin_transactions_taler-bank.c
test_wire_plugin_transactions_taler_bank_LDADD = \
  -lgnunetjson \
  -lgnunetutil \
  -ljansson \
  $(top_builddir)/src/wire/libtalerwire.la \
  $(top_builddir)/src/bank-lib/libtalerbank.la \
  $(top_builddir)/src/bank-lib/libtalerfakebank.la \
  $(top_builddir)/src/util/libtalerutil.la
