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
  mint_api_common.c mint_api_common.h \
  mint_api_context.c mint_api_context.h \
  mint_api_json.c mint_api_json.h \
  mint_api_handle.c mint_api_handle.h \
  mint_api_admin.c \
  mint_api_deposit.c \
  mint_api_refresh.c \
  mint_api_refresh_link.c \
  mint_api_withdraw.c

libtalermint_la_LIBADD = \
  -lgnunetutil \
  -ljansson \
  -lcurl $(XLIB)

check_PROGRAMS = \
  test_mint_api

TESTS = \
  $(check_PROGRAMS)

test_mint_api_SOURCES = \
  test_mint_api.c
test_mint_api_LDADD = \
  libtalermint.la \
  $(LIBGCRYPT_LIBS) \
  $(top_builddir)/src/util/libtalerutil.la \
  -lgnunetutil \
  -ljansson

EXTRA_DIST = \
  test-mint-home/config/mint-common.conf \
  test-mint-home/master.priv \
  test-mint-home/denomkeys/ \
  test-mint-home/signkeys/
