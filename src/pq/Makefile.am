# This Makefile.am is in the public domain
AM_CPPFLAGS = -I$(top_srcdir)/src/include $(LIBGCRYPT_CFLAGS) $(POSTGRESQL_CPPFLAGS)

if USE_COVERAGE
  AM_CFLAGS = --coverage -O0
  XLIB = -lgcov
endif

lib_LTLIBRARIES = \
  libtalerpq.la

libtalerpq_la_SOURCES = \
  pq_common.h pq_common.c \
  pq_query_helper.c \
  pq_result_helper.c
libtalerpq_la_LIBADD = \
  $(top_builddir)/src/util/libtalerutil.la  \
  -lgnunetutil -ljansson \
  -lgnunetpq \
  -lpq \
  $(XLIB)
libtalerpq_la_LDFLAGS = \
  $(POSTGRESQL_LDFLAGS) \
  -version-info 0:0:0 \
  -no-undefined

check_PROGRAMS= \
 test_pq

TESTS = \
 $(check_PROGRAMS)

test_pq_SOURCES = \
  test_pq.c
test_pq_LDADD = \
  libtalerpq.la \
  $(top_builddir)/src/util/libtalerutil.la  \
  -lgnunetpq \
  -lgnunetutil \
  -ljansson \
  -lpq \
  $(XLIB)
