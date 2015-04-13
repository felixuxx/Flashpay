# This Makefile.am is in the public domain
AM_CPPFLAGS = -I$(top_srcdir)/src/include

if USE_COVERAGE
  AM_CFLAGS = --coverage -O0
  XLIB = -lgcov
endif

lib_LTLIBRARIES = \
  libtalermint.la

libtalermint_la_LDFLAGS = \
  -version-info 0:0:0 \
  -no-undefined

libtalermint_la_SOURCES = \
  mint_api.c

libtalermint_la_LIBADD = \
  -lgnunetutil \
  -ljansson \
  -lcurl $(XLIB)

check_PROGRAMS = \
  test_mint_api

test_mint_api_SOURCES = \
  test_mint_api.c
test_mint_api_LDADD = \
  libtalermint.la \
  $(LIBGCRYPT_LIBS) \
  $(top_builddir)/src/util/libtalerutil.la \
  -lgnunetutil \
  -ljansson

