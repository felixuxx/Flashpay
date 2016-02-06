# This Makefile.am is in the public domain
AM_CPPFLAGS = -I$(top_srcdir)/src/include $(LIBGCRYPT_CFLAGS) $(POSTGRESQL_CPPFLAGS)

if USE_COVERAGE
  AM_CFLAGS = --coverage -O0
  XLIB = -lgcov
endif

talerincludedir = $(includedir)/taler

lib_LTLIBRARIES = \
  libtalerpq.la

libtalerpq_la_SOURCES = \
  pq_query_helper.c \
  pq_result_helper.c

libtalerpq_la_LIBADD = \
  $(top_builddir)/src/util/libtalerutil.la  \
  -lgnunetutil -ljansson \
  -lpq $(XLIB)

libtalerpq_la_LDFLAGS = \
  $(POSTGRESQL_LDFLAGS) \
  -version-info 0:0:0 \
  -export-dynamic -no-undefined

TESTS = \
 test_pq

check_PROGRAMS= \
 test_pq

test_pq_SOURCES = \
  test_pq.c
test_pq_LDADD = \
  libtalerpq.la \
  $(top_builddir)/src/util/libtalerutil.la  \
  -lgnunetpq \
  -lgnunetutil \
  -ljansson \
  -lpq $(XLIB)
