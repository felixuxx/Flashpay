# This Makefile.am is in the public domain
AM_CPPFLAGS = -I$(top_srcdir)/src/include $(LIBGCRYPT_CFLAGS)

if USE_COVERAGE
  AM_CFLAGS = --coverage -O0
  XLIB = -lgcov
endif


libexecdir = $(libdir)/taler/libexec

pkgcfgdir = $(prefix)/share/taler/config.d/

pkgcfg_DATA = \
  paths.conf \
  taler-helper-crypto-rsa.conf

EXTRA_DIST = \
  paths.conf \
  taler-config.in \
  test_helper_rsa.conf

libexec_PROGRAMS = \
  taler-helper-crypto-rsa

bin_SCRIPTS = \
  taler-config

edit_script = $(SED) -e 's,%libdir%,$(libdir),'g $(NULL)

taler-config: taler-config.in
	rm -f $@ $@.tmp && \
	$(edit_script) $< >$@.tmp && \
	chmod a-w+x $@.tmp && \
	mv $@.tmp $@


taler_helper_crypto_rsa_SOURCES = \
  taler-helper-crypto-rsa.c taler-helper-crypto-rsa.h
taler_helper_crypto_rsa_LDADD = \
  libtalerutil.la \
  -lgnunetutil \
  -lpthread \
  $(LIBGCRYPT_LIBS) \
  $(XLIB)

lib_LTLIBRARIES = \
  libtalerutil.la

libtalerutil_la_SOURCES = \
  amount.c \
  config.c \
  crypto.c \
  crypto_helper_denom.c \
  crypto_wire.c \
  getopt.c \
  lang.c \
  mhd.c \
  payto.c \
  taler_error_codes.c \
  url.c \
  util.c \
  yna.c \
  os_installation.c

libtalerutil_la_LIBADD = \
  -lgnunetutil \
  $(LIBGCRYPT_LIBS) \
  -lmicrohttpd $(XLIB)

libtalerutil_la_LDFLAGS = \
  -version-info 0:0:0 \
  -export-dynamic -no-undefined


AM_TESTS_ENVIRONMENT=export TALER_PREFIX=$${TALER_PREFIX:-@libdir@};export PATH=$${TALER_PREFIX:-@prefix@}/bin:$$PATH;

check_PROGRAMS = \
 test_amount \
 test_crypto \
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
