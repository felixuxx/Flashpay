# This Makefile.am is in the public domain
AM_CPPFLAGS = -I$(top_srcdir)/src/include $(LIBGCRYPT_CFLAGS)

if USE_COVERAGE
  AM_CFLAGS = --coverage -O0
  XLIB = -lgcov
endif


pkgcfgdir = $(prefix)/share/taler/config.d/

pkgcfg_DATA = \
  paths.conf

EXTRA_DIST = \
  paths.conf \
  taler-config.in

bin_SCRIPTS = \
  taler-config

edit_script = $(SED) -e 's,%libdir%,$(libdir),'g $(NULL)

taler-config: taler-config.in
	rm -f $@ $@.tmp && \
	$(edit_script) $< >$@.tmp && \
	chmod a-w+x $@.tmp && \
	mv $@.tmp $@



lib_LTLIBRARIES = \
  libtalerutil.la

libtalerutil_la_SOURCES = \
  amount.c \
  config.c \
  crypto.c \
  crypto_wire.c \
  getopt.c \
  mhd.c \
  payto.c \
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


check_PROGRAMS = \
 test_amount \
 test_crypto \
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

test_url_SOURCES = \
  test_url.c
test_url_LDADD = \
  -lgnunetutil \
  libtalerutil.la
