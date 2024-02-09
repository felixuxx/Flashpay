# This Makefile.am is in the public domain
AM_CPPFLAGS = -I$(top_srcdir)/src/include $(LIBGCRYPT_CFLAGS)

if USE_COVERAGE
  AM_CFLAGS = --coverage -O0
  XLIB = -lgcov
endif


pkgcfgdir = $(prefix)/share/taler/config.d/

pkgcfg_DATA = \
  currencies.conf \
  paths.conf \
  taler-exchange-secmod-eddsa.conf \
  taler-exchange-secmod-rsa.conf \
  taler-exchange-secmod-cs.conf

EXTRA_DIST = \
  $(pkgcfg_DATA) \
  taler-config.in \
  test_helper_eddsa.conf \
  test_helper_rsa.conf \
  test_helper_cs.conf \
  test_conversion.sh

bin_PROGRAMS = \
  taler-exchange-secmod-eddsa \
  taler-exchange-secmod-rsa \
  taler-exchange-secmod-cs

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

taler_exchange_secmod_cs_SOURCES = \
  taler-exchange-secmod-cs.c taler-exchange-secmod-cs.h \
  secmod_common.c secmod_common.h
taler_exchange_secmod_cs_LDADD = \
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
  age_restriction.c \
  amount.c \
  aml_signatures.c \
  auditor_signatures.c \
  config.c \
  conversion.c \
  crypto.c \
  crypto_confirmation.c \
  crypto_contract.c \
  crypto_helper_common.c crypto_helper_common.h \
  crypto_helper_rsa.c \
  crypto_helper_cs.c \
  crypto_helper_esign.c \
  crypto_wire.c \
  denom.c \
  exchange_signatures.c \
  getopt.c \
  lang.c \
  iban.c \
  merchant_signatures.c \
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
  -lgnunetjson \
  -lsodium \
  -ljansson \
  $(LIBGCRYPT_LIBS) \
  -lmicrohttpd $(XLIB) \
  -lunistring \
  -lz \
  -lm

libtalerutil_la_LDFLAGS = \
  -version-info 3:0:2 \
  -no-undefined


AM_TESTS_ENVIRONMENT=export TALER_PREFIX=$${TALER_PREFIX:-@libdir@};export PATH=$${TALER_PREFIX:-@prefix@}/bin:$$PATH;

check_PROGRAMS = \
 test_age_restriction \
 test_amount \
 test_conversion \
 test_crypto \
 test_helper_eddsa \
 test_helper_rsa \
 test_helper_cs \
 test_payto \
 test_url

TESTS = \
 $(check_PROGRAMS)

test_age_restriction_SOURCES = \
  test_age_restriction.c
test_age_restriction_LDADD = \
  -lgnunetutil \
  libtalerutil.la

test_conversion_SOURCES = \
  test_conversion.c
test_conversion_LDADD = \
  -lgnunetjson \
  -lgnunetutil \
  -ljansson \
  libtalerutil.la

test_amount_SOURCES = \
  test_amount.c
test_amount_LDADD = \
  -lgnunetutil \
  libtalerutil.la

test_crypto_SOURCES = \
  test_crypto.c
test_crypto_LDADD = \
  libtalerutil.la \
  -lgnunetutil \
  -ljansson

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

test_helper_cs_SOURCES = \
  test_helper_cs.c
test_helper_cs_LDADD = \
  -lgnunetutil \
  libtalerutil.la

test_url_SOURCES = \
  test_url.c
test_url_LDADD = \
  -lgnunetutil \
  libtalerutil.la
