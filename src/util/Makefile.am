AM_CPPFLAGS = -I$(top_srcdir)/src/include $(LIBGCRYPT_CFLAGS) $(POSTGRESQL_CPPFLAGS)

lib_LTLIBRARIES = \
  libtalerutil.la

libtalerutil_la_SOURCES = \
  util.c \
  json.c \
  db.c \
  rsa.c

libtalerutil_la_LIBADD = \
  -lgnunetutil \
  $(LIBGCRYPT_LIBS) \
  -ljansson \
  -lmicrohttpd \
  -lpq

libtalerutil_la_LDFLAGS = \
  $(POSTGRESQL_LDFLAGS) \
  -version-info 0:0:0 \
  -export-dynamic -no-undefined

check_PROGRAMS = \
  test-hash-context \
  test-rsa

TESTS = \
  $(check_PROGRAMS)

test_hash_context_SOURCES = test_hash_context.c
test_hash_context_CPPFLAGS = $(AM_CPPFLAGS) $(LIBGCRYPT_CFLAGS)
test_hash_context_LDADD = libtalerutil.la \
  -lgnunetutil $(LIBGCRYPT_LIBS)

test_rsa_SOURCES = test_rsa.c
test_rsa_LDADD = libtalerutil.la \
  -lgnunetutil $(LIBGCRYPT_LIBS)
