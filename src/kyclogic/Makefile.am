# This Makefile.am is in the public domain
AM_CPPFLAGS = -I$(top_srcdir)/src/include

if USE_COVERAGE
  AM_CFLAGS = --coverage -O0
  XLIB = -lgcov
endif

pkgcfgdir = $(prefix)/share/taler-exchange/config.d/

pkgcfg_DATA = \
  kyclogic.conf \
  kyclogic-kycaid.conf \
  kyclogic-oauth2.conf \
  kyclogic-persona.conf

bin_SCRIPTS = \
  taler-exchange-helper-converter-oauth2-test-full_name \
  taler-exchange-helper-measure-defaults-but-investigate \
  taler-exchange-helper-measure-enable-deposits \
  taler-exchange-helper-measure-freeze \
  taler-exchange-helper-measure-none \
  taler-exchange-helper-measure-preserve-but-investigate \
  taler-exchange-helper-measure-preserve-set-expiration \
  taler-exchange-helper-measure-tops-postal-check \
  taler-exchange-helper-measure-tops-sms-check \
  taler-exchange-helper-measure-test-form \
  taler-exchange-helper-measure-test-oauth \
  taler-exchange-helper-measure-update-from-context \
  taler-exchange-kyc-kycaid-converter.sh \
  taler-exchange-kyc-persona-converter.sh \
  taler-exchange-kyc-oauth2-test-converter.sh \
  taler-exchange-kyc-oauth2-challenger.sh \
  taler-exchange-kyc-oauth2-nda.sh

EXTRA_DIST = \
  $(pkgcfg_DATA) \
  $(bin_SCRIPTS) \
  sample.conf

lib_LTLIBRARIES = \
  libtalerkyclogic.la

libtalerkyclogic_la_SOURCES = \
  kyclogic_api.c
libtalerkyclogic_la_LIBADD = \
  $(top_builddir)/src/json/libtalerjson.la \
  $(top_builddir)/src/util/libtalerutil.la \
  -ljansson \
  -lgnunetutil \
  $(XLIB)
libtalerkyclogic_la_LDFLAGS = \
  -version-info 1:0:0 \
  -no-undefined


bin_PROGRAMS = \
  taler-exchange-kyc-tester

taler_exchange_kyc_tester_SOURCES = \
  taler-exchange-kyc-tester.c
taler_exchange_kyc_tester_LDADD = \
  $(LIBGCRYPT_LIBS) \
  libtalerkyclogic.la \
  $(top_builddir)/src/mhd/libtalermhd.la \
  $(top_builddir)/src/json/libtalerjson.la \
  $(top_builddir)/src/templating/libtalertemplating.la \
  $(top_builddir)/src/util/libtalerutil.la \
  -lmicrohttpd \
  -lgnunetcurl \
  -lgnunetutil \
  -lgnunetjson \
  -ljansson \
  -lcurl \
  -lz \
  $(XLIB)



plugindir = $(libdir)/taler-exchange

plugin_LTLIBRARIES = \
  libtaler_plugin_kyclogic_kycaid.la \
  libtaler_plugin_kyclogic_oauth2.la \
  libtaler_plugin_kyclogic_persona.la \
  libtaler_plugin_kyclogic_template.la

libtaler_plugin_kyclogic_template_la_SOURCES = \
  plugin_kyclogic_template.c
libtaler_plugin_kyclogic_template_la_LIBADD = \
  $(LTLIBINTL)
libtaler_plugin_kyclogic_template_la_LDFLAGS = \
  $(TALER_PLUGIN_LDFLAGS) \
  -lgnunetcurl \
  -lgnunetutil \
  $(XLIB)

libtaler_plugin_kyclogic_oauth2_la_SOURCES = \
  plugin_kyclogic_oauth2.c
libtaler_plugin_kyclogic_oauth2_la_LIBADD = \
  $(LTLIBINTL)
libtaler_plugin_kyclogic_oauth2_la_LDFLAGS = \
  $(TALER_PLUGIN_LDFLAGS) \
  $(top_builddir)/src/templating/libtalertemplating.la \
  $(top_builddir)/src/mhd/libtalermhd.la \
  $(top_builddir)/src/curl/libtalercurl.la \
  $(top_builddir)/src/json/libtalerjson.la \
  $(top_builddir)/src/util/libtalerutil.la \
  -lgnunetcurl \
  -lgnunetjson \
  -lgnunetutil \
  -lmicrohttpd \
  -ljansson \
  -lcurl \
  $(XLIB)

libtaler_plugin_kyclogic_kycaid_la_SOURCES = \
  plugin_kyclogic_kycaid.c
libtaler_plugin_kyclogic_kycaid_la_LIBADD = \
  $(LTLIBINTL)
libtaler_plugin_kyclogic_kycaid_la_LDFLAGS = \
  $(TALER_PLUGIN_LDFLAGS) \
  $(top_builddir)/src/templating/libtalertemplating.la \
  $(top_builddir)/src/mhd/libtalermhd.la \
  $(top_builddir)/src/json/libtalerjson.la \
  $(top_builddir)/src/curl/libtalercurl.la \
  $(top_builddir)/src/util/libtalerutil.la \
  -lgnunetcurl \
  -lgnunetjson \
  -lgnunetutil \
  -lmicrohttpd \
  -ljansson \
  -lcurl \
  $(XLIB)

libtaler_plugin_kyclogic_persona_la_SOURCES = \
  plugin_kyclogic_persona.c
libtaler_plugin_kyclogic_persona_la_LIBADD = \
  $(LTLIBINTL)
libtaler_plugin_kyclogic_persona_la_DEPENDENCIES = \
  libtalerkyclogic.la
libtaler_plugin_kyclogic_persona_la_LDFLAGS = \
  $(TALER_PLUGIN_LDFLAGS) \
  libtalerkyclogic.la \
  $(top_builddir)/src/mhd/libtalermhd.la \
  $(top_builddir)/src/json/libtalerjson.la \
  $(top_builddir)/src/curl/libtalercurl.la \
  $(top_builddir)/src/templating/libtalertemplating.la \
  $(top_builddir)/src/util/libtalerutil.la \
  -lgnunetcurl \
  -lgnunetjson \
  -lgnunetutil \
  -lmicrohttpd \
  -ljansson \
  -lcurl \
  $(XLIB)

AM_TESTS_ENVIRONMENT=export TALER_PREFIX=$${TALER_PREFIX:-@libdir@};export PATH=$${TALER_PREFIX:-@prefix@}/bin:$$PATH;
