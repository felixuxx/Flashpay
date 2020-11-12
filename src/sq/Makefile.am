# This Makefile.am is in the public domain
AM_CPPFLAGS = -I$(top_srcdir)/src/include $(LIBGCRYPT_CFLAGS) $(SQLITE_CPPFLAGS)

if USE_COVERAGE
  AM_CFLAGS = --coverage -O0
  XLIB = -lgcov
endif

lib_LTLIBRARIES = \
  libtalersq.la

libtalersq_la_SOURCES = \
  sq_query_helper.c \
  sq_result_helper.c
libtalersq_la_LIBADD = \
  $(top_builddir)/src/util/libtalerutil.la  \
  -lgnunetutil -ljansson \
  -lsqlite3 \
  $(XLIB)
libtalersq_la_LDFLAGS = \
  $(SQLITE_LDFLAGS) \
  -version-info 0:0:0 \
  -export-dynamic -no-undefined

check_PROGRAMS= \
 test_sq

TESTS = \
 $(check_PROGRAMS)

test_sq_SOURCES = \
  test_sq.c
test_sq_LDADD = \
  libtalersq.la \
  $(top_builddir)/src/util/libtalerutil.la  \
  -lgnunetsq \
  -lgnunetutil \
  -ljansson \
  -lsqlite3 \
  $(XLIB)
