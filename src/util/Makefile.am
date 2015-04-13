# This Makefile.am is in the public domain
AM_CPPFLAGS = -I$(top_srcdir)/src/include $(LIBGCRYPT_CFLAGS) $(POSTGRESQL_CPPFLAGS)

if USE_COVERAGE
  AM_CFLAGS = --coverage -O0
  XLIB = -lgcov
endif

lib_LTLIBRARIES = \
  libtalerutil.la

libtalerutil_la_SOURCES = \
  amount.c \
  crypto.c \
  util.c \
  json.c \
  os_installation.c \
  wireformats.c

libtalerutil_la_LIBADD = \
  -lgnunetutil \
  $(LIBGCRYPT_LIBS) \
  -ljansson \
  -lmicrohttpd $(XLIB)

libtalerutil_la_LDFLAGS = \
  -version-info 0:0:0 \
  -export-dynamic -no-undefined

TESTS = \
 test_amount \
 test_crypto \
 test_json \
 test_wireformats

check_PROGRAMS= \
 test_amount \
 test_crypto \
 test_json \
 test_wireformats


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

test_json_SOURCES = \
  test_json.c
test_json_LDADD = \
  -lgnunetutil \
  -ljansson \
  libtalerutil.la

test_wireformats_SOURCES = \
  test_wireformats.c
test_wireformats_LDADD = \
  -lgnunetutil \
  -ljansson \
  libtalerutil.la
