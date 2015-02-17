# This Makefile.am is in the public domain
AM_CPPFLAGS = -I$(top_srcdir)/src/include $(LIBGCRYPT_CFLAGS) $(POSTGRESQL_CPPFLAGS)

lib_LTLIBRARIES = \
  libtalerutil.la

libtalerutil_la_SOURCES = \
  amount.c \
  crypto.c \
  util.c \
  json.c

libtalerutil_la_LIBADD = \
  -lgnunetutil \
  $(LIBGCRYPT_LIBS) \
  -ljansson \
  -lmicrohttpd

libtalerutil_la_LDFLAGS = \
  -version-info 0:0:0 \
  -export-dynamic -no-undefined

TESTS=\
 test-json-validations

check_PROGRAMS=\
 test-json-validations

test_json_validations_SOURCES=test_json_validations.c
test_json_validations_LDADD=\
  -lgnunetutil \
  -ljansson \
  libtalerutil.la
