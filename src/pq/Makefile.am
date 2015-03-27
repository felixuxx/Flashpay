# This Makefile.am is in the public domain
AM_CPPFLAGS = -I$(top_srcdir)/src/include $(LIBGCRYPT_CFLAGS) $(POSTGRESQL_CPPFLAGS)

talerincludedir = $(includedir)/taler

lib_LTLIBRARIES = \
  libtalerpq.la

libtalerpq_la_SOURCES = \
  db_pq.c

libtalerpq_la_LIBADD = \
  -lgnunetutil \
  -lpq

libtalerpq_la_LDFLAGS = \
  $(POSTGRESQL_LDFLAGS) \
  -version-info 0:0:0 \
  -export-dynamic -no-undefined
