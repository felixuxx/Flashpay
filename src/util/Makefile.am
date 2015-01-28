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
