# This Makefile.am is in the public domain
AM_CPPFLAGS = -I$(top_srcdir)/src/include $(LIBGCRYPT_CFLAGS)

if USE_COVERAGE
  AM_CFLAGS = --coverage -O0
  XLIB = -lgcov
endif


pkgcfgdir = $(prefix)/share/taler/config.d/

pkgcfg_DATA = \
  paths.conf \
  taler-exchange-secmod-eddsa.conf \
  taler-exchange-secmod-rsa.conf

EXTRA_DIST = \
  $(pkgcfg_DATA) \
  taler-config.in \
  test_helper_eddsa.conf \
  test_helper_rsa.conf

bin_PROGRAMS = \
  taler-exchange-secmod-eddsa \
  taler-exchange-secmod-rsa

bin_SCRIPTS = \
  taler-config

edit_script = $(SED) -e 's,%libdir%,$(libdir),'g $(NULL)

taler-config: taler-config.in
	rm -f $@ $@.tmp && \
	$(edit_script) $< >$@.tmp && \
	chmod a-w+x $@.tmp && \
	mv $@.tmp $@

CLEANFILES = \
  taler-config

taler_exchange_secmod_rsa_SOURCES = \
  taler-exchange-secmod-rsa.c taler-exchange-secmod-rsa.h \
  secmod_common.c secmod_common.h
taler_exchange_secmod_rsa_LDADD = \
  libtalerutil.la \
  -lgnunetutil \
  -lpthread \
  $(LIBGCRYPT_LIBS) \
  $(XLIB)

taler_exchange_secmod_eddsa_SOURCES = \
  taler-exchange-secmod-eddsa.c taler-exchange-secmod-eddsa.h \
  secmod_common.c secmod_common.h
taler_exchange_secmod_eddsa_LDADD = \
  libtalerutil.la \
  -lgnunetutil \
  -lpthread \
  $(LIBGCRYPT_LIBS) \
  $(XLIB)

lib_LTLIBRARIES = \
  libtalerutil.la

libtalerutil_la_SOURCES = \
  amount.c \
  auditor_signatures.c \
  config.c \
  crypto.c \
  crypto_helper_denom.c \
  crypto_helper_esign.c \
  crypto_wire.c \
  getopt.c \
  lang.c \
  mhd.c \
  offline_signatures.c \
  payto.c \
  secmod_signatures.c \
  taler_error_codes.c \
  url.c \
  util.c \
  wallet_signatures.c \
  yna.c \
  os_installation.c

libtalerutil_la_LIBADD = \
  -lgnunetutil \
  $(LIBGCRYPT_LIBS) \
  -lmicrohttpd $(XLIB)

libtalerutil_la_LDFLAGS = \
  -version-info 0:0:0 \
  -no-undefined


AM_TESTS_ENVIRONMENT=export TALER_PREFIX=$${TALER_PREFIX:-@libdir@};export PATH=$${TALER_PREFIX:-@prefix@}/bin:$$PATH;

check_PROGRAMS = \
 test_amount \
 test_crypto \
 test_helper_eddsa \
 test_helper_rsa \
 test_payto \
 test_url

TESTS = \
 $(check_PROGRAMS)


test_amount_SOURCES = \
  test_amount.c
test_amount_LDADD = \
  -lgnunetutil \
  libtalerutil.la

test_crypto_SOURCES = \
  test_crypto.c
test_crypto_LDADD = \
  -lgnunetutil \
  libtalerutil.la

test_payto_SOURCES = \
  test_payto.c
test_payto_LDADD = \
  -lgnunetutil \
  libtalerutil.la

test_helper_eddsa_SOURCES = \
  test_helper_eddsa.c
test_helper_eddsa_LDADD = \
  -lgnunetutil \
  libtalerutil.la

test_helper_rsa_SOURCES = \
  test_helper_rsa.c
test_helper_rsa_LDADD = \
  -lgnunetutil \
  libtalerutil.la

test_url_SOURCES = \
  test_url.c
test_url_LDADD = \
  -lgnunetutil \
  libtalerutil.la
