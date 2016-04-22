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
  paths.conf

templated_scripts = taler-config taler-arm
dist_bin_SCRIPTS = $(templated_scripts)

# See https://www.gnu.org/software/autoconf/manual/autoconf-2.63/html_node/Installation-Directory-Variables.html
# for an explanation and why this ugliness is necessary.
edit = sed -e 's|@libdir[@]|$(libdir)|g'
$(templated_scripts): %: Makefile $(srcdir)/%.in
	rm -f $@ $@.tmp
	$(edit) '$(srcdir)/$@.in' >$@.tmp
	chmod +x $@.tmp
	chmod a-w $@.tmp
	mv $@.tmp $@

if WALLET_ONLY
lib_LTLIBRARIES = \
  libtalerutil_wallet.la
else
lib_LTLIBRARIES = \
  libtalerutil.la
endif

libtalerutil_wallet_la_SOURCES = \
  amount.c \
  crypto.c

libtalerutil_wallet_la_LIBADD = \
  -lgnunetutil_taler_wallet \
  $(LIBGCRYPT_LIBS) \
  $(XLIB)

libtalerutil_wallet_la_LDFLAGS = \
  -version-info 0:0:0 \
  -export-dynamic -no-undefined

libtalerutil_la_SOURCES = \
  amount.c \
  crypto.c \
  util.c \
  os_installation.c

libtalerutil_la_LIBADD = \
  -lgnunetutil \
  $(LIBGCRYPT_LIBS) \
  -lmicrohttpd $(XLIB)

libtalerutil_la_LDFLAGS = \
  -version-info 0:0:0 \
  -export-dynamic -no-undefined

TESTS = \
 test_amount \
 test_crypto

check_PROGRAMS = \
 test_amount \
 test_crypto


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
